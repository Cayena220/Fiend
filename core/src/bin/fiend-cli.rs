//! Command-line access to the Fiend engine, for smoke tests and debugging.
//!
//!   fiend-cli <method> [json-params]          call a method and print the result
//!   fiend-cli job <kind> [json-params]        run a background job and wait for it
//!
//! Examples:
//!   fiend-cli drives.list
//!   fiend-cli job cache.analyze
//!   fiend-cli job shield.scan "{\"mode\":\"quick\"}"

use fiend_core::invoke_json;
use serde_json::{json, Value};
use std::io::Write;

fn call(method: &str, params: Value) -> Value {
    let out = invoke_json(&json!({ "method": method, "params": params }).to_string());
    serde_json::from_str(&out).expect("engine returned invalid JSON")
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("usage: fiend-cli <method> [json] | fiend-cli job <kind> [json]");
        std::process::exit(2);
    }
    let parse = |s: Option<&String>| s.map(|t| serde_json::from_str(t).expect("params must be JSON")).unwrap_or(Value::Null);

    let response = if args[0] == "job" {
        let kind = args.get(1).expect("job kind required");
        let started = call("job.start", json!({ "kind": kind, "params": parse(args.get(2)) }));
        let Some(id) = started["data"]["id"].as_u64() else {
            println!("{}", serde_json::to_string_pretty(&started).unwrap());
            std::process::exit(1);
        };
        loop {
            let status = call("job.status", json!({ "id": id }));
            let d = &status["data"];
            let p = &d["progress"];
            eprint!("\r{:<28} {:>8}/{:<8} found {:<4}", p["phase"].as_str().unwrap_or(""), p["done"], p["total"], p["found"]);
            let _ = std::io::stderr().flush();
            if d["finished"].as_bool().unwrap_or(true) {
                eprintln!();
                call("job.dispose", json!({ "id": id }));
                break status;
            }
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
    } else {
        call(&args[0], parse(args.get(1)))
    };

    println!("{}", serde_json::to_string_pretty(&response).unwrap());
    if response["ok"] != true {
        std::process::exit(1);
    }
}
