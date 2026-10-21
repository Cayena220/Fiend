import 'dart:async';

import 'bridge.dart';

/// In-memory engine with realistic sample data. Used by widget tests and by
/// `Fiend.exe --demo`, which shows the app without touching the real PC.
class FakeBridge implements FiendBridge {
  FakeBridge({this.failWith});

  /// When set, every call throws this message (to test the error screen).
  final String? failWith;
  final List<String> calls = [];
  Map<String, dynamic>? savedSettings;
  final Map<int, dynamic> _jobs = {};
  final List<Map<String, dynamic>> _quarantine = [];
  int _nextJob = 1;

  static const _gb = 1024 * 1024 * 1024;
  static const _mb = 1024 * 1024;
  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  Future<dynamic> call(String method, [Map<String, dynamic>? params]) async {
    calls.add(method);
    if (failWith != null) throw FiendException(failWith!);
    final p = params ?? const {};
    switch (method) {
      case 'settings.get':
        return savedSettings ?? {};
      case 'settings.set':
        savedSettings = p;
        return p;
      case 'system.info':
        return {
          'os': 'Windows 11 Pro',
          'version': '25H2',
          'build': 26200,
          'computer': 'FIEND-DEMO',
          'user': 'Alex',
          'admin': false,
          'defender': true,
          'data_dir': r'C:\Users\Alex\AppData\Roaming\Fiend',
          'core_version': '0.3.0',
          'app_version': '1.1.0',
          'exe_path': r'C:\Users\Alex\AppData\Local\Programs\Fiend\Fiend.exe',
        };
      case 'state.get':
        return {'last_scan_at': _now - 2 * 86400, 'last_scan_mode': 'quick', 'last_scan_findings': 2, 'total_freed': 0};
      case 'drives.list':
        return [
          {'root': r'C:\', 'label': '', 'file_system': 'NTFS', 'kind': 'fixed', 'total': 476 * _gb, 'free': 61 * _gb, 'used': 415 * _gb, 'system': true},
          {'root': r'D:\', 'label': 'Games', 'file_system': 'NTFS', 'kind': 'fixed', 'total': 1863 * _gb, 'free': 702 * _gb, 'used': 1161 * _gb, 'system': false},
          {'root': r'E:\', 'label': 'Backup', 'file_system': 'NTFS', 'kind': 'fixed', 'total': 931 * _gb, 'free': 74 * _gb, 'used': 857 * _gb, 'system': false},
        ];
      case 'drives.health':
        return _driveHealth;
      case 'quarantine.list':
        return _quarantine;
      case 'quarantine.add':
        final e = {
          'id': '$_now-demo${_quarantine.length}',
          'original_path': p['path'],
          'name': (p['path'] as String).split('\\').last,
          'size': 482304,
          'sha256': 'ab' * 32,
          'reason': p['reason'] ?? '',
          'score': p['score'] ?? 0,
          'quarantined_at': _now,
        };
        _quarantine.insert(0, e);
        return e;
      case 'quarantine.restore':
      case 'quarantine.delete':
        _quarantine.removeWhere((e) => e['id'] == p['id']);
        return {'path': ''};
      case 'signatures.info':
        return {'count': 1380, 'path': '', 'updated_at': _now - 7200};
      case 'defender.scan':
        return {'status': 'clean', 'threat': null, 'detail': 'Defender found no threats'};
      case 'shield.allow':
        return {'shield': {'allowlist': [p['entry']]}};
      case 'startup.list':
        return _startup;
      case 'startup.disabled':
        return [];
      case 'job.start':
        final id = _nextJob++;
        _jobs[id] = _jobResult(p['kind'] as String, (p['params'] as Map?)?.cast<String, dynamic>() ?? {});
        return {'id': id};
      case 'job.status':
        final id = (p['id'] as num).toInt();
        return {
          'id': id,
          'finished': true,
          'progress': {'phase': 'Done', 'current': '', 'done': 1, 'total': 1, 'bytes': 0, 'found': 0},
          'result': _jobs[id],
          'error': null,
        };
      default:
        return true;
    }
  }

  /// One reading every two weeks over ~10 months, wearing linearly from `from` to `to` percent.
  static List<Map<String, dynamic>> _history(int from, int to, int hours) {
    final today = _now ~/ 86400;
    return [
      for (var i = 0; i <= 21; i++)
        {
          'day': today - (21 - i) * 14,
          'life': from - ((from - to) * i / 21).round(),
          'hours': hours - (21 - i) * 60,
          'written': null,
        },
    ];
  }

  static final _driveHealth = [
    {
      'id': 'demo-nvme', 'number': 0, 'model': 'Samsung SSD 980 PRO 500GB', 'serial_tail': '4K2D', 'firmware': '5B2QGXA7',
      'bus': 'NVMe', 'kind': 'ssd', 'size': 500 * _gb, 'letters': ['C:'], 'source': 'nvme', 'needs_admin': false,
      'status': 'good', 'reasons': ['No warnings from the drive'],
      'life_remaining': 91, 'temperature_c': 44, 'power_on_hours': 6120, 'power_cycles': 1834, 'unsafe_shutdowns': 41,
      'data_written': 61 * 1000 * _gb, 'data_read': 88 * 1000 * _gb, 'media_errors': 0, 'available_spare': 100,
      'spare_threshold': 10, 'critical_warning': 0, 'projection_hours': 61880, 'history': _history(94, 91, 6120),
    },
    {
      'id': 'demo-sata', 'number': 1, 'model': 'Crucial CT2000MX500SSD1', 'serial_tail': '9E1F', 'firmware': 'M3CR046',
      'bus': 'SATA', 'kind': 'ssd', 'size': 2000 * _gb, 'letters': ['D:'], 'source': 'smart', 'needs_admin': false,
      'status': 'caution', 'reasons': ['1 worn sector replaced with spares'],
      'life_remaining': 64, 'temperature_c': 38, 'power_on_hours': 18950, 'power_cycles': 4021, 'unsafe_shutdowns': 112,
      'data_written': 214 * 1000 * _gb, 'reallocated': 1, 'pending': 0, 'uncorrectable': 0,
      'projection_hours': 33689, 'history': _history(68, 64, 18950),
    },
    {
      'id': 'demo-hdd', 'number': 2, 'model': 'WDC WD10EZEX-08WN4A0', 'serial_tail': '7XQ2', 'firmware': '01.01A01',
      'bus': 'SATA', 'kind': 'hdd', 'size': 1000 * _gb, 'letters': ['E:'], 'source': 'smart', 'needs_admin': false,
      'status': 'good', 'reasons': ['No warnings from the drive'],
      'temperature_c': 35, 'power_on_hours': 41200, 'power_cycles': 2210, 'reallocated': 0, 'pending': 0,
      'uncorrectable': 0, 'projection_hours': null, 'history': [],
    },
  ];

  static final _startup = [
    {
      'id': 'reg|HKCU|Run|WinUpdateHelper',
      'name': 'WinUpdateHelper',
      'command': r'C:\Users\Alex\AppData\Roaming\wuhelper.exe /silent',
      'target': r'C:\Users\Alex\AppData\Roaming\wuhelper.exe',
      'location': 'HKCU Run',
      'source': 'registry',
      'exists': true,
      'signed': 'unsigned',
      'score': 40,
      'severity': 'medium',
      'reasons': [
        {'code': 'location', 'label': 'Starts a program stored loose in AppData', 'weight': 25},
        {'code': 'unsigned', 'label': 'Has no digital signature', 'weight': 15},
      ],
    },
    for (final (name, loc, cmd) in [
      ('OneDrive', 'HKCU Run', r'"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'),
      ('Steam', 'HKCU Run', r'"C:\Program Files (x86)\Steam\steam.exe" -silent'),
      ('Discord', 'HKCU Run', r'C:\Users\Alex\AppData\Local\Discord\Update.exe --processStart Discord.exe'),
      ('SecurityHealth', 'HKLM Run', r'%windir%\system32\SecurityHealthSystray.exe'),
    ])
      {
        'id': 'reg|$loc|$name',
        'name': name,
        'command': cmd,
        'target': null,
        'location': loc,
        'source': 'registry',
        'exists': true,
        'signed': 'signed',
        'score': 0,
        'severity': 'none',
        'reasons': [
          {'code': 'signed', 'label': 'Signed by a verified publisher', 'weight': -30},
        ],
      },
  ];

  Map<String, dynamic> _cat(String id, String name, String desc, String group, int eligible, int total, int files,
          {bool admin = false, bool denied = false}) =>
      {
        'id': id,
        'name': name,
        'description': desc,
        'group': group,
        'admin': admin,
        'enabled': id != 'recycle_bin',
        'denied': denied,
        'size': total,
        'files': files,
        'eligible_size': eligible,
        'eligible_files': (files * (total == 0 ? 0 : eligible / total)).round(),
        'roots': [],
      };

  dynamic _jobResult(String kind, Map<String, dynamic> params) {
    switch (kind) {
      case 'cache.analyze':
        return [
          _cat('user_temp', 'Temporary files', 'Leftovers from installers and apps in your Temp folder', 'Windows', 1240 * _mb, 2172 * _mb, 3962),
          _cat('windows_temp', 'Windows temporary files', 'System-wide Temp folder', 'Windows', 0, 0, 0, admin: true, denied: true),
          _cat('thumbnails', 'Thumbnail cache', 'Preview images Explorer rebuilds on demand', 'Windows', 182 * _mb, 230 * _mb, 30),
          _cat('shader_cache', 'Graphics shader cache', 'Compiled shaders from DirectX, NVIDIA and AMD. Games rebuild them', 'Windows', 1403 * _mb, 1660 * _mb, 401),
          _cat('crash_dumps', 'Crash dumps', 'Memory dumps written when apps crash', 'Windows', 107 * _mb, 107 * _mb, 10),
          _cat('windows_update', 'Windows Update downloads', 'Update packages that are already installed', 'Windows', 0, 0, 0, admin: true),
          _cat('recycle_bin', 'Recycle Bin', 'Files you deleted earlier. Emptying it is permanent', 'Windows', 640 * _mb, 640 * _mb, 38),
          _cat('browser_chrome', 'Google Chrome', 'Web cache, code cache and GPU cache', 'Browsers', 1915 * _mb, 1915 * _mb, 22455),
          _cat('browser_edge', 'Microsoft Edge', 'Web cache, code cache and GPU cache', 'Browsers', 244 * _mb, 297 * _mb, 2032),
          _cat('browser_firefox', 'Firefox', 'Web cache for every profile', 'Browsers', 380 * _mb, 412 * _mb, 5120),
        ];
      case 'cache.clean':
        return {'dry_run': params['dry_run'] == true, 'freed': 5471 * _mb, 'deleted': 34190, 'skipped': 12, 'categories': []};
      case 'shield.scan':
        return {
          'mode': params['mode'] ?? 'quick',
          'started_at': _now,
          'elapsed_ms': 13154,
          'roots': [],
          'files_seen': 28041,
          'files_examined': 1739,
          'threshold': 30,
          'signatures': 1380,
          'defender_used': true,
          'cancelled': false,
          'startup': [_startup.first],
          'findings': [
            _finding('f0', r'C:\Users\Alex\Downloads\invoice_0425.pdf.exe', 75, 'high', 'unsigned', [
              ('double_extension', 'Looks like a .pdf file but runs as .exe', 60),
              ('location', 'Runnable file in Downloads, a folder malware often uses', 15),
            ]),
            _finding('f1', r'C:\Users\Alex\AppData\Roaming\Microsoft\sync\update.vbs', 70, 'high', null, [
              ('script', 'Runs an encoded PowerShell command', 20),
              ('script', 'Downloads content from the internet', 15),
              ('script', 'Runs with a hidden window', 10),
              ('script', 'Uses Windows Script Host to launch commands', 10),
              ('location', 'Runnable file in AppData, a folder malware often uses', 15),
            ]),
            _finding('f2', r'C:\Users\Alex\Downloads\photoshop_full_unlocked.exe', 55, 'medium', 'unsigned', [
              ('location', 'Runnable file in Downloads, a folder malware often uses', 15),
              ('packed', 'Contents look packed or encrypted', 20),
              ('unsigned', 'Has no digital signature', 20),
            ], defender: {'status': 'clean', 'threat': null, 'detail': 'Defender found no threats'}),
          ],
        };
      case 'disk.analyze':
        final root = (params['path'] as String?) ?? r'C:\';
        DirNodeJson n(String name, int gb, int files, [List<Map<String, dynamic>> kids = const []]) =>
            {'name': name, 'path': '$root$name', 'size': gb * _gb, 'files': files, 'children': kids};
        return {
          'root': root,
          'size': 415 * _gb,
          'files': 1284512,
          'denied': 214,
          'large_files': 23,
          'elapsed_ms': 21480,
          'cancelled': false,
          'tree': {
            'name': root,
            'path': root,
            'size': 415 * _gb,
            'files': 1284512,
            'children': [
              n('Users', 188, 512000, [n('Alex', 186, 500000), n('Public', 2, 12000)]),
              n('Program Files', 92, 310000, [n('Steam', 41, 9000), n('Adobe', 18, 40000), n('Microsoft Office', 6, 20000)]),
              n('Windows', 46, 260000, [n('WinSxS', 14, 90000), n('System32', 9, 30000), n('Installer', 7, 900)]),
              n('Program Files (x86)', 38, 120000),
              n('ProgramData', 21, 60000),
              n('hiberfil.sys', 13, 1),
              n('pagefile.sys', 12, 1),
              n('Recovery', 3, 40),
              n('XboxGames', 2, 3000),
            ],
          },
          'top_files': [
            for (final (name, path, kind, gb, days) in [
              ('Elden Ring Backup.zip', r'C:\Users\Alex\Downloads', 'Archives & images', 48, 40),
              ('hiberfil.sys', r'C:', 'System & app data', 13, 1),
              ('pagefile.sys', r'C:', 'System & app data', 12, 1),
              ('wedding-4k.mp4', r'C:\Users\Alex\Videos', 'Video', 9, 300),
              ('Win11_25H2_English_x64.iso', r'C:\Users\Alex\Downloads', 'Archives & images', 7, 90),
              ('ext4.vhdx', r'C:\Users\Alex\AppData\Local\Docker\wsl\disk', 'Archives & images', 6, 2),
              ('Lightroom Catalog.lrcat', r'C:\Users\Alex\Pictures\Lightroom', 'Other', 3, 12),
            ])
              {'name': name, 'path': '$path\\$name', 'kind': kind, 'size': gb * _gb, 'modified': _now - days * 86400},
          ],
          'kinds': [
            {'kind': 'Archives & images', 'size': 96 * _gb, 'files': 812},
            {'kind': 'Apps', 'size': 88 * _gb, 'files': 140200},
            {'kind': 'Video', 'size': 71 * _gb, 'files': 960},
            {'kind': 'System & app data', 'size': 64 * _gb, 'files': 301000},
            {'kind': 'Other', 'size': 42 * _gb, 'files': 512000},
            {'kind': 'Images', 'size': 29 * _gb, 'files': 41000},
            {'kind': 'Documents', 'size': 11 * _gb, 'files': 9800},
            {'kind': 'Audio', 'size': 8 * _gb, 'files': 4100},
            {'kind': 'Code', 'size': 6 * _gb, 'files': 275000},
          ],
        };
      default:
        return null;
    }
  }

  Map<String, dynamic> _finding(String id, String path, int score, String severity, String? signed, List<(String, String, int)> reasons,
          {Map<String, dynamic>? defender}) =>
      {
        'id': id,
        'path': path,
        'name': path.split('\\').last,
        'size': 482304 + score * 9137,
        'modified': _now - score * 3600,
        'score': score,
        'severity': severity,
        'reasons': [for (final (c, l, w) in reasons) {'code': c, 'label': l, 'weight': w}],
        'sha256': '9f2c41d0be77a3e8c5d6b1f0a4e3927c8d15e6b2a0f4c7d9e1b3a5c7d9e0f1a2',
        'signed': signed,
        'defender': defender,
        'quarantine_id': null,
      };
}

typedef DirNodeJson = Map<String, dynamic>;
