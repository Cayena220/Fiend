//! Per-file evidence: disguised names, hidden executables, packed code, risky scripts,
//! missing signatures and known-bad hashes.

use super::authenticode::{self, Trust};
use super::signatures::SignatureDb;
use super::{score, Reason};
use crate::{paths, util};
use std::fs::Metadata;
use std::path::{Path, PathBuf};

pub const EXEC_EXTS: &[&str] = &["exe", "dll", "scr", "com", "pif", "cpl", "sys", "msi", "ocx", "drv"];
/// Scripts that are rarely legitimate outside developer folders.
pub const DANGEROUS_SCRIPTS: &[&str] = &["bat", "cmd", "ps1", "vbs", "vbe", "jse", "wsf", "wsh", "hta"];
/// Scripts that are common in normal software, only examined in risky places.
pub const LOOSE_SCRIPTS: &[&str] = &["js", "jar", "psm1", "reg", "lnk"];
/// Extensions that attackers use as a disguise.
pub const LURE_EXTS: &[&str] = &[
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "jpg", "jpeg", "png", "gif", "bmp", "mp3", "mp4",
    "avi", "mov", "zip", "rar",
];

pub fn is_exec(ext: &str) -> bool {
    EXEC_EXTS.contains(&ext)
}

fn is_runnable(ext: &str) -> bool {
    is_exec(ext) || DANGEROUS_SCRIPTS.contains(&ext)
}

/// Evidence that only depends on the file name.
pub fn name_signals(name: &str) -> Vec<Reason> {
    let mut reasons = Vec::new();
    if name.contains('\u{202E}') {
        reasons.push(Reason::new("rtlo", "Hidden right-to-left character reverses how the name is displayed", 70));
    }
    let lower = name.to_lowercase();
    let parts: Vec<&str> = lower.split('.').collect();
    if parts.len() >= 3 {
        let last = parts[parts.len() - 1];
        let prev_raw = parts[parts.len() - 2];
        let prev = prev_raw.trim();
        if is_runnable(last) && LURE_EXTS.contains(&prev) {
            reasons.push(Reason::new(
                "double_extension",
                format!("Looks like a .{prev} file but runs as .{last}"),
                60,
            ));
        }
        if is_runnable(last) && prev_raw.len() - prev_raw.trim_end().len() >= 6 {
            reasons.push(Reason::new("padding", "Long run of spaces hides the real extension", 40));
        }
    }
    reasons
}

const SCRIPT_INDICATORS: &[(&[&str], &str, i32)] = &[
    (&["-encodedcommand", " -enc ", " -ec "], "Runs an encoded PowerShell command", 20),
    (&["frombase64string"], "Decodes hidden Base64 data", 10),
    (&["downloadstring", "downloadfile", "invoke-webrequest", "net.webclient", "start-bitstransfer"], "Downloads content from the internet", 15),
    (&["invoke-expression", "iex(", "iex ("], "Runs text as code", 15),
    (&["wscript.shell", "shell.application"], "Uses Windows Script Host to launch commands", 10),
    (&["-windowstyle hidden", "-w hidden"], "Runs with a hidden window", 10),
    (&["bitsadmin /transfer"], "Uses bitsadmin to download files", 20),
    (&["certutil -urlcache", "certutil.exe -urlcache"], "Uses certutil to download files", 25),
    (&["mshta http", "mshta.exe http", "mshta vbscript", "mshta javascript"], "Runs remote code through mshta", 25),
    (&["/i:http"], "Loads a remote scriptlet through regsvr32", 25),
    (&["add-mppreference -exclusion"], "Adds Microsoft Defender exclusions", 35),
    (&["disablerealtimemonitoring"], "Turns off Defender real-time protection", 40),
    (&["vssadmin delete shadows", "vssadmin.exe delete shadows", "shadowcopy delete"], "Deletes shadow copies, a common ransomware step", 45),
    (&["recoveryenabled no"], "Disables Windows recovery", 35),
    (&["wbadmin delete catalog"], "Deletes the backup catalog", 35),
];

/// Evidence from a script's text.
pub fn content_signals(text: &str) -> Vec<Reason> {
    let lower = text.to_lowercase();
    let mut reasons = Vec::new();
    let mut total = 0;
    for (needles, label, weight) in SCRIPT_INDICATORS {
        if needles.iter().any(|n| lower.contains(n)) && total < 70 {
            let w = (*weight).min(70 - total);
            total += w;
            reasons.push(Reason::new("script", *label, w));
        }
    }
    reasons
}

