//! System and app caches: what exists, how big it is, and cleaning it safely.

use crate::jobs::Ctx;
use crate::settings::{Cleaner, Settings};
use crate::{paths, util, win};
use rayon::prelude::*;
use serde::Serialize;
use std::fs::Metadata;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

#[derive(Clone, Debug, PartialEq)]
pub enum Kind {
    /// Every file under the roots.
    Files,
    /// Only files whose lowercase name starts with one of these prefixes.
    NamePrefix(Vec<&'static str>),
    RecycleBin,
}

#[derive(Clone, Debug)]
pub struct Category {
    pub id: String,
    pub name: String,
    pub description: String,
    pub group: &'static str,
    pub admin: bool,
    pub roots: Vec<PathBuf>,
    pub kind: Kind,
    pub max_depth: Option<usize>,
}

impl Category {
    fn new(id: &str, name: &str, description: &str, group: &'static str, roots: Vec<PathBuf>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            description: description.into(),
            group,
            admin: false,
            roots,
            kind: Kind::Files,
            max_depth: None,
        }
    }

    fn admin(mut self) -> Self {
        self.admin = true;
        self
    }
}

/// Cache folders inside every profile of a Chromium-based browser.
fn chromium_roots(user_data: &Path) -> Vec<PathBuf> {
    let mut roots = vec![user_data.join("ShaderCache"), user_data.join("GrShaderCache")];
    if let Ok(entries) = std::fs::read_dir(user_data) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name == "Default" || name.starts_with("Profile ") || name == "Guest Profile" {
                let profile = entry.path();
                for sub in ["Cache", "Code Cache", "GPUCache"] {
                    roots.push(profile.join(sub));
                }
            }
        }
    }
    roots
}

fn firefox_roots(local: &Path) -> Vec<PathBuf> {
    let profiles = local.join(r"Mozilla\Firefox\Profiles");
    std::fs::read_dir(profiles)
        .map(|entries| entries.flatten().map(|e| e.path().join("cache2")).collect())
        .unwrap_or_default()
}

pub fn builtin() -> Vec<Category> {
    let local = paths::local_appdata();
    let windows = paths::windows_dir();
    let program_data = paths::program_data();

    let mut thumbnails = Category::new(
        "thumbnails",
        "Thumbnail cache",
        "Preview images Explorer rebuilds on demand",
        "Windows",
        vec![local.join(r"Microsoft\Windows\Explorer")],
    );
    thumbnails.kind = Kind::NamePrefix(vec!["thumbcache_", "iconcache_"]);
    thumbnails.max_depth = Some(1);

    let mut recycle = Category::new(
        "recycle_bin",
        "Recycle Bin",
        "Files you deleted earlier. Emptying it is permanent",
        "Windows",
        vec![],
    );
    recycle.kind = Kind::RecycleBin;

    vec![
        Category::new("user_temp", "Temporary files", "Leftovers from installers and apps in your Temp folder", "Windows", vec![paths::temp()]),
        Category::new("windows_temp", "Windows temporary files", "System-wide Temp folder", "Windows", vec![windows.join("Temp")]).admin(),
        thumbnails,
        Category::new(
            "shader_cache",
            "Graphics shader cache",
            "Compiled shaders from DirectX, NVIDIA and AMD. Games rebuild them",
            "Windows",
            vec![local.join("D3DSCache"), local.join(r"NVIDIA\DXCache"), local.join(r"NVIDIA\GLCache"), local.join(r"AMD\DxCache")],
        ),
        Category::new("crash_dumps", "Crash dumps", "Memory dumps written when apps crash", "Windows", vec![local.join("CrashDumps")]),
        Category::new(
            "error_reports",
            "Error reports",
            "Windows Error Reporting archives for your account",
            "Windows",
            vec![local.join(r"Microsoft\Windows\WER\ReportArchive"), local.join(r"Microsoft\Windows\WER\ReportQueue")],
        ),
        Category::new(
            "system_error_reports",
            "System error reports",
            "Windows Error Reporting archives for all users",
            "Windows",
            vec![program_data.join(r"Microsoft\Windows\WER\ReportArchive"), program_data.join(r"Microsoft\Windows\WER\ReportQueue")],
        )
        .admin(),
        Category::new(
            "windows_update",
            "Windows Update downloads",
            "Update packages that are already installed",
            "Windows",
            vec![windows.join(r"SoftwareDistribution\Download")],
        )
        .admin(),
        recycle,
        Category::new("browser_chrome", "Google Chrome", "Web cache, code cache and GPU cache", "Browsers", chromium_roots(&local.join(r"Google\Chrome\User Data"))),
        Category::new("browser_edge", "Microsoft Edge", "Web cache, code cache and GPU cache", "Browsers", chromium_roots(&local.join(r"Microsoft\Edge\User Data"))),
        Category::new("browser_brave", "Brave", "Web cache, code cache and GPU cache", "Browsers", chromium_roots(&local.join(r"BraveSoftware\Brave-Browser\User Data"))),
        Category::new("browser_firefox", "Firefox", "Web cache for every profile", "Browsers", firefox_roots(&local)),
    ]
}

