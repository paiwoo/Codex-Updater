use crate::{
    model::{Diagnosis, RunState},
    storage,
};
use serde::Serialize;
use serde_json::{json, Value};

#[derive(Serialize)]
pub struct Preview {
    pub id: String,
    pub content: String,
}
pub fn redact(d: Option<&Diagnosis>, run: Option<&RunState>) -> Value {
    json!({
        "schemaVersion":1,"toolVersion":env!("CARGO_PKG_VERSION"),"exportedAt":storage::now(),
        "diagnosis":d.map(|d|json!({"checkedAt":d.checked_at,"installedVersion":d.package.as_ref().map(|p|&p.version),"architecture":d.package.as_ref().map(|p|&p.architecture),"offeredVersion":d.offer.as_ref().map(|o|&o.version),"storeVersion":d.offer.as_ref().and_then(|o|o.store_version.as_ref()),"staged":d.staged,"updateAvailable":d.update_available,"prompt":d.prompt,"evidenceCodes":d.evidence.iter().map(|e|&e.code).collect::<Vec<_>>()})),
        "repair":run.map(|s|json!({"stage":s.stage,"code":s.code,"beforeVersion":s.before_version,"targetVersion":s.target_version,"startedAt":s.started_at,"updatedAt":s.updated_at,"deployed":s.deployed,"running":s.running,"prompt":s.prompt}))
    })
}
pub fn preview() -> Result<Preview, String> {
    let d: Option<Diagnosis> = storage::read(storage::root()?.join("diagnosis.json")).ok();
    let run = storage::current();
    let content = serde_json::to_string_pretty(&redact(d.as_ref(), run.as_ref()))
        .map_err(|e| e.to_string())?;
    let id = uuid::Uuid::new_v4().simple().to_string();
    let folder = storage::root()?.join("exports");
    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    storage::write(folder.join(format!("{id}.json")), &content)?;
    Ok(Preview { id, content })
}
pub fn save(id: &str) -> Result<String, String> {
    if !storage::valid_id(id) {
        return Err("Invalid export preview".into());
    }
    let prepared = storage::root()?.join("exports").join(format!("{id}.json"));
    let content: String = storage::read(&prepared)?;
    if content.len() > 65_536 {
        return Err("Diagnostic export exceeds the expected size".into());
    }
    let downloads = dirs::download_dir().ok_or("Downloads folder unavailable")?;
    if !downloads.is_dir() {
        return Err("Downloads folder does not exist".into());
    }
    let path = downloads.join(format!(
        "codex-updater-diagnostic-{}-{}.json",
        chrono::Utc::now().format("%Y%m%d-%H%M%S"),
        &id[..6]
    ));
    use std::io::Write;
    let mut file = std::fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&path)
        .map_err(|e| e.to_string())?;
    file.write_all(content.as_bytes())
        .map_err(|e| e.to_string())?;
    // Keep the reviewed snapshot for repeated saves from the same dialog.
    Ok(path.to_string_lossy().into())
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Evidence, PackageInfo, ProcessInfo};
    #[test]
    fn export_uses_allowlisted_fields_and_excludes_paths_and_errors() {
        let d = Diagnosis {
            checked_at: "time".into(),
            package: Some(PackageInfo {
                name: "OpenAI.Codex".into(),
                version: "1.2.3.4".into(),
                architecture: "x64".into(),
                publisher: "private publisher".into(),
                family: "private family".into(),
                location: "C:\\Users\\SecretName".into(),
                app_id: "App".into(),
                processes: vec![ProcessInfo {
                    id: 123,
                    path: "C:\\Users\\SecretName\\private.exe".into(),
                }],
            }),
            offer: None,
            staged: false,
            supported: true,
            update_available: None,
            prompt: "unverified".into(),
            evidence: vec![Evidence {
                code: "feed_unavailable".into(),
                detail: "SECRET-TOKEN in raw error".into(),
                level: "error".into(),
            }],
        };
        let text = redact(Some(&d), None).to_string();
        assert!(text.contains("1.2.3.4"));
        assert!(text.contains("feed_unavailable"));
        for secret in [
            "SecretName",
            "SECRET-TOKEN",
            "private.exe",
            "private publisher",
            "private family",
        ] {
            assert!(!text.contains(secret), "{secret}");
        }
    }
}