pub struct Analyzer {
    pub sigs: std::sync::Arc<SignatureDb>,
    pub verify_signatures: bool,
    pub max_bytes: u64,
    risky: Vec<(PathBuf, &'static str)>,
    loose_parents: Vec<PathBuf>,
    trusted_roots: Vec<PathBuf>,
    profile: PathBuf,
}

#[derive(Debug, Clone, Default)]
pub struct Verdict {
    pub score: i32,
    pub reasons: Vec<Reason>,
    pub sha256: Option<String>,
    pub signed: Option<&'static str>,
    pub is_pe: bool,
}

impl Analyzer {
    pub fn new(sigs: std::sync::Arc<SignatureDb>, verify_signatures: bool, max_bytes: u64) -> Self {
        let mut risky = vec![
            (paths::temp(), "Temp"),
            (paths::windows_dir().join("Temp"), "Windows Temp"),
            (paths::public(), "Public"),
            (paths::startup_user(), "Startup"),
            (paths::startup_common(), "Startup"),
        ];
        if let Some(d) = paths::downloads() {
            risky.push((d, "Downloads"));
        }
        Self {
            sigs,
            verify_signatures,
            max_bytes,
            risky,
            loose_parents: vec![paths::roaming(), paths::local_appdata(), paths::program_data()],
            trusted_roots: vec![
                paths::windows_dir(),
                PathBuf::from(r"C:\Program Files"),
                PathBuf::from(r"C:\Program Files (x86)"),
            ],
            profile: paths::home(),
        }
    }

    /// Name of the risky place a file sits in, if any.
    pub fn risky_place(&self, path: &Path) -> Option<&'static str> {
        if let Some((_, label)) = self.risky.iter().find(|(root, _)| paths::is_within(path, root)) {
            return Some(label);
        }
        // Loose files directly in AppData or ProgramData, or one folder below.
        let parent = path.parent()?;
        for base in &self.loose_parents {
            if paths::norm(parent) == paths::norm(base)
                || parent.parent().is_some_and(|gp| paths::norm(gp) == paths::norm(base))
            {
                return Some("AppData");
            }
        }
        None
    }

    /// Whether the scanner should look at this file at all.
    pub fn is_candidate(&self, path: &Path) -> bool {
        let ext = util::ext_lower(path);
        if is_runnable(&ext) {
            return true;
        }
        let risky = self.risky_place(path).is_some();
        if risky && (LOOSE_SCRIPTS.contains(&ext.as_str()) || LURE_EXTS.contains(&ext.as_str())) {
            return true;
        }
        !name_signals(&util::file_name(path)).is_empty()
    }

