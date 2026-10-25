use crate::{
    feed,
    model::{version, Diagnosis, Offer},
    platform, storage,
};
use serde_json::json;
use std::{thread, time::Duration};

pub fn diagnose(include_prompt: bool) -> Diagnosis {
    let mut d = Diagnosis {
        checked_at: storage::now(),
        package: None,
        offer: None,
        staged: false,
        supported: false,
        update_available: None,
        prompt: "unverified".into(),
        evidence: vec![],
    };
    match platform::inspect() {
        Ok(Some(p)) => {
            d.evidence("package_found", &p.version, "info");
            d.supported = p.architecture == "x64";
            if !d.supported {
                d.evidence("unsupported_arch", &p.architecture, "warning");
            }
            d.evidence(
                if p.processes.is_empty() {
                    "app_closed"
                } else {
                    "app_running"
                },
                p.processes.len().to_string(),
                if p.processes.is_empty() {
                    "info"
                } else {
                    "warning"
                },
            );
            d.package = Some(p);
        }
        Ok(None) => {
            d.evidence("package_missing", "", "error");
            return d;
        }
        Err(e) => {
            d.evidence("unsupported_install", e, "error");
            return d;
        }
    }
    let arch = d.package.as_ref().unwrap().architecture.clone();
    let feed_thread = thread::spawn(move || feed::fetch(&arch));
    let events = platform::operation("Events", json!({}), Some(Duration::from_secs(12)));
    if let Ok(events) = events {
        if events["blocked"] == true {
            d.evidence(
                "registration_blocked",
                events["time"].as_str().unwrap_or("").to_string(),
                "warning",
            );
        }
    }
    let fetched = feed_thread
        .join()
        .unwrap_or_else(|_| Err("Official release check failed".into()));
    match fetched {
        Ok((mut offer, warning)) => {
            if let Some(code) = warning {
                d.evidence(&code, "", "warning");
            }
            if let Some(store) = &offer.store_version {
                if store == &offer.version {
                    d.evidence("feeds_agree", &offer.version, "info");
                } else {
                    d.evidence(
                        "feeds_differ",
                        format!("direct: {}; Store: {}", offer.version, store),
                        "warning",
                    );
                }
            }
            let installed = d.package.as_ref().unwrap().version.clone();
            // A newer Store version may only be used if Windows has actually staged it.
            // Never synthesize a download URL for a version absent from the direct feed.
            if let Some(store) = offer.store_version.clone() {
                if version(&store).ok() > version(&offer.version).ok()
                    && version(&store).ok() > version(&installed).ok()
                {
                    if staged(&store) {
                        offer.version = store;
                        offer.url.clear();
                        d.staged = true;
                    } else {
                        d.evidence("channel_pending", store, "warning");
                    }
                }
            }
            if let (Ok(local), Ok(target)) = (version(&installed), version(&offer.version)) {
                if local < target {
                    d.update_available = Some(true);
                    if !d.staged {
                        d.staged = staged(&offer.version);
                    }
                    d.evidence(
                        if d.staged {
                            "staged_ready"
                        } else {
                            "stage_absent"
                        },
                        &offer.version,
                        "info",
                    );
                } else if offer
                    .store_version
                    .as_ref()
                    .and_then(|s| version(s).ok())
                    .is_some_and(|store| local < store)
                {
                    d.update_available = None;
                } else {
                    d.update_available = Some(false);
                    if local > target {
                        d.evidence("source_behind", installed, "info");
                    }
                }
            }
            d.offer = Some(offer);
        }
        Err(e) => d.evidence("feed_unavailable", e, "error"),
    }
    if include_prompt {
        d.prompt = platform::prompt();
        d.evidence(
            if d.prompt == "visible" {
                "prompt_visible"
            } else if d.prompt == "not_detected" {
                "prompt_not_detected"
            } else {
                "prompt_unverified"
            },
            "",
            "info",
        );
    }
    d
}
pub fn staged(target: &str) -> bool {
    platform::operation(
        "Staged",
        json!({"targetVersion":target}),
        Some(Duration::from_secs(12)),
    )
    .map(|v| v["exists"] == true)
    .unwrap_or(false)
}
pub fn can_start<'a>(
    d: &'a Diagnosis,
    target: &str,
) -> Result<(&'a crate::model::PackageInfo, &'a Offer), String> {
    let p = d
        .package
        .as_ref()
        .ok_or("Official Codex is not installed")?;
    let offer = d
        .offer
        .as_ref()
        .ok_or("Official release version is not known")?;
    if !d.supported || p.architecture != "x64" {
        return Err("This preview only repairs Windows x64 installations".into());
    }
    if d.update_available != Some(true)
        || offer.version != target
        || version(target)? <= version(&p.version)?
    {
        return Err("The repair plan has changed. Check for updates again".into());
    }
    Ok((p, offer))
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::PackageInfo;
    fn plan() -> Diagnosis {
        Diagnosis {
            checked_at: String::new(),
            package: Some(PackageInfo {
                name: "OpenAI.Codex".into(),
                version: "26.1016.6573.0".into(),
                architecture: "x64".into(),
                publisher: String::new(),
                family: String::new(),
                location: String::new(),
                app_id: "App".into(),
                processes: vec![],
            }),
            offer: Some(Offer {
                version: "26.1016.8622.0".into(),
                architecture: "x64".into(),
                url: String::new(),
                store_version: None,
                released_at: None,
            }),
            staged: true,
            supported: true,
            update_available: Some(true),
            prompt: "unverified".into(),
            evidence: vec![],
        }
    }
    #[test]
    fn accepts_only_the_reviewed_target() {
        let d = plan();
        assert!(can_start(&d, "26.1016.8622.0").is_ok());
        assert!(can_start(&d, "26.1016.9999.0").is_err());
    }
    #[test]
    fn unknown_and_current_versions_cannot_start_repair() {
        for status in [None, Some(false)] {
            let mut d = plan();
            d.update_available = status;
            assert!(can_start(&d, "26.1016.8622.0").is_err());
        }
    }
    #[test]
    fn unverified_architecture_and_downgrades_are_blocked() {
        let mut d = plan();
        d.package.as_mut().unwrap().architecture = "arm64".into();
        assert!(can_start(&d, "26.1016.8622.0").is_err());
        let mut d = plan();
        d.package.as_mut().unwrap().version = "26.1016.9999.0".into();
        assert!(can_start(&d, "26.1016.8622.0").is_err());
    }
}
