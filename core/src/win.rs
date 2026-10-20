//! Thin, safe wrappers over the Win32 calls Fiend needs.

use crate::util::{from_wide, wide, wide_path};
use std::path::Path;
use std::ptr::{null, null_mut};

use windows_sys::Win32::Storage::FileSystem::{
    GetDiskFreeSpaceExW, GetDriveTypeW, GetLogicalDrives, GetVolumeInformationW,
};
use windows_sys::Win32::UI::Shell::{
    IsUserAnAdmin, SHEmptyRecycleBinW, SHFileOperationW, SHQueryRecycleBinW, ShellExecuteW,
    FOF_ALLOWUNDO, FOF_NOCONFIRMATION, FOF_NOERRORUI, FOF_SILENT, FO_DELETE, SHERB_NOCONFIRMATION,
    SHERB_NOPROGRESSUI, SHERB_NOSOUND, SHFILEOPSTRUCTW, SHQUERYRBINFO,
};

pub struct VolumeInfo {
    pub label: String,
    pub file_system: String,
}

/// Drive roots such as `C:\` for every assigned letter.
pub fn logical_drives() -> Vec<String> {
    let mask = unsafe { GetLogicalDrives() };
    (0..26u8)
        .filter(|i| mask & (1 << i) != 0)
        .map(|i| format!("{}:\\", (b'A' + i) as char))
        .collect()
}

/// 2 removable, 3 fixed, 4 network, 5 optical, 6 RAM disk.
pub fn drive_type(root: &str) -> u32 {
    let w = wide(root);
    unsafe { GetDriveTypeW(w.as_ptr()) }
}

pub fn volume_info(root: &str) -> Option<VolumeInfo> {
    let w = wide(root);
    let mut label = [0u16; 261];
    let mut fs = [0u16; 261];
    let ok = unsafe {
        GetVolumeInformationW(
            w.as_ptr(),
            label.as_mut_ptr(),
            label.len() as u32,
            null_mut(),
            null_mut(),
            null_mut(),
            fs.as_mut_ptr(),
            fs.len() as u32,
        )
    };
    (ok != 0).then(|| VolumeInfo {
        label: from_wide(&label),
        file_system: from_wide(&fs),
    })
}

/// (total bytes, free bytes available to the caller)
pub fn disk_space(root: &str) -> Option<(u64, u64)> {
    let w = wide(root);
    let mut free_to_caller = 0u64;
    let mut total = 0u64;
    let mut total_free = 0u64;
    let ok = unsafe { GetDiskFreeSpaceExW(w.as_ptr(), &mut free_to_caller, &mut total, &mut total_free) };
    (ok != 0).then_some((total, free_to_caller))
}

/// (bytes, item count) across all Recycle Bins.
pub fn recycle_bin_info() -> Option<(u64, u64)> {
    let mut info: SHQUERYRBINFO = unsafe { std::mem::zeroed() };
    info.cbSize = std::mem::size_of::<SHQUERYRBINFO>() as u32;
    let hr = unsafe { SHQueryRecycleBinW(null(), &mut info) };
    (hr == 0).then(|| (info.i64Size.max(0) as u64, info.i64NumItems.max(0) as u64))
}

pub fn empty_recycle_bin() -> Result<(), String> {
    let hr = unsafe {
        SHEmptyRecycleBinW(
            null_mut(),
            null(),
            SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND,
        )
    };
    // E_UNEXPECTED is returned when the bin is already empty.
    if hr == 0 || hr as u32 == 0x8000_FFFF {
        Ok(())
    } else {
        Err(format!("Windows could not empty the Recycle Bin (0x{:08X})", hr as u32))
    }
}

/// Moves files or folders to the Recycle Bin so the user can undo.
pub fn send_to_recycle_bin(paths: &[&Path]) -> Result<(), String> {
    if paths.is_empty() {
        return Ok(());
    }
    // Double-null-terminated list of paths.
    let mut from: Vec<u16> = Vec::new();
    for p in paths {
        from.extend(wide_path(p));
    }
    from.push(0);

    let mut op: SHFILEOPSTRUCTW = unsafe { std::mem::zeroed() };
    op.wFunc = FO_DELETE as _;
    op.pFrom = from.as_ptr();
    op.fFlags = (FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI) as _;
    let rc = unsafe { SHFileOperationW(&mut op) };
    if rc == 0 && op.fAnyOperationsAborted == 0 {
        Ok(())
    } else {
        Err(format!("Windows could not move the item to the Recycle Bin (code {rc})"))
    }
}

pub fn is_admin() -> bool {
    unsafe { IsUserAnAdmin() != 0 }
}

/// Starts `file` with `verb` ("open", "runas", ...). Returns false when Windows refuses
/// (for example when the user declines the UAC prompt).
pub fn shell_execute(verb: &str, file: &Path, params: &str) -> bool {
    let verb = wide(verb);
    let file = wide_path(file);
    let params = wide(params);
    let rc = unsafe {
        ShellExecuteW(
            null_mut(),
            verb.as_ptr(),
            file.as_ptr(),
            params.as_ptr(),
            null(),
            1, // SW_SHOWNORMAL
        )
    };
    rc as isize > 32
}
