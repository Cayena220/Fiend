//! Method dispatch for the JSON bridge.

use crate::threats::{defender, quarantine, scan, signatures, startup};
use crate::{cache, disk, health, jobs, settings, system, win};
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

fn to_value<T: Serialize>(v: T) -> Result<Value, String> {
    serde_json::to_value(v).map_err(|e| e.to_string())
}

fn param<T: DeserializeOwned>(p: &Value, key: &str) -> Result<T, String> {
    serde_json::from_value(p.get(key).cloned().unwrap_or(Value::Null)).map_err(|e| format!("Bad or missing \"{key}\": {e}"))
}

fn path_param(p: &Value) -> Result<PathBuf, String> {
    let s: String = param(p, "path")?;
    if s.trim().is_empty() {
        return Err("A path is required".into());
    }
    Ok(PathBuf::from(s))
}

pub fn dispatch(method: &str, p: Value) -> Result<Value, String> {
    match method {
        "core.version" => Ok(json!({ "version": env!("CARGO_PKG_VERSION") })),

        "settings.get" => to_value(settings::load()),
        "settings.set" => {
            let s: settings::Settings = serde_json::from_value(p).map_err(|e| format!("Settings are not valid: {e}"))?;
            settings::save(&s)?;
            to_value(s)
        }
        "settings.reset" => {
            let s = settings::Settings::default();
            settings::save(&s)?;
            to_value(s)
        }
        "state.get" => to_value(settings::load_state()),

        "system.info" => Ok(system::info()),
        "system.relaunch_admin" => system::relaunch_admin().map(|_| json!(true)),
        "system.reveal" => system::reveal(&path_param(&p)?).map(|_| json!(true)),
        "update.install" => system::install_update(&path_param(&p)?).map(|_| json!(true)),

        "drives.list" => to_value(disk::list_drives()),
        "drives.health" => to_value(health::report(settings::load().disk.life_warning)),
        "disk.recycle" => {
            let paths: Vec<String> = param(&p, "paths")?;
            let refs: Vec<&Path> = paths.iter().map(Path::new).collect();
            win::send_to_recycle_bin(&refs).map(|_| json!({ "recycled": paths.len() }))
        }

        "startup.list" => to_value(startup::list(settings::load().shield.verify_signatures)),
        "startup.disable" => startup::disable(&param::<String>(&p, "id")?).map(|_| json!(true)),
        "startup.restore" => startup::restore(&param::<String>(&p, "id")?).map(|_| json!(true)),
        "startup.disabled" => to_value(startup::disabled()),

        "defender.available" => Ok(json!({ "available": defender::locate().is_some() })),
        "defender.scan" => to_value(defender::scan_file(&path_param(&p)?)),

        "shield.allow" => {
            let entry: String = param(&p, "entry")?;
            let mut s = settings::load();
            if !s.shield.allowlist.iter().any(|a| a.eq_ignore_ascii_case(&entry)) {
                s.shield.allowlist.push(entry);
                settings::save(&s)?;
            }
            to_value(s)
        }

        "quarantine.list" => to_value(quarantine::list()),
        "quarantine.add" => {
            let reason: String = param(&p, "reason").unwrap_or_default();
            let score: i32 = param(&p, "score").unwrap_or(0);
            to_value(quarantine::add(&path_param(&p)?, &reason, score)?)
        }
        "quarantine.restore" => quarantine::restore(&param::<String>(&p, "id")?).map(|path| json!({ "path": path })),
        "quarantine.delete" => quarantine::delete(&param::<String>(&p, "id")?).map(|_| json!(true)),

        "signatures.info" => Ok(signatures::info()),
        "signatures.import" => {
            let text: String = param(&p, "text")?;
            let label: String = param(&p, "label").unwrap_or_default();
            signatures::import(&text, &label)
        }
        "signatures.reset" => signatures::reset(),

        "job.start" => start_job(&param::<String>(&p, "kind")?, p.get("params").cloned().unwrap_or(Value::Null)),
        "job.status" => jobs::status(param(&p, "id")?),
        "job.cancel" => jobs::cancel(param(&p, "id")?),
        "job.dispose" => jobs::dispose(param(&p, "id")?),

        "" => Err("No method given".into()),
        other => Err(format!("Unknown method: {other}")),
    }
}

fn start_job(kind: &str, p: Value) -> Result<Value, String> {
    let id = match kind {
        "cache.analyze" => jobs::start(kind, |ctx| {
            let s = settings::load();
            to_value(cache::analyze(&cache::all(&s), &s.cleaner, ctx))
        }),
        "cache.clean" => {
            let ids: Vec<String> = param(&p, "ids")?;
            let dry_run: bool = param(&p, "dry_run").unwrap_or(false);
            jobs::start(kind, move |ctx| {
                let s = settings::load();
                let report = cache::clean(&cache::all(&s), &ids, &s.cleaner, dry_run, ctx);
                if !dry_run {
                    settings::update_state(|st| {
                        st.last_clean_at = Some(crate::util::now_secs());
                        st.total_freed += report.freed;
                    })?;
                }
                to_value(report)
            })
        }
        "disk.analyze" => {
            let root = path_param(&p)?;
            jobs::start(kind, move |ctx| {
                let prefs = settings::load().disk;
                to_value(disk::analyze(&root, prefs.top_files, prefs.large_file_mb * 1024 * 1024, ctx)?)
            })
        }
        "shield.scan" => {
            let params: scan::ScanParams = serde_json::from_value(p).map_err(|e| e.to_string())?;
            jobs::start(kind, move |ctx| to_value(scan::run(&params, &settings::load().shield, ctx)))
        }
        other => return Err(format!("Unknown job kind: {other}")),
    };
    Ok(json!({ "id": id }))
}

#[cfg(test)]
mod tests {
    use crate::invoke_json;
    use serde_json::Value;

    fn call(req: &str) -> Value {
        serde_json::from_str(&invoke_json(req)).unwrap()
    }

    #[test]
    fn envelope_contract() {
        let ok = call(r#"{"method":"core.version"}"#);
        assert_eq!(ok["ok"], true);
        assert!(ok["data"]["version"].is_string());

        let unknown = call(r#"{"method":"nope.nothing"}"#);
        assert_eq!(unknown["ok"], false);
        assert!(unknown["error"].as_str().unwrap().contains("Unknown method"));

        let bad = call("{not json");
        assert_eq!(bad["ok"], false);

        let missing = call(r#"{"method":"job.status","params":{}}"#);
        assert_eq!(missing["ok"], false);
    }

    #[test]
    fn drives_are_listed_through_the_bridge() {
        let r = call(r#"{"method":"drives.list"}"#);
        assert_eq!(r["ok"], true);
        assert!(!r["data"].as_array().unwrap().is_empty());
    }
}
