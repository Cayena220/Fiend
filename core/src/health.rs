//! Physical drive health: identity, the NVMe health log (no admin needed), ATA SMART
//! attributes (admin), a plain-language verdict, and a daily history of wear.

use crate::{paths, util, win};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::{CloseHandle, GENERIC_READ, GENERIC_WRITE, HANDLE, INVALID_HANDLE_VALUE};
use windows_sys::Win32::Storage::FileSystem::{CreateFileW, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING};
use windows_sys::Win32::System::IO::DeviceIoControl;

const IOCTL_STORAGE_QUERY_PROPERTY: u32 = 0x002D_1400;
const IOCTL_DISK_GET_DRIVE_GEOMETRY_EX: u32 = 0x0007_00A0;
const IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS: u32 = 0x0056_0000;
const SMART_RCV_DRIVE_DATA: u32 = 0x0007_C088;

const BUS_ATAPI: u32 = 2;
const BUS_ATA: u32 = 3;
const BUS_USB: u32 = 7;
const BUS_RAID: u32 = 8;
const BUS_SATA: u32 = 11;
const BUS_NVME: u32 = 17;

const HISTORY_DAYS: usize = 400;

/// Everything a drive can tell us about its condition. Fields are absent when the drive
/// (or Windows, without admin rights) doesn't report them.
#[derive(Serialize, Clone, Debug, Default, PartialEq)]
pub struct Metrics {
    pub life_remaining: Option<u8>,
    pub temperature_c: Option<i32>,
    pub power_on_hours: Option<u64>,
    pub power_cycles: Option<u64>,
    pub unsafe_shutdowns: Option<u64>,
    pub data_written: Option<u64>,
    pub data_read: Option<u64>,
    pub media_errors: Option<u64>,
    pub available_spare: Option<u8>,
    pub spare_threshold: Option<u8>,
    pub critical_warning: Option<u8>,
    pub reallocated: Option<u64>,
    pub pending: Option<u64>,
    pub uncorrectable: Option<u64>,
    /// SMART attribute ids whose value has fallen to the vendor's failure threshold.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub failing_attributes: Vec<u8>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct HealthPoint {
    /// Days since 1970-01-01 (UTC).
    pub day: u64,
    pub life: Option<u8>,
    pub written: Option<u64>,
    pub hours: Option<u64>,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct DriveHealth {
    /// Stable key across runs: a short hash of model and serial number.
    pub id: String,
    pub number: u32,
    pub model: String,
    /// Last four characters only, enough to tell identical drives apart.
    pub serial_tail: String,
    pub firmware: String,
    pub bus: String,
    /// ssd, hdd or unknown
    pub kind: String,
    pub size: u64,
    pub letters: Vec<String>,
    /// nvme, smart or basic (identity only)
    pub source: String,
    pub needs_admin: bool,
    /// good, caution, bad or unknown
    pub status: String,
    pub reasons: Vec<String>,
    #[serde(flatten)]
    pub metrics: Metrics,
    /// Powered-on hours left at the wear rate so far, when it can be estimated.
    pub projection_hours: Option<u64>,
    pub history: Vec<HealthPoint>,
}

// ---------- byte helpers ----------

fn u16_at(b: &[u8], o: usize) -> u16 {
    b.get(o..o + 2).map(|s| u16::from_le_bytes([s[0], s[1]])).unwrap_or(0)
}

fn u32_at(b: &[u8], o: usize) -> u32 {
    b.get(o..o + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]])).unwrap_or(0)
}

fn u64_at(b: &[u8], o: usize) -> u64 {
    b.get(o..o + 8).map(|s| u64::from_le_bytes(s.try_into().unwrap())).unwrap_or(0)
}

fn cstr_at(b: &[u8], offset: u32) -> String {
    let o = offset as usize;
    if o == 0 || o >= b.len() {
        return String::new();
    }
    let end = b[o..].iter().position(|&c| c == 0).map(|e| o + e).unwrap_or(b.len());
    String::from_utf8_lossy(&b[o..end]).trim().to_string()
}

