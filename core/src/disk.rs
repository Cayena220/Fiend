//! Drives and the space analyzer.

use crate::jobs::Ctx;
use crate::{paths, util, win};
use rayon::prelude::*;
use serde::Serialize;
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering::Relaxed;
use walkdir::WalkDir;

#[derive(Serialize, Clone, Debug)]
pub struct Drive {
    pub root: String,
    pub label: String,
    pub file_system: String,
    pub kind: String,
    pub total: u64,
    pub free: u64,
    pub used: u64,
    pub system: bool,
}

pub fn list_drives() -> Vec<Drive> {
    let system_root = paths::norm(&paths::windows_dir());
    win::logical_drives()
        .into_iter()
        .filter_map(|root| {
            let kind = match win::drive_type(&root) {
                2 => "removable",
                3 => "fixed",
                4 => "network",
                5 => "optical",
                6 => "ram",
                _ => return None,
            };
            let (total, free) = win::disk_space(&root)?;
            let info = win::volume_info(&root);
            Some(Drive {
                system: system_root.starts_with(&root[..2].to_lowercase()),
                label: info.as_ref().map(|i| i.label.clone()).unwrap_or_default(),
                file_system: info.map(|i| i.file_system).unwrap_or_default(),
                kind: kind.into(),
                used: total.saturating_sub(free),
                total,
                free,
                root,
            })
        })
        .collect()
}

pub fn file_kind(ext: &str) -> &'static str {
    match ext {
        "mp4" | "mkv" | "avi" | "mov" | "wmv" | "flv" | "webm" | "m4v" | "mpg" | "mpeg" => "Video",
        "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "wma" | "opus" => "Audio",
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "heic" | "tif" | "tiff" | "psd" | "raw" | "cr2" | "nef" | "svg" | "ico" => "Images",
        "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "md" | "rtf" | "odt" | "csv" | "epub" => "Documents",
        "zip" | "rar" | "7z" | "tar" | "gz" | "bz2" | "xz" | "iso" | "cab" | "img" | "vhd" | "vhdx" => "Archives & images",
        "exe" | "dll" | "msi" | "sys" | "appx" | "msix" | "msixbundle" => "Apps",
        "rs" | "dart" | "js" | "ts" | "py" | "java" | "c" | "cpp" | "h" | "cs" | "go" | "json" | "xml" | "html" | "css" | "yml" | "yaml" | "toml" | "lock" => "Code",
        "tmp" | "log" | "dmp" | "etl" | "pf" | "cache" | "dat" | "db" | "bin" | "pak" | "blob" => "System & app data",
        _ => "Other",
    }
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct Node {
    pub name: String,
    pub path: String,
    pub size: u64,
    pub files: u64,
    pub children: Vec<Node>,
}

#[derive(Serialize, Clone, Debug)]
pub struct FileEntry {
    pub path: String,
    pub name: String,
    pub size: u64,
    pub modified: u64,
    pub kind: &'static str,
}

#[derive(Serialize, Clone, Debug)]
pub struct KindStat {
    pub kind: &'static str,
    pub size: u64,
    pub files: u64,
}

#[derive(Serialize, Clone, Debug)]
pub struct Analysis {
    pub root: String,
    pub size: u64,
    pub files: u64,
    pub denied: u64,
    pub large_files: u64,
    pub tree: Node,
    pub top_files: Vec<FileEntry>,
    pub kinds: Vec<KindStat>,
    pub elapsed_ms: u128,
    pub cancelled: bool,
}

#[derive(Default)]
struct Partial {
    size: u64,
    files: u64,
    denied: u64,
    large: u64,
    children: HashMap<PathBuf, (u64, u64)>,
    top: BinaryHeap<Reverse<(u64, PathBuf, u64)>>,
    kinds: HashMap<&'static str, (u64, u64)>,
}

impl Partial {
    fn add_file(&mut self, path: &Path, size: u64, modified: u64, top_n: usize, large: u64) {
        self.size += size;
        self.files += 1;
        if size >= large {
            self.large += 1;
        }
        let k = self.kinds.entry(file_kind(&util::ext_lower(path))).or_default();
        k.0 += size;
        k.1 += 1;
        if top_n > 0 && (self.top.len() < top_n || self.top.peek().is_some_and(|Reverse(t)| size > t.0)) {
            self.top.push(Reverse((size, path.to_path_buf(), modified)));
            if self.top.len() > top_n {
                self.top.pop();
            }
        }
    }

    fn merge(&mut self, other: Partial, top_n: usize) {
        self.size += other.size;
        self.files += other.files;
        self.denied += other.denied;
        self.large += other.large;
        for (k, (s, f)) in other.kinds {
            let e = self.kinds.entry(k).or_default();
            e.0 += s;
            e.1 += f;
        }
        for item in other.top {
            self.top.push(item);
            if self.top.len() > top_n {
                self.top.pop();
            }
        }
    }
}