    pub fn analyze(&self, path: &Path, meta: &Metadata) -> Verdict {
        let mut v = Verdict::default();
        let name = util::file_name(path);
        let ext = util::ext_lower(path);
        let ext = ext.as_str();
        let size = meta.len();
        v.reasons = name_signals(&name);

        // Never open cloud-only files: that would download them.
        if util::is_cloud_placeholder(meta) {
            v.score = score(&v.reasons);
            return v;
        }

        let head = util::read_head(path, 2).unwrap_or_default();
        v.is_pe = head.starts_with(b"MZ");
        let place = self.risky_place(path);

        if v.is_pe && !is_exec(ext) && LURE_EXTS.contains(&ext) {
            v.reasons.push(Reason::new("masquerade", format!("Contains program code but is named .{ext}"), 55));
        }

        if size <= self.max_bytes && (v.is_pe || is_runnable(ext) || LOOSE_SCRIPTS.contains(&ext) || place.is_some()) {
            if let Ok(hash) = util::sha256_file(path) {
                if let Some(label) = self.sigs.lookup(&hash) {
                    v.reasons.push(Reason::new("signature", format!("Matches a known malware hash ({label})"), 100));
                }
                v.sha256 = Some(util::hex(&hash));
            }
        }

        if (DANGEROUS_SCRIPTS.contains(&ext) || ext == "js" || ext == "psm1") && size < 2 * 1024 * 1024 {
            if let Ok(bytes) = std::fs::read(path) {
                v.reasons.extend(content_signals(&String::from_utf8_lossy(&bytes)));
            }
        }

        if let Some(place) = place {
            if is_runnable(ext) || v.is_pe {
                v.reasons.push(Reason::new("location", format!("Runnable file in {place}, a folder malware often uses"), 15));
            }
        }

        let attrs = util::attributes(meta);
        if attrs & util::ATTR_HIDDEN != 0 && attrs & util::ATTR_SYSTEM != 0 && is_runnable(ext) && paths::is_within(path, &self.profile) {
            v.reasons.push(Reason::new("hidden", "Hidden system file in your user folder", 30));
        }

        if v.is_pe && size <= self.max_bytes {
            if let Ok(sample) = util::read_head(path, 2 * 1024 * 1024) {
                if util::shannon_entropy(&sample) > 7.2 {
                    v.reasons.push(Reason::new("packed", "Contents look packed or encrypted", 20));
                }
            }
            let in_trusted = self.trusted_roots.iter().any(|r| paths::is_within(path, r));
            let worth_checking = place.is_some() || v.reasons.iter().any(|r| r.weight > 0);
            if self.verify_signatures && worth_checking {
                let trust = authenticode::verify(path);
                v.signed = Some(trust.as_str());
                match trust {
                    Trust::Signed => v.reasons.push(Reason::new("signed", "Signed by a verified publisher", -40)),
                    Trust::Unsigned if !in_trusted => v.reasons.push(Reason::new("unsigned", "Has no digital signature", 20)),
                    Trust::Untrusted(_) => v.reasons.push(Reason::new("bad_signature", "Digital signature is invalid or not trusted", 35)),
                    Trust::Expired => v.reasons.push(Reason::new("expired_signature", "Digital signature has expired", 10)),
                    Trust::Unsigned | Trust::Unknown => {}
                }
            }
        }

        v.score = score(&v.reasons);
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn analyzer(db: SignatureDb) -> Analyzer {
        Analyzer::new(Arc::new(db), false, 50 * 1024 * 1024)
    }

    #[test]
    fn disguised_names() {
        assert_eq!(name_signals("invoice.pdf.exe")[0].code, "double_extension");
        assert!(name_signals("setup.exe").is_empty());
        assert!(name_signals("archive.tar.gz").is_empty());
        let padded = name_signals("photo.jpg              .scr");
        assert!(padded.iter().any(|r| r.code == "padding"));
        assert!(name_signals("cv\u{202E}fdp.exe").iter().any(|r| r.code == "rtlo"));
    }

    #[test]
    fn script_indicators_are_capped() {
        let text = "powershell -w hidden -EncodedCommand AAA; IEX (New-Object Net.WebClient).DownloadString('x'); vssadmin delete shadows /all; Set-MpPreference -DisableRealtimeMonitoring $true";
        let reasons = content_signals(text);
        assert!(reasons.len() >= 4);
        assert_eq!(reasons.iter().map(|r| r.weight).sum::<i32>(), 70);
        assert!(content_signals("echo hello world").is_empty());
    }

    #[test]
    fn program_code_behind_a_document_name_is_flagged() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("holiday.jpg");
        let mut bytes = b"MZ".to_vec();
        bytes.extend(vec![0u8; 510]);
        std::fs::write(&f, bytes).unwrap();
        let v = analyzer(SignatureDb::default()).analyze(&f, &std::fs::metadata(&f).unwrap());
        assert!(v.is_pe);
        assert!(v.reasons.iter().any(|r| r.code == "masquerade"));
        assert!(v.score >= 55);
    }

    #[test]
    fn known_hash_scores_100() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("tool.exe");
        let content = b"MZ this pretends to be a bad program";
        std::fs::write(&f, content).unwrap();
        let mut db = SignatureDb::default();
        db.add_text(&util::hex(&util::sha256_bytes(content)), "Unit test");
        let v = analyzer(db).analyze(&f, &std::fs::metadata(&f).unwrap());
        assert_eq!(v.score, 100);
        assert_eq!(v.sha256.as_deref(), Some(util::hex(&util::sha256_bytes(content)).as_str()));
    }

    #[test]
    fn packed_program_is_flagged() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("packed.exe");
        // MZ header followed by pseudo-random bytes (high entropy).
        let mut bytes = b"MZ".to_vec();
        let mut x: u32 = 0x1234_5678;
        for _ in 0..200_000 {
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
            bytes.push((x >> 24) as u8);
        }
        std::fs::write(&f, bytes).unwrap();
        let v = analyzer(SignatureDb::default()).analyze(&f, &std::fs::metadata(&f).unwrap());
        assert!(v.reasons.iter().any(|r| r.code == "packed"));
    }

    #[test]
    fn plain_document_is_clean() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("notes.txt");
        std::fs::write(&f, b"shopping list").unwrap();
        let v = analyzer(SignatureDb::default()).analyze(&f, &std::fs::metadata(&f).unwrap());
        assert_eq!(v.score, 0);
    }
}
