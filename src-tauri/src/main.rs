#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod diagnostics;
mod engine;
mod export;
mod feed;
mod model;
mod platform;
mod storage;
use model::{Diagnosis, RunState, Snapshot};

#[tauri::command]
async fn diagnose() -> Result<Diagnosis, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let _lock = storage::lock("diagnose.lock")?;
        if storage::current().is_some_and(|s| !s.terminal()) {
            return Err("Wait for the active repair before starting a new diagnostic".into());
        }
        let d = diagnostics::diagnose(true);
        storage::write(storage::root()?.join("diagnosis.json"), &d)?;
        Ok(d)
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn snapshot() -> Result<Snapshot, String> {
    Ok(Snapshot {
        diagnosis: storage::read(storage::root()?.join("diagnosis.json")).ok(),
        run: storage::current(),
        history: storage::history(),
    })
}
#[tauri::command]
async fn start_repair(target_version: String) -> Result<RunState, String> {
    model::version(&target_version)?;
    tauri::async_runtime::spawn_blocking(move || {
        let d: Diagnosis = storage::read(storage::root()?.join("diagnosis.json"))?;
        engine::start(&d, &target_version)
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn resume_repair(run_id: String) -> Result<RunState, String> {
    tauri::async_runtime::spawn_blocking(move || engine::resume(&run_id))
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
fn control_run(action: String) -> Result<(), String> {
    engine::send_control(&action)
}
#[tauri::command]
fn export_preview() -> Result<export::Preview, String> {
    export::preview()
}
#[tauri::command]
fn save_export(preview_id: String) -> Result<String, String> {
    export::save(&preview_id)
}
#[cfg(windows)]
fn memory_target(webview: &tauri::WebviewWindow, focused: bool) {
    use webview2_com::Microsoft::Web::WebView2::Win32::{
        ICoreWebView2_19, ICoreWebView2_3, COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW,
        COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL,
    };
    use webview2_com::TrySuspendCompletedHandler;
    use windows_core::Interface;
    let _ = webview.with_webview(move |webview| unsafe {
        // Older runtimes may lack this optional background memory hint.
        if let Ok(core) = webview.controller().CoreWebView2() {
            if let Ok(core) = core.cast::<ICoreWebView2_19>() {
                let level = if focused {
                    COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL
                } else {
                    COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW
                };
                let _ = core.SetMemoryUsageTargetLevel(level);
            }
            if let Ok(core) = core.cast::<ICoreWebView2_3>() {
                if focused {
                    let _ = core.Resume();
                } else {
                    let callback = TrySuspendCompletedHandler::create(Box::new(|_, _| Ok(())));
                    let _ = core.TrySuspend(&callback);
                }
            }
        }
    });
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    if args.get(1).is_some_and(|s| s == "--package-processes") {
        match args
            .get(2)
            .ok_or("Missing process identifiers")
            .and_then(|input| {
                platform::package_processes(input).map_err(|_| "Package process inspection failed")
            }) {
            Ok(ids) => println!("{}", serde_json::to_string(&ids).unwrap()),
            Err(_) => std::process::exit(1),
        }
        return;
    }
    #[cfg(debug_assertions)]
    if args.get(1).is_some_and(|s| s == "--probe-detachment") {
        let result = (|| -> Result<(), String> {
            let id = args.get(2).ok_or("Missing probe identifier")?;
            let request: model::Request =
                storage::read(storage::run_dir(id)?.join("request.json"))?;
            if request.sid != "INVALID_TEST_SID"
                || std::env::var_os("CODEX_UPDATER_TEST_DATA_DIR").is_none()
            {
                return Err("Detachment probes require an isolated state directory and a deliberately invalid SID".into());
            }
            #[cfg(windows)]
            if std::env::var_os("CODEX_UPDATER_PROBE_JOB").is_some() {
                platform::probe_restrictive_job()?;
            }
            platform::spawn_detached(&std::env::current_exe().map_err(|e| e.to_string())?, id)?;
            Ok(())
        })();
        if result.is_err() {
            std::process::exit(1);
        }
        return;
    }
    if args.get(1).is_some_and(|s| s == "--repair-worker") {
        let result = args
            .get(2)
            .ok_or_else(|| "Missing worker identifier".into())
            .and_then(|id| engine::worker(id));
        if result.is_err() {
            std::process::exit(1);
        }
        return;
    }
    if args.get(1).is_some_and(|s| s == "--diagnose-json") {
        let d = diagnostics::diagnose(true);
        if let Some(path) = args.get(2) {
            if let Err(e) = storage::write(std::path::Path::new(path), &d) {
                eprintln!("{e}");
                std::process::exit(1);
            }
        } else {
            println!("{}", serde_json::to_string_pretty(&d).unwrap_or_default());
        }
        return;
    }
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(windows)]
            {
                use tauri::Manager;
                if let Some(webview) = app.get_webview_window("main") {
                    memory_target(&webview, webview.is_focused().unwrap_or(false));
                }
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(windows)]
            if let tauri::WindowEvent::Focused(focused) = event {
                use tauri::Manager;
                if let Some(webview) = window.get_webview_window(window.label()) {
                    memory_target(&webview, *focused);
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            diagnose,
            snapshot,
            start_repair,
            resume_repair,
            control_run,
            export_preview,
            save_export
        ])
        .run(tauri::generate_context!())
        .expect("Could not launch Codex Updater");
}
