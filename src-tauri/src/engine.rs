use crate::{
    diagnostics, feed,
    model::{version, Diagnosis, Request, RunState},
    platform, storage,
};
use serde_json::{json, Value};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::Path,
    sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender},
    thread,
    time::{Duration, Instant},
};

const CANCELLED: &str = "cancel_requested";
fn transition(s: &mut RunState, stage: &str) -> Result<(), String> {
    s.stage = stage.into();
    s.code = stage.into();
    s.percent = None;
    storage::save_run(s)
}
fn control(id: &str) -> Option<String> {
    let path = storage::run_dir(id).ok()?.join("control.json");
    let value: Value = storage::read(&path).ok()?;
    let _ = fs::remove_file(path);
    value["action"].as_str().map(str::to_owned)
}
fn check_cancel(s: &RunState) -> Result<(), String> {
    if matches!(control(&s.id).as_deref(), Some("cancel")) {
        Err(CANCELLED.into())
    } else {
        Ok(())
    }
}

pub fn start(d: &Diagnosis, target: &str) -> Result<RunState, String> {
    let _start_lock = storage::lock("start.lock")?;
    if storage::worker_alive() || storage::current().is_some_and(|s| !s.terminal()) {
        return Err("A repair is already active. Reopen its progress instead".into());
    }
    let (p, _) = diagnostics::can_start(d, target)?;
    let sid = platform::identity()?;
    create_run(&p.version, target, sid, false, false)
}
pub fn resume(id: &str) -> Result<RunState, String> {
    let _start_lock = storage::lock("start.lock")?;
    if storage::worker_alive() {
        return Err("A repair or Windows deployment is still active".into());
    }
    let previous = storage::current().ok_or("No repair to continue")?;
    if previous.id != id || !resumable(&previous) {
        return Err("This repair cannot be continued. Recheck its current state".into());
    }
    let request: Request = storage::read(storage::run_dir(id)?.join("request.json"))?;
    let sid = platform::identity()?;
    if request.id != id || request.target_version != previous.target_version || request.sid != sid {
        return Err("The saved repair does not belong to this Windows account or target".into());
    }
    let p = platform::inspect()?.ok_or("Official Codex is not installed")?;
    if p.architecture != "x64" {
        return Err("This preview only repairs Windows x64 installations".into());
    }
    version(&request.target_version)?;
    create_run(
        &p.version,
        &request.target_version,
        sid,
        true,
        request.fresh_download || previous.code == "verification_failed",
    )
}
fn resumable(s: &RunState) -> bool {
    matches!(s.stage.as_str(), "failed" | "cancelled" | "interrupted")
}
fn create_run(
    before: &str,
    target: &str,
    sid: String,
    resume: bool,
    fresh_download: bool,
) -> Result<RunState, String> {
    let id = uuid::Uuid::new_v4().simple().to_string();
    let dir = storage::run_dir(&id)?;
    fs::create_dir(&dir).map_err(|e| e.to_string())?;
    let request = Request {
        id: id.clone(),
        target_version: target.into(),
        sid,
        resume,
        fresh_download,
    };
    storage::write(dir.join("request.json"), &request)?;
    let mut state = RunState {
        id: id.clone(),
        stage: "preparing".into(),
        code: "preparing".into(),
        started_at: storage::now(),
        updated_at: storage::now(),
        target_version: target.into(),
        before_version: before.into(),
        downloaded_bytes: 0,
        total_bytes: None,
        percent: None,
        deployed: false,
        running: false,
        prompt: "unverified".into(),
        message: None,
        worker_alive: false,
    };
    storage::save_run(&mut state)?;
    storage::write(storage::root()?.join("current.json"), &id)?;
    if let Err(e) =
        platform::spawn_detached(&std::env::current_exe().map_err(|e| e.to_string())?, &id)
    {
        state.stage = "failed".into();
        state.code = "worker_start_failed".into();
        state.message = Some(e.clone());
        storage::save_run(&mut state)?;
        return Err(e);
    }
    Ok(state)
}
pub fn worker(id: &str) -> Result<(), String> {
    let _lock = storage::lock("worker.lock")?;
    let dir = storage::run_dir(id)?;
    let request: Request = storage::read(dir.join("request.json"))?;
    if request.id != id || storage::read::<String>(storage::root()?.join("current.json"))? != id {
        return Err("Worker request does not own the active run".into());
    }
    let mut s: RunState = storage::read(dir.join("state.json"))?;
    if s.terminal() {
        return Err("This run has already ended".into());
    }
    s.worker_alive = true;
    storage::save_run(&mut s)?;
    let result = repair(&request, &mut s);
    match result {
        Ok(()) => {
            s.stage = "complete".into();
            s.code = if s.prompt == "visible" {
                "updated_prompt_remains"
            } else {
                "updated"
            }
            .into();
        }
        Err(e) => {
            let failed_at = s.stage.clone();
            s.stage = if e == CANCELLED {
                "cancelled"
            } else {
                "failed"
            }
            .into();
            s.code = failure_code(&failed_at, &e).into();
            s.message = if e == CANCELLED { None } else { Some(e) };
            // Restore only after this repair requested exit. Never kill the app to recover.
            if dir.join("exit-requested").exists() {
                let _ = platform::operation_in(
                    &dir,
                    "Launch",
                    json!({"sid":request.sid}),
                    Some(Duration::from_secs(15)),
                    || Ok(()),
                );
            }
        }
    }
    s.worker_alive = false;
    s.percent = None;
    storage::save_run(&mut s)?;
    // Packages are temporary repair inputs, never an unbounded cache of installers.
    let _ = fs::remove_file(dir.join("package.partial"));
    let _ = fs::remove_file(dir.join("package.msix"));
    Ok(())
}
fn failure_code(stage: &str, error: &str) -> &'static str {
    let text = error.to_lowercase();
    if error == CANCELLED {
        return "cancel_requested";
    }
    if text.contains("80070005")
        || text.contains("access is denied")
        || text.contains("access denied")
        || text.contains("拒绝访问")
        || text.contains("80073d28")
    {
        return "access_denied";
    }
    if text.contains("800700e9")
        || text.contains("80073d02")
        || text.contains("still running")
        || text.contains("需要关闭")
    {
        return "app_in_use";
    }
    if stage == "validating" || text.contains("signature") || text.contains("publisher") {
        return "verification_failed";
    }
    if stage == "downloading" {
        return "download_failed";
    }
    if stage == "launching" || stage == "verifying" {
        return "launch_unverified";
    }
    "repair_failed"
}
fn repair(request: &Request, s: &mut RunState) -> Result<(), String> {
    if platform::identity()? != request.sid {
        return Err("The worker is running as a different Windows account".into());
    }
    check_cancel(s)?;
    if request.resume {
        let p = platform::inspect()?.ok_or("Official Codex is not installed")?;
        if package_reached_target(&p, &request.target_version)? {
            s.deployed = true;
            if !running_target(&p) && !p.processes.is_empty() {
                let dir = storage::run_dir(&s.id)?;
                fs::write(dir.join("exit-requested"), b"requested").map_err(|e| e.to_string())?;
                transition(s, "closing")?;
                platform::operation_in(
                    &dir,
                    "Quit",
                    json!({}),
                    Some(Duration::from_secs(15)),
                    || storage::save_run(s),
                )?;
                wait_for_exit(request, s)?;
            }
            return finish(
                request,
                s,
                storage::read(storage::root()?.join("diagnosis.json")).ok(),
            );
        }
    }
    let fresh = diagnostics::diagnose(false);
    storage::write(storage::root()?.join("diagnosis.json"), &fresh)?;
    let (installed, offer) = diagnostics::can_start(&fresh, &request.target_version)?;
    let originally_running = !installed.processes.is_empty();
    let dir = storage::run_dir(&s.id)?;
    let staged = if request.fresh_download {
        json!({"exists":false})
    } else {
        platform::operation_in(
            &dir,
            "Staged",
            json!({"targetVersion":request.target_version}),
            Some(Duration::from_secs(15)),
            || storage::save_run(s),
        )?
    };
    let register = staged["exists"] == true;
    let path = if register {
        staged["path"]
            .as_str()
            .ok_or("Missing staged package path")?
            .to_string()
    } else {
        if offer.url.is_empty() {
            return Err(
                "The target package is not staged and has no official download. Check again later"
                    .into(),
            );
        }
        transition(s, "downloading")?;
        download(
            &offer.url,
            &request.target_version,
            &installed.architecture,
            &dir,
            s,
        )?;
        dir.join("package.msix").to_string_lossy().to_string()
    };
    check_cancel(s)?;
    transition(s, "validating")?;
    let deploy_data = json!({"sid":request.sid,"targetVersion":request.target_version,"register":register,"packagePath":path});
    platform::operation_in(
        &dir,
        "Validate",
        deploy_data.clone(),
        Some(Duration::from_secs(120)),
        || {
            storage::save_run(s)?;
            check_cancel(s)
        },
    )?;
    check_cancel(s)?;
    transition(s, "closing")?;
    if originally_running {
        fs::write(dir.join("exit-requested"), b"requested").map_err(|e| e.to_string())?;
    }
    platform::operation_in(
        &dir,
        "Quit",
        json!({}),
        Some(Duration::from_secs(15)),
        || storage::save_run(s),
    )?;
    wait_for_exit(request, s)?;
    check_cancel(s)?;
    transition(s, "deploying")?;
    platform::operation_in(&dir, "Deploy", deploy_data, None, || {
        if let Ok(progress) = storage::read::<Value>(dir.join("deployment-progress.json")) {
            s.percent = progress["percent"]
                .as_f64()
                .filter(|p| *p >= 0.0 && *p <= 100.0);
        }
        storage::save_run(s)
    })?;
    s.deployed = true;
    storage::save_run(s)?;
    finish(request, s, Some(fresh))
}
fn package_reached_target(p: &crate::model::PackageInfo, target: &str) -> Result<bool, String> {
    if p.architecture != "x64" {
        return Err("Unsupported recovery architecture".into());
    }
    Ok(version(&p.version)? >= version(target)?)
}
fn running_target(p: &crate::model::PackageInfo) -> bool {
    !p.processes.is_empty()
        && p.processes.iter().all(|v| {
            Path::new(&v.path)
                .parent()
                .is_some_and(|parent| parent == Path::new(&p.location).join("app"))
        })
}
fn finish(request: &Request, s: &mut RunState, fresh: Option<Diagnosis>) -> Result<(), String> {
    let dir = storage::run_dir(&s.id)?;
    let p = platform::inspect()?.ok_or("The registered Codex package disappeared")?;
    if !running_target(&p) {
        check_cancel(s)?;
        transition(s, "launching")?;
        platform::operation_in(
            &dir,
            "Launch",
            json!({"sid":request.sid}),
            Some(Duration::from_secs(20)),
            || storage::save_run(s),
        )?;
    }
    transition(s, "verifying")?;
    let deadline = Instant::now() + Duration::from_secs(75);
    loop {
        let p = platform::inspect()?.ok_or("The registered Codex package disappeared")?;
        s.deployed = package_reached_target(&p, &request.target_version)?;
        s.running = s.deployed && running_target(&p);
        storage::save_run(s)?;
        if s.running {
            break;
        }
        if Instant::now() > deadline {
            return Err("The package was deployed but its running version could not be verified. Check your launch method".into());
        }
        thread::sleep(Duration::from_secs(2));
    }
    // Give the client a moment to populate its UI. The prompt is auxiliary evidence.
    for _ in 0..5 {
        storage::save_run(s)?;
        thread::sleep(Duration::from_secs(1));
    }
    s.prompt = platform::prompt();
    if let Some(mut refreshed) = fresh {
        refreshed.checked_at = storage::now();
        refreshed.package = platform::inspect()?;
        refreshed.prompt = s.prompt.clone();
        refreshed.update_available = refreshed
            .package
            .as_ref()
            .zip(refreshed.offer.as_ref())
            .and_then(|(p, offer)| Some(version(&p.version).ok()? < version(&offer.version).ok()?));
        refreshed.staged = false;
        storage::write(storage::root()?.join("diagnosis.json"), &refreshed)?;
    }
    Ok(())
}
fn wait_for_exit(request: &Request, s: &mut RunState) -> Result<(), String> {
    let dir = storage::run_dir(&s.id)?;
    let mut deadline = Instant::now() + Duration::from_secs(30);
    let mut clear = 0;
    loop {
        let action = control(&s.id);
        if action.as_deref() == Some("cancel") {
            return Err(CANCELLED.into());
        }
        if s.stage == "waiting_for_exit" {
            match action.as_deref() {
                Some("force_exit") => {
                    platform::operation_in(
                        &dir,
                        "ForceQuit",
                        json!({"sid":request.sid,"confirmed":true}),
                        Some(Duration::from_secs(20)),
                        || storage::save_run(s),
                    )?;
                    transition(s, "closing")?;
                    deadline = Instant::now() + Duration::from_secs(30);
                }
                Some("retry") => {
                    transition(s, "closing")?;
                    platform::operation_in(
                        &dir,
                        "Quit",
                        json!({}),
                        Some(Duration::from_secs(15)),
                        || storage::save_run(s),
                    )?;
                    deadline = Instant::now() + Duration::from_secs(30);
                }
                _ => {}
            }
        }
        let p = platform::inspect()?.ok_or("Codex is no longer registered")?;
        if p.processes.is_empty() {
            clear += 1;
            if clear >= 2 {
                return Ok(());
            }
        } else {
            clear = 0;
        }
        if Instant::now() > deadline && s.stage != "waiting_for_exit" {
            transition(s, "waiting_for_exit")?;
        }
        storage::save_run(s)?;
        thread::sleep(Duration::from_secs(1));
    }
}
fn download(
    url: &str,
    target: &str,
    arch: &str,
    dir: &Path,
    s: &mut RunState,
) -> Result<(), String> {
    feed::download_url(url, target, arch)?;
    let receiver = package_stream(url.to_owned());
    const MAX: u64 = 3 * 1024 * 1024 * 1024;
    let partial = dir.join("package.partial");
    let mut file = File::create(&partial).map_err(|e| e.to_string())?;
    let mut last = Instant::now();
    let started = Instant::now();
    loop {
        if started.elapsed() > Duration::from_secs(1800) {
            return Err("The package download exceeded 30 minutes".into());
        }
        check_cancel(s)?;
        match receiver.recv_timeout(Duration::from_millis(650)) {
            Ok(Ok(PackageChunk::Start(total))) => {
                s.total_bytes = total;
                if total.is_some_and(|n| n > MAX) {
                    return Err("The official package exceeds the download limit".into());
                }
            }
            Ok(Ok(PackageChunk::Data(data))) => {
                s.downloaded_bytes += data.len() as u64;
                if s.downloaded_bytes > MAX {
                    return Err("The package download exceeds the limit".into());
                }
                file.write_all(&data).map_err(|e| e.to_string())?;
            }
            Ok(Ok(PackageChunk::End)) => break,
            Ok(Err(e)) => return Err(e),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                return Err("The download worker stopped unexpectedly".into())
            }
        }
        s.percent = s
            .total_bytes
            .filter(|n| *n > 0)
            .map(|n| s.downloaded_bytes as f64 / n as f64 * 100.0);
        if last.elapsed() > Duration::from_millis(500) {
            storage::save_run(s)?;
            last = Instant::now();
        }
    }
    if s.total_bytes.is_some_and(|n| n != s.downloaded_bytes) || s.downloaded_bytes == 0 {
        return Err("The downloaded package is incomplete".into());
    }
    file.sync_all().map_err(|e| e.to_string())?;
    fs::rename(partial, dir.join("package.msix")).map_err(|e| e.to_string())?;
    storage::save_run(s)
}
enum PackageChunk {
    Start(Option<u64>),
    Data(Vec<u8>),
    End,
}
fn package_stream(url: String) -> Receiver<Result<PackageChunk, String>> {
    // A bounded queue lets cancellation keep working even while a network read is stalled.
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let result = (|| {
            let response = feed::client(Duration::from_secs(1800))?
                .get(url)
                .send()
                .map_err(|_| "Could not start the official package download")?
                .error_for_status()
                .map_err(|_| "The official package is not available for download")?;
            if !feed::trusted_url(response.url()) {
                return Err("Unexpected package download source".into());
            }
            stream_body(response, &sender)
        })();
        if let Err(e) = result {
            let _ = sender.send(Err(e));
        }
    });
    receiver
}
fn stream_body(
    mut response: reqwest::blocking::Response,
    sender: &SyncSender<Result<PackageChunk, String>>,
) -> Result<(), String> {
    let send = |chunk| sender.send(Ok(chunk)).map_err(|_| CANCELLED.to_string());
    send(PackageChunk::Start(response.content_length()))?;
    let mut buffer = [0u8; 65_536];
    loop {
        let n = response
            .read(&mut buffer)
            .map_err(|_| "The package download was interrupted")?;
        if n == 0 {
            return send(PackageChunk::End);
        }
        send(PackageChunk::Data(buffer[..n].to_vec()))?;
    }
}

