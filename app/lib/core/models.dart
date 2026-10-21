import 'dart:convert';

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
int? _iOrNull(dynamic v) => (v as num?)?.toInt();
String _s(dynamic v) => v?.toString() ?? '';
String? _sOrNull(dynamic v) => v?.toString();
bool _b(dynamic v) => v == true;

/// Deep copy into plain JSON maps and lists, so every nested map is `Map<String, dynamic>`.
Map<String, dynamic> _plain(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();

/// User preferences. Wraps the engine's settings JSON so unknown keys survive round trips.
class Settings {
  Settings(this.raw);

  factory Settings.defaults() => Settings(_plain({
        'appearance': {
          'accent': 'hellfire',
          'custom_accent': '#FF3B4E',
          'depth': 'abyss',
          'density': 'comfortable',
          'radius': 10.0,
          'glow': true,
          'reduce_motion': false,
        },
        'dashboard': {
          'cards': ['health', 'drives', 'cache', 'shield', 'actions'],
          'hidden': <String>[],
        },
        'cleaner': {'enabled': <String>[], 'min_age_hours': 24, 'custom_paths': [], 'exclusions': <String>[]},
        'shield': {
          'sensitivity': 'balanced',
          'extra_locations': <String>[],
          'exclusions': <String>[],
          'allowlist': <String>[],
          'use_defender': true,
          'auto_quarantine': false,
          'scan_on_launch': false,
          'verify_signatures': true,
          'max_file_mb': 200,
        },
        'disk': {'large_file_mb': 500, 'top_files': 50, 'temperature_unit': 'c', 'life_warning': 20},
        'updates': {'check_on_launch': true, 'skipped_version': ''},
      }));

  final Map<String, dynamic> raw;

  Map<String, dynamic> section(String name) =>
      (raw[name] ??= <String, dynamic>{}) as Map<String, dynamic>;

  T get<T>(String sec, String key, T fallback) {
    final v = section(sec)[key];
    if (v is T) return v;
    if (T == double && v is num) return v.toDouble() as T;
    if (T == int && v is num) return v.toInt() as T;
    return fallback;
  }

  void set(String sec, String key, Object? value) => section(sec)[key] = value;

  List<String> strings(String sec, String key) =>
      ((section(sec)[key] as List?) ?? const []).map((e) => e.toString()).toList();

  Settings copy() => Settings(_plain(raw));

  String get accent => get('appearance', 'accent', 'hellfire');
  String get customAccent => get('appearance', 'custom_accent', '#FF3B4E');
  String get depth => get('appearance', 'depth', 'abyss');
  String get density => get('appearance', 'density', 'comfortable');
  double get radius => get('appearance', 'radius', 10.0);
  bool get glow => get('appearance', 'glow', true);
  bool get reduceMotion => get('appearance', 'reduce_motion', false);

  List<String> get dashboardCards => strings('dashboard', 'cards');
  List<String> get dashboardHidden => strings('dashboard', 'hidden');

  int get minAgeHours => get('cleaner', 'min_age_hours', 24);
  List<String> get cleanerEnabled => strings('cleaner', 'enabled');
  List<String> get cleanerExclusions => strings('cleaner', 'exclusions');
  List<Map<String, dynamic>> get customPaths =>
      ((section('cleaner')['custom_paths'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  String get sensitivity => get('shield', 'sensitivity', 'balanced');
  bool get useDefender => get('shield', 'use_defender', true);
  bool get autoQuarantine => get('shield', 'auto_quarantine', false);
  bool get scanOnLaunch => get('shield', 'scan_on_launch', false);
  bool get verifySignatures => get('shield', 'verify_signatures', true);
  int get maxFileMb => get('shield', 'max_file_mb', 200);
  List<String> get extraLocations => strings('shield', 'extra_locations');
  List<String> get shieldExclusions => strings('shield', 'exclusions');
  List<String> get allowlist => strings('shield', 'allowlist');

  int get largeFileMb => get('disk', 'large_file_mb', 500);
  int get topFiles => get('disk', 'top_files', 50);
  String get temperatureUnit => get('disk', 'temperature_unit', 'c');
  int get lifeWarning => get('disk', 'life_warning', 20);

  bool get checkUpdates => get('updates', 'check_on_launch', true);
  String get skippedVersion => get('updates', 'skipped_version', '');
}

class SystemInfo {
  SystemInfo(this.j);
  final Map<String, dynamic> j;
  String get os => _s(j['os']);
  String get version => _s(j['version']);
  int get build => _i(j['build']);
  String get computer => _s(j['computer']);
  String get user => _s(j['user']);
  bool get admin => _b(j['admin']);
  bool get defender => _b(j['defender']);
  String get dataDir => _s(j['data_dir']);
  String get coreVersion => _s(j['core_version']);
  /// From Fiend.exe's version resource; null when running without one.
  String? get appVersion => _sOrNull(j['app_version']);
  String get exePath => _s(j['exe_path']);
}

class EngineState {
  EngineState(this.j);
  final Map<String, dynamic> j;
  int? get lastScanAt => _iOrNull(j['last_scan_at']);
  String get lastScanMode => _s(j['last_scan_mode']);
  int get lastScanFiles => _i(j['last_scan_files']);
  int get lastScanFindings => _i(j['last_scan_findings']);
  int? get lastCleanAt => _iOrNull(j['last_clean_at']);
  int get totalFreed => _i(j['total_freed']);
  int? get signaturesUpdatedAt => _iOrNull(j['signatures_updated_at']);
}

class Drive {
  Drive(Map<String, dynamic> j)
      : root = _s(j['root']),
        label = _s(j['label']),
        fileSystem = _s(j['file_system']),
        kind = _s(j['kind']),
        total = _i(j['total']),
        free = _i(j['free']),
        used = _i(j['used']),
        system = _b(j['system']);

  final String root, label, fileSystem, kind;
  final int total, free, used;
  final bool system;

  double get usedFraction => total == 0 ? 0 : used / total;
  double get freeFraction => total == 0 ? 0 : free / total;
  String get letter => root.replaceAll('\\', '');
  String get title => label.isEmpty ? (system ? 'Windows' : 'Local disk') : label;
}

class CacheCategory {
  CacheCategory(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        description = _s(j['description']),
        group = _s(j['group']),
        admin = _b(j['admin']),
        enabled = _b(j['enabled']),
        denied = _b(j['denied']),
        size = _i(j['size']),
        files = _i(j['files']),
        eligibleSize = _i(j['eligible_size']),
        eligibleFiles = _i(j['eligible_files']),
        roots = (j['roots'] as List? ?? const []).map((e) => e.toString()).toList();

  final String id, name, description, group;
  final bool admin, enabled, denied;
  final int size, files, eligibleSize, eligibleFiles;
  final List<String> roots;

  bool get isRecycleBin => id == 'recycle_bin';
  bool get isBrowser => id.startsWith('browser_');
}

class CleanReport {
  CleanReport(Map<String, dynamic> j)
      : dryRun = _b(j['dry_run']),
        freed = _i(j['freed']),
        deleted = _i(j['deleted']),
        skipped = _i(j['skipped']);
  final bool dryRun;
  final int freed, deleted, skipped;
}

class DirNode {
  DirNode(Map<String, dynamic> j)
      : name = _s(j['name']),
        path = _s(j['path']),
        size = _i(j['size']),
        files = _i(j['files']),
        children = _list(j['children'], DirNode.new);
  final String name, path;
  final int size, files;
  final List<DirNode> children;
}

class FileEntry {
  FileEntry(Map<String, dynamic> j)
      : path = _s(j['path']),
        name = _s(j['name']),
        kind = _s(j['kind']),
        size = _i(j['size']),
        modified = _i(j['modified']);
  final String path, name, kind;
  final int size, modified;
}

class KindStat {
  KindStat(Map<String, dynamic> j)
      : kind = _s(j['kind']),
        size = _i(j['size']),
        files = _i(j['files']);
  final String kind;
  final int size, files;
}

class DiskAnalysis {
  DiskAnalysis(Map<String, dynamic> j)
      : root = _s(j['root']),
        size = _i(j['size']),
        files = _i(j['files']),
        denied = _i(j['denied']),
        largeFiles = _i(j['large_files']),
        tree = DirNode((j['tree'] as Map).cast<String, dynamic>()),
        topFiles = _list(j['top_files'], FileEntry.new),
        kinds = _list(j['kinds'], KindStat.new),
        elapsedMs = _i(j['elapsed_ms']),
        cancelled = _b(j['cancelled']);
  final String root;
  final int size, files, denied, largeFiles, elapsedMs;
  final DirNode tree;
  final List<FileEntry> topFiles;
  final List<KindStat> kinds;
  final bool cancelled;
}

class Reason {
  Reason(Map<String, dynamic> j)
      : code = _s(j['code']),
        label = _s(j['label']),
        weight = _i(j['weight']);
  final String code, label;
  final int weight;
}

class DefenderResult {
  DefenderResult(Map<String, dynamic> j)
      : status = _s(j['status']),
        threat = _sOrNull(j['threat']),
        detail = _s(j['detail']);
  final String status;
  final String? threat;
  final String detail;
}

class Finding {
  Finding(Map<String, dynamic> j)
      : id = _s(j['id']),
        path = _s(j['path']),
        name = _s(j['name']),
        size = _i(j['size']),
        modified = _i(j['modified']),
        score = _i(j['score']),
        severity = _s(j['severity']),
        reasons = _list(j['reasons'], Reason.new),
        sha256 = _sOrNull(j['sha256']),
        signed = _sOrNull(j['signed']),
        defender = j['defender'] == null
            ? null
            : DefenderResult((j['defender'] as Map).cast<String, dynamic>()),
        quarantineId = _sOrNull(j['quarantine_id']);

  final String id, path, name, severity;
  final int size, modified, score;
  final List<Reason> reasons;
  final String? sha256, signed;
  DefenderResult? defender;
  String? quarantineId;
  bool dismissed = false;

  String get headline =>
      (reasons.where((r) => r.weight > 0).toList()..sort((a, b) => b.weight.compareTo(a.weight)))
          .map((r) => r.label)
          .firstOrNull ??
      'Suspicious file';
}

class StartupItem {
  StartupItem(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        command = _s(j['command']),
        target = _sOrNull(j['target']),
        location = _s(j['location']),
        source = _s(j['source']),
        exists = _b(j['exists']),
        signed = _sOrNull(j['signed']),
        score = _i(j['score']),
        severity = _s(j['severity']),
        reasons = _list(j['reasons'], Reason.new);

  final String id, name, command, location, source, severity;
  final String? target, signed;
  final bool exists;
  final int score;
  final List<Reason> reasons;
}

class DisabledStartup {
  DisabledStartup(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        command = _s(j['command']),
        location = _s(j['location']),
        source = _s(j['source']),
        disabledAt = _i(j['disabled_at']);
  final String id, name, command, location, source;
  final int disabledAt;
}

class ScanReport {
  ScanReport(Map<String, dynamic> j)
      : mode = _s(j['mode']),
        startedAt = _i(j['started_at']),
        elapsedMs = _i(j['elapsed_ms']),
        roots = (j['roots'] as List? ?? const []).map((e) => e.toString()).toList(),
        filesSeen = _i(j['files_seen']),
        filesExamined = _i(j['files_examined']),
        findings = _list(j['findings'], Finding.new),
        startup = _list(j['startup'], StartupItem.new),
        threshold = _i(j['threshold']),
        signatures = _i(j['signatures']),
        defenderUsed = _b(j['defender_used']),
        cancelled = _b(j['cancelled']);

  final String mode;
  final int startedAt, elapsedMs, filesSeen, filesExamined, threshold, signatures;
  final List<String> roots;
  final List<Finding> findings;
  final List<StartupItem> startup;
  final bool defenderUsed, cancelled;

  Iterable<Finding> get open => findings.where((f) => f.quarantineId == null && !f.dismissed);
  int count(String severity) => open.where((f) => f.severity == severity).length;
}

class QuarantineEntry {
  QuarantineEntry(Map<String, dynamic> j)
      : id = _s(j['id']),
        originalPath = _s(j['original_path']),
        name = _s(j['name']),
        size = _i(j['size']),
        sha256 = _s(j['sha256']),
        reason = _s(j['reason']),
        score = _i(j['score']),
        quarantinedAt = _i(j['quarantined_at']);
  final String id, originalPath, name, sha256, reason;
  final int size, score, quarantinedAt;
}

class HealthPoint {
  HealthPoint(Map<String, dynamic> j)
      : day = _i(j['day']),
        life = _iOrNull(j['life']),
        written = _iOrNull(j['written']),
        hours = _iOrNull(j['hours']);
  final int day;
  final int? life, written, hours;
}

/// One physical drive's health, as read from its NVMe log or SMART data.
class DriveHealth {
  DriveHealth(Map<String, dynamic> j)
      : id = _s(j['id']),
        model = _s(j['model']),
        serialTail = _s(j['serial_tail']),
        firmware = _s(j['firmware']),
        bus = _s(j['bus']),
        kind = _s(j['kind']),
        size = _i(j['size']),
        letters = (j['letters'] as List? ?? const []).map((e) => e.toString()).toList(),
        source = _s(j['source']),
        needsAdmin = _b(j['needs_admin']),
        status = _s(j['status']),
        reasons = (j['reasons'] as List? ?? const []).map((e) => e.toString()).toList(),
        lifeRemaining = _iOrNull(j['life_remaining']),
        temperatureC = _iOrNull(j['temperature_c']),
        powerOnHours = _iOrNull(j['power_on_hours']),
        powerCycles = _iOrNull(j['power_cycles']),
        unsafeShutdowns = _iOrNull(j['unsafe_shutdowns']),
        dataWritten = _iOrNull(j['data_written']),
        dataRead = _iOrNull(j['data_read']),
        mediaErrors = _iOrNull(j['media_errors']),
        availableSpare = _iOrNull(j['available_spare']),
        spareThreshold = _iOrNull(j['spare_threshold']),
        reallocated = _iOrNull(j['reallocated']),
        pending = _iOrNull(j['pending']),
        uncorrectable = _iOrNull(j['uncorrectable']),
        projectionHours = _iOrNull(j['projection_hours']),
        history = _list(j['history'], HealthPoint.new);

  final String id, model, serialTail, firmware, bus, kind, source, status;
  final int size;
  final List<String> letters, reasons;
  final bool needsAdmin;
  final int? lifeRemaining, temperatureC, powerOnHours, powerCycles, unsafeShutdowns;
  final int? dataWritten, dataRead, mediaErrors, availableSpare, spareThreshold;
  final int? reallocated, pending, uncorrectable, projectionHours;
  final List<HealthPoint> history;

  bool get hasData => source != 'basic';

  /// "NVMe SSD", "SATA SSD", "SATA HDD", "USB drive".
  String get kindLabel => switch (kind) {
        'ssd' => '$bus SSD',
        'hdd' => '$bus HDD',
        _ => '$bus drive',
      };
}

class JobProgress {
  JobProgress(Map<String, dynamic> j)
      : phase = _s(j['phase']),
        current = _s(j['current']),
        done = _i(j['done']),
        total = _i(j['total']),
        bytes = _i(j['bytes']),
        found = _i(j['found']);

  JobProgress.starting(this.phase)
      : current = '',
        done = 0,
        total = 0,
        bytes = 0,
        found = 0;

  final String phase, current;
  final int done, total, bytes, found;

  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}
