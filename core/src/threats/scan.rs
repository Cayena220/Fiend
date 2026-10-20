//! Quick, full and custom scans.

use super::defender::{self, DefenderResult};
use super::heuristics::Analyzer;
use super::startup::{self, StartupItem};
use super::{quarantine, score, severity, signatures, Reason};
use crate::jobs::Ctx;
use crate::settings::{self, Shield};
use crate::{paths, util};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering::Relaxed;
use std::sync::Mutex;
use walkdir::WalkDir;

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct ScanParams {
    /// quick, full or custom
    pub mode: String,
    pub paths: Vec<String>,
}

#[derive(Serialize, Clone, Debug)]
pub struct Finding {
    pub id: String,
    pub path: String,
    pub name: String,
    pub size: u64,
    pub modified: u64,
    pub score: i32,
    pub severity: &'static str,
    pub reasons: Vec<Reason>,
    pub sha256: Option<String>,
    pub signed: Option<&'static str>,
    pub defender: Option<DefenderResult>,
    pub quarantine_id: Option<String>,
}

#[derive(Serialize, Clone, Debug)]
pub struct ScanReport {
    pub mode: String,
    pub started_at: u64,
    pub elapsed_ms: u128,
    pub roots: Vec<String>,
    pub files_seen: u64,
    pub files_examined: u64,
    pub findings: Vec<Finding>,
    pub startup: Vec<StartupItem>,
    pub threshold: i32,
    pub signatures: usize,
    pub defender_used: bool,
    pub cancelled: bool,
}

/// Folders (with a depth limit) each mode walks.
pub fn roots_for(params: &ScanParams, shield: &Shield) -> Vec<(PathBuf, Option<usize>)> {
    let mut roots: Vec<(PathBuf, Option<usize>)> = match params.mode.as_str() {
        "full" => crate::disk::list_drives()
            .into_iter()
            .filter(|d| d.kind == "fixed")
            .map(|d| (PathBuf::from(d.root), None))
            .chain(std::iter::once((paths::windows_dir().join("Temp"), None)))
            .collect(),
        "custom" => params.paths.iter().map(|p| (PathBuf::from(paths::expand_env(p)), None)).collect(),
        _ => {
            let mut r = vec![
                (paths::temp(), Some(4)),
                (paths::windows_dir().join("Temp"), Some(3)),
                (paths::roaming(), Some(3)),
                (paths::local_appdata(), Some(2)),
                (paths::program_data(), Some(2)),
                (paths::public(), Some(3)),
                (paths::startup_user(), Some(2)),
                (paths::startup_common(), Some(2)),
            ];
            if let Some(d) = paths::downloads() {
                r.push((d, Some(4)));
            }
            if let Some(d) = paths::desktop() {
                r.push((d, Some(3)));
            }
            r.extend(shield.extra_locations.iter().map(|p| (PathBuf::from(paths::expand_env(p)), None)));
            r
        }
    };
    roots.retain(|(p, _)| p.exists());
    roots
}

/// Folders a full scan skips: Windows itself (catalog-signed, huge) and Fiend's own vault.
fn skip_dirs(mode: &str) -> Vec<PathBuf> {
    let mut skip = vec![quarantine::dir()];
    if mode == "full" {
        let windows = paths::windows_dir();
        if let Ok(rd) = std::fs::read_dir(&windows) {
            skip.extend(rd.flatten().map(|e| e.path()).filter(|p| !util::file_name(p).eq_ignore_ascii_case("Temp")));
        }
    }
    skip
}

fn collect_candidates(roots: &[(PathBuf, Option<usize>)], analyzer: &Analyzer, shield: &Shield, mode: &str, ctx: &Ctx) -> (Vec<PathBuf>, u64) {
    ctx.set_phase("Finding files to examine");
    let skip = skip_dirs(mode);
    let mut seen = HashSet::new();
    let mut candidates = Vec::new();
    let mut files_seen = 0u64;
    for (root, depth) in roots {
        let mut walker = WalkDir::new(root).follow_links(false);
        if let Some(d) = depth {
            walker = walker.max_depth(*d);
        }
        let iter = walker.into_iter().filter_entry(|e| {
            !(e.file_type().is_dir() && e.depth() > 0 && skip.iter().any(|s| paths::is_within(e.path(), s)))
                && !paths::is_excluded(e.path(), &shield.exclusions)
        });
        for entry in iter.flatten() {
            if ctx.cancelled() {
                return (candidates, files_seen);
            }
            if !entry.file_type().is_file() {
                continue;
            }
            files_seen += 1;
            if files_seen.is_multiple_of(512) {
                ctx.set_current(&entry.path().to_string_lossy());
            }
            if analyzer.is_candidate(entry.path()) && seen.insert(paths::norm(entry.path())) {
                candidates.push(entry.into_path());
            }
        }
    }
    (candidates, files_seen)
}

fn is_allowed(f: &Finding, allowlist: &[String]) -> bool {
    allowlist.iter().any(|a| {
        let a = a.trim();
        f.sha256.as_deref().is_some_and(|h| h.eq_ignore_ascii_case(a)) || paths::norm(Path::new(a)) == paths::norm(Path::new(&f.path))
    })
}