// ---------- parsing (pure, unit-tested) ----------

/// Parses the 512-byte NVMe SMART / Health Information log (log page 0x02).
pub fn parse_nvme_log(log: &[u8]) -> Option<Metrics> {
    if log.len() < 192 {
        return None;
    }
    let kelvin = u16_at(log, 1) as i32;
    let used = log[5].min(100);
    // Data units are thousands of 512-byte blocks.
    let units = |o: usize| u64_at(log, o).saturating_mul(512_000);
    Some(Metrics {
        critical_warning: Some(log[0]),
        temperature_c: (kelvin > 0).then_some(kelvin - 273),
        available_spare: Some(log[3]),
        spare_threshold: Some(log[4]),
        life_remaining: Some(100 - used),
        data_read: Some(units(32)),
        data_written: Some(units(48)),
        power_cycles: Some(u64_at(log, 112)),
        power_on_hours: Some(u64_at(log, 128)),
        unsafe_shutdowns: Some(u64_at(log, 144)),
        media_errors: Some(u64_at(log, 160)),
        ..Default::default()
    })
}

struct Attribute {
    id: u8,
    current: u8,
    raw: u64,
}

fn ata_attributes(data: &[u8]) -> Vec<Attribute> {
    (0..30)
        .filter_map(|i| {
            let e = data.get(2 + i * 12..2 + i * 12 + 12)?;
            let mut raw = [0u8; 8];
            raw[..6].copy_from_slice(&e[5..11]);
            (e[0] != 0).then(|| Attribute { id: e[0], current: e[3], raw: u64::from_le_bytes(raw) })
        })
        .collect()
}

/// Parses ATA SMART attribute data (and, when available, the matching thresholds).
pub fn parse_ata_smart(data: &[u8], thresholds: Option<&[u8]>, is_ssd: bool) -> Metrics {
    let attrs = ata_attributes(data);
    let mut m = Metrics::default();
    let low32 = |raw: u64| raw & 0xFFFF_FFFF;
    for a in &attrs {
        match a.id {
            5 => m.reallocated = Some(low32(a.raw)),
            9 => m.power_on_hours = Some(low32(a.raw)),
            12 => m.power_cycles = Some(low32(a.raw)),
            194 => m.temperature_c = Some((a.raw & 0xFF) as i32),
            190 if m.temperature_c.is_none() => m.temperature_c = Some((a.raw & 0xFF) as i32),
            197 => m.pending = Some(low32(a.raw)),
            198 => m.uncorrectable = Some(low32(a.raw)),
            192 => m.unsafe_shutdowns = Some(low32(a.raw)),
            241 => m.data_written = Some(a.raw.saturating_mul(512)),
            246 if m.data_written.is_none() => m.data_written = Some(a.raw.saturating_mul(512)),
            242 => m.data_read = Some(a.raw.saturating_mul(512)),
            _ => {}
        }
    }
    if is_ssd {
        // Vendors report remaining life under different ids; the normalized value is the percentage.
        for id in [231u8, 202, 233, 177] {
            if let Some(a) = attrs.iter().find(|a| a.id == id && a.current > 0 && a.current <= 100) {
                m.life_remaining = Some(a.current);
                break;
            }
        }
    }
    if let Some(t) = thresholds {
        for i in 0..30 {
            let Some(e) = t.get(2 + i * 12..2 + i * 12 + 2) else { break };
            let (id, limit) = (e[0], e[1]);
            if id != 0 && limit > 0 {
                if let Some(a) = attrs.iter().find(|a| a.id == id) {
                    if a.current <= limit {
                        m.failing_attributes.push(id);
                    }
                }
            }
        }
    }
    m
}

