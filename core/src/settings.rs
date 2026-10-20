//! Every user customization lives here and is stored in `%APPDATA%\Fiend\settings.json`.

use crate::paths;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::path::Path;

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
#[serde(default)]
pub struct Settings {
    pub appearance: Appearance,
    pub dashboard: Dashboard,
    pub cleaner: Cleaner,
    pub shield: Shield,
    pub disk: DiskPrefs,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Appearance {
    /// Preset name (hellfire, ember, toxic, spectral, ice) or "custom".
    pub accent: String,
    pub custom_accent: String,
    /// abyss, midnight or slate.
    pub depth: String,
    /// compact or comfortable.
    pub density: String,
    pub radius: f64,
    pub glow: bool,
    pub reduce_motion: bool,
}

impl Default for Appearance {
    fn default() -> Self {
        Self {
            accent: "hellfire".into(),
            custom_accent: "#FF3B4E".into(),
            depth: "abyss".into(),
            density: "comfortable".into(),
            radius: 10.0,
            glow: true,
            reduce_motion: false,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Dashboard {
    pub cards: Vec<String>,
    pub hidden: Vec<String>,
}

impl Default for Dashboard {
    fn default() -> Self {
        Self {
            cards: ["health", "drives", "cache", "shield", "actions"]
                .map(String::from)
                .to_vec(),
            hidden: vec![],
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Cleaner {
    /// Category ids that are ticked by default.
    pub enabled: Vec<String>,
    /// Only files older than this are removed.
    pub min_age_hours: u64,
    pub custom_paths: Vec<CustomPath>,
    pub exclusions: Vec<String>,
}

impl Default for Cleaner {
    fn default() -> Self {
        Self {
            enabled: [
                "user_temp",
                "windows_temp",
                "thumbnails",
                "shader_cache",
                "crash_dumps",
                "error_reports",
                "browser_chrome",
                "browser_edge",
                "browser_brave",
                "browser_firefox",
            ]
            .map(String::from)
            .to_vec(),
            min_age_hours: 24,
            custom_paths: vec![],
            exclusions: vec![],
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
#[serde(default)]
pub struct CustomPath {
    pub name: String,
    pub path: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Shield {
    /// low, balanced or paranoid.
    pub sensitivity: String,
    /// Extra folders added to a quick scan.
    pub extra_locations: Vec<String>,
    pub exclusions: Vec<String>,
    /// SHA-256 hashes (or full paths) the user marked as safe.
    pub allowlist: Vec<String>,
    pub use_defender: bool,
    pub auto_quarantine: bool,
    pub scan_on_launch: bool,
    pub verify_signatures: bool,
    pub max_file_mb: u64,
}

impl Default for Shield {
    fn default() -> Self {
        Self {
            sensitivity: "balanced".into(),
            extra_locations: vec![],
            exclusions: vec![],
            allowlist: vec![],
            use_defender: true,
            auto_quarantine: false,
            scan_on_launch: false,
            verify_signatures: true,
            max_file_mb: 200,
        }
    }
}

impl Shield {
    /// Minimum score a file needs before it is reported.
    pub fn threshold(&self) -> i32 {
        match self.sensitivity.as_str() {
            "low" => 50,
            "paranoid" => 15,
            _ => 30,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct DiskPrefs {
    pub large_file_mb: u64,
    pub top_files: usize,
}

impl Default for DiskPrefs {
    fn default() -> Self {
        Self {
            large_file_mb: 500,
            top_files: 50,
        }
    }
}

/// Things Fiend remembers between runs (not user choices).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
#[serde(default)]
pub struct State {
    pub last_scan_at: Option<u64>,
    pub last_scan_mode: String,
    pub last_scan_files: u64,
    pub last_scan_findings: u64,
    pub last_clean_at: Option<u64>,
    pub total_freed: u64,
    pub signatures_updated_at: Option<u64>,
}

fn read_json<T: DeserializeOwned + Default>(path: &Path) -> T {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

/// Writes through a temp file so a crash never leaves half a settings file.
fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let tmp = path.with_extension("json.tmp");
    let text = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    std::fs::write(&tmp, text).map_err(|e| format!("Could not save {}: {e}", path.display()))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("Could not save {}: {e}", path.display()))
}

pub fn load() -> Settings {
    read_json(&paths::data_dir().join("settings.json"))
}

pub fn save(settings: &Settings) -> Result<(), String> {
    write_json(&paths::data_dir().join("settings.json"), settings)
}

pub fn load_state() -> State {
    read_json(&paths::data_dir().join("state.json"))
}

pub fn update_state(change: impl FnOnce(&mut State)) -> Result<State, String> {
    let mut state = load_state();
    change(&mut state);
    write_json(&paths::data_dir().join("state.json"), &state)?;
    Ok(state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_json_fills_defaults() {
        let s: Settings = serde_json::from_str(r#"{"appearance":{"accent":"toxic"}}"#).unwrap();
        assert_eq!(s.appearance.accent, "toxic");
        assert_eq!(s.appearance.depth, "abyss");
        assert_eq!(s.cleaner.min_age_hours, 24);
        assert_eq!(s.shield.threshold(), 30);
    }

    #[test]
    fn roundtrip_through_disk() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let mut s = Settings::default();
        s.shield.sensitivity = "paranoid".into();
        write_json(&path, &s).unwrap();
        let back: Settings = read_json(&path);
        assert_eq!(back, s);
        assert_eq!(back.shield.threshold(), 15);
    }
}