pub fn send_control(action: &str) -> Result<(), String> {
    let s = storage::current().ok_or("No active repair")?;
    if s.terminal() {
        return Err("This repair has already ended".into());
    }
    if !control_allowed(&s, action) {
        return Err("This action is not available in the current repair stage".into());
    }
    storage::write(
        storage::run_dir(&s.id)?.join("control.json"),
        &json!({"action":action}),
    )
}
fn control_allowed(s: &RunState, action: &str) -> bool {
    !s.terminal()
        && match action {
            "cancel" => s.can_cancel(),
            "force_exit" | "retry" => s.stage == "waiting_for_exit",
            _ => false,
        }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn state(stage: &str) -> RunState {
        RunState {
            id: "abcdef0123456789abcdef0123456789".into(),
            stage: stage.into(),
            code: stage.into(),
            started_at: String::new(),
            updated_at: String::new(),
            target_version: "1.2.3.4".into(),
            before_version: "1.2.3.3".into(),
            downloaded_bytes: 0,
            total_bytes: None,
            percent: None,
            deployed: false,
            running: false,
            prompt: "unverified".into(),
            message: None,
            worker_alive: true,
        }
    }
    #[test]
    fn deployment_is_never_cancelled_or_force_quit() {
        for stage in ["deploying", "launching", "verifying", "complete"] {
            for action in ["cancel", "force_exit", "retry"] {
                assert!(!control_allowed(&state(stage), action), "{stage}: {action}");
            }
        }
    }
    #[test]
    fn force_quit_requires_waiting_stage() {
        assert!(control_allowed(&state("waiting_for_exit"), "force_exit"));
        assert!(!control_allowed(&state("closing"), "force_exit"));
        assert!(!control_allowed(&state("downloading"), "force_exit"));
        assert!(control_allowed(&state("downloading"), "cancel"));
    }
    #[test]
    fn classifies_failure_without_erasing_the_failed_stage() {
        assert_eq!(
            failure_code("deploying", "0x800700E9 needs the app to close"),
            "app_in_use"
        );
        assert_eq!(
            failure_code("deploying", "0x80070005 access denied"),
            "access_denied"
        );
        assert_eq!(
            failure_code("validating", "The manifest is invalid"),
            "verification_failed"
        );
        assert_eq!(
            failure_code("verifying", "No running version"),
            "launch_unverified"
        );
        assert_eq!(failure_code("downloading", CANCELLED), "cancel_requested");
    }
    #[test]
    fn only_ended_unsuccessful_runs_offer_continuation() {
        for stage in ["failed", "cancelled", "interrupted"] {
            assert!(resumable(&state(stage)));
        }
        for stage in ["complete", "deploying", "waiting_for_exit", "preparing"] {
            assert!(!resumable(&state(stage)));
        }
    }
    #[test]
    fn recovery_skips_deployment_only_for_a_supported_registered_target() {
        let mut p = crate::model::PackageInfo {
            name: "OpenAI.Codex".into(),
            version: "1.2.3.4".into(),
            architecture: "x64".into(),
            publisher: String::new(),
            family: String::new(),
            location: r"C:\WindowsApps\OpenAI.Codex_1.2.3.4".into(),
            app_id: "App".into(),
            processes: vec![],
        };
        assert!(package_reached_target(&p, "1.2.3.4").unwrap());
        assert!(package_reached_target(&p, "1.2.3.3").unwrap());
        assert!(!package_reached_target(&p, "1.2.3.5").unwrap());
        assert!(!running_target(&p));
        p.processes.push(crate::model::ProcessInfo {
            id: 1,
            path: format!(r"{}\app\ChatGPT.exe", p.location),
        });
        assert!(running_target(&p));
        p.processes.push(crate::model::ProcessInfo {
            id: 2,
            path: r"C:\WindowsApps\OpenAI.Codex_1.2.3.3\app\ChatGPT.exe".into(),
        });
        assert!(!running_target(&p));
        p.architecture = "arm64".into();
        assert!(package_reached_target(&p, "1.2.3.4").is_err());
    }
    #[test]
    fn streamed_download_reports_bytes_and_stops_when_cancelled() {
        use std::net::TcpListener;
        for cancel in [false, true] {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let addr = listener.local_addr().unwrap();
            let server = thread::spawn(move || {
                let (mut stream, _) = listener.accept().unwrap();
                let _ = stream.read(&mut [0; 1024]);
                stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nabcdefgh").unwrap();
            });
            let (sender, receiver) = mpsc::sync_channel(1);
            let reader = thread::spawn(move || {
                let response = feed::client(Duration::from_secs(3))
                    .unwrap()
                    .get(format!("http://{addr}"))
                    .send()
                    .unwrap();
                stream_body(response, &sender)
            });
            assert!(matches!(
                receiver.recv().unwrap().unwrap(),
                PackageChunk::Start(Some(8))
            ));
            if cancel {
                drop(receiver);
                assert_eq!(reader.join().unwrap().unwrap_err(), CANCELLED);
            } else {
                let mut body = vec![];
                loop {
                    match receiver.recv().unwrap().unwrap() {
                        PackageChunk::Data(data) => body.extend(data),
                        PackageChunk::End => break,
                        _ => panic!("Unexpected repeated download header"),
                    }
                }
                assert_eq!(body, b"abcdefgh");
                reader.join().unwrap().unwrap();
            }
            server.join().unwrap();
        }
    }
}