fn count(n: u64, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

/// Turns raw metrics into good / caution / bad with reasons a person can act on.
pub fn verdict(m: &Metrics, life_warning: u8) -> (String, Vec<String>) {
    let mut bad = Vec::new();
    let mut caution = Vec::new();

    if let Some(w) = m.critical_warning.filter(|w| *w != 0) {
        let parts: Vec<&str> = [
            (0x01, "spare space is running out"),
            (0x02, "temperature is outside the safe range"),
            (0x04, "reliability has degraded"),
            (0x08, "the drive has switched to read-only"),
            (0x10, "the backup power circuit failed"),
        ]
        .iter()
        .filter(|(bit, _)| w & bit != 0)
        .map(|(_, text)| *text)
        .collect();
        bad.push(if parts.is_empty() {
            "The drive reports a critical warning".to_string()
        } else {
            format!("The drive reports a critical warning: {}", parts.join(", "))
        });
    }
    if let Some(life) = m.life_remaining {
        if life < 5 {
            bad.push(format!("Only {life}% of its rated life is left. Back up and plan a replacement"));
        } else if life < life_warning {
            caution.push(format!("Only {life}% of its rated life is left"));
        }
    }
    if let (Some(spare), Some(limit)) = (m.available_spare, m.spare_threshold) {
        if limit > 0 && spare <= limit {
            bad.push(format!("Spare blocks are down to {spare}%, the drive's own limit"));
        }
    }
    if let Some(n) = m.media_errors.filter(|n| *n > 0) {
        bad.push(format!("{} recorded", count(n, "media error", "media errors")));
    }
    if let Some(n) = m.uncorrectable.filter(|n| *n > 0) {
        bad.push(format!("{} couldn't be read back", count(n, "sector", "sectors")));
    }
    if !m.failing_attributes.is_empty() {
        let ids: Vec<String> = m.failing_attributes.iter().map(|i| i.to_string()).collect();
        bad.push(format!("SMART attribute {} is past its failure threshold", ids.join(", ")));
    }
    if let Some(t) = m.temperature_c.filter(|t| *t >= 70) {
        caution.push(format!("Running hot at {t} °C"));
    }
    if let Some(n) = m.reallocated.filter(|n| *n > 0) {
        caution.push(format!("{} replaced with spares", count(n, "worn sector", "worn sectors")));
    }
    if let Some(n) = m.pending.filter(|n| *n > 0) {
        caution.push(format!("{} waiting to be checked", count(n, "unstable sector", "unstable sectors")));
    }

    if !bad.is_empty() {
        bad.extend(caution);
        ("bad".into(), bad)
    } else if !caution.is_empty() {
        ("caution".into(), caution)
    } else {
        ("good".into(), vec!["No warnings from the drive".into()])
    }
}

/// Powered-on hours left if wear continues at the same pace. Needs at least 1% wear.
pub fn projection(m: &Metrics) -> Option<u64> {
    let life = m.life_remaining? as u64;
    let used = 100 - life;
    let hours = m.power_on_hours.filter(|h| *h > 0)?;
    (used >= 1).then(|| hours * life / used)
}

// ---------- Windows access ----------

struct Device(HANDLE);

impl Device {
    fn open(path: &str, access: u32) -> Option<Self> {
        let w = util::wide(path);
        let h = unsafe { CreateFileW(w.as_ptr(), access, FILE_SHARE_READ | FILE_SHARE_WRITE, null(), OPEN_EXISTING, 0, null_mut()) };
        (h != INVALID_HANDLE_VALUE && !h.is_null()).then_some(Self(h))
    }

    /// Sends one IOCTL; `buf` is both the input and the output buffer.
    fn ioctl(&self, code: u32, buf: &mut [u8], input_len: usize) -> Option<usize> {
        let mut returned = 0u32;
        let ptr = buf.as_mut_ptr();
        let ok = unsafe {
            DeviceIoControl(self.0, code, ptr as *const _, input_len as u32, ptr as *mut _, buf.len() as u32, &mut returned, null_mut())
        };
        (ok != 0).then_some(returned as usize)
    }

    fn query_property(&self, property_id: u32, out_len: usize) -> Option<Vec<u8>> {
        let mut buf = vec![0u8; out_len.max(12)];
        buf[0..4].copy_from_slice(&property_id.to_le_bytes());
        let n = self.ioctl(IOCTL_STORAGE_QUERY_PROPERTY, &mut buf, 12)?;
        buf.truncate(n);
        Some(buf)
    }
}

impl Drop for Device {
    fn drop(&mut self) {
        unsafe { CloseHandle(self.0) };
    }
}

fn bus_name(bus: u32) -> &'static str {
    match bus {
        1 => "SCSI",
        BUS_ATAPI => "ATAPI",
        BUS_ATA => "ATA",
        BUS_USB => "USB",
        BUS_RAID => "RAID",
        10 => "SAS",
        BUS_SATA => "SATA",
        12 => "SD",
        14 | 15 => "Virtual",
        16 => "Storage Spaces",
        BUS_NVME => "NVMe",
        _ => "Unknown",
    }
}

