import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/format.dart';
import '../core/models.dart';
import 'app_state.dart';

/// MalwareBazaar (abuse.ch) export of SHA-256 hashes added in the last 48 hours.
const malwareBazaarRecent = 'https://bazaar.abuse.ch/export/txt/sha256/recent/';

class ShieldState extends ChangeNotifier {
  ShieldState(this.app);

  final AppState app;
  ScanReport? report;
  bool scanning = false;
  String? scanMode;
  JobProgress? progress;
  String? error;
  Job? _job;

  List<StartupItem> startup = [];
  List<DisabledStartup> disabled = [];
  bool loadingStartup = false;
  bool startupLoaded = false;

  /// Set when another screen sends the user straight to the startup list.
  bool focusStartup = false;

  final Set<String> working = {};
  bool updatingSignatures = false;

  int get openFindings => report?.open.length ?? 0;

  Future<void> scan(String mode, {List<String> paths = const []}) async {
    if (scanning) return;
    scanning = true;
    scanMode = mode;
    error = null;
    progress = JobProgress.starting('Starting scan');
    notifyListeners();
    try {
      await app.flushSettings();
      _job = await Job.start(app.bridge, 'shield.scan', {'mode': mode, 'paths': paths});
      final r = await _job!.wait((p) {
        progress = p;
        notifyListeners();
      }, interval: const Duration(milliseconds: 300));
      report = ScanReport((r as Map).cast());
      final n = report!.findings.length + report!.startup.length;
      app.toast(report!.cancelled
          ? 'Scan stopped'
          : n == 0
              ? 'Scan finished. Nothing suspicious.'
              : 'Scan finished. ${plural(n, 'item')} to review.');
    } catch (e) {
      error = '$e';
    } finally {
      scanning = false;
      progress = null;
      _job = null;
      notifyListeners();
    }
    await Future.wait([app.refreshEngine(), app.refreshQuarantine()]);
  }

  Future<void> cancel() async => _job?.cancel();

  Future<void> _busy(String key, Future<void> Function() work) async {
    working.add(key);
    notifyListeners();
    try {
      await work();
    } catch (e) {
      app.toast('$e');
    } finally {
      working.remove(key);
      notifyListeners();
    }
  }

  Future<void> quarantine(Finding f) => _busy(f.id, () async {
        final r = await app.bridge.call('quarantine.add', {'path': f.path, 'reason': f.headline, 'score': f.score}) as Map;
        f.quarantineId = r['id'] as String?;
        app.toast('${f.name} moved to quarantine');
        await app.refreshQuarantine();
      });

  Future<void> askDefender(Finding f) => _busy(f.id, () async {
        final r = await app.bridge.call('defender.scan', {'path': f.path}) as Map;
        f.defender = DefenderResult(r.cast());
        app.toast(f.defender!.detail);
      });

  /// Marks a finding as safe so future scans skip it.
  Future<void> markSafe(Finding f) => _busy(f.id, () async {
        final s = await app.bridge.call('shield.allow', {'entry': f.sha256 ?? f.path}) as Map;
        app.settings.section('shield')['allowlist'] = (s['shield'] as Map)['allowlist'];
        f.dismissed = true;
        app.toast('Fiend will skip ${f.name} from now on');
      });

  Future<void> loadStartup() async {
    loadingStartup = true;
    notifyListeners();
    try {
      final items = await app.bridge.call('startup.list') as List;
      startup = items.map((e) => StartupItem((e as Map).cast())).toList();
      final off = await app.bridge.call('startup.disabled') as List;
      disabled = off.map((e) => DisabledStartup((e as Map).cast())).toList();
      startupLoaded = true;
    } catch (e) {
      app.toast('$e');
    } finally {
      loadingStartup = false;
      notifyListeners();
    }
  }

  Future<void> disableStartup(StartupItem item) => _busy(item.id, () async {
        await app.bridge.call('startup.disable', {'id': item.id});
        app.toast('${item.name} won\'t start with Windows');
        await loadStartup();
      });

  Future<void> restoreStartup(DisabledStartup item) => _busy(item.id, () async {
        await app.bridge.call('startup.restore', {'id': item.id});
        app.toast('${item.name} will start with Windows again');
        await loadStartup();
      });

  Future<void> _import(String text, String label) async {
    final r = await app.bridge.call('signatures.import', {'text': text, 'label': label}) as Map;
    await app.refreshSignatures();
    app.toast('Added ${plural(r['added'] as num, 'new signature')}. Fiend now knows ${fmtCount(r['count'] as num)}.');
  }

  Future<void> updateFromMalwareBazaar() async {
    updatingSignatures = true;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(malwareBazaarRecent));
      req.headers.set(HttpHeaders.userAgentHeader, 'Fiend/1.0');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw FiendException('MalwareBazaar answered with HTTP ${res.statusCode}. Try again later.');
      }
      final text = await res.transform(utf8.decoder).join();
      await _import(text, 'MalwareBazaar');
    } on SocketException {
      app.toast('Couldn\'t reach MalwareBazaar. Check your internet connection.');
    } catch (e) {
      app.toast('$e');
    } finally {
      client.close();
      updatingSignatures = false;
      notifyListeners();
    }
  }

  Future<void> importFile(String path) async {
    try {
      final name = path.split(RegExp(r'[\\/]')).last;
      await _import(await File(path).readAsString(), name);
    } catch (e) {
      app.toast('Couldn\'t import that file: $e');
    }
  }

  Future<void> resetSignatures() async {
    await app.bridge.call('signatures.reset');
    await app.refreshSignatures();
    app.toast('Imported signatures removed');
  }
}
