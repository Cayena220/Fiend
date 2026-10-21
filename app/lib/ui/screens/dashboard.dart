import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../state/app_state.dart';
import '../../state/cleaner_state.dart';
import '../../state/disk_state.dart';
import '../../state/health.dart';
import '../../state/shield_state.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/drive_health.dart';
import '../widgets/sigil.dart';

const dashboardCardLabels = {
  'health': 'Health score',
  'drives': 'Drives',
  'cache': 'Reclaimable space',
  'shield': 'Shield status',
  'actions': 'Quick actions',
};

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late';
    if (h < 12) return 'Morning';
    if (h < 18) return 'Afternoon';
    return 'Evening';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final sys = app.system;
    final hidden = app.settings.dashboardHidden.toSet();
    final order = [
      ...app.settings.dashboardCards.where(dashboardCardLabels.containsKey),
      ...dashboardCardLabels.keys.where((k) => !app.settings.dashboardCards.contains(k)),
    ].where((k) => !hidden.contains(k)).toList();

    Widget card(String id) => switch (id) {
          'health' => const _HealthCard(),
          'drives' => const _DrivesCard(),
          'cache' => const _CacheCard(),
          'shield' => const _ShieldCard(),
          _ => const _ActionsCard(),
        };

    // Health spans the full width; the rest pair up two per row.
    final rows = <Widget>[];
    final pending = <String>[];
    void flush() {
      if (pending.isEmpty) return;
      final ids = List.of(pending);
      pending.clear();
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: card(ids[0])),
            SizedBox(width: fx.gap),
            Expanded(child: ids.length > 1 ? card(ids[1]) : const SizedBox()),
          ],
        ),
      ));
    }

    for (final id in order) {
      if (id == 'health') {
        flush();
        rows.add(card(id));
      } else {
        pending.add(id);
        if (pending.length == 2) flush();
      }
    }
    flush();

    return ScreenBody(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_greeting()}, ${sys?.user.isNotEmpty == true ? sys!.user : 'there'}.', style: t.displayMedium),
                const SizedBox(height: 6),
                Text(
                  [sys?.os, if ((sys?.version ?? '').isNotEmpty) sys!.version, sys?.computer]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join('  ·  '),
                  style: t.bodyMedium!.copyWith(color: fx.muted),
                ),
              ],
            ),
          ),
          FButton.quiet('Customize', icon: Icons.dashboard_customize_outlined, onPressed: () => app.go(Section.settings)),
        ],
      ),
      if (order.isEmpty)
        Panel(
          child: EmptyState(
            icon: Icons.visibility_off_outlined,
            title: 'Every card is hidden',
            body: 'Turn cards back on under Customize › Overview.',
            action: FButton('Customize', onPressed: () => app.go(Section.settings)),
          ),
        ),
      for (final r in rows) r,
    ]);
  }
}

Color levelColor(Fx fx, Level l) => switch (l) {
      Level.good => safeColor,
      Level.warn => warnColor,
      Level.bad => dangerColor,
      Level.unknown => fx.faint,
    };

