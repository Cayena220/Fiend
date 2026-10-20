//! Background jobs with pollable progress. Long work (scans, analysis, cleaning) runs on a
//! Rust thread; the app polls `job.status` and can `job.cancel`.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};

#[derive(Default)]
pub struct Ctx {
    cancel: AtomicBool,
    pub done: AtomicU64,
    pub total: AtomicU64,
    pub bytes: AtomicU64,
    pub found: AtomicU64,
    phase: Mutex<String>,
    current: Mutex<String>,
}

impl Ctx {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancelled(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }

    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }

    pub fn set_phase(&self, phase: &str) {
        if let Ok(mut p) = self.phase.lock() {
            *p = phase.to_string();
        }
    }

    pub fn set_current(&self, current: &str) {
        if let Ok(mut c) = self.current.lock() {
            current.clone_into(&mut c);
        }
    }

    /// Counts one unit of work and occasionally records what is being worked on.
    pub fn tick(&self, current: &str) {
        let n = self.done.fetch_add(1, Ordering::Relaxed);
        if n.is_multiple_of(64) {
            self.set_current(current);
        }
    }

    pub fn snapshot(&self) -> Value {
        json!({
            "phase": self.phase.lock().map(|p| p.clone()).unwrap_or_default(),
            "current": self.current.lock().map(|c| c.clone()).unwrap_or_default(),
            "done": self.done.load(Ordering::Relaxed),
            "total": self.total.load(Ordering::Relaxed),
            "bytes": self.bytes.load(Ordering::Relaxed),
            "found": self.found.load(Ordering::Relaxed),
            "cancelled": self.cancelled(),
        })
    }
}

struct Job {
    kind: String,
    started: u64,
    ctx: Ctx,
    outcome: Mutex<Option<Result<Value, String>>>,
}

static JOBS: LazyLock<Mutex<HashMap<u64, Arc<Job>>>> = LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub fn start<F>(kind: &str, work: F) -> u64
where
    F: FnOnce(&Ctx) -> Result<Value, String> + Send + 'static,
{
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let job = Arc::new(Job {
        kind: kind.to_string(),
        started: crate::util::now_secs(),
        ctx: Ctx::new(),
        outcome: Mutex::new(None),
    });
    JOBS.lock().unwrap().insert(id, job.clone());

    std::thread::spawn(move || {
        let result = std::panic::catch_unwind(AssertUnwindSafe(|| work(&job.ctx)))
            .unwrap_or_else(|_| Err("The job stopped because of an internal error".to_string()));
        *job.outcome.lock().unwrap() = Some(result);
    });
    id
}

fn get(id: u64) -> Result<Arc<Job>, String> {
    JOBS.lock()
        .unwrap()
        .get(&id)
        .cloned()
        .ok_or_else(|| format!("No job with id {id}"))
}

pub fn status(id: u64) -> Result<Value, String> {
    let job = get(id)?;
    let outcome = job.outcome.lock().unwrap();
    let (finished, result, error) = match outcome.as_ref() {
        None => (false, Value::Null, Value::Null),
        Some(Ok(v)) => (true, v.clone(), Value::Null),
        Some(Err(e)) => (true, Value::Null, Value::String(e.clone())),
    };
    Ok(json!({
        "id": id,
        "kind": job.kind,
        "started": job.started,
        "finished": finished,
        "progress": job.ctx.snapshot(),
        "result": result,
        "error": error,
    }))
}

pub fn cancel(id: u64) -> Result<Value, String> {
    get(id)?.ctx.cancel();
    Ok(json!(true))
}

pub fn dispose(id: u64) -> Result<Value, String> {
    if let Some(job) = JOBS.lock().unwrap().remove(&id) {
        job.ctx.cancel();
    }
    Ok(json!(true))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn job_runs_and_reports() {
        let id = start("test", |ctx| {
            ctx.set_phase("Working");
            ctx.tick("a");
            Ok(json!({"answer": 42}))
        });
        for _ in 0..200 {
            let s = status(id).unwrap();
            if s["finished"].as_bool().unwrap() {
                assert_eq!(s["result"]["answer"], 42);
                assert_eq!(s["progress"]["done"], 1);
                dispose(id).unwrap();
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        panic!("job never finished");
    }
}
