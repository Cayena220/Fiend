//! Machine facts and small shell actions.

use crate::{paths, threats, win};
use serde_json::{json, Value};
use std::os::windows::process::CommandExt;
use std::path::Path;
use std::process::Command;
use winreg::enums::HKEY_LOCAL_MACHINE;
use winreg::RegKey;

pub fn info() -> Value {
    let cv = RegKey::predef(HKEY_LOCAL_MACHINE).open_subkey(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion").ok();
    let read = |name: &str| cv.as_ref().and_then(|k| k.get_value::<String, _>(name).ok()).unwrap_or_default();
    let build: u32 = read("CurrentBuild").parse().unwrap_or(0);
    let mut product = read("ProductName");
    // The registry still says "Windows 10" on Windows 11.
    if build >= 22000 {
        product = product.replace("Windows 10", "Windows 11");
    }
    json!({
        "os": product,
        "version": read("DisplayVersion"),
        "build": build,
        "computer": std::env::var("COMPUTERNAME").unwrap_or_default(),
        "user": std::env::var("USERNAME").unwrap_or_default(),
        "cpus": std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1),
        "admin": win::is_admin(),
        "defender": threats::defender::locate().is_some(),
        "data_dir": paths::data_dir().display().to_string(),
        "core_version": env!("CARGO_PKG_VERSION"),
        "app_version": std::env::current_exe().ok().and_then(|exe| win::file_version(&exe)),
        "exe_path": std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default(),
    })
}

/// Restarts the current process elevated. The caller should exit after this succeeds.
pub fn relaunch_admin() -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    if win::shell_execute("runas", &exe, "") {
        Ok(())
    } else {
        Err("Windows didn't start Fiend as administrator. The request may have been declined.".into())
    }
}

/// Hands a downloaded installer to a hidden helper that waits for this process to exit
/// (the installer refuses to run while Fiend holds its app mutex), then runs it silently.
/// The installer's /UPDATE switch reopens Fiend when it's done. The caller should exit next.
pub fn install_update(installer: &Path) -> Result<(), String> {
    let ok_name = installer
        .file_name()
        .map(|n| n.to_string_lossy().to_lowercase())
        .is_some_and(|n| n.starts_with("fiend-") && n.ends_with("-setup.exe"));
    if !ok_name || !installer.is_file() {
        return Err("That isn't a Fiend installer".into());
    }
    let quote = |p: &Path| p.display().to_string().replace('\'', "''");
    // Logs sit next to the installer, so a failed update can be diagnosed.
    let dir = installer.parent().unwrap_or(Path::new("."));
    let log = dir.join("update.log");
    let setup_log = dir.join("setup.log");
    let script = format!(
        "$log = '{log}'; \
         try {{ \
           Wait-Process -Id {pid} -Timeout 60 -ErrorAction SilentlyContinue; \
           \"$(Get-Date -Format s) Fiend closed, starting {name}\" | Out-File $log -Append -Encoding utf8; \
           Start-Process -FilePath '{path}' -ArgumentList '/SILENT','/SP-','/NOCANCEL','/SUPPRESSMSGBOXES','/UPDATE','/LOG=\"{setup_log}\"' -ErrorAction Stop \
         }} catch {{ \"$(Get-Date -Format s) $_\" | Out-File $log -Append -Encoding utf8 }}",
        log = quote(&log),
        pid = std::process::id(),
        name = crate::util::file_name(installer).replace('\'', "''"),
        path = quote(installer),
        setup_log = quote(&setup_log),
    );
    Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", &script])
        .creation_flags(0x0800_0000) // CREATE_NO_WINDOW: a hidden console, which PowerShell needs
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("Couldn't start the installer: {e}"))
}

/// Opens Explorer with the item selected.
pub fn reveal(path: &Path) -> Result<(), String> {
    let arg = format!("/select,\"{}\"", path.display());
    Command::new("explorer.exe")
        .raw_arg(arg)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("Couldn't open Explorer: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_anything_but_a_fiend_installer() {
        let dir = tempfile::tempdir().unwrap();
        let other = dir.path().join("evil.exe");
        std::fs::write(&other, b"MZ").unwrap();
        assert!(install_update(&other).is_err());
        assert!(install_update(&dir.path().join("Fiend-9.9.9-setup.exe")).is_err(), "must exist");
    }

    #[test]
    fn reads_version_resources() {
        // Windows' own binaries always carry one; the test binary does not.
        let notepad = crate::paths::windows_dir().join(r"System32\notepad.exe");
        if notepad.exists() {
            let v = win::file_version(&notepad).expect("notepad has a version");
            assert_eq!(v.split('.').count(), 3);
        }
    }
}
