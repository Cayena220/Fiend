//! Authenticode signature check through WinVerifyTrust (embedded signatures, no network).

use crate::util::wide_path;
use std::ffi::c_void;
use std::path::Path;
use std::ptr::null_mut;
use windows_sys::Win32::Security::WinTrust::{
    WinVerifyTrust, WINTRUST_ACTION_GENERIC_VERIFY_V2, WINTRUST_DATA, WINTRUST_FILE_INFO,
    WTD_CACHE_ONLY_URL_RETRIEVAL, WTD_CHOICE_FILE, WTD_REVOKE_NONE, WTD_STATEACTION_CLOSE,
    WTD_STATEACTION_VERIFY, WTD_UI_NONE,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Trust {
    Signed,
    Unsigned,
    Expired,
    /// The file couldn't be opened for checking (for example a Store app alias).
    Unknown,
    Untrusted(u32),
}

impl Trust {
    pub fn as_str(&self) -> &'static str {
        match self {
            Trust::Signed => "signed",
            Trust::Unsigned => "unsigned",
            Trust::Expired => "expired",
            Trust::Unknown => "unknown",
            Trust::Untrusted(_) => "untrusted",
        }
    }
}

const TRUST_E_NOSIGNATURE: u32 = 0x800B_0100;
const TRUST_E_SUBJECT_FORM_UNKNOWN: u32 = 0x800B_0003;
const TRUST_E_PROVIDER_UNKNOWN: u32 = 0x800B_0001;
const CERT_E_EXPIRED: u32 = 0x800B_0101;

pub fn verify(path: &Path) -> Trust {
    // App execution aliases (WindowsApps) and other unreadable or empty files can't be checked.
    if !std::fs::metadata(path).is_ok_and(|m| m.len() > 0) {
        return Trust::Unknown;
    }
    let wpath = wide_path(path);
    let mut file_info = WINTRUST_FILE_INFO {
        cbStruct: std::mem::size_of::<WINTRUST_FILE_INFO>() as u32,
        pcwszFilePath: wpath.as_ptr(),
        hFile: null_mut(),
        pgKnownSubject: null_mut(),
    };
    let mut data: WINTRUST_DATA = unsafe { std::mem::zeroed() };
    data.cbStruct = std::mem::size_of::<WINTRUST_DATA>() as u32;
    data.dwUIChoice = WTD_UI_NONE;
    data.fdwRevocationChecks = WTD_REVOKE_NONE;
    data.dwUnionChoice = WTD_CHOICE_FILE;
    data.Anonymous.pFile = &mut file_info;
    data.dwStateAction = WTD_STATEACTION_VERIFY;
    data.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;

    let mut action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    let status = unsafe { WinVerifyTrust(null_mut(), &mut action, &mut data as *mut _ as *mut c_void) } as u32;

    data.dwStateAction = WTD_STATEACTION_CLOSE;
    unsafe { WinVerifyTrust(null_mut(), &mut action, &mut data as *mut _ as *mut c_void) };

    match status {
        0 => Trust::Signed,
        TRUST_E_NOSIGNATURE | TRUST_E_SUBJECT_FORM_UNKNOWN | TRUST_E_PROVIDER_UNKNOWN => Trust::Unsigned,
        CERT_E_EXPIRED => Trust::Expired,
        // Plain Win32 errors (0x8007xxxx) mean the file itself couldn't be read.
        code if code >> 16 == 0x8007 => Trust::Unknown,
        code => Trust::Untrusted(code),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_text_file_is_unsigned() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("note.txt");
        std::fs::write(&f, b"hello").unwrap();
        assert_eq!(verify(&f), Trust::Unsigned);
    }

    #[test]
    fn signed_browser_binary_verifies() {
        // Browsers ship with embedded signatures; many inbox Windows files are catalog-signed instead.
        for exe in [
            r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        ] {
            let exe = Path::new(exe);
            if exe.exists() {
                assert_eq!(verify(exe), Trust::Signed, "{}", exe.display());
            }
        }
    }
}
