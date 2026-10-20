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

/// Opens Explorer with the item selected.
pub fn reveal(path: &Path) -> Result<(), String> {
    let arg = format!("/select,\"{}\"", path.display());
    Command::new("explorer.exe")
        .raw_arg(arg)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("Couldn't open Explorer: {e}"))
}
