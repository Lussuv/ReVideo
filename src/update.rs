use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};

/// Public repo holding only the release files; the source repo stays private.
const LATEST: &str = "https://api.github.com/repos/Lussuv/ReVideo-releases/releases/latest";

#[derive(Debug, Clone)]
pub struct Update {
    pub version: String,
    pub page: String,
    /// Windows only: installer URL and its SHA-256 (hex) from the release.
    pub installer: Option<(String, String)>,
}

#[derive(Deserialize)]
struct Release {
    tag_name: String,
    html_url: String,
    assets: Vec<Asset>,
}

#[derive(Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
    /// "sha256:<hex>", computed by GitHub on upload.
    digest: Option<String>,
}

/// Newer release than the running one, if any. Offline or API errors count as "none".
pub async fn check() -> Option<Update> {
    tokio::task::spawn_blocking(|| {
        latest()
            .inspect_err(|e| eprintln!("Update-Prüfung fehlgeschlagen: {e}"))
            .ok()
            .flatten()
    })
    .await
    .ok()
    .flatten()
}

fn latest() -> Result<Option<Update>, ureq::Error> {
    let release: Release = ureq::get(LATEST)
        .header("User-Agent", "ReVideo")
        .call()?
        .body_mut()
        .read_json()?;
    let version = release.tag_name.trim_start_matches('v');
    if !is_newer(version, env!("CARGO_PKG_VERSION")) {
        return Ok(None);
    }
    let installer = cfg!(windows)
        .then(|| {
            release
                .assets
                .iter()
                .find(|a| a.name.ends_with("-setup.exe"))
        })
        .flatten()
        .and_then(|a| {
            let hash = a.digest.as_deref()?.strip_prefix("sha256:")?;
            Some((a.browser_download_url.clone(), hash.to_lowercase()))
        });
    Ok(Some(Update {
        version: version.to_string(),
        page: release.html_url,
        installer,
    }))
}

fn is_newer(candidate: &str, current: &str) -> bool {
    let parse = |v: &str| -> Option<Vec<u32>> { v.split('.').map(|p| p.parse().ok()).collect() };
    matches!((parse(candidate), parse(current)), (Some(c), Some(r)) if c > r)
}

pub fn open_page(url: &str) -> Result<(), String> {
    let opener = if cfg!(windows) {
        "explorer"
    } else {
        "xdg-open"
    };
    std::process::Command::new(opener)
        .arg(url)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("Browser konnte nicht geöffnet werden: {e}"))
}

/// Downloads and verifies the installer, then starts it silently. The installer
/// waits for this process to exit and launches the new version afterwards.
pub async fn install(url: String, sha256: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let path = crate::ffmpeg::temp_subdir("update")
            .map_err(|e| e.to_string())?
            .join("ReVideo-setup.exe");
        download(&url, &sha256, &path)?;
        let mut cmd = std::process::Command::new(&path);
        cmd.arg("/S");
        #[cfg(windows)]
        std::os::windows::process::CommandExt::creation_flags(&mut cmd, 0x0800_0000); // CREATE_NO_WINDOW
        cmd.spawn()
            .map(|_| ())
            .map_err(|e| format!("Installer konnte nicht gestartet werden: {e}"))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn download(url: &str, sha256: &str, path: &std::path::Path) -> Result<(), String> {
    let fail = |e: &dyn std::fmt::Display| format!("Update-Download fehlgeschlagen: {e}");
    let mut response = ureq::get(url)
        .header("User-Agent", "ReVideo")
        .call()
        .map_err(|e| fail(&e))?;
    let mut reader = response.body_mut().as_reader();
    let mut file = std::fs::File::create(path).map_err(|e| fail(&e))?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0; 1 << 16];
    loop {
        let n = reader.read(&mut buf).map_err(|e| fail(&e))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        file.write_all(&buf[..n]).map_err(|e| fail(&e))?;
    }
    let actual: String = hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    if actual != sha256 {
        let _ = std::fs::remove_file(path);
        return Err("Update verworfen: Prüfsumme stimmt nicht.".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::is_newer;

    #[test]
    fn compares_versions_numerically() {
        assert!(is_newer("3.1.1", "3.1.0"));
        assert!(is_newer("3.10.0", "3.9.0"));
        assert!(is_newer("4.0.0", "3.99.99"));
        assert!(!is_newer("3.1.0", "3.1.0"));
        assert!(!is_newer("3.0.9", "3.1.0"));
        assert!(!is_newer("3.2.0-beta", "3.1.0"));
    }
}
