//! Quarantine: flagged files are moved into Fiend's vault with their bytes scrambled so they
//! can't run, and can be restored later.

use crate::{paths, util};
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

const KEY: [u8; 16] = *b"fiend-quarantine";

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Entry {
    pub id: String,
    pub original_path: String,
    pub name: String,
    pub size: u64,
    pub sha256: String,
    pub reason: String,
    pub score: i32,
    pub quarantined_at: u64,
}

pub fn dir() -> PathBuf {
    paths::data_dir().join("Quarantine")
}

/// Copies `from` into `to`, XOR-ing every byte with the key. Returns the SHA-256 of the input.
fn scramble(from: &Path, to: &Path) -> std::io::Result<[u8; 32]> {
    use sha2::{Digest, Sha256};
    let mut reader = BufReader::new(File::open(from)?);
    let mut writer = BufWriter::new(File::create(to)?);
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 64 * 1024];
    let mut offset = 0usize;
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        for b in &mut buf[..n] {
            *b ^= KEY[offset % KEY.len()];
            offset += 1;
        }
        writer.write_all(&buf[..n])?;
    }
    writer.flush()?;
    Ok(hasher.finalize().into())
}

pub fn add_in(vault: &Path, path: &Path, reason: &str, score: i32) -> Result<Entry, String> {
    let meta = std::fs::metadata(path).map_err(|e| format!("Can't read {}: {e}", path.display()))?;
    if !meta.is_file() {
        return Err("Only files can be quarantined".into());
    }
    std::fs::create_dir_all(vault).map_err(|e| e.to_string())?;
    let id = format!("{}-{:08x}", util::now_secs(), rand_suffix(path));
    let blob = vault.join(format!("{id}.fq"));
    let hash = scramble(path, &blob).map_err(|e| {
        let _ = std::fs::remove_file(&blob);
        format!("Couldn't copy {} into quarantine: {e}", path.display())
    })?;
    if let Err(e) = std::fs::remove_file(path) {
        let _ = std::fs::remove_file(&blob);
        return Err(format!("{} is in use or protected, so it wasn't moved: {e}", util::file_name(path)));
    }
    let entry = Entry {
        id: id.clone(),
        original_path: path.display().to_string(),
        name: util::file_name(path),
        size: meta.len(),
        sha256: util::hex(&hash),
        reason: reason.to_string(),
        score,
        quarantined_at: util::now_secs(),
    };
    let json = serde_json::to_string_pretty(&entry).map_err(|e| e.to_string())?;
    std::fs::write(vault.join(format!("{id}.json")), json).map_err(|e| e.to_string())?;
    Ok(entry)
}

fn rand_suffix(path: &Path) -> u32 {
    let h = util::sha256_bytes(format!("{}{:?}", path.display(), std::time::Instant::now()).as_bytes());
    u32::from_le_bytes([h[0], h[1], h[2], h[3]])
}

pub fn list_in(vault: &Path) -> Vec<Entry> {
    let mut entries: Vec<Entry> = std::fs::read_dir(vault)
        .map(|rd| {
            rd.flatten()
                .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
                .filter_map(|e| std::fs::read_to_string(e.path()).ok())
                .filter_map(|t| serde_json::from_str(&t).ok())
                .collect()
        })
        .unwrap_or_default();
    entries.sort_by_key(|e| std::cmp::Reverse(e.quarantined_at));
    entries
}

fn find(vault: &Path, id: &str) -> Result<Entry, String> {
    if id.contains(['\\', '/', '.']) {
        return Err("Invalid quarantine id".into());
    }
    let text = std::fs::read_to_string(vault.join(format!("{id}.json"))).map_err(|_| "That item is no longer in quarantine".to_string())?;
    serde_json::from_str(&text).map_err(|e| e.to_string())
}

/// Puts the file back. If something already exists at the old path, restores next to it.
pub fn restore_in(vault: &Path, id: &str) -> Result<String, String> {
    let entry = find(vault, id)?;
    let original = PathBuf::from(&entry.original_path);
    let mut target = original.clone();
    if target.exists() {
        let stem = original.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        let ext = original.extension().map(|s| format!(".{}", s.to_string_lossy())).unwrap_or_default();
        target = original.with_file_name(format!("{stem} (restored){ext}"));
    }
    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let blob = vault.join(format!("{id}.fq"));
    scramble(&blob, &target).map_err(|e| format!("Couldn't restore the file: {e}"))?;
    let _ = std::fs::remove_file(&blob);
    let _ = std::fs::remove_file(vault.join(format!("{id}.json")));
    Ok(target.display().to_string())
}

pub fn delete_in(vault: &Path, id: &str) -> Result<(), String> {
    find(vault, id)?;
    let _ = std::fs::remove_file(vault.join(format!("{id}.fq")));
    std::fs::remove_file(vault.join(format!("{id}.json"))).map_err(|e| e.to_string())
}

pub fn add(path: &Path, reason: &str, score: i32) -> Result<Entry, String> {
    add_in(&dir(), path, reason, score)
}
pub fn list() -> Vec<Entry> {
    list_in(&dir())
}
pub fn restore(id: &str) -> Result<String, String> {
    restore_in(&dir(), id)
}
pub fn delete(id: &str) -> Result<(), String> {
    delete_in(&dir(), id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quarantine_roundtrip() {
        let work = tempfile::tempdir().unwrap();
        let vault = work.path().join("vault");
        let victim = work.path().join("suspect.exe");
        let content = b"MZ pretend payload".to_vec();
        std::fs::write(&victim, &content).unwrap();

        let entry = add_in(&vault, &victim, "Test", 80).unwrap();
        assert!(!victim.exists());
        let blob = std::fs::read(vault.join(format!("{}.fq", entry.id))).unwrap();
        assert_ne!(blob, content, "stored bytes are scrambled");
        assert_eq!(entry.sha256, util::hex(&util::sha256_bytes(&content)));
        assert_eq!(list_in(&vault).len(), 1);

        let restored = restore_in(&vault, &entry.id).unwrap();
        assert_eq!(std::fs::read(&restored).unwrap(), content);
        assert!(list_in(&vault).is_empty());
    }

    #[test]
    fn delete_removes_entry_and_rejects_bad_ids() {
        let work = tempfile::tempdir().unwrap();
        let vault = work.path().join("vault");
        let f = work.path().join("x.bat");
        std::fs::write(&f, b"echo").unwrap();
        let e = add_in(&vault, &f, "Test", 40).unwrap();
        assert!(delete_in(&vault, r"..\..\x").is_err());
        delete_in(&vault, &e.id).unwrap();
        assert!(list_in(&vault).is_empty());
    }
}