/// Built-in categories that exist on this PC plus the user's custom folders.
pub fn all(settings: &Settings) -> Vec<Category> {
    let mut cats: Vec<Category> = builtin()
        .into_iter()
        .map(|mut c| {
            c.roots.retain(|r| r.is_dir());
            c
        })
        .filter(|c| c.kind == Kind::RecycleBin || !c.roots.is_empty())
        .collect();

    for (i, custom) in settings.cleaner.custom_paths.iter().enumerate() {
        let path = PathBuf::from(paths::expand_env(custom.path.trim()));
        if custom.path.trim().is_empty() || !path.is_dir() || is_protected(&path) {
            continue;
        }
        let name = if custom.name.trim().is_empty() { util::file_name(&path) } else { custom.name.clone() };
        cats.push(Category::new(&format!("custom_{i}"), &name, &path.display().to_string(), "Custom", vec![path]));
    }
    cats
}

/// Folders a custom cache path may never point at.
pub fn is_protected(path: &Path) -> bool {
    let n = paths::norm(path);
    if n.len() <= 3 {
        return true; // a drive root
    }
    let protected = [
        paths::windows_dir(),
        paths::home(),
        paths::program_data(),
        PathBuf::from(r"C:\Program Files"),
        PathBuf::from(r"C:\Program Files (x86)"),
        paths::data_dir(),
    ];
    protected.iter().any(|p| paths::norm(p) == n)
        || paths::is_within(path, &paths::windows_dir().join("System32"))
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct CategoryReport {
    pub id: String,
    pub name: String,
    pub description: String,
    pub group: String,
    pub admin: bool,
    pub enabled: bool,
    pub roots: Vec<String>,
    pub size: u64,
    pub files: u64,
    pub eligible_size: u64,
    pub eligible_files: u64,
    pub denied: bool,
}

/// Walks the category's files. Returns true if a root could not be read.
fn for_each_file(cat: &Category, exclusions: &[String], ctx: &Ctx, mut f: impl FnMut(&Path, &Metadata)) -> bool {
    let mut denied = false;
    for root in &cat.roots {
        let mut walker = WalkDir::new(root).follow_links(false);
        if let Some(depth) = cat.max_depth {
            walker = walker.max_depth(depth);
        }
        let iter = walker
            .into_iter()
            .filter_entry(|e| !paths::is_excluded(e.path(), exclusions));
        for entry in iter {
            if ctx.cancelled() {
                return denied;
            }
            let entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    if e.depth() == 0 {
                        denied = true;
                    }
                    continue;
                }
            };
            if !entry.file_type().is_file() {
                continue;
            }
            if let Kind::NamePrefix(prefixes) = &cat.kind {
                let name = entry.file_name().to_string_lossy().to_lowercase();
                if !prefixes.iter().any(|p| name.starts_with(p)) {
                    continue;
                }
            }
            if let Ok(meta) = entry.metadata() {
                f(entry.path(), &meta);
            }
        }
    }
    denied
}

