import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/format.dart';
import '../core/models.dart';
import 'app_state.dart';

class CleanerState extends ChangeNotifier {
  CleanerState(this.app);

  final AppState app;
  List<CacheCategory> categories = [];
  final Set<String> selected = {};
  bool analyzing = false;
  bool cleaning = false;
  bool measured = false;
  JobProgress? progress;
  CleanReport? result;
  String? error;
  Job? _job;

  bool get busy => analyzing || cleaning;

  bool usable(CacheCategory c) => !c.denied && !(c.admin && !app.isAdmin);

  int get reclaimable =>
      categories.where(usable).fold(0, (sum, c) => sum + c.eligibleSize);

  Iterable<CacheCategory> get selectedCategories =>
      categories.where((c) => selected.contains(c.id) && usable(c));

  int get selectedBytes => selectedCategories.fold(0, (sum, c) => sum + c.eligibleSize);
  int get selectedFiles => selectedCategories.fold(0, (sum, c) => sum + c.eligibleFiles);

  Future<void> analyze() async {
    if (busy) return;
    analyzing = true;
    error = null;
    progress = JobProgress.starting('Measuring caches');
    notifyListeners();
    try {
      await app.flushSettings();
      _job = await Job.start(app.bridge, 'cache.analyze');
      final r = await _job!.wait((p) {
        progress = p;
        notifyListeners();
      });
      categories = (r as List).map((e) => CacheCategory((e as Map).cast())).toList();
      if (!measured) {
        selected
          ..clear()
          ..addAll(categories.where((c) => c.enabled && usable(c) && !c.isRecycleBin).map((c) => c.id));
      }
      selected.removeWhere((id) => !categories.any((c) => c.id == id));
      measured = true;
    } catch (e) {
      error = '$e';
    } finally {
      analyzing = false;
      progress = null;
      _job = null;
      notifyListeners();
    }
  }

  /// Ticks or unticks a category and remembers it as the default for next time.
  void toggle(String id, bool on) {
    on ? selected.add(id) : selected.remove(id);
    app.updateSettings((s) {
      final enabled = s.cleanerEnabled.toSet();
      on ? enabled.add(id) : enabled.remove(id);
      s.set('cleaner', 'enabled', enabled.toList());
    });
    notifyListeners();
  }

  Future<void> setMinAge(int hours) async {
    app.updateSettings((s) => s.set('cleaner', 'min_age_hours', hours));
    await app.flushSettings();
    await analyze();
  }

  Future<void> clean({required bool dryRun}) async {
    if (busy || selected.isEmpty) return;
    cleaning = true;
    error = null;
    result = null;
    progress = JobProgress.starting(dryRun ? 'Previewing' : 'Cleaning');
    notifyListeners();
    try {
      _job = await Job.start(app.bridge, 'cache.clean', {
        'ids': selectedCategories.map((c) => c.id).toList(),
        'dry_run': dryRun,
      });
      final r = await _job!.wait((p) {
        progress = p;
        notifyListeners();
      });
      result = CleanReport((r as Map).cast());
      if (!dryRun) {
        app.toast('Freed ${fmtBytes(result!.freed)}');
      }
    } catch (e) {
      error = '$e';
    } finally {
      cleaning = false;
      progress = null;
      _job = null;
      notifyListeners();
    }
    if (!dryRun) {
      await Future.wait([analyze(), app.refreshDrives(), app.refreshEngine()]);
    }
  }

  Future<void> cancel() async => _job?.cancel();
}