/// Walks one top-level folder, also totalling its immediate children.
fn walk_child(dir: &Path, top_n: usize, large: u64, ctx: &Ctx) -> Partial {
    let mut part = Partial::default();
    for entry in WalkDir::new(dir).follow_links(false) {
        if ctx.cancelled() {
            break;
        }
        let entry = match entry {
            Ok(e) => e,
            Err(_) => {
                part.denied += 1;
                continue;
            }
        };
        if !entry.file_type().is_file() {
            continue;
        }
        let Ok(meta) = entry.metadata() else { continue };
        // Cloud placeholders take no local space.
        let size = if util::is_cloud_placeholder(&meta) { 0 } else { meta.len() };
        part.add_file(entry.path(), size, util::modified_secs(&meta), top_n, large);
        ctx.bytes.fetch_add(size, Relaxed);
        ctx.tick(&entry.path().to_string_lossy());

        if entry.depth() >= 2 {
            if let Ok(rel) = entry.path().strip_prefix(dir) {
                if let Some(first) = rel.components().next() {
                    let c = part.children.entry(dir.join(first)).or_default();
                    c.0 += size;
                    c.1 += 1;
                }
            }
        }
    }
    part
}

pub fn analyze(root: &Path, top_n: usize, large_file_bytes: u64, ctx: &Ctx) -> Result<Analysis, String> {
    let started = std::time::Instant::now();
    ctx.set_phase("Mapping folders");
    let entries: Vec<_> = std::fs::read_dir(root)
        .map_err(|e| format!("Fiend can't open {}: {e}", root.display()))?
        .flatten()
        .collect();

    let mut total = Partial::default();
    let mut loose = Node { name: "Files in this folder".into(), path: root.display().to_string(), ..Default::default() };
    let mut dirs = Vec::new();
    for entry in entries {
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_dir() && !ft.is_symlink() {
            dirs.push(entry.path());
        } else if ft.is_file() {
            if let Ok(meta) = entry.metadata() {
                let size = if util::is_cloud_placeholder(&meta) { 0 } else { meta.len() };
                total.add_file(&entry.path(), size, util::modified_secs(&meta), top_n, large_file_bytes);
                loose.size += size;
                loose.files += 1;
            }
        }
    }
    ctx.total.store(dirs.len() as u64, Relaxed);

    let parts: Vec<(PathBuf, Partial)> = dirs
        .par_iter()
        .map(|d| (d.clone(), walk_child(d, top_n, large_file_bytes, ctx)))
        .collect();

    let mut children = Vec::new();
    for (dir, part) in parts {
        let mut grand: Vec<Node> = part
            .children
            .iter()
            .map(|(p, (s, f))| Node { name: util::file_name(p), path: p.display().to_string(), size: *s, files: *f, children: vec![] })
            .collect();
        grand.sort_by_key(|n| Reverse(n.size));
        grand.truncate(24);
        children.push(Node { name: util::file_name(&dir), path: dir.display().to_string(), size: part.size, files: part.files, children: grand });
        total.merge(part, top_n);
    }
    if loose.files > 0 {
        children.push(loose);
    }
    children.sort_by_key(|n| Reverse(n.size));

    let mut top_files: Vec<FileEntry> = total
        .top
        .into_sorted_vec()
        .into_iter()
        .map(|Reverse((size, path, modified))| FileEntry {
            name: util::file_name(&path),
            kind: file_kind(&util::ext_lower(&path)),
            path: path.display().to_string(),
            size,
            modified,
        })
        .collect();
    top_files.sort_by_key(|f| Reverse(f.size));

    let mut kinds: Vec<KindStat> = total.kinds.into_iter().map(|(kind, (size, files))| KindStat { kind, size, files }).collect();
    kinds.sort_by_key(|k| Reverse(k.size));

    Ok(Analysis {
        root: root.display().to_string(),
        size: total.size,
        files: total.files,
        denied: total.denied,
        large_files: total.large,
        tree: Node { name: root.display().to_string(), path: root.display().to_string(), size: total.size, files: total.files, children },
        top_files,
        kinds,
        elapsed_ms: started.elapsed().as_millis(),
        cancelled: ctx.cancelled(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn analyzer_totals_tree_and_top_files() {
        let dir = tempfile::tempdir().unwrap();
        let r = dir.path();
        fs::create_dir_all(r.join(r"videos\trips")).unwrap();
        fs::create_dir_all(r.join("docs")).unwrap();
        fs::write(r.join(r"videos\trips\a.mp4"), vec![0u8; 5000]).unwrap();
        fs::write(r.join(r"videos\b.mkv"), vec![0u8; 3000]).unwrap();
        fs::write(r.join(r"docs\c.pdf"), vec![0u8; 100]).unwrap();
        fs::write(r.join("loose.txt"), vec![0u8; 10]).unwrap();

        let a = analyze(r, 2, 4000, &Ctx::new()).unwrap();
        assert_eq!(a.size, 8110);
        assert_eq!(a.files, 4);
        assert_eq!(a.large_files, 1);
        assert_eq!(a.tree.children[0].name, "videos");
        assert_eq!(a.tree.children[0].size, 8000);
        assert_eq!(a.tree.children[0].children[0].name, "trips");
        assert_eq!(a.top_files.len(), 2);
        assert_eq!(a.top_files[0].name, "a.mp4");
        assert_eq!(a.kinds[0].kind, "Video");
    }

    #[test]
    fn lists_at_least_the_system_drive() {
        let drives = list_drives();
        assert!(drives.iter().any(|d| d.system && d.total > 0));
    }
}
