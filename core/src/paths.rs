use std::path::{Path, PathBuf};

/// Where Fiend keeps settings, signatures and quarantine. `FIEND_DATA_DIR` overrides it (tests).
pub fn data_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("FIEND_DATA_DIR") {
        return PathBuf::from(dir);
    }
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Fiend")
}

pub fn ensure_data_dir() -> PathBuf {
    let dir = data_dir();
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn env_dir(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(fallback))
}

pub fn local_appdata() -> PathBuf {
    dirs::data_local_dir().unwrap_or_else(|| env_dir("LOCALAPPDATA", ""))
}

pub fn roaming() -> PathBuf {
    dirs::data_dir().unwrap_or_else(|| env_dir("APPDATA", ""))
}

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| env_dir("USERPROFILE", ""))
}

pub fn temp() -> PathBuf {
    std::env::temp_dir()
}

pub fn windows_dir() -> PathBuf {
    env_dir("SystemRoot", r"C:\Windows")
}

pub fn program_data() -> PathBuf {
    env_dir("ProgramData", r"C:\ProgramData")
}

pub fn public() -> PathBuf {
    env_dir("PUBLIC", r"C:\Users\Public")
}

pub fn downloads() -> Option<PathBuf> {
    dirs::download_dir()
}

pub fn desktop() -> Option<PathBuf> {
    dirs::desktop_dir()
}

pub fn startup_user() -> PathBuf {
    roaming().join(r"Microsoft\Windows\Start Menu\Programs\Startup")
}

pub fn startup_common() -> PathBuf {
    program_data().join(r"Microsoft\Windows\Start Menu\Programs\StartUp")
}

/// Lowercase, backslash-separated, no trailing separator.
pub fn norm(p: &Path) -> String {
    p.to_string_lossy()
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_lowercase()
}

/// True when `path` is `base` or inside it (case-insensitive).
pub fn is_within(path: &Path, base: &Path) -> bool {
    let p = norm(path);
    let b = norm(base);
    !b.is_empty() && (p == b || (p.starts_with(&b) && p.as_bytes().get(b.len()) == Some(&b'\\')))
}

pub fn is_excluded(path: &Path, exclusions: &[String]) -> bool {
    exclusions
        .iter()
        .map(|e| e.trim())
        .filter(|e| !e.is_empty())
        .any(|e| is_within(path, Path::new(&expand_env(e))))
}

/// Expands `%VAR%` references using the process environment.
pub fn expand_env(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while let Some(start) = rest.find('%') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        match after.find('%') {
            Some(end) if end > 0 => {
                let name = &after[..end];
                match std::env::var(name) {
                    Ok(value) => out.push_str(&value),
                    Err(_) => {
                        out.push('%');
                        out.push_str(name);
                        out.push('%');
                    }
                }
                rest = &after[end + 1..];
            }
            _ => {
                out.push('%');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn within_is_case_insensitive_and_boundary_safe() {
        assert!(is_within(Path::new(r"C:\Users\A\Temp\x.exe"), Path::new(r"c:\users\a\temp")));
        assert!(is_within(Path::new(r"C:\Data"), Path::new(r"C:\")));
        assert!(!is_within(Path::new(r"C:\Users\A\Temporary\x"), Path::new(r"C:\Users\A\Temp")));
    }

    #[test]
    fn expands_known_vars_only() {
        std::env::set_var("FIEND_TEST_VAR", "abc");
        assert_eq!(expand_env(r"%FIEND_TEST_VAR%\x"), r"abc\x");
        assert_eq!(expand_env("%NOPE_NOT_SET_42%"), "%NOPE_NOT_SET_42%");
        assert_eq!(expand_env("100%"), "100%");
    }
}