class _HealthCard extends StatelessWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cleaner = context.watch<CleanerState>();
    final shield = context.watch<ShieldState>();
    final health = Health.of(app, cleaner, shield);
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final ringColor = health.score >= 80 ? safeColor : health.score >= 50 ? warnColor : dangerColor;

    Widget? action(Factor f) => switch (f.id) {
          'storage' => FButton('Map drive', dense: true, onPressed: () {
              final d = app.systemDrive;
              if (d != null) context.read<DiskState>().open(d.root);
              app.go(Section.disk);
            }),
          'clutter' => FButton('Clean', dense: true, onPressed: () => app.go(Section.cleaner)),
          'drives' => FButton('Details', dense: true, onPressed: () {
              context.read<DiskState>().setView(health: true);
              app.go(Section.disk);
            }),
          'threats' => FButton('Review', dense: true, onPressed: () => app.go(Section.shield)),
          'fresh' => FButton('Quick scan', dense: true, busy: shield.scanning, onPressed: () {
              shield.scan('quick');
              app.go(Section.shield);
            }),
          _ => null,
        };

    return Panel(
      padding: EdgeInsets.all(fx.pad + 4),
      child: Row(
        children: [
          Ring(
            value: health.score / 100,
            color: ringColor,
            track: fx.surface2,
            size: 176,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${health.score}',
                    style: t.displayLarge!.copyWith(fontSize: 52, fontFeatures: tabular)),
                Text('HEALTH', style: t.labelSmall),
              ],
            ),
          ),
          SizedBox(width: fx.pad + 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(health.verdict, style: t.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  health.issues == 0
                      ? 'Fiend checked storage, clutter, threats and scan history.'
                      : '${plural(health.issues, 'area')} could be better. Each fix is one click away.',
                  style: t.bodyMedium!.copyWith(color: fx.muted),
                ),
                const SizedBox(height: 14),
                for (final f in health.factors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: levelColor(fx, f.level),
                            shape: BoxShape.circle,
                            boxShadow: fx.glowOf(levelColor(fx, f.level), strength: 0.4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(width: 92, child: Text(f.title, style: t.titleSmall)),
                        Expanded(child: Text(f.detail, style: t.bodyMedium!.copyWith(color: fx.muted))),
                        if (f.level == Level.warn || f.level == Level.bad || f.level == Level.unknown)
                          action(f) ?? const SizedBox(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardHead extends StatelessWidget {
  const _CardHead(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [Expanded(child: Eyebrow(title)), ?trailing]),
      );
}

class _DrivesCard extends StatelessWidget {
  const _DrivesCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead('Drives', trailing: FButton.quiet('Open Disk', dense: true, onPressed: () => app.go(Section.disk))),
          for (final d in app.drives.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(d.letter, style: t.titleMedium!.copyWith(fontFeatures: tabular)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d.title, style: t.bodyMedium!.copyWith(color: fx.muted))),
                      if (app.healthFor(d.letter) case final h?) ...[LifePill(h), const SizedBox(width: 10)],
                      Text('${fmtBytes(d.free)} free', style: t.bodyMedium!.copyWith(fontFeatures: tabular)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  UsageBar(fraction: d.usedFraction, color: fullnessColor(context, d.usedFraction)),
                  const SizedBox(height: 6),
                  Text('${(d.usedFraction * 100).round()}% used of ${fmtBytes(d.total)}  ·  ${d.fileSystem}',
                      style: t.bodySmall!.copyWith(fontFeatures: tabular)),
                ],
              ),
            ),
          if (app.drives.isEmpty) Text('No drives found', style: t.bodySmall),
        ],
      ),
    );
  }
}

class _CacheCard extends StatelessWidget {
  const _CacheCard();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cleaner = context.watch<CleanerState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final top = cleaner.categories.where(cleaner.usable).toList()
      ..sort((a, b) => b.eligibleSize.compareTo(a.eligibleSize));
    final max = top.isEmpty ? 1 : top.first.eligibleSize.clamp(1, 1 << 62);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead('Reclaimable space'),
          if (!cleaner.measured)
            Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fx.accent)),
              const SizedBox(width: 10),
              Text('Measuring caches…', style: t.bodyMedium!.copyWith(color: fx.muted)),
            ])
          else ...[
            Text(fmtBytes(cleaner.reclaimable), style: t.displayMedium!.copyWith(fontFeatures: tabular)),
            Text('in files older than ${_age(app.settings.minAgeHours)}', style: t.bodySmall),
            const SizedBox(height: 16),
            for (final c in top.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 150, child: Text(c.name, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
                    Expanded(child: UsageBar(fraction: c.eligibleSize / max, height: 5)),
                    SizedBox(
                      width: 78,
                      child: Text(fmtBytes(c.eligibleSize),
                          textAlign: TextAlign.right, style: t.bodySmall!.copyWith(color: fx.text, fontFeatures: tabular)),
                    ),
                  ],
                ),
              ),
          ],
          const Spacer(),
          const SizedBox(height: 8),
          FButton.primary('Review and clean', icon: Icons.cleaning_services_outlined, onPressed: () => app.go(Section.cleaner)),
        ],
      ),
    );
  }
}

