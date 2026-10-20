//! SHA-256 blocklist stored in `%APPDATA%\Fiend\signatures.txt` as `hash<TAB>label` lines.

use crate::{paths, util};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, RwLock};

/// SHA-256 of the standard EICAR antivirus test file, so detection can be checked safely.
pub const EICAR_SHA256: &str = "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f";

#[derive(Default)]
pub struct SignatureDb {
    labels: Vec<String>,
    hashes: HashMap<[u8; 32], u16>,
}

impl SignatureDb {
    pub fn len(&self) -> usize {
        self.hashes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.hashes.is_empty()
    }

    pub fn lookup(&self, hash: &[u8; 32]) -> Option<&str> {
        self.hashes.get(hash).map(|&i| self.labels[i as usize].as_str())
    }

    fn label_index(&mut self, label: &str) -> u16 {
        if let Some(i) = self.labels.iter().position(|l| l == label) {
            return i as u16;
        }
        self.labels.push(label.to_string());
        (self.labels.len() - 1).min(u16::MAX as usize) as u16
    }

    /// Adds hashes from text (one per line, first token is the hash, `#` starts a comment).
    /// Returns the hashes that were new.
    pub fn add_text(&mut self, text: &str, label: &str) -> Vec<[u8; 32]> {
        let idx = self.label_index(label);
        let mut added = Vec::new();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let token = line.split(|c: char| c.is_whitespace() || c == ',' || c == ';' || c == '"').find(|t| !t.is_empty());
            if let Some(hash) = token.and_then(util::parse_sha256) {
                if self.hashes.insert(hash, idx).is_none() {
                    added.push(hash);
                }
            }
        }
        added
    }

    pub fn load(path: &Path) -> Self {
        let mut db = Self::default();
        db.add_text(EICAR_SHA256, "EICAR test file");
        if let Ok(text) = std::fs::read_to_string(path) {
            for line in text.lines() {
                let (hash, label) = line.split_once('\t').unwrap_or((line, "Imported"));
                db.add_text(hash, label.trim());
            }
        }
        db
    }
}

fn db_path() -> PathBuf {
    paths::data_dir().join("signatures.txt")
}

static DB: LazyLock<RwLock<Option<Arc<SignatureDb>>>> = LazyLock::new(|| RwLock::new(None));

/// Shared, lazily loaded copy of the blocklist.
pub fn db() -> Arc<SignatureDb> {
    if let Some(db) = DB.read().unwrap().as_ref() {
        return db.clone();
    }
    let loaded = Arc::new(SignatureDb::load(&db_path()));
    *DB.write().unwrap() = Some(loaded.clone());
    loaded
}

pub fn info() -> Value {
    let state = crate::settings::load_state();
    json!({
        "count": db().len(),
        "path": db_path().display().to_string(),
        "updated_at": state.signatures_updated_at,
    })
}

/// Imports hashes from text and appends the new ones to the blocklist file.
pub fn import(text: &str, label: &str) -> Result<Value, String> {
    let label = if label.trim().is_empty() { "Imported" } else { label.trim() };
    let mut db = SignatureDb::load(&db_path());
    let added = db.add_text(text, label);
    if !added.is_empty() {
        paths::ensure_data_dir();
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(db_path())
            .map_err(|e| format!("Couldn't save signatures: {e}"))?;
        let mut out = String::with_capacity(added.len() * 80);
        for hash in &added {
            out.push_str(&util::hex(hash));
            out.push('\t');
            out.push_str(label);
            out.push('\n');
        }
        file.write_all(out.as_bytes()).map_err(|e| format!("Couldn't save signatures: {e}"))?;
    }
    let total = db.len();
    *DB.write().unwrap() = Some(Arc::new(db));
    crate::settings::update_state(|s| s.signatures_updated_at = Some(util::now_secs()))?;
    Ok(json!({ "added": added.len(), "count": total }))
}

/// Removes every imported hash (the built-in test signature stays).
pub fn reset() -> Result<Value, String> {
    let _ = std::fs::remove_file(db_path());
    *DB.write().unwrap() = None;
    Ok(json!({ "count": db().len() }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hash_lists_and_ignores_noise() {
        let mut db = SignatureDb::default();
        let h = util::hex(&util::sha256_bytes(b"bad"));
        let text = format!("# MalwareBazaar export\n{h}\n\"{h}\",x\nnot-a-hash\n\n");
        let added = db.add_text(&text, "Test feed");
        assert_eq!(added.len(), 1);
        assert_eq!(db.lookup(&util::sha256_bytes(b"bad")), Some("Test feed"));
        assert_eq!(db.lookup(&util::sha256_bytes(b"good")), None);
    }

    #[test]
    fn file_roundtrip_keeps_labels_and_eicar() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("signatures.txt");
        let h = util::hex(&util::sha256_bytes(b"sample"));
        std::fs::write(&path, format!("{h}\tUser\n")).unwrap();
        let db = SignatureDb::load(&path);
        assert_eq!(db.len(), 2);
        assert_eq!(db.lookup(&util::sha256_bytes(b"sample")), Some("User"));
        assert_eq!(db.lookup(&util::parse_sha256(EICAR_SHA256).unwrap()), Some("EICAR test file"));
    }
}