fn read_nvme(dev: &Device) -> Option<Metrics> {
    let mut buf = vec![0u8; 8 + 40 + 512];
    buf[0..4].copy_from_slice(&50u32.to_le_bytes()); // StorageDeviceProtocolSpecificProperty
    buf[8..12].copy_from_slice(&3u32.to_le_bytes()); // ProtocolTypeNvme
    buf[12..16].copy_from_slice(&2u32.to_le_bytes()); // NVMeDataTypeLogPage
    buf[16..20].copy_from_slice(&2u32.to_le_bytes()); // SMART / health information
    buf[24..28].copy_from_slice(&40u32.to_le_bytes()); // data follows the 40-byte header
    buf[28..32].copy_from_slice(&512u32.to_le_bytes());
    let len = buf.len();
    let n = dev.ioctl(IOCTL_STORAGE_QUERY_PROPERTY, &mut buf, len)?;
    // STORAGE_PROTOCOL_DATA_DESCRIPTOR: the data offset and length sit inside the 40-byte header at 8.
    let offset = 8 + u32_at(&buf, 8 + 16) as usize;
    let size = u32_at(&buf, 8 + 20) as usize;
    if n == 0 || size < 192 || offset + size > buf.len() {
        return None;
    }
    parse_nvme_log(&buf[offset..offset + size])
}

fn smart_command(dev: &Device, number: u32, feature: u8) -> Option<Vec<u8>> {
    // SENDCMDINPARAMS is packed: 33 bytes. SENDCMDOUTPARAMS returns the 512-byte sector at offset 16.
    let mut buf = vec![0u8; 16 + 512];
    buf[0..4].copy_from_slice(&512u32.to_le_bytes());
    buf[4] = feature; // bFeaturesReg
    buf[5] = 1; // bSectorCountReg
    buf[6] = 1; // bSectorNumberReg
    buf[7] = 0x4F; // bCylLowReg
    buf[8] = 0xC2; // bCylHighReg
    buf[9] = 0xA0 | (((number & 1) as u8) << 4); // bDriveHeadReg
    buf[10] = 0xB0; // SMART_CMD
    buf[12] = number as u8;
    let n = dev.ioctl(SMART_RCV_DRIVE_DATA, &mut buf, 33)?;
    (n >= 16 + 362).then(|| buf[16..16 + 512].to_vec())
}

fn volume_disks(root: &str) -> Vec<u32> {
    let Some(dev) = Device::open(&format!(r"\\.\{}", root.trim_end_matches('\\')), 0) else { return vec![] };
    let mut buf = vec![0u8; 8 + 24 * 16];
    let Some(_) = dev.ioctl(IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, &mut buf, 0) else { return vec![] };
    let n = u32_at(&buf, 0).min(16) as usize;
    (0..n).map(|i| u32_at(&buf, 8 + i * 24)).collect()
}

