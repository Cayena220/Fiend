import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../state/cleaner_state.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';

const ageChoices = {0: 'Any age', 1: '1 hour', 24: '1 day', 168: '1 week'};

class CleanerScreen extends StatefulWidget {
  const CleanerScreen({super.key});

  @override
  State<CleanerScreen> createState() => _CleanerScreenState();
}

class _CleanerScreenState extends State<CleanerScreen> {
  @override
  void initState() {
    super.initState();
    final c = context.read<CleanerState>();
    if (!c.measured && !c.busy) c.analyze();
  }

  Future<void> _clean(CleanerState c) async {
    final bin = c.selectedCategories.any((x) => x.isRecycleBin);
    final browsers = c.selectedCategories.where((x) => x.isBrowser).map((x) => x.name).toList();
    final body = StringBuffer(
        'Fiend will delete ${plural(c.selectedFiles, 'file')} (${fmtBytes(c.selectedBytes)}). Files that are in use are skipped.');
    if (browsers.isNotEmpty) body.write('\n\nClose ${browsers.join(', ')} first so their cache isn\'t locked.');
    if (bin) body.write('\n\nEmptying the Recycle Bin is permanent.');
    final ok = await confirm(context, title: 'Clean ${fmtBytes(c.selectedBytes)}?', body: body.toString(), confirmLabel: 'Clean now', danger: bin);
    if (ok) await c.clean(dryRun: false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.watch<CleanerState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final groups = <String, List<CacheCategory>>{};
    for (final cat in c.categories) {
      groups.putIfAbsent(cat.group, () => []).add(cat);
    }
    final minAge = app.settings.minAgeHours;

    return ScreenBody(children: [
      ScreenHeader(
        title: 'Cleaner',
        subtitle: 'Clears caches that Windows, browsers and apps rebuild on their own.',
        actions: [FButton('Measure again', icon: Icons.refresh_rounded, onPressed: c.busy ? null : c.analyze)],
      ),
      Panel(
        highlight: c.selectedBytes > 0 && !c.busy,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Selected to clean'),
                  const SizedBox(height: 6),
                  Text(c.measured ? fmtBytes(c.selectedBytes) : '—', style: t.displayLarge!.copyWith(fontFeatures: tabular)),
                  Text(
                    c.measured
                        ? '${plural(c.selectedFiles, 'file')} in ${plural(c.selectedCategories.length, 'location')}'
                        : 'Measuring…',
                    style: t.bodyMedium!.copyWith(color: fx.muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Only remove files older than', style: t.bodySmall),
                const SizedBox(height: 8),
                Segmented<int>(
                  options: ageChoices,
                  value: ageChoices.containsKey(minAge) ? minAge : 24,
                  onChanged: c.busy ? (_) {} : c.setMinAge,
                ),
                const SizedBox(height: 16),
                Row(children: [
                  FButton('Preview', icon: Icons.preview_outlined, onPressed: c.busy || c.selected.isEmpty ? null : () => c.clean(dryRun: true)),
                  const SizedBox(width: 10),
                  FButton.primary('Clean now',
                      icon: Icons.cleaning_services_outlined,
                      busy: c.cleaning,
                      onPressed: c.busy || c.selectedBytes == 0 ? null : () => _clean(c)),
                ]),
              ],
            ),
          ],
        ),
      ),
      if (c.busy) JobPanel(title: c.cleaning ? 'Cleaning' : 'Measuring caches', progress: c.progress, onCancel: c.cancel, unit: c.cleaning ? 'locations' : 'locations', showBytes: true),
      if (c.error != null) ErrorBanner(c.error!),
      if (c.result != null && !c.busy) _ResultBanner(c.result!),
      for (final g in groups.entries)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Eyebrow(g.key)),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < g.value.length; i++) ...[
                    if (i > 0) Divider(indent: 56, color: fx.border),
                    _CategoryRow(cat: g.value[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      if (c.measured && c.categories.isEmpty)
        const Panel(child: EmptyState(icon: Icons.check_circle_outline, title: 'No caches found', body: 'Fiend didn\'t find any cache folders on this PC.')),
    ]);
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner(this.r);
  final CleanReport r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final text = r.dryRun
        ? 'Preview: cleaning would remove ${plural(r.deleted, 'file')} and free ${fmtBytes(r.freed)}. Nothing was deleted.'
        : 'Freed ${fmtBytes(r.freed)} by removing ${plural(r.deleted, 'file')}.'
            '${r.skipped > 0 ? ' ${plural(r.skipped, 'file')} in use ${r.skipped == 1 ? 'was' : 'were'} skipped.' : ''}';
    final color = r.dryRun ? infoColor : safeColor;
    return Panel(
      color: color.withValues(alpha: 0.07),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(r.dryRun ? Icons.preview_outlined : Icons.check_circle_outline_rounded, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: t.bodyMedium)),
      ]),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.cat});
  final CacheCategory cat;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = context.watch<CleanerState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final needsAdmin = cat.admin && !app.isAdmin;
    final usable = c.usable(cat);
    final checked = c.selected.contains(cat.id) && usable;
    final maxEligible = c.categories.fold<int>(1, (m, x) => x.eligibleSize > m ? x.eligibleSize : m);

    return Opacity(
      opacity: usable ? 1 : 0.6,
      child: InkWell(
        borderRadius: BorderRadius.circular(fx.radius),
        onTap: usable && !c.busy ? () => c.toggle(cat.id, !checked) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: fx.compact ? 8 : 12),
          child: Row(
            children: [
              Checkbox(value: checked, onChanged: usable && !c.busy ? (v) => c.toggle(cat.id, v ?? false) : null),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(cat.name, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
                      if (needsAdmin) ...[const SizedBox(width: 8), Pill('Needs admin', color: warnColor, icon: Icons.lock_outline)],
                      if (!needsAdmin && cat.denied) ...[const SizedBox(width: 8), Pill('Can\'t read', color: fx.muted)],
                      if (cat.isRecycleBin) ...[const SizedBox(width: 8), Pill('Permanent', color: dangerColor)],
                    ]),
                    const SizedBox(height: 2),
                    Text(cat.description, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: UsageBar(fraction: cat.eligibleSize / maxEligible, height: 5, color: checked ? fx.accent : fx.faint),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fmtBytes(cat.eligibleSize), style: t.titleSmall!.copyWith(fontFeatures: tabular)),
                    Text(
                      cat.isRecycleBin ? plural(cat.files, 'item') : 'of ${fmtBytes(cat.size)} · ${fmtCount(cat.files)} files',
                      style: t.bodySmall!.copyWith(fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                child: needsAdmin
                    ? IconButton(
                        tooltip: 'Restart Fiend as administrator',
                        iconSize: 17,
                        color: warnColor,
                        onPressed: () async {
                          if (await app.relaunchAsAdmin()) {
                            await windowManager.destroy();
                            exit(0);
                          }
                        },
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                      )
                    : cat.roots.isNotEmpty
                        ? IconButton(
                            tooltip: 'Show in Explorer',
                            iconSize: 16,
                            color: fx.faint,
                            onPressed: () => Process.run('explorer.exe', [cat.roots.first]),
                            icon: const Icon(Icons.folder_open_outlined),
                          )
                        : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