String _age(int hours) => switch (hours) {
      0 => 'any age',
      1 => '1 hour',
      24 => '1 day',
      168 => '1 week',
      _ => hours % 24 == 0 ? '${hours ~/ 24} days' : '$hours hours',
    };

class _ShieldCard extends StatelessWidget {
  const _ShieldCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shield = context.watch<ShieldState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final r = shield.report;
    final last = r?.startedAt ?? app.engine.lastScanAt;
    final high = r?.count('high') ?? 0;
    final medium = r?.count('medium') ?? 0;
    final low = r?.count('low') ?? 0;

    final (icon, color, headline) = shield.scanning
        ? (Icons.radar_rounded, fx.accent, 'Scanning…')
        : last == null
            ? (Icons.shield_outlined, fx.muted, 'Not scanned yet')
            : high > 0
                ? (Icons.gpp_maybe_outlined, dangerColor, plural(high, 'high-risk file'))
                : (medium + low) > 0
                    ? (Icons.policy_outlined, warnColor, '${plural(medium + low, 'file')} to review')
                    : (Icons.verified_user_outlined, safeColor, 'No threats found');

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHead('Shield', trailing: FButton.quiet('Open Shield', dense: true, onPressed: () => app.go(Section.shield))),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(fx.radius),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline, style: t.titleLarge),
                    Text(last == null ? 'Run a quick scan to start' : 'Last ${r?.mode ?? app.engine.lastScanMode} scan ${fmtAgo(last)}',
                        style: t.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (r != null) ...[
              Pill('$high high', color: high > 0 ? dangerColor : fx.faint),
              Pill('$medium medium', color: medium > 0 ? warnColor : fx.faint),
              Pill('$low low', color: low > 0 ? infoColor : fx.faint),
            ],
            Pill('${app.quarantine.length} in quarantine', color: fx.muted),
            Pill(app.system?.defender == true ? 'Defender on hand' : 'Defender unavailable',
                color: app.system?.defender == true ? safeColor : fx.faint),
          ]),
          const Spacer(),
          const SizedBox(height: 16),
          if (shield.scanning)
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: shield.progress?.fraction, minHeight: 4))
          else
            FButton.primary('Quick scan', icon: Icons.radar_rounded, onPressed: () {
              shield.scan('quick');
              app.go(Section.shield);
            }),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;

    Widget tile(IconData icon, String title, String body, VoidCallback onTap) => Material(
          color: fx.surface2,
          borderRadius: BorderRadius.circular(fx.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(fx.radius),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fx.radius),
                border: Border.all(color: fx.border),
              ),
              child: Row(
                children: [
                  Icon(icon, color: fx.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.titleSmall),
                        Text(body, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: fx.faint, size: 18),
                ],
              ),
            ),
          ),
        );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHead('Quick actions'),
          tile(Icons.radar_rounded, 'Quick scan', 'Downloads, Temp, AppData and startup', () {
            context.read<ShieldState>().scan('quick');
            app.go(Section.shield);
          }),
          const SizedBox(height: 8),
          tile(Icons.preview_outlined, 'Preview cleanup', 'See what would be removed first', () {
            context.read<CleanerState>().clean(dryRun: true);
            app.go(Section.cleaner);
          }),
          const SizedBox(height: 8),
          tile(Icons.donut_large_rounded, 'Map the system drive', 'Find the folders taking the most space', () {
            final d = app.systemDrive;
            if (d != null) context.read<DiskState>().open(d.root);
            app.go(Section.disk);
          }),
          const SizedBox(height: 8),
          tile(Icons.rocket_launch_outlined, 'Startup programs', 'Choose what runs when Windows starts', () {
            final shield = context.read<ShieldState>()..focusStartup = true;
            if (!shield.startupLoaded) shield.loadStartup();
            app.go(Section.shield);
          }),
        ],
      ),
    );
  }
}
