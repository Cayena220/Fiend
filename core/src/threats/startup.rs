//! Programs that start with Windows: Run keys, Startup folders and scheduled tasks.

use super::authenticode;
use super::{score, severity, Reason};
use crate::{paths, util};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use winreg::enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ, KEY_SET_VALUE};
use winreg::{RegKey, HKEY};

const RUN_KEYS: &[(&str, &str)] = &[
    ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run"),
    ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\RunOnce"),
    ("HKLM", r"SOFTWARE\Microsoft\Windows\CurrentVersion\Run"),
    ("HKLM", r"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"),
    ("HKLM", r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"),
];

#[derive(Serialize, Clone, Debug)]
pub struct StartupItem {
    pub id: String,
    pub name: String,
    pub command: String,
    pub target: Option<String>,
    pub location: String,
    pub source: String,
    pub exists: bool,
    pub signed: Option<&'static str>,
    pub score: i32,
    pub severity: &'static str,
    pub reasons: Vec<Reason>,
}

/// Disabled entries are kept here so they can be turned back on.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct DisabledItem {
    pub id: String,
    pub name: String,
    pub command: String,
    pub location: String,
    pub source: String,
    /// Where a Startup-folder file was moved to.
    pub stash: Option<String>,
    pub disabled_at: u64,
}

fn hive(name: &str) -> HKEY {
    if name == "HKLM" {
        HKEY_LOCAL_MACHINE
    } else {
        HKEY_CURRENT_USER
    }
}

/// The program a command line launches.
pub fn extract_target(command: &str) -> Option<String> {
    let cmd = paths::expand_env(command.trim());
    if let Some(rest) = cmd.strip_prefix('"') {
        return rest.split('"').next().map(str::to_string).filter(|s| !s.is_empty());
    }
    let lower = cmd.to_lowercase();
    for ext in [".exe", ".bat", ".cmd", ".com", ".scr", ".ps1", ".vbs", ".js"] {
        if let Some(i) = lower.find(ext) {
            let end = i + ext.len();
            if lower.as_bytes().get(end).is_none_or(|c| *c == b' ') {
                return Some(cmd[..end].to_string());
            }
        }
    }
    cmd.split_whitespace().next().map(str::to_string)
}

const LOLBINS: &[&str] = &["mshta", "wscript", "cscript", "rundll32", "regsvr32", "powershell", "pwsh", "cmd.exe", "certutil", "bitsadmin"];

/// Evidence from the command line itself.
pub fn command_signals(command: &str) -> Vec<Reason> {
    let lower = command.to_lowercase();
    let mut reasons = super::heuristics::content_signals(command);
    if let Some(bin) = LOLBINS.iter().find(|b| {
        let target = extract_target(command).unwrap_or_default().to_lowercase();
        target.ends_with(&format!("{b}.exe")) || target.ends_with(*b)
    }) {
        reasons.push(Reason::new("lolbin", format!("Starts through {bin}, which malware often borrows"), 15));
    }
    if lower.contains("http://") || lower.contains("https://") {
        reasons.push(Reason::new("url", "Command contains a web address", 15));
    }
    reasons
}

fn assess(command: &str, target: Option<&str>, verify: bool) -> (bool, Option<&'static str>, Vec<Reason>) {
    let mut reasons = command_signals(command);
    let mut exists = false;
    let mut signed = None;
    if let Some(t) = target {
        let p = Path::new(t);
        exists = p.is_file();
        let ext = util::ext_lower(p);
        let place = if paths::is_within(p, &paths::temp()) {
            Some("Temp")
        } else if paths::downloads().is_some_and(|d| paths::is_within(p, &d)) {
            Some("Downloads")
        } else if paths::is_within(p, &paths::public()) {
            Some("Public")
        } else {
            None
        };
        if let Some(place) = place {
            reasons.push(Reason::new("location", format!("Starts a program from {place}"), 30));
        }
        if p.parent().is_some_and(|d| paths::norm(d) == paths::norm(&paths::roaming()) || paths::norm(d) == paths::norm(&paths::local_appdata())) {
            reasons.push(Reason::new("location", "Starts a program stored loose in AppData", 25));
        }
        if !exists && p.is_absolute() {
            reasons.push(Reason::new("missing", "The program it points to no longer exists", 5));
        }
        if exists && verify && super::heuristics::is_exec(&ext) {
            let trust = authenticode::verify(p);
            signed = Some(trust.as_str());
            match trust {
                authenticode::Trust::Signed => reasons.push(Reason::new("signed", "Signed by a verified publisher", -30)),
                authenticode::Trust::Unsigned if reasons.iter().any(|r| r.weight > 5) => reasons.push(Reason::new("unsigned", "Has no digital signature", 15)),
                authenticode::Trust::Untrusted(_) => reasons.push(Reason::new("bad_signature", "Digital signature is invalid or not trusted", 35)),
                authenticode::Trust::Expired => reasons.push(Reason::new("expired_signature", "Digital signature has expired", 5)),
                _ => {}
            }
        }
    }
    (exists, signed, reasons)
}

