import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'common.dart';
import 'sigil.dart';

Color healthColor(Fx fx, String status) => switch (status) {
      'good' => safeColor,
      'caution' => warnColor,
      'bad' => dangerColor,
      _ => fx.faint,
    };

/// Kept in a const map so release builds keep every glyph when they tree-shake the icon font.
const statusIcons = <String, IconData>{
  'good': Icons.check_circle_outline_rounded,
  'caution': Icons.warning_amber_rounded,
  'bad': Icons.error_outline_rounded,
  'unknown': Icons.help_outline_rounded,
};

String healthLabel(String status) => switch (status) {
      'good' => 'Good',
      'caution' => 'Caution',
      'bad' => 'Bad',
      _ => 'Unknown',
    };

/// Small "Life 93%" pill for drive cards.
class LifePill extends StatelessWidget {
  const LifePill(this.h, {super.key});
  final DriveHealth h;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final text = h.lifeRemaining != null ? 'Life ${h.lifeRemaining}%' : healthLabel(h.status);
    return Tooltip(
      message: h.reasons.join('\n'),
      child: Pill(text, color: healthColor(fx, h.status), icon: Icons.favorite_rounded),
    );
  }
}

/// One physical drive: life ring, verdict, the numbers behind it, and its wear trend.
class DriveHealthPanel extends StatelessWidget {
  const DriveHealthPanel(this.h, {super.key});
  final DriveHealth h;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final color = healthColor(fx, h.status);
    final unit = app.settings.temperatureUnit;

    final Widget center = h.lifeRemaining != null
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${h.lifeRemaining}%', style: t.displayMedium!.copyWith(fontFeatures: tabular)),
            Text('LIFE LEFT', style: t.labelSmall),
          ])
        : h.powerOnHours != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fmtSpan(h.powerOnHours!), style: t.titleLarge!.copyWith(fontFeatures: tabular)),
                Text('POWERED ON', style: t.labelSmall),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text('?', style: t.displayMedium),
                Text('NO DATA', style: t.labelSmall),
              ]);

    final stats = <(String, String, Color?)>[
      if (h.temperatureC != null)
        ('Temperature', fmtTemp(h.temperatureC!, unit), h.temperatureC! >= 70 ? dangerColor : h.temperatureC! >= 60 ? warnColor : null),
      if (h.powerOnHours != null) ('Powered on', '${fmtCount(h.powerOnHours!)} h', null),
      if (h.dataWritten != null) ('Data written', fmtBytes(h.dataWritten!), null),
      if (h.dataRead != null) ('Data read', fmtBytes(h.dataRead!), null),
      if (h.powerCycles != null) ('Power cycles', fmtCount(h.powerCycles!), null),
      if (h.unsafeShutdowns != null) ('Unsafe shutdowns', fmtCount(h.unsafeShutdowns!), null),
      if (h.availableSpare != null) ('Spare blocks', '${h.availableSpare}%', h.spareThreshold != null && h.availableSpare! <= h.spareThreshold! ? dangerColor : null),
      if (h.mediaErrors != null) ('Media errors', fmtCount(h.mediaErrors!), h.mediaErrors! > 0 ? dangerColor : null),
      if (h.reallocated != null) ('Replaced sectors', fmtCount(h.reallocated!), h.reallocated! > 0 ? warnColor : null),
      if (h.pending != null) ('Unstable sectors', fmtCount(h.pending!), h.pending! > 0 ? warnColor : null),
      if (h.uncorrectable != null) ('Unreadable sectors', fmtCount(h.uncorrectable!), h.uncorrectable! > 0 ? dangerColor : null),
    ];

    return Panel(
      highlight: h.status == 'bad',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Ring(
            value: (h.lifeRemaining ?? 0) / 100,
            color: color,
            track: fx.surface2,
            size: 150,
            stroke: 10,
            child: center,
          ),
          SizedBox(width: fx.pad + 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(h.model.isEmpty ? 'Unnamed drive' : h.model, style: t.titleLarge),
                    Pill(healthLabel(h.status), color: color, solid: h.status == 'bad'),
                    Pill(h.kindLabel, color: fx.muted),
                    for (final l in h.letters) Pill(l, color: fx.text.withValues(alpha: 0.75)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (h.size > 0) fmtBytes(h.size),
                    if (h.firmware.isNotEmpty) 'firmware ${h.firmware}',
                    if (h.serialTail.isNotEmpty) 'serial …${h.serialTail}',
                  ].join('  ·  '),
                  style: t.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final r in h.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(statusIcons[h.status] ?? Icons.warning_amber_rounded, size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r, style: t.bodyMedium)),
                    ]),
                  ),
                if (h.needsAdmin) ...[
                  const SizedBox(height: 8),
                  FButton('Restart as admin to read it', icon: Icons.admin_panel_settings_outlined, dense: true, onPressed: () async {
                    if (await app.relaunchAsAdmin()) {
                      await windowManager.destroy();
                      exit(0);
                    }
                  }),
                ],
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [for (final s in stats) _Stat(label: s.$1, value: s.$2, color: s.$3)],
                  ),
                ],
                if (h.hasData) ...[
                  const SizedBox(height: 16),
                  _Trend(h),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fx.surface2,
        borderRadius: BorderRadius.circular(fx.radius),
        border: Border.all(color: color?.withValues(alpha: 0.5) ?? fx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value, style: t.titleMedium!.copyWith(color: color, fontFeatures: tabular)),
        ],
      ),
    );
  }
}

/// Projection plus a sparkline of life left over the days Fiend has seen this drive.
class _Trend extends StatelessWidget {
  const _Trend(this.h);
  final DriveHealth h;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final points = h.history.where((p) => p.life != null).toList();
    final p = h.projectionHours;
    final projection = p == null
        ? (h.lifeRemaining == null
            ? 'Spinning drives don\'t report wear, so Fiend watches their errors and age instead.'
            : 'No measurable wear yet, so there\'s nothing to project.')
        : 'At this pace, about ${fmtCount(p)} more powered-on hours: roughly ${fmtSpan(p * 3)} at 8 hours a day.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(projection, style: t.bodyMedium!.copyWith(color: fx.muted)),
        const SizedBox(height: 10),
        if (points.length >= 2) ...[
          SizedBox(
            height: 56,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparkPainter(points, healthColor(fx, h.status), fx.border),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Life left over the last ${plural(points.last.day - points.first.day, 'day')}: '
            '${points.first.life}% → ${points.last.life}%',
            style: t.bodySmall,
          ),
        ] else
          Text('Fiend records a reading each day it runs, so a wear trend appears here over time.', style: t.bodySmall),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.grid);
  final List<HealthPoint> points;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final d0 = points.first.day, d1 = math.max(points.last.day, d0 + 1);
    final lifes = points.map((p) => p.life!).toList();
    final lo = math.max(0, lifes.reduce(math.min) - 3).toDouble();
    final hi = math.min(100, lifes.reduce(math.max) + 1).toDouble();
    Offset at(HealthPoint p) => Offset(
          (p.day - d0) / (d1 - d0) * size.width,
          size.height - (p.life! - lo) / math.max(hi - lo, 1) * (size.height - 6) - 3,
        );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), gridPaint);

    final line = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      line.lineTo(at(p).dx, at(p).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(points.last).dx, size.height)
      ..lineTo(at(points.first).dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(points.last), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.points != points || old.color != color;
}