fn letters_by_disk() -> HashMap<u32, Vec<String>> {
    let mut map: HashMap<u32, Vec<String>> = HashMap::new();
    for root in win::logical_drives() {
        // Skip network and optical drives: they have no physical disk here and can be slow.
        if matches!(win::drive_type(&root), 4 | 5) {
            continue;
        }
        for disk in volume_disks(&root) {
            let letter = root.trim_end_matches('\\').to_string();
            let entry = map.entry(disk).or_default();
            if !entry.contains(&letter) {
                entry.push(letter);
            }
        }
    }
    map
}

fn probe(number: u32, admin: bool, letters: &HashMap<u32, Vec<String>>) -> Option<DriveHealth> {
    let path = format!(r"\\.\PhysicalDrive{number}");
    let dev = Device::open(&path, 0)?;
    let desc = dev.query_property(0, 1024)?;
    let bus = u32_at(&desc, 28);
    let vendor = cstr_at(&desc, u32_at(&desc, 12));
    let product = cstr_at(&desc, u32_at(&desc, 16));
    let model = match (vendor.is_empty(), product.is_empty()) {
        (false, false) if !product.starts_with(&vendor) => format!("{vendor} {product}"),
        (_, false) => product,
        _ => vendor,
    };
    let serial = cstr_at(&desc, u32_at(&desc, 24)).trim_end_matches('.').trim().to_string();
    let kind = if bus == BUS_NVME {
        "ssd"
    } else {
        match dev.query_property(7, 12).filter(|d| d.len() >= 9) {
            Some(d) if d[8] != 0 => "hdd",
            Some(_) => "ssd",
            None => "unknown",
        }
    };
    let mut geometry = vec![0u8; 256];
    let size = dev.ioctl(IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, &mut geometry, 0).map(|_| u64_at(&geometry, 24)).unwrap_or(0);

    let key = if serial.is_empty() { format!("{model}|disk{number}") } else { format!("{model}|{serial}") };
    let serial_chars: Vec<char> = serial.chars().collect();
    let mut d = DriveHealth {
        id: util::hex(&util::sha256_bytes(key.as_bytes()))[..12].to_string(),
        number,
        serial_tail: serial_chars[serial_chars.len().saturating_sub(4)..].iter().collect(),
        firmware: cstr_at(&desc, u32_at(&desc, 20)),
        bus: bus_name(bus).into(),
        kind: kind.into(),
        size,
        letters: letters.get(&number).cloned().unwrap_or_default(),
        source: "basic".into(),
        model,
        ..Default::default()
    };

    let mut metrics = None;
    if bus == BUS_NVME || bus == BUS_RAID {
        metrics = read_nvme(&dev);
        if metrics.is_some() {
            d.source = "nvme".into();
        }
    }
    if metrics.is_none() && matches!(bus, BUS_SATA | BUS_ATA | BUS_ATAPI | BUS_RAID) {
        if admin {
            if let Some(rw) = Device::open(&path, GENERIC_READ | GENERIC_WRITE) {
                if let Some(attrs) = smart_command(&rw, number, 0xD0) {
                    let thresholds = smart_command(&rw, number, 0xD1);
                    metrics = Some(parse_ata_smart(&attrs, thresholds.as_deref(), kind == "ssd"));
                    d.source = "smart".into();
                }
            }
        } else {
            d.needs_admin = true;
        }
    }

    match metrics {
        Some(m) => d.metrics = m,
        None => {
            d.status = "unknown".into();
            d.reasons = vec![if d.needs_admin {
                "Windows only shares this drive's health data with administrators".into()
            } else if bus == BUS_USB {
                "USB enclosures usually hide the drive's health data".into()
            } else {
                "This drive doesn't report health data to Windows".into()
            }];
        }
    }
    Some(d)
}

// ---------- history ----------

fn history_path() -> std::path::PathBuf {
    paths::data_dir().join("drive_history.json")
}