fn base_report(cat: &Category, cleaner: &Cleaner) -> CategoryReport {
    CategoryReport {
        id: cat.id.clone(),
        name: cat.name.clone(),
        description: cat.description.clone(),
        group: cat.group.to_string(),
        admin: cat.admin,
        enabled: cleaner.enabled.contains(&cat.id) || cat.group == "Custom",
        roots: cat.roots.iter().map(|r| r.display().to_string()).collect(),
        ..Default::default()
    }
}

pub fn analyze(cats: &[Category], cleaner: &Cleaner, ctx: &Ctx) -> Vec<CategoryReport> {
    ctx.set_phase("Measuring caches");
    ctx.total.store(cats.len() as u64, std::sync::atomic::Ordering::Relaxed);

    cats.par_iter()
        .map(|cat| {
            let mut report = base_report(cat, cleaner);
            if cat.kind == Kind::RecycleBin {
                if let Some((bytes, items)) = win::recycle_bin_info() {
                    report.size = bytes;
                    report.files = items;
                    report.eligible_size = bytes;
                    report.eligible_files = items;
                }
            } else {
                report.denied = for_each_file(cat, &cleaner.exclusions, ctx, |_, meta| {
                    report.size += meta.len();
                    report.files += 1;
                    if util::age_hours(meta) >= cleaner.min_age_hours as f64 {
                        report.eligible_size += meta.len();
                        report.eligible_files += 1;
                    }
                });
            }
            ctx.bytes.fetch_add(report.eligible_size, std::sync::atomic::Ordering::Relaxed);
            ctx.tick(&cat.name);
            report
        })
        .collect()
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct CleanCategory {
    pub id: String,
    pub name: String,
    pub freed: u64,
    pub deleted: u64,
    pub skipped: u64,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct CleanReport {
    pub dry_run: bool,
    pub freed: u64,
    pub deleted: u64,
    pub skipped: u64,
    pub categories: Vec<CleanCategory>,
}

fn delete_file(path: &Path) -> bool {
    match std::fs::remove_file(path) {
        Ok(()) => true,
        Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
            // Read-only files: clear the flag and try once more.
            if let Ok(meta) = std::fs::metadata(path) {
                let mut perms = meta.permissions();
                #[allow(clippy::permissions_set_readonly_false)]
                perms.set_readonly(false);
                let _ = std::fs::set_permissions(path, perms);
            }
            std::fs::remove_file(path).is_ok()
        }
        Err(_) => false,
    }
}

/// Removes folders left empty under a root, never the root itself.
fn prune_empty_dirs(root: &Path) {
    for entry in WalkDir::new(root).follow_links(false).contents_first(true).min_depth(1).into_iter().flatten() {
        if entry.file_type().is_dir() {
            let _ = std::fs::remove_dir(entry.path());
        }
    }
}

pub fn clean(cats: &[Category], ids: &[String], cleaner: &Cleaner, dry_run: bool, ctx: &Ctx) -> CleanReport {
    use std::sync::atomic::Ordering::Relaxed;
    ctx.set_phase(if dry_run { "Previewing" } else { "Cleaning" });
    let selected: Vec<&Category> = cats.iter().filter(|c| ids.contains(&c.id)).collect();
    ctx.total.store(selected.len() as u64, Relaxed);

    let mut report = CleanReport { dry_run, ..Default::default() };
    for cat in selected {
        if ctx.cancelled() {
            break;
        }
        ctx.set_current(&cat.name);
        let mut result = CleanCategory { id: cat.id.clone(), name: cat.name.clone(), ..Default::default() };

        if cat.kind == Kind::RecycleBin {
            let (bytes, items) = win::recycle_bin_info().unwrap_or((0, 0));
            if dry_run || win::empty_recycle_bin().is_ok() {
                result.freed = bytes;
                result.deleted = items;
            } else {
                result.skipped = items;
            }
        } else {
            let mut eligible = Vec::new();
            for_each_file(cat, &cleaner.exclusions, ctx, |path, meta| {
                if util::age_hours(meta) >= cleaner.min_age_hours as f64 {
                    eligible.push((path.to_path_buf(), meta.len()));
                }
            });
            for (path, size) in eligible {
                if ctx.cancelled() {
                    break;
                }
                if dry_run || delete_file(&path) {
                    result.freed += size;
                    result.deleted += 1;
                    ctx.bytes.fetch_add(size, Relaxed);
                } else {
                    result.skipped += 1;
                }
            }
            if !dry_run && cat.kind == Kind::Files {
                for root in &cat.roots {
                    prune_empty_dirs(root);
                }
            }
        }

        report.freed += result.freed;
        report.deleted += result.deleted;
        report.skipped += result.skipped;
        report.categories.push(result);
        ctx.tick(&cat.name);
    }
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use std::time::{Duration, SystemTime};

    fn make_file(path: &Path, size: usize, age_hours: u64) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, vec![7u8; size]).unwrap();
        let when = SystemTime::now() - Duration::from_secs(age_hours * 3600);
        File::options().write(true).open(path).unwrap().set_modified(when).unwrap();
    }

    fn fake_category(root: &Path) -> Category {
        Category::new("fake", "Fake cache", "test", "Custom", vec![root.to_path_buf()])
    }

    #[test]
    fn analyze_respects_age_and_exclusions() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        make_file(&root.join("old.tmp"), 1000, 48);
        make_file(&root.join("new.tmp"), 500, 0);
        make_file(&root.join(r"keep\old.tmp"), 300, 48);

        let cleaner = Cleaner {
            min_age_hours: 24,
            exclusions: vec![root.join("keep").display().to_string()],
            ..Default::default()
        };
        let reports = analyze(&[fake_category(root)], &cleaner, &Ctx::new());
        let r = &reports[0];
        assert_eq!(r.files, 2);
        assert_eq!(r.size, 1500);
        assert_eq!(r.eligible_files, 1);
        assert_eq!(r.eligible_size, 1000);
    }

    #[test]
    fn dry_run_deletes_nothing_and_real_clean_keeps_new_files() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        make_file(&root.join(r"a\old1.bin"), 100, 72);
        make_file(&root.join("old2.bin"), 200, 72);
        make_file(&root.join("fresh.bin"), 50, 0);
        let cats = [fake_category(root)];
        let ids = vec!["fake".to_string()];
        let cleaner = Cleaner { min_age_hours: 24, ..Default::default() };

        let preview = clean(&cats, &ids, &cleaner, true, &Ctx::new());
        assert_eq!((preview.deleted, preview.freed), (2, 300));
        assert!(root.join("old2.bin").exists());

        let done = clean(&cats, &ids, &cleaner, false, &Ctx::new());
        assert_eq!((done.deleted, done.freed, done.skipped), (2, 300, 0));
        assert!(!root.join("old2.bin").exists());
        assert!(!root.join("a").exists(), "empty folder is pruned");
        assert!(root.join("fresh.bin").exists());
        assert!(root.exists(), "root is never removed");
    }

    #[test]
    fn name_prefix_filter() {
        let dir = tempfile::tempdir().unwrap();
        make_file(&dir.path().join("thumbcache_256.db"), 10, 48);
        make_file(&dir.path().join("important.db"), 10, 48);
        let mut cat = fake_category(dir.path());
        cat.kind = Kind::NamePrefix(vec!["thumbcache_"]);
        let r = analyze(&[cat], &Cleaner { min_age_hours: 0, ..Default::default() }, &Ctx::new());
        assert_eq!(r[0].files, 1);
    }

    #[test]
    fn protected_paths_are_refused() {
        assert!(is_protected(Path::new(r"C:\")));
        assert!(is_protected(&paths::windows_dir()));
        assert!(is_protected(&paths::windows_dir().join(r"System32\drivers")));
        assert!(!is_protected(&paths::temp()));
    }
}