fn item(id: String, name: String, command: String, location: String, source: &str, verify: bool) -> StartupItem {
    let target = extract_target(&command);
    let (exists, signed, reasons) = assess(&command, target.as_deref(), verify);
    let score = score(&reasons);
    StartupItem { id, name, command, target, location, source: source.into(), exists, signed, score, severity: severity(score), reasons }
}

fn registry_items(verify: bool) -> Vec<StartupItem> {
    let mut items = Vec::new();
    for (hive_name, path) in RUN_KEYS {
        let Ok(key) = RegKey::predef(hive(hive_name)).open_subkey_with_flags(path, KEY_READ) else { continue };
        for (name, _) in key.enum_values().flatten() {
            let Ok(command) = key.get_value::<String, _>(&name) else { continue };
            let short = path.rsplit('\\').next().unwrap_or(path);
            items.push(item(
                format!("reg|{hive_name}|{path}|{name}"),
                name.clone(),
                command,
                format!("{hive_name} {short}"),
                "registry",
                verify,
            ));
        }
    }
    items
}

fn folder_items(verify: bool) -> Vec<StartupItem> {
    let mut items = Vec::new();
    for (folder, label) in [(paths::startup_user(), "Your Startup folder"), (paths::startup_common(), "All users Startup folder")] {
        let Ok(rd) = std::fs::read_dir(&folder) else { continue };
        for entry in rd.flatten() {
            let p = entry.path();
            if !p.is_file() || util::file_name(&p).eq_ignore_ascii_case("desktop.ini") {
                continue;
            }
            let mut it = item(
                format!("folder|{}", p.display()),
                util::file_name(&p),
                p.display().to_string(),
                label.into(),
                "folder",
                verify,
            );
            let ext = util::ext_lower(&p);
            if ext != "lnk" && ext != "url" {
                it.reasons.push(Reason::new("startup_file", "A program or script placed directly in a Startup folder", 20));
                it.score = score(&it.reasons);
                it.severity = severity(it.score);
            }
            items.push(it);
        }
    }
    items
}

/// Splits one CSV line from schtasks into fields.
pub fn parse_csv_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut cur = String::new();
    let mut quoted = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '"' if quoted && chars.peek() == Some(&'"') => {
                cur.push('"');
                chars.next();
            }
            '"' => quoted = !quoted,
            ',' if !quoted => fields.push(std::mem::take(&mut cur)),
            _ => cur.push(c),
        }
    }
    fields.push(cur);
    fields
}

fn task_items(verify: bool) -> Vec<StartupItem> {
    let Ok(out) = Command::new("schtasks.exe")
        .args(["/query", "/fo", "csv", "/v", "/nh"])
        .creation_flags(0x0800_0000)
        .output()
    else {
        return vec![];
    };
    let text = String::from_utf8_lossy(&out.stdout);
    let mut seen = HashSet::new();
    let mut items = Vec::new();
    // Columns in verbose CSV: 1 TaskName, 7 Author, 8 Task To Run, 11 Scheduled Task State.
    for line in text.lines() {
        let f = parse_csv_line(line);
        if f.len() < 12 {
            continue;
        }
        let name = f[1].trim().to_string();
        let run = f[8].trim().to_string();
        if name.is_empty() || name.starts_with(r"\Microsoft\") || run.is_empty() || run.eq_ignore_ascii_case("COM handler") || !seen.insert(name.clone()) {
            continue;
        }
        if f[11].trim().eq_ignore_ascii_case("disabled") {
            continue;
        }
        items.push(item(format!("task|{name}"), name.trim_start_matches('\\').to_string(), run, "Task Scheduler".into(), "task", verify));
    }
    items
}