/// Records today's reading for a drive (one per day, the latest wins) and returns its history.
pub fn record_in(file: &Path, id: &str, point: HealthPoint) -> Vec<HealthPoint> {
    let mut all: HashMap<String, Vec<HealthPoint>> =
        std::fs::read_to_string(file).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
    let list = all.entry(id.to_string()).or_default();
    match list.last_mut() {
        Some(last) if last.day == point.day => *last = point,
        _ => list.push(point),
    }
    if list.len() > HISTORY_DAYS {
        let extra = list.len() - HISTORY_DAYS;
        list.drain(..extra);
    }
    let result = list.clone();
    if let Some(dir) = file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(text) = serde_json::to_string(&all) {
        let _ = std::fs::write(file, text);
    }
    result
}

/// Reads every physical drive, judges its health and records today's snapshot.
pub fn report(life_warning: u8) -> Vec<DriveHealth> {
    let admin = win::is_admin();
    let letters = letters_by_disk();
    let today = util::now_secs() / 86_400;
    let mut drives: Vec<DriveHealth> = (0..32).filter_map(|n| probe(n, admin, &letters)).collect();
    for d in &mut drives {
        if d.source == "basic" {
            continue;
        }
        let (status, reasons) = verdict(&d.metrics, life_warning);
        d.status = status;
        d.reasons = reasons;
        d.projection_hours = projection(&d.metrics);
        let point = HealthPoint {
            day: today,
            life: d.metrics.life_remaining,
            written: d.metrics.data_written,
            hours: d.metrics.power_on_hours,
        };
        d.history = record_in(&history_path(), &d.id, point);
    }
    drives
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The real reading from the development machine's SK hynix BC901 NVMe SSD.
    fn nvme_fixture(critical: u8, used: u8, spare: u8) -> Vec<u8> {
        let mut log = vec![0u8; 512];
        log[0] = critical;
        log[1..3].copy_from_slice(&314u16.to_le_bytes()); // 41 °C
        log[3] = spare;
        log[4] = 10;
        log[5] = used;
        log[32..40].copy_from_slice(&80_000_000u64.to_le_bytes());
        log[48..56].copy_from_slice(&92_148_437u64.to_le_bytes());
        log[112..120].copy_from_slice(&24_269u64.to_le_bytes());
        log[128..136].copy_from_slice(&3_370u64.to_le_bytes());
        log[144..152].copy_from_slice(&79u64.to_le_bytes());
        log
    }

    fn attr(id: u8, current: u8, raw: u64) -> [u8; 12] {
        let mut e = [0u8; 12];
        e[0] = id;
        e[3] = current;
        e[4] = current;
        e[5..11].copy_from_slice(&raw.to_le_bytes()[..6]);
        e
    }

    fn smart_table(entries: &[[u8; 12]]) -> Vec<u8> {
        let mut data = vec![0u8; 512];
        for (i, e) in entries.iter().enumerate() {
            data[2 + i * 12..2 + i * 12 + 12].copy_from_slice(e);
        }
        data
    }

    #[test]
    fn parses_nvme_health_log() {
        let m = parse_nvme_log(&nvme_fixture(0, 7, 100)).unwrap();
        assert_eq!(m.life_remaining, Some(93));
        assert_eq!(m.temperature_c, Some(41));
        assert_eq!(m.power_on_hours, Some(3_370));
        assert_eq!(m.power_cycles, Some(24_269));
        assert_eq!(m.unsafe_shutdowns, Some(79));
        assert_eq!(m.media_errors, Some(0));
        assert_eq!(m.data_written, Some(92_148_437 * 512_000));
        assert_eq!(verdict(&m, 20).0, "good");
        assert_eq!(projection(&m), Some(3_370 * 93 / 7));
        assert!(parse_nvme_log(&[0u8; 64]).is_none());
    }

    #[test]
    fn nvme_over_100_percent_used_means_no_life_left() {
        let m = parse_nvme_log(&nvme_fixture(0, 255, 100)).unwrap();
        assert_eq!(m.life_remaining, Some(0));
        assert_eq!(verdict(&m, 20).0, "bad");
    }

    #[test]
    fn critical_warning_and_spare_are_bad() {
        let (status, reasons) = verdict(&parse_nvme_log(&nvme_fixture(0x04, 30, 100)).unwrap(), 20);
        assert_eq!(status, "bad");
        assert!(reasons[0].contains("reliability has degraded"));
        let (status, reasons) = verdict(&parse_nvme_log(&nvme_fixture(0, 30, 10)).unwrap(), 20);
        assert_eq!(status, "bad");
        assert!(reasons.iter().any(|r| r.contains("Spare blocks")));
    }

    #[test]
    fn life_warning_threshold_boundary() {
        let m = |life| Metrics { life_remaining: Some(life), ..Default::default() };
        assert_eq!(verdict(&m(20), 20).0, "good");
        assert_eq!(verdict(&m(19), 20).0, "caution");
        assert_eq!(verdict(&m(19), 10).0, "good");
        assert_eq!(verdict(&m(4), 10).0, "bad");
    }

    #[test]
    fn parses_sata_ssd_smart_with_a_remapped_sector() {
        let data = smart_table(&[
            attr(5, 100, 1),
            attr(9, 100, 12_345),
            attr(12, 100, 900),
            attr(194, 62, 0x0026_0014_0026), // 38 °C in the low byte
            attr(202, 64, 36),
            attr(246, 100, 1_000_000_000),
        ]);
        let thresholds = smart_table(&[[5, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]);
        let m = parse_ata_smart(&data, Some(&thresholds), true);
        assert_eq!(m.life_remaining, Some(64));
        assert_eq!(m.reallocated, Some(1));
        assert_eq!(m.power_on_hours, Some(12_345));
        assert_eq!(m.temperature_c, Some(38));
        assert_eq!(m.data_written, Some(512_000_000_000));
        assert!(m.failing_attributes.is_empty());
        let (status, reasons) = verdict(&m, 20);
        assert_eq!(status, "caution");
        assert_eq!(reasons, vec!["1 worn sector replaced with spares".to_string()]);
    }

    #[test]
    fn hdd_has_no_life_percentage_or_projection() {
        let data = smart_table(&[attr(9, 54, 41_200), attr(194, 110, 33), attr(231, 90, 0)]);
        let m = parse_ata_smart(&data, None, false);
        assert_eq!(m.life_remaining, None, "wear ids are ignored on spinning disks");
        assert_eq!(projection(&m), None);
        assert_eq!(verdict(&m, 20).0, "good");
    }

    #[test]
    fn attribute_past_threshold_is_bad() {
        let data = smart_table(&[attr(5, 9, 2_000)]);
        let thresholds = smart_table(&[[5, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]);
        let m = parse_ata_smart(&data, Some(&thresholds), false);
        assert_eq!(m.failing_attributes, vec![5]);
        assert_eq!(verdict(&m, 20).0, "bad");
    }

    #[test]
    fn no_projection_before_any_wear() {
        let m = Metrics { life_remaining: Some(100), power_on_hours: Some(50), ..Default::default() };
        assert_eq!(projection(&m), None);
    }

    #[test]
    fn history_keeps_one_point_per_day() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("history.json");
        let p = |day, life| HealthPoint { day, life: Some(life), written: None, hours: None };
        record_in(&file, "a", p(10, 95));
        record_in(&file, "a", p(10, 94));
        let h = record_in(&file, "a", p(11, 94));
        assert_eq!(h, vec![p(10, 94), p(11, 94)]);
        assert_eq!(record_in(&file, "b", p(11, 80)).len(), 1, "drives are kept apart");
    }

    #[test]
    fn reads_this_pcs_drives() {
        // probe() only reads; report() would also write history, so it isn't called here.
        let letters = letters_by_disk();
        let drives: Vec<DriveHealth> = (0..32).filter_map(|n| probe(n, false, &letters)).collect();
        assert!(!drives.is_empty(), "at least one physical drive");
        assert!(drives.iter().any(|d| d.letters.iter().any(|l| l.starts_with('C'))));
    }
}
