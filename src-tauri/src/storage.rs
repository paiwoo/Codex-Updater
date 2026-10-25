use crate::model::RunState;
use atomicwrites::{AtomicFile, OverwriteBehavior::AllowOverwrite};
use fs2::FileExt;
use serde::{de::DeserializeOwned, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::PathBuf,
};

pub fn root() -> Result<PathBuf, String> {
    #[cfg(debug_assertions)]
    if let Some(path) = std::env::var_os("CODEX_UPDATER_TEST_DATA_DIR") {
        let p = PathBuf::from(path);
        fs::create_dir_all(p.join("runs")).map_err(|e| e.to_string())?;
        return Ok(p);
    }
    let p = dirs::data_local_dir()
        .ok_or("Local app data unavailable")?
        .join("CodexUpdater");
    fs::create_dir_all(p.join("runs")).map_err(|e| e.to_string())?;
    Ok(p)
}
pub fn now() -> String {
    chrono::Utc::now().to_rfc3339()
}
pub fn valid_id(id: &str) -> bool {
    id.len() == 32 && id.bytes().all(|c| c.is_ascii_hexdigit())
}
pub fn run_dir(id: &str) -> Result<PathBuf, String> {
    if !valid_id(id) {
        return Err("Invalid run identifier".into());
    }
    Ok(root()?.join("runs").join(id))
}
pub fn read<T: DeserializeOwned>(path: impl AsRef<std::path::Path>) -> Result<T, String> {
    serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}
pub fn write<T: Serialize>(path: impl AsRef<std::path::Path>, value: &T) -> Result<(), String> {
    let data = serde_json::to_vec_pretty(value).map_err(|e| e.to_string())?;
    AtomicFile::new(path.as_ref(), AllowOverwrite)
        .write(|f| f.write_all(&data))
        .map_err(|e| e.to_string())
}
pub fn lock(name: &str) -> Result<File, String> {
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(root()?.join(name))
        .map_err(|e| e.to_string())?;
    file.try_lock_exclusive()
        .map_err(|_| "Another update task is active".to_string())?;
    Ok(file)
}
pub fn worker_alive() -> bool {
    // The deployment child holds a non-shared handle as well. If the Rust worker
    // is externally terminated, another repair must still wait for Windows.
    lock("worker.lock").is_err() || lock("deployment.lock").is_err()
}
pub fn save_run(state: &mut RunState) -> Result<(), String> {
    state.updated_at = now();
    write(run_dir(&state.id)?.join("state.json"), state)
}
pub fn current() -> Option<RunState> {
    let id: String = read(root().ok()?.join("current.json")).ok()?;
    let mut s: RunState = read(run_dir(&id).ok()?.join("state.json")).ok()?;
    s.worker_alive = worker_alive();
    if !s.terminal()
        && !s.worker_alive
        && chrono::DateTime::parse_from_rfc3339(&s.updated_at)
            .map(|v| chrono::Utc::now().signed_duration_since(v).num_seconds() > 90)
            .unwrap_or(true)
    {
        s.stage = "interrupted".into();
        s.code = "worker_stopped".into();
    }
    Some(s)
}
pub fn history() -> Vec<RunState> {
    let Ok(root) = root() else { return vec![] };
    let Ok(entries) = fs::read_dir(root.join("runs")) else {
        return vec![];
    };
    let active = current();
    let mut states: Vec<RunState> = entries
        .flatten()
        .filter_map(|e| read::<RunState>(e.path().join("state.json")).ok())
        .map(|mut s| {
            if let Some(current) = active.as_ref().filter(|v| v.id == s.id) {
                return current.clone();
            }
            if !s.terminal() {
                s.stage = "interrupted".into();
                s.code = "worker_stopped".into();
            }
            s
        })
        .collect();
    states.sort_by(|a, b| b.started_at.cmp(&a.started_at));
    states.truncate(30);
    states
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ids_cannot_escape_storage() {
        assert!(!valid_id("../state"));
        assert!(!valid_id("C:\\arbitrary"));
        assert!(valid_id("abcdef0123456789abcdef0123456789"));
    }
}