pub fn list(verify: bool) -> Vec<StartupItem> {
    let mut items = registry_items(verify);
    items.extend(folder_items(verify));
    items.extend(task_items(verify));
    items.sort_by(|a, b| b.score.cmp(&a.score).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    items
}

fn backup_path() -> PathBuf {
    paths::data_dir().join("disabled_startup.json")
}

pub fn disabled() -> Vec<DisabledItem> {
    std::fs::read_to_string(backup_path()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn save_disabled(items: &[DisabledItem]) -> Result<(), String> {
    paths::ensure_data_dir();
    std::fs::write(backup_path(), serde_json::to_string_pretty(items).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

fn admin_hint(e: std::io::Error) -> String {
    if e.kind() == std::io::ErrorKind::PermissionDenied {
        "Windows needs administrator rights to change this item. Restart Fiend as administrator and try again.".into()
    } else {
        e.to_string()
    }
}

/// Turns a startup item off and remembers it so it can be restored.
pub fn disable(id: &str) -> Result<(), String> {
    let mut list = disabled();
    let parts: Vec<&str> = id.splitn(4, '|').collect();
    let mut record = DisabledItem { id: id.into(), name: String::new(), command: String::new(), location: String::new(), source: parts[0].into(), stash: None, disabled_at: util::now_secs() };
    match parts.as_slice() {
        ["reg", hive_name, path, name] => {
            let key = RegKey::predef(hive(hive_name)).open_subkey_with_flags(path, KEY_READ | KEY_SET_VALUE).map_err(admin_hint)?;
            record.command = key.get_value::<String, _>(name).map_err(|e| e.to_string())?;
            key.delete_value(name).map_err(admin_hint)?;
            record.name = name.to_string();
            record.location = format!("{hive_name} {path}");
        }
        ["folder", path] => {
            let src = PathBuf::from(path);
            let stash_dir = paths::data_dir().join("DisabledStartup");
            std::fs::create_dir_all(&stash_dir).map_err(|e| e.to_string())?;
            let dest = stash_dir.join(format!("{}-{}", util::now_secs(), util::file_name(&src)));
            std::fs::rename(&src, &dest).map_err(admin_hint)?;
            record.name = util::file_name(&src);
            record.command = path.to_string();
            record.stash = Some(dest.display().to_string());
        }
        ["task", name] => {
            let out = Command::new("schtasks.exe").args(["/change", "/tn", name, "/disable"]).creation_flags(0x0800_0000).output().map_err(|e| e.to_string())?;
            if !out.status.success() {
                return Err("Task Scheduler refused the change. Restart Fiend as administrator and try again.".into());
            }
            record.name = name.to_string();
        }
        _ => return Err("Unknown startup item".into()),
    }
    list.retain(|d| d.id != id);
    list.push(record);
    save_disabled(&list)
}

pub fn restore(id: &str) -> Result<(), String> {
    let mut list = disabled();
    let Some(pos) = list.iter().position(|d| d.id == id) else { return Err("That item isn't in the disabled list".into()) };
    let rec = list[pos].clone();
    let parts: Vec<&str> = id.splitn(4, '|').collect();
    match parts.as_slice() {
        ["reg", hive_name, path, name] => {
            let (key, _) = RegKey::predef(hive(hive_name)).create_subkey(path).map_err(admin_hint)?;
            key.set_value(name, &rec.command).map_err(admin_hint)?;
        }
        ["folder", path] => {
            let stash = rec.stash.as_deref().ok_or("Missing stash")?;
            std::fs::rename(stash, path).map_err(admin_hint)?;
        }
        ["task", name] => {
            let out = Command::new("schtasks.exe").args(["/change", "/tn", name, "/enable"]).creation_flags(0x0800_0000).output().map_err(|e| e.to_string())?;
            if !out.status.success() {
                return Err("Task Scheduler refused the change. Restart Fiend as administrator and try again.".into());
            }
        }
        _ => return Err("Unknown startup item".into()),
    }
    list.remove(pos);
    save_disabled(&list)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_targets() {
        assert_eq!(extract_target(r#""C:\Program Files\App\app.exe" --min"#).as_deref(), Some(r"C:\Program Files\App\app.exe"));
        assert_eq!(extract_target(r"C:\Tools\sync.exe /background").as_deref(), Some(r"C:\Tools\sync.exe"));
        assert_eq!(extract_target(r"C:\Program Files\Thing\thing.exe -x").as_deref(), Some(r"C:\Program Files\Thing\thing.exe"));
    }

    #[test]
    fn flags_living_off_the_land_commands() {
        let r = command_signals(r#"mshta.exe "javascript:a=new ActiveXObject('WScript.Shell')""#);
        assert!(r.iter().any(|x| x.code == "lolbin"));
        let r = command_signals(r"powershell.exe -w hidden -enc SQBFAFgA");
        assert!(score(&r) >= 40, "{r:?}");
        assert!(command_signals(r#""C:\Program Files\Steam\steam.exe" -silent"#).is_empty());
    }

    #[test]
    fn csv_parser_handles_quotes() {
        let f = parse_csv_line(r#""HOST","\Updater","N/A","Ready","x","y","z","Me","""C:\a b\u.exe"" /s""#);
        assert_eq!(f[1], r"\Updater");
        assert_eq!(f[8], r#""C:\a b\u.exe" /s"#);
    }
}
