import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import 'app_state.dart';

class DiskState extends ChangeNotifier {
  DiskState(this.app);

  final AppState app;

  /// Which half of the Disk screen is showing: space or health.
  bool showHealth = false;

  void setView({required bool health}) {
    if (showHealth == health) return;
    showHealth = health;
    notifyListeners();
  }

  /// Folders the user drilled into, newest last.
  final List<String> trail = [];
  final Map<String, DiskAnalysis> _cache = {};
  DiskAnalysis? analysis;
  bool busy = false;
  JobProgress? progress;
  String? error;
  Job? _job;

  Future<void> analyze(String path, {bool fresh = false, bool push = true}) async {
    if (busy) await cancel();
    if (push) {
      final i = trail.indexOf(path);
      if (i >= 0) {
        trail.removeRange(i + 1, trail.length);
      } else {
        trail.add(path);
      }
    }
    if (!fresh && _cache.containsKey(path)) {
      analysis = _cache[path];
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    progress = JobProgress.starting('Mapping folders');
    notifyListeners();
    try {
      await app.flushSettings();
      _job = await Job.start(app.bridge, 'disk.analyze', {'path': path});
      final r = await _job!.wait((p) {
        progress = p;
        notifyListeners();
      });
      final a = DiskAnalysis((r as Map).cast());
      analysis = a;
      if (!a.cancelled) _cache[path] = a;
    } catch (e) {
      error = '$e';
      if (trail.isNotEmpty && trail.last == path) trail.removeLast();
    } finally {
      busy = false;
      progress = null;
      _job = null;
      notifyListeners();
    }
  }

  /// Starts a new analysis from a drive or picked folder.
  Future<void> open(String path) {
    trail.clear();
    return analyze(path, fresh: true);
  }

  Future<void> up() async {
    if (trail.length < 2) return;
    trail.removeLast();
    await analyze(trail.last, push: false);
  }

  Future<void> cancel() async => _job?.cancel();

  Future<bool> recycle(FileEntry f) async {
    try {
      await app.bridge.call('disk.recycle', {'paths': [f.path]});
      analysis?.topFiles.remove(f);
      _cache.clear();
      if (analysis != null) _cache[analysis!.root] = analysis!;
      app.toast('Moved ${f.name} to the Recycle Bin');
      notifyListeners();
      await app.refreshDrives();
      return true;
    } catch (e) {
      app.toast('$e');
      return false;
    }
  }
}
