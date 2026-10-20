import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/models.dart';

enum Section { dashboard, cleaner, disk, shield, quarantine, settings }

/// App-wide state: settings, machine facts, drives and quarantine.
class AppState extends ChangeNotifier {
  AppState(this.bridge);

  final FiendBridge bridge;
  final messenger = GlobalKey<ScaffoldMessengerState>();

  Settings settings = Settings.defaults();
  SystemInfo? system;
  EngineState engine = EngineState(const {});
  List<Drive> drives = [];
  List<QuarantineEntry> quarantine = [];
  int signatureCount = 0;
  int? signaturesUpdatedAt;

  bool ready = false;
  String? fatal;
  Section section = Section.dashboard;

  Timer? _saveTimer;
  Future<void>? _saving;

  bool get isAdmin => system?.admin ?? false;
  Drive? get systemDrive => drives.where((d) => d.system).firstOrNull ?? drives.firstOrNull;

  Future<void> init() async {
    try {
      final s = await bridge.call('settings.get') as Map;
      final merged = Settings.defaults();
      s.cast<String, dynamic>().forEach((k, v) {
        if (v is Map) merged.section(k).addAll(v.cast<String, dynamic>());
      });
      settings = merged;
      system = SystemInfo((await bridge.call('system.info') as Map).cast());
      await Future.wait([refreshDrives(), refreshEngine(), refreshQuarantine(), refreshSignatures()]);
      ready = true;
    } catch (e) {
      fatal = e.toString();
    }
    notifyListeners();
  }

  void go(Section s) {
    if (section == s) return;
    section = s;
    notifyListeners();
  }

  void toast(String message) {
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Applies a settings change at once and saves it shortly after.
  void updateSettings(void Function(Settings s) change) {
    change(settings);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () => _saving = _save());
  }

  /// Makes sure pending settings are on disk (the engine reads them from there).
  Future<void> flushSettings() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saving = _save();
    }
    await _saving;
  }

  Future<void> _save() async {
    try {
      await bridge.call('settings.set', settings.raw);
    } catch (e) {
      toast('Settings weren\'t saved: $e');
    }
  }

  Future<void> resetSettings() async {
    final s = await bridge.call('settings.reset') as Map;
    settings = Settings(s.cast());
    notifyListeners();
  }

  Future<void> refreshDrives() async {
    drives = ((await bridge.call('drives.list')) as List).map((e) => Drive((e as Map).cast())).toList();
    notifyListeners();
  }

  Future<void> refreshEngine() async {
    engine = EngineState((await bridge.call('state.get') as Map).cast());
    notifyListeners();
  }

  Future<void> refreshQuarantine() async {
    quarantine = ((await bridge.call('quarantine.list')) as List)
        .map((e) => QuarantineEntry((e as Map).cast()))
        .toList();
    notifyListeners();
  }

  Future<void> refreshSignatures() async {
    final info = (await bridge.call('signatures.info') as Map).cast<String, dynamic>();
    signatureCount = (info['count'] as num?)?.toInt() ?? 0;
    signaturesUpdatedAt = (info['updated_at'] as num?)?.toInt();
    notifyListeners();
  }

  Future<void> restoreFromQuarantine(QuarantineEntry e) async {
    try {
      final r = await bridge.call('quarantine.restore', {'id': e.id}) as Map;
      toast('Restored to ${r['path']}');
    } catch (err) {
      toast('$err');
    }
    await refreshQuarantine();
  }

  Future<void> deleteFromQuarantine(QuarantineEntry e) async {
    try {
      await bridge.call('quarantine.delete', {'id': e.id});
      toast('${e.name} deleted for good');
    } catch (err) {
      toast('$err');
    }
    await refreshQuarantine();
  }

  Future<void> reveal(String path) async {
    try {
      await bridge.call('system.reveal', {'path': path});
    } catch (e) {
      toast('$e');
    }
  }

  /// Asks Windows to start an elevated copy. Returns true if the caller should close.
  Future<bool> relaunchAsAdmin() async {
    try {
      await bridge.call('system.relaunch_admin');
      return true;
    } catch (e) {
      toast('$e');
      return false;
    }
  }
}
