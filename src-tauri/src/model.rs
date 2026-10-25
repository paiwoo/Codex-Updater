use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessInfo {
    pub id: u32,
    pub path: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PackageInfo {
    pub name: String,
    pub version: String,
    pub architecture: String,
    pub publisher: String,
    pub family: String,
    pub location: String,
    pub app_id: String,
    pub processes: Vec<ProcessInfo>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Offer {
    pub version: String,
    pub architecture: String,
    pub url: String,
    pub store_version: Option<String>,
    pub released_at: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Evidence {
    pub code: String,
    pub detail: String,
    pub level: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Diagnosis {
    pub checked_at: String,
    pub package: Option<PackageInfo>,
    pub offer: Option<Offer>,
    pub staged: bool,
    pub supported: bool,
    pub update_available: Option<bool>,
    pub prompt: String,
    pub evidence: Vec<Evidence>,
}
impl Diagnosis {
    pub fn evidence(&mut self, code: &str, detail: impl Into<String>, level: &str) {
        self.evidence.push(Evidence {
            code: code.into(),
            detail: detail.into(),
            level: level.into(),
        });
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RunState {
    pub id: String,
    pub stage: String,
    pub code: String,
    pub started_at: String,
    pub updated_at: String,
    pub target_version: String,
    pub before_version: String,
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub percent: Option<f64>,
    pub deployed: bool,
    pub running: bool,
    pub prompt: String,
    pub message: Option<String>,
    pub worker_alive: bool,
}
impl RunState {
    pub fn terminal(&self) -> bool {
        matches!(
            self.stage.as_str(),
            "complete" | "failed" | "cancelled" | "interrupted"
        )
    }
    pub fn can_cancel(&self) -> bool {
        matches!(
            self.stage.as_str(),
            "preparing" | "downloading" | "validating" | "closing" | "waiting_for_exit"
        )
    }
}
#[derive(Serialize)]
pub struct Snapshot {
    pub diagnosis: Option<Diagnosis>,
    pub run: Option<RunState>,
    pub history: Vec<RunState>,
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub id: String,
    pub target_version: String,
    pub sid: String,
    #[serde(default)]
    pub resume: bool,
    #[serde(default)]
    pub fresh_download: bool,
}

pub fn version(s: &str) -> Result<[u32; 4], String> {
    let mut out = [0; 4];
    let parts: Vec<_> = s.split('.').collect();
    if parts.len() != 4 {
        return Err("Expected a four-part MSIX version".into());
    }
    for (i, part) in parts.iter().enumerate() {
        if part.is_empty() || !part.bytes().all(|c| c.is_ascii_digit()) {
            return Err("Invalid MSIX version".into());
        }
        out[i] = part.parse().map_err(|_| "Invalid MSIX version component")?;
        if out[i] > u16::MAX as u32 {
            return Err("MSIX version component exceeds 65535".into());
        }
    }
    Ok(out)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compares_numerically() {
        assert!(version("26.1016.8622.0").unwrap() > version("26.1016.6573.0").unwrap());
        assert!(version("1.10.0.0").unwrap() > version("1.9.0.0").unwrap());
    }
    #[test]
    fn rejects_non_versions() {
        for s in [
            "1.2.3",
            "1.2.3.-4",
            "1.2.3.4/msix",
            "1.2..4",
            "1.2.3.999999999999999",
        ] {
            assert!(version(s).is_err());
        }
    }
    #[test]
    fn older_saved_requests_do_not_enable_recovery_or_skip_staging_checks() {
        let request: Request =
            serde_json::from_str(r#"{"id":"test","targetVersion":"1.2.3.4","sid":"test"}"#)
                .unwrap();
        assert!(!request.resume);
        assert!(!request.fresh_download);
    }
}