pub fn run(params: &ScanParams, shield: &Shield, ctx: &Ctx) -> ScanReport {
    let started = std::time::Instant::now();
    let started_at = util::now_secs();
    let mode = if params.mode.is_empty() { "quick".to_string() } else { params.mode.clone() };
    let sigs = signatures::db();
    let analyzer = Analyzer::new(sigs.clone(), shield.verify_signatures, shield.max_file_mb * 1024 * 1024);
    let threshold = shield.threshold();
    let roots = roots_for(&ScanParams { mode: mode.clone(), paths: params.paths.clone() }, shield);

    let (candidates, files_seen) = collect_candidates(&roots, &analyzer, shield, &mode, ctx);
    ctx.total.store(candidates.len() as u64, Relaxed);
    ctx.set_phase("Examining files");

    let findings = Mutex::new(Vec::new());
    candidates.par_iter().for_each(|path| {
        if ctx.cancelled() {
            return;
        }
        ctx.tick(&path.to_string_lossy());
        let Ok(meta) = std::fs::symlink_metadata(path) else { return };
        ctx.bytes.fetch_add(meta.len(), Relaxed);
        let v = analyzer.analyze(path, &meta);
        if v.score >= threshold {
            ctx.found.fetch_add(1, Relaxed);
            findings.lock().unwrap().push(Finding {
                id: String::new(),
                path: path.display().to_string(),
                name: util::file_name(path),
                size: meta.len(),
                modified: util::modified_secs(&meta),
                score: v.score,
                severity: severity(v.score),
                reasons: v.reasons,
                sha256: v.sha256,
                signed: v.signed,
                defender: None,
                quarantine_id: None,
            });
        }
    });
    let mut findings: Vec<Finding> = findings.into_inner().unwrap().into_iter().filter(|f| !is_allowed(f, &shield.allowlist)).collect();

    let mut startup = Vec::new();
    if !ctx.cancelled() {
        ctx.set_phase("Checking startup programs");
        startup = startup::list(shield.verify_signatures).into_iter().filter(|s| s.score >= threshold).collect();
    }

    let defender_available = shield.use_defender && defender::locate().is_some();
    if defender_available && !ctx.cancelled() {
        ctx.set_phase("Asking Microsoft Defender");
        for f in findings.iter_mut().filter(|f| f.score >= 40) {
            if ctx.cancelled() {
                break;
            }
            ctx.set_current(&f.path);
            let result = defender::scan_file(Path::new(&f.path));
            if result.status == "threat" {
                f.reasons.push(Reason::new("defender", result.detail.clone(), 100));
                f.score = score(&f.reasons);
                f.severity = severity(f.score);
            }
            f.defender = Some(result);
        }
    }

    findings.sort_by(|a, b| b.score.cmp(&a.score).then_with(|| a.path.cmp(&b.path)));
    for (i, f) in findings.iter_mut().enumerate() {
        f.id = format!("f{i}");
    }

    if shield.auto_quarantine && !ctx.cancelled() {
        ctx.set_phase("Quarantining high-risk files");
        for f in findings.iter_mut().filter(|f| f.score >= 70) {
            let reason = f.reasons.iter().max_by_key(|r| r.weight).map(|r| r.label.clone()).unwrap_or_default();
            if let Ok(entry) = quarantine::add(Path::new(&f.path), &reason, f.score) {
                f.quarantine_id = Some(entry.id);
            }
        }
    }

    let report = ScanReport {
        mode: mode.clone(),
        started_at,
        elapsed_ms: started.elapsed().as_millis(),
        roots: roots.iter().map(|(p, _)| p.display().to_string()).collect(),
        files_seen,
        files_examined: ctx.done.load(Relaxed),
        threshold,
        signatures: sigs.len(),
        defender_used: defender_available,
        cancelled: ctx.cancelled(),
        startup,
        findings,
    };

    if !report.cancelled {
        let _ = settings::update_state(|s| {
            s.last_scan_at = Some(started_at);
            s.last_scan_mode = mode;
            s.last_scan_files = report.files_seen;
            s.last_scan_findings = (report.findings.len() + report.startup.len()) as u64;
        });
    }
    report
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn custom_scan_finds_planted_samples() {
        let data = tempfile::tempdir().unwrap();
        std::env::set_var("FIEND_DATA_DIR", data.path());
        let dir = tempfile::tempdir().unwrap();
        let r = dir.path();
        std::fs::write(r.join("invoice.pdf.exe"), b"MZ fake").unwrap();
        let mut pe = b"MZ".to_vec();
        pe.extend(vec![0u8; 100]);
        std::fs::write(r.join("cat.jpg"), pe).unwrap();
        std::fs::write(r.join("readme.txt"), b"hello").unwrap();

        let shield = Shield { use_defender: false, verify_signatures: false, ..Default::default() };
        let params = ScanParams { mode: "custom".into(), paths: vec![r.display().to_string()] };
        let report = run(&params, &shield, &Ctx::new());

        let names: Vec<&str> = report.findings.iter().map(|f| f.name.as_str()).collect();
        assert!(names.contains(&"invoice.pdf.exe"), "{names:?}");
        assert!(names.contains(&"cat.jpg"), "{names:?}");
        assert!(!names.contains(&"readme.txt"));
        assert!(report.findings.iter().all(|f| f.score >= report.threshold));

        // Allowlisting by path hides the finding on the next scan.
        let allowed = Shield { allowlist: vec![r.join("cat.jpg").display().to_string()], ..shield };
        let again = run(&params, &allowed, &Ctx::new());
        assert!(!again.findings.iter().any(|f| f.name == "cat.jpg"));
    }
}
