//! Second opinion from the Microsoft Defender engine built into Windows.

use crate::paths;
use serde::Serialize;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct DefenderResult {
    /// clean, threat, error or unavailable
    pub status: String,
    pub threat: Option<String>,
    pub detail: String,
}

/// Newest MpCmdRun.exe from the Defender platform folder, else the inbox copy.
pub fn locate() -> Option<PathBuf> {
    let platform = paths::program_data().join(r"Microsoft\Windows Defender\Platform");
    let mut versions: Vec<PathBuf> = std::fs::read_dir(&platform)
        .map(|rd| rd.flatten().map(|e| e.path()).filter(|p| p.join("MpCmdRun.exe").is_file()).collect())
        .unwrap_or_default();
    versions.sort_by_key(|p| version_key(p));
    if let Some(latest) = versions.pop() {
        return Some(latest.join("MpCmdRun.exe"));
    }
    let inbox = PathBuf::from(std::env::var("ProgramFiles").unwrap_or_else(|_| r"C:\Program Files".into()))
        .join(r"Windows Defender\MpCmdRun.exe");
    inbox.is_file().then_some(inbox)
}

/// "4.18.25080.5-0" -> [4, 18, 25080, 5, 0] so folders sort by real version.
fn version_key(p: &Path) -> Vec<u64> {
    p.file_name()
        .map(|n| n.to_string_lossy().split(['.', '-']).map(|s| s.parse().unwrap_or(0)).collect())
        .unwrap_or_default()
}

/// Pulls the threat name out of MpCmdRun output.
pub fn parse_threat(output: &str) -> Option<String> {
    output.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        (key.trim().eq_ignore_ascii_case("threat") && !value.trim().is_empty()).then(|| value.trim().to_string())
    })
}

/// Scans one file without letting Defender remove it (Fiend quarantines instead).
pub fn scan_file(path: &Path) -> DefenderResult {
    let Some(exe) = locate() else {
        return DefenderResult { status: "unavailable".into(), threat: None, detail: "Microsoft Defender isn't available on this PC".into() };
    };
    let output = Command::new(exe)
        .args(["-Scan", "-ScanType", "3", "-File"])
        .arg(path)
        .arg("-DisableRemediation")
        .creation_flags(CREATE_NO_WINDOW)
        .output();
    match output {
        Ok(out) => {
            let text = String::from_utf8_lossy(&out.stdout).to_string();
            match out.status.code() {
                Some(0) => DefenderResult { status: "clean".into(), threat: None, detail: "Defender found no threats".into() },
                Some(2) => {
                    let threat = parse_threat(&text);
                    DefenderResult {
                        status: "threat".into(),
                        detail: format!("Defender detected {}", threat.as_deref().unwrap_or("a threat")),
                        threat,
                    }
                }
                code => DefenderResult {
                    status: "error".into(),
                    threat: None,
                    detail: format!(
                        "Defender couldn't scan this file (exit code {}). Real-time protection may be managed by another antivirus.",
                        code.map(|c| c.to_string()).unwrap_or_else(|| "none".into())
                    ),
                },
            }
        }
        Err(e) => DefenderResult { status: "error".into(), threat: None, detail: format!("Couldn't start Defender: {e}") },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_threat_line() {
        let out = "Scan starting...\nScan finished.\nScanning C:\\x found 1 threats.\n\nThreat                  : Virus:DOS/EICAR_Test_File\nResources               : 1 total\n";
        assert_eq!(parse_threat(out).as_deref(), Some("Virus:DOS/EICAR_Test_File"));
        assert_eq!(parse_threat("Scan finished."), None);
    }

    #[test]
    fn versions_sort_numerically() {
        assert!(version_key(Path::new("4.18.10000.1-0")) > version_key(Path::new("4.18.9999.9-0")));
    }
}
