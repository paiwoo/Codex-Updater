use crate::model::{version, Offer};
use reqwest::{blocking::Client, redirect::Policy, Url};
use serde::Deserialize;
use std::time::Duration;

pub const RELEASE: &str = "https://persistent.oaistatic.com/codex-app-prod/windows-release.json";
pub const STORE: &str = "https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json";
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Release {
    schema_version: u32,
    package_version: String,
    release_date: Option<String>,
    packages: Vec<Download>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Download {
    architecture: String,
    download_url: String,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Store {
    schema_version: u32,
    build_version: String,
    store_product_id: String,
    package_identity: String,
}

pub fn trusted_url(url: &Url) -> bool {
    url.scheme() == "https"
        && url.host_str() == Some("persistent.oaistatic.com")
        && url.port_or_known_default() == Some(443)
        && url.username().is_empty()
        && url.password().is_none()
        && url.fragment().is_none()
}
pub fn download_url(raw: &str, target: &str, arch: &str) -> Result<String, String> {
    version(target)?;
    if !["x64", "arm64"].contains(&arch) {
        return Err("Unsupported download architecture".into());
    }
    let url = Url::parse(raw).map_err(|_| "Invalid official download URL")?;
    let expected = format!("/codex-app-prod/releases/{target}/ChatGPT-{arch}.msix");
    if !trusted_url(&url) || url.path() != expected || url.query().is_some() {
        return Err("Unexpected official download URL, version, or architecture".into());
    }
    Ok(url.to_string())
}
pub fn client(timeout: Duration) -> Result<Client, String> {
    Client::builder()
        .connect_timeout(Duration::from_secs(15))
        // Use the blocking client's timeout, which also bounds blocking reads.
        // Async read_timeout would poll a Tokio timer outside its reactor here.
        .timeout(timeout)
        .user_agent(concat!("CodexUpdater/", env!("CARGO_PKG_VERSION")))
        .redirect(Policy::custom(|attempt| {
            if attempt.previous().len() >= 4 || !trusted_url(attempt.url()) {
                attempt.error("Unexpected redirect from official source")
            } else {
                attempt.follow()
            }
        }))
        .build()
        .map_err(|e| e.to_string())
}
fn small_json<T: serde::de::DeserializeOwned>(client: &Client, url: &str) -> Result<T, String> {
    use std::io::Read;
    let response = client
        .get(url)
        .send()
        .map_err(request_error)?
        .error_for_status()
        .map_err(request_error)?;
    if !trusted_url(response.url()) {
        return Err("Unexpected release source".into());
    }
    let mut bytes = vec![];
    response
        .take(1_048_577)
        .read_to_end(&mut bytes)
        .map_err(|_| "Could not read official release data")?;
    if bytes.len() > 1_048_576 {
        return Err("Official release response is too large".into());
    }
    serde_json::from_slice(&bytes).map_err(|_| "Unsupported official release response".into())
}
fn request_error(error: reqwest::Error) -> String {
    if error.is_timeout() {
        "Official release request timed out. Check your connection or proxy and retry".into()
    } else if let Some(status) = error.status() {
        format!("Official release source returned HTTP {}", status.as_u16())
    } else if error.is_redirect() {
        "Official release redirect was rejected or exceeded the redirect limit".into()
    } else if error.is_connect() {
        // Keep proxy addresses and credentials out of diagnostic messages.
        "Could not establish a secure connection to the official release source. Check network, proxy, and certificate settings".into()
    } else {
        "Could not read the official release response. Retry the check".into()
    }
}
pub fn fetch(arch: &str) -> Result<(Offer, Option<String>), String> {
    let c = client(Duration::from_secs(30))?;
    let release: Release = small_json(&c, RELEASE)?;
    let mut offer = parse_release(release, arch)?;
    let store = small_json::<Store>(&c, STORE).and_then(parse_store);
    let warning = match store {
        Ok(s) => {
            offer.store_version = Some(s);
            None
        }
        Err(_) => Some("store_unavailable".into()),
    };
    Ok((offer, warning))
}
fn parse_release(release: Release, arch: &str) -> Result<Offer, String> {
    if release.schema_version != 1 {
        return Err("Unsupported official release schema".into());
    }
    version(&release.package_version)?;
    let packages: Vec<_> = release
        .packages
        .into_iter()
        .filter(|p| p.architecture == arch || (arch == "x64" && p.architecture == "x86_64"))
        .collect();
    if packages.len() != 1 {
        return Err(
            "The release source must offer exactly one package for this architecture".into(),
        );
    }
    let url = download_url(&packages[0].download_url, &release.package_version, arch)?;
    Ok(Offer {
        version: release.package_version,
        architecture: arch.into(),
        url,
        store_version: None,
        released_at: release.release_date,
    })
}
fn parse_store(store: Store) -> Result<String, String> {
    if store.schema_version != 1
        || store.package_identity != "OpenAI.Codex"
        || store.store_product_id != "9PLM9XGG6VKS"
    {
        return Err("Unexpected Store update identity".into());
    }
    version(&store.build_version)?;
    Ok(store.build_version)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn http_diagnostics_include_status_without_disclosing_urls() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let _ = stream.read(&mut [0; 1024]);
            stream.write_all(b"HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
        });
        let error = client(Duration::from_secs(3))
            .unwrap()
            .get(format!("http://{addr}/private-path"))
            .send()
            .unwrap()
            .error_for_status()
            .unwrap_err();
        assert_eq!(
            request_error(error),
            "Official release source returned HTTP 407"
        );
        server.join().unwrap();
    }
    #[test]
    fn blocking_response_body_can_be_read_without_a_tokio_runtime() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buf = [0; 1024];
            let _ = stream.read(&mut buf);
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
                .unwrap();
        });
        let mut response = client(Duration::from_secs(3))
            .unwrap()
            .get(format!("http://{addr}"))
            .send()
            .unwrap();
        let mut body = String::new();
        response.read_to_string(&mut body).unwrap();
        assert_eq!(body, "{}");
        server.join().unwrap();
    }
    #[test]
    fn rejects_urls_that_escape_the_expected_package() {
        let target = "26.1016.8622.0";
        assert!(download_url(&format!("https://persistent.oaistatic.com/codex-app-prod/releases/{target}/ChatGPT-x64.msix"),target,"x64").is_ok());
        for bad in ["http://persistent.oaistatic.com/codex-app-prod/releases/26.1016.8622.0/ChatGPT-x64.msix","https://evil.example/codex-app-prod/releases/26.1016.8622.0/ChatGPT-x64.msix","https://user@persistent.oaistatic.com/codex-app-prod/releases/26.1016.8622.0/ChatGPT-x64.msix","https://persistent.oaistatic.com/codex-app-prod/releases/26.1016.8622.0/ChatGPT-arm64.msix","https://persistent.oaistatic.com/codex-app-prod/releases/26.1016.6573.0/ChatGPT-x64.msix","https://persistent.oaistatic.com/codex-app-prod/releases/26.1016.8622.0/ChatGPT-x64.msix?other=1"]{assert!(download_url(bad,target,"x64").is_err(),"{bad}");}
    }
    #[test]
    fn validates_store_identity() {
        assert!(parse_store(Store {
            schema_version: 1,
            build_version: "26.1016.8622.0".into(),
            store_product_id: "wrong".into(),
            package_identity: "OpenAI.Codex".into()
        })
        .is_err());
    }
    #[test]
    fn refuses_duplicate_architecture_packages() {
        let raw = r#"{"schemaVersion":1,"packageVersion":"1.2.3.4","packages":[{"architecture":"x64","downloadUrl":"https://persistent.oaistatic.com/codex-app-prod/releases/1.2.3.4/ChatGPT-x64.msix"},{"architecture":"x64","downloadUrl":"https://persistent.oaistatic.com/codex-app-prod/releases/1.2.3.4/ChatGPT-x64.msix"}]}"#;
        assert!(parse_release(serde_json::from_str(raw).unwrap(), "x64").is_err());
    }
}
