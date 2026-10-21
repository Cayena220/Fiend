import '../core/format.dart';
import '../core/models.dart';
import 'app_state.dart';
import 'cleaner_state.dart';
import 'shield_state.dart';

enum Level { good, warn, bad, unknown }

class Factor {
  const Factor(this.id, this.title, this.detail, this.level, this.penalty);
  final String id;
  final String title;
  final String detail;
  final Level level;
  final int penalty;
}

class Health {
  Health(this.factors) : score = (100 - factors.fold<int>(0, (a, f) => a + f.penalty)).clamp(0, 100);

  final List<Factor> factors;
  final int score;

  String get verdict => score >= 80
      ? 'Your PC is in good shape'
      : score >= 50
          ? 'A few things need attention'
          : 'Your PC needs care';

  int get issues => factors.where((f) => f.level == Level.bad || f.level == Level.warn).length;

  static Health of(AppState app, CleanerState cleaner, ShieldState shield) {
    final factors = <Factor>[];

    final d = app.systemDrive;
    if (d == null) {
      factors.add(const Factor('storage', 'Storage', 'No drives found', Level.unknown, 0));
    } else {
      final free = d.freeFraction;
      final detail = '${fmtBytes(d.free)} free of ${fmtBytes(d.total)} on ${d.letter}';
      factors.add(free < 0.1
          ? Factor('storage', 'Storage', detail, Level.bad, 25)
          : free < 0.2
              ? Factor('storage', 'Storage', detail, Level.warn, 10)
              : Factor('storage', 'Storage', detail, Level.good, 0));
    }

    final readable = app.driveHealth.where((h) => h.hasData).toList();
    if (readable.isEmpty) {
      factors.add(Factor('drives', 'Drive life',
          app.driveHealth.any((h) => h.needsAdmin) ? 'Restart as admin to read drive health' : 'Drives don\'t report their health',
          Level.unknown, 0));
    } else {
      DriveHealth? pick(String s) => readable.where((h) => h.status == s).firstOrNull;
      final bad = pick('bad'), caution = pick('caution');
      // Letters already end in a colon ("D: ..."); a model name gets one.
      String name(DriveHealth h) => h.letters.isNotEmpty ? h.letters.join(' ') : '${h.model}:';
      if (bad != null) {
        factors.add(Factor('drives', 'Drive life', '${name(bad)} ${bad.reasons.first}', Level.bad, 25));
      } else if (caution != null) {
        factors.add(Factor('drives', 'Drive life', '${name(caution)} ${caution.reasons.first}', Level.warn, 10));
      } else {
        final lives = readable.where((h) => h.lifeRemaining != null).map((h) => '${name(h)} ${h.lifeRemaining}%');
        factors.add(Factor('drives', 'Drive life',
            lives.isEmpty ? 'All drives report good health' : 'Healthy: ${lives.join(', ')} life left', Level.good, 0));
      }
    }

    if (!cleaner.measured) {
      factors.add(Factor('clutter', 'Clutter', cleaner.analyzing ? 'Measuring caches…' : 'Not measured yet', Level.unknown, 0));
    } else {
      final r = cleaner.reclaimable;
      final detail = r < 1024 * 1024 ? 'Caches are already lean' : '${fmtBytes(r)} of cache can be cleaned';
      const gb = 1024 * 1024 * 1024;
      factors.add(r > 5 * gb
          ? Factor('clutter', 'Clutter', detail, Level.bad, 15)
          : r > gb
              ? Factor('clutter', 'Clutter', detail, Level.warn, 7)
              : Factor('clutter', 'Clutter', detail, Level.good, 0));
    }

    final report = shield.report;
    if (report != null) {
      final high = report.count('high'), medium = report.count('medium'), low = report.count('low');
      final flaggedStartup = report.startup.length;
      if (high > 0) {
        factors.add(Factor('threats', 'Threats', '${plural(high, 'high-risk file')} waiting for a decision', Level.bad, 35));
      } else if (medium + low + flaggedStartup > 0) {
        factors.add(Factor('threats', 'Threats', '${plural(medium + low + flaggedStartup, 'item')} worth a look', Level.warn, 12));
      } else {
        factors.add(const Factor('threats', 'Threats', 'Nothing suspicious in the last scan', Level.good, 0));
      }
    } else if (app.engine.lastScanAt != null) {
      final n = app.engine.lastScanFindings;
      factors.add(n > 0
          ? Factor('threats', 'Threats', 'Last scan flagged ${plural(n, 'item')}', Level.warn, 12)
          : const Factor('threats', 'Threats', 'Nothing suspicious in the last scan', Level.good, 0));
    } else {
      factors.add(const Factor('threats', 'Threats', 'No scan results yet', Level.unknown, 0));
    }

    final last = report?.startedAt ?? app.engine.lastScanAt;
    if (last == null) {
      factors.add(const Factor('fresh', 'Last scan', 'Fiend hasn\'t scanned this PC yet', Level.bad, 15));
    } else {
      final days = (DateTime.now().millisecondsSinceEpoch ~/ 1000 - last) / 86400;
      final detail = 'Scanned ${fmtAgo(last)}';
      factors.add(days > 14
          ? Factor('fresh', 'Last scan', detail, Level.bad, 15)
          : days > 3
              ? Factor('fresh', 'Last scan', detail, Level.warn, 7)
              : Factor('fresh', 'Last scan', detail, Level.good, 0));
    }
    return Health(factors);
  }
}
