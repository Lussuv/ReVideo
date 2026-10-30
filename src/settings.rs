use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Kept between runs in `settings.json` under the user's config directory.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub volume: f64,
    pub muted: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            volume: 0.8,
            muted: false,
        }
    }
}

/// %APPDATA%\ReVideo on Windows, $XDG_CONFIG_HOME/revideo elsewhere
/// (inside Flatpak that points into ~/.var/app).
fn file() -> Option<PathBuf> {
    let dir = if cfg!(windows) {
        PathBuf::from(std::env::var_os("APPDATA")?).join("ReVideo")
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?
            .join("revideo")
    };
    Some(dir.join("settings.json"))
}

/// Missing or unreadable file counts as defaults.
pub fn load() -> Settings {
    file()
        .and_then(|f| std::fs::read(f).ok())
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

pub fn save(settings: Settings) {
    let Some(f) = file() else { return };
    let result = f
        .parent()
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| std::fs::write(&f, serde_json::to_vec(&settings).unwrap_or_default()));
    if let Err(e) = result {
        eprintln!("Einstellungen nicht gespeichert: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::Settings;

    #[test]
    fn missing_fields_fall_back_to_defaults() {
        let s: Settings = serde_json::from_str("{}").unwrap();
        assert_eq!(s, Settings::default());
        let s: Settings = serde_json::from_str(r#"{"volume":0.3}"#).unwrap();
        assert_eq!(s.volume, 0.3);
    }
}
