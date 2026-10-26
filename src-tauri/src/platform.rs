use crate::{model::PackageInfo, storage};
use serde_json::{json, Value};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

#[cfg(windows)]
pub fn hidden(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW
}
#[cfg(not(windows))]
pub fn hidden(_command: &mut Command) {}

pub fn spawn_detached(executable: &Path, id: &str) -> Result<Child, String> {
    let mut command = Command::new(executable);
    command
        .args(["--repair-worker", id])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000 | 0x00000200 | 0x01000000); // no console, new group, breakaway from job
    }
    command
        .spawn()
        .map_err(|e| format!("Could not start independent worker: {e}"))
}

pub fn powershell() -> Result<PathBuf, String> {
    #[cfg(not(windows))]
    {
        return Err("This release supports Windows only".into());
    }
    #[cfg(windows)]
    {
        let root = std::env::var_os("SystemRoot").ok_or("Windows directory unavailable")?;
        let path = PathBuf::from(root).join("System32/WindowsPowerShell/v1.0/powershell.exe");
        if !path.is_file() {
            return Err("Windows PowerShell 5.1 is required".into());
        }
        Ok(path)
    }
}

pub fn operation(op: &str, data: Value, timeout: Option<Duration>) -> Result<Value, String> {
    let dir = storage::root()?
        .join("checks")
        .join(uuid::Uuid::new_v4().simple().to_string());
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let result = operation_in(&dir, op, data, timeout, || Ok(()));
    // Only these two generated files are removed; no recursive cleanup of computed paths.
    let _ = fs::remove_file(dir.join("operation.ps1"));
    let _ = fs::remove_file(dir.join("input.json"));
    let _ = fs::remove_dir(&dir);
    result
}

pub fn operation_in<F: FnMut() -> Result<(), String>>(
    dir: &Path,
    op: &str,
    data: Value,
    timeout: Option<Duration>,
    mut tick: F,
) -> Result<Value, String> {
    let allowed = [
        "Identity",
        "Inspect",
        "Staged",
        "Validate",
        "Activity",
        "Quit",
        "ForceQuit",
        "Deploy",
        "Launch",
        "Prompt",
        "Events",
    ];
    if !allowed.contains(&op) {
        return Err("Unsupported system operation".into());
    }
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let script = dir.join("operation.ps1");
    let input = dir.join("input.json");
    fs::write(&script, include_str!("../scripts/windows.ps1")).map_err(|e| e.to_string())?;
    storage::write(&input, &data)?;
    let mut cmd = Command::new(powershell()?);
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
    ])
    .arg(&script)
    .arg("-Operation")
    .arg(op)
    .arg("-InputPath")
    .arg(&input)
    .stdin(Stdio::null())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());
    hidden(&mut cmd);
    let mut child = cmd.spawn().map_err(|e| e.to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or("System operation output unavailable")?;
    let stderr = child
        .stderr
        .take()
        .ok_or("System operation errors unavailable")?;
    // Drain both pipes while polling, so a diagnostic cannot block on a full output buffer.
    let out_thread = thread::spawn(move || {
        use std::io::Read;
        let mut s = String::new();
        let _ = stdout.take(1_048_576).read_to_string(&mut s);
        s
    });
    let err_thread = thread::spawn(move || {
        use std::io::Read;
        let mut s = String::new();
        let _ = stderr.take(65_536).read_to_string(&mut s);
        s
    });
    let start = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait().map_err(|e| e.to_string())? {
            break Ok(s);
        }
        if timeout.is_some_and(|t| start.elapsed() > t) {
            let _ = child.kill();
            let _ = child.wait();
            break Err(format!("{op} timed out; its result is unverified"));
        }
        if let Err(e) = tick() {
            // A deployment must never be killed because the UI or heartbeat failed.
            if op != "Deploy" {
                let _ = child.kill();
                let _ = child.wait();
                break Err(e);
            }
        }
        thread::sleep(Duration::from_millis(650));
    };
    let out = out_thread.join().unwrap_or_default();
    let err = err_thread.join().unwrap_or_default();
    let status = status?;
    let parsed: Value =
        serde_json::from_str(out.trim_start_matches('\u{feff}').trim()).map_err(|_| {
            format!(
                "System operation {op} did not return a valid result: {}",
                err.chars().take(700).collect::<String>()
            )
        })?;
    if !status.success() || parsed["ok"] != true {
        return Err(parsed["error"]
            .as_str()
            .unwrap_or("Windows operation failed")
            .to_string());
    }
    Ok(parsed["value"].clone())
}
pub fn inspect() -> Result<Option<PackageInfo>, String> {
    let value = operation("Inspect", json!({}), Some(Duration::from_secs(25)))?;
    if value.is_null() {
        Ok(None)
    } else {
        serde_json::from_value(value)
            .map(Some)
            .map_err(|e| e.to_string())
    }
}
pub fn identity() -> Result<String, String> {
    let v = operation("Identity", json!({}), Some(Duration::from_secs(15)))?;
    v["sid"]
        .as_str()
        .map(str::to_owned)
        .ok_or("Windows identity unavailable".into())
}
pub fn prompt() -> String {
    operation("Prompt", json!({}), Some(Duration::from_secs(18)))
        .ok()
        .and_then(|v| v["prompt"].as_str().map(str::to_owned))
        .filter(|v| ["visible", "not_detected", "unverified"].contains(&v.as_str()))
        .unwrap_or_else(|| "unverified".into())
}
