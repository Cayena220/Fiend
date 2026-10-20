//! Fiend core: the engine behind the Fiend desktop app.
//!
//! Everything is reachable through one JSON entry point, [`invoke_json`], which the
//! Flutter app calls over a tiny C ABI (`fiend_invoke` / `fiend_free`).

pub mod api;
pub mod cache;
pub mod disk;
pub mod jobs;
pub mod paths;
pub mod settings;
pub mod system;
pub mod threats;
pub mod util;
pub mod win;

mod ffi;

use serde_json::{json, Value};

/// Handles a request of the form `{"method": "...", "params": {...}}` and returns
/// `{"ok": true, "data": ...}` or `{"ok": false, "error": "..."}`.
pub fn invoke_json(request: &str) -> String {
    let response = match serde_json::from_str::<Value>(request) {
        Ok(req) => {
            let method = req.get("method").and_then(Value::as_str).unwrap_or("");
            let params = req.get("params").cloned().unwrap_or(Value::Null);
            match api::dispatch(method, params) {
                Ok(data) => json!({ "ok": true, "data": data }),
                Err(error) => json!({ "ok": false, "error": error }),
            }
        }
        Err(e) => json!({ "ok": false, "error": format!("Request is not valid JSON: {e}") }),
    };
    response.to_string()
}
