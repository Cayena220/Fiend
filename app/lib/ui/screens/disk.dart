import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../state/disk_state.dart';
import '../../theme/theme.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/drive_health.dart';
import '../widgets/treemap.dart';

class DiskScreen extends StatelessWidget {
  const DiskScreen({super.key});

  Future<void> _pick(DiskState disk) async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder for Fiend to map');
    if (path != null) await disk.open(path);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final disk = context.watch<DiskState>();
    final fx = Fx.of(context);

    final t = Theme.of(context).textTheme;
    final worst = app.driveHealth.where((h) => h.status == 'bad' || h.status == 'caution').length;

    return ScreenBody(children: [
      ScreenHeader(
        title: 'Disk',
        subtitle: 'See what fills your drives, how much life they have left, and clear the biggest files.',
        actions: [
          if (disk.showHealth)
            FButton('Read again', icon: Icons.refresh_rounded, busy: app.readingHealth, onPressed: app.refreshDriveHealth)
          else ...[
            FButton('Refresh drives', icon: Icons.refresh_rounded, onPressed: app.refreshDrives),
            FButton('Map a folder…', icon: Icons.folder_open_outlined, onPressed: () => _pick(disk)),
          ],
        ],
      ),
      Row(children: [
        Segmented<bool>(
          options: {false: 'Space', true: worst > 0 ? 'Health ($worst)' : 'Health'},
          value: disk.showHealth,
          onChanged: (v) => disk.setView(health: v),
        ),
      ]),
      if (disk.showHealth) ...[
        if (app.driveHealth.isEmpty)
          Panel(
            child: EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: app.readingHealth ? 'Reading your drives…' : 'No drive health data',
              body: 'Fiend reads wear, temperature and error counts straight from each drive. Windows didn\'t report any physical drives this time.',
              action: FButton('Read again', onPressed: app.refreshDriveHealth),
            ),
          )
        else ...[
          Text(
            'Life left is the drive\'s own estimate of its rated endurance. Temperatures are shown in '
            '${app.settings.temperatureUnit == 'f' ? '°F' : '°C'}; change units and the warning level under Customize.',
            style: t.bodySmall,
          ),
          for (final h in app.driveHealth) DriveHealthPanel(h),
        ],
      ] else ...[
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 1000 ? 3 : 2;
        final w = (box.maxWidth - fx.gap * (cols - 1)) / cols;
        return Wrap(
          spacing: fx.gap,
          runSpacing: fx.gap,
          children: [for (final d in app.drives) SizedBox(width: w, child: _DriveCard(d))],
        );
      }),
      if (disk.busy)
        JobPanel(
          title: 'Mapping ${disk.trail.isEmpty ? '' : disk.trail.last}',
          progress: disk.progress,
          onCancel: disk.cancel,
          showBytes: true,
        ),
      if (disk.error != null) ErrorBanner(disk.error!),
      if (disk.analysis != null && !disk.busy) _AnalysisView(a: disk.analysis!),
      if (disk.analysis == null && !disk.busy)
        Panel(
          child: EmptyState(
            icon: Icons.donut_large_rounded,
            title: 'Pick a drive to map',
            body: 'Fiend walks every folder and shows where the space went, biggest first. Mapping a whole drive can take a minute.',
            action: app.systemDrive == null
                ? null
                : FButton.primary('Map ${app.systemDrive!.letter}', icon: Icons.donut_large_rounded, onPressed: () => disk.open(app.systemDrive!.root)),
          ),
        ),
      ],
    ]);
  }
}

class _DriveCard extends StatelessWidget {
  const _DriveCard(this.d);
  final Drive d;

  @override
  Widget build(BuildContext context) {
    final disk = context.watch<DiskState>();
    final health = context.watch<AppState>().healthFor(d.letter);
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final color = fullnessColor(context, d.usedFraction);
    final active = disk.trail.isNotEmpty && disk.trail.first.toLowerCase() == d.root.toLowerCase();
    return Panel(
      highlight: active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.letter, style: t.displayMedium!.copyWith(fontFeatures: tabular)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.title, style: t.titleSmall),
                      Text('${d.fileSystem} · ${d.kind}${d.system && d.label.isNotEmpty ? ' · Windows' : ''}', style: t.bodySmall),
                    ],
                  ),
                ),
              ),
              if (health != null) ...[
                InkWell(onTap: () => disk.setView(health: true), borderRadius: BorderRadius.circular(99), child: LifePill(health)),
                const SizedBox(width: 6),
              ],
              Pill('${(d.usedFraction * 100).round()}%', color: color),
            ],
          ),
          const SizedBox(height: 16),
          UsageBar(fraction: d.usedFraction, color: color, height: 8),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('${fmtBytes(d.free)} free of ${fmtBytes(d.total)}',
                    style: t.bodyMedium!.copyWith(color: fx.muted, fontFeatures: tabular)),
              ),
              FButton(active ? 'Map again' : 'Map', dense: true, icon: Icons.donut_large_rounded, onPressed: disk.busy ? null : () => disk.open(d.root)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView({required this.a});
  final DiskAnalysis a;

  @override
  Widget build(BuildContext context) {
    final disk = context.watch<DiskState>();
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final maxKind = a.kinds.isEmpty ? 1 : a.kinds.first.size.clamp(1, 1 << 62);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (disk.trail.length > 1) ...[
              FButton('Up', icon: Icons.arrow_upward_rounded, dense: true, onPressed: disk.up),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(a.root, style: mono(context, size: 13.5, color: fx.text), overflow: TextOverflow.ellipsis)),
            Text(
              '${fmtBytes(a.size)}  ·  ${fmtCount(a.files)} files  ·  ${fmtDuration(a.elapsedMs)}'
              '${a.denied > 0 ? '  ·  ${fmtCount(a.denied)} unreadable' : ''}',
              style: t.bodySmall!.copyWith(fontFeatures: tabular),
            ),
          ],
        ),
        if (a.cancelled) ...[
          const SizedBox(height: 10),
          const ErrorBanner('Mapping was stopped early, so these totals are partial.'),
        ],
        SizedBox(height: fx.gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                        child: Row(children: [
                          const Expanded(child: Eyebrow('Folders by size')),
                          Text('Click a block to open it', style: t.bodySmall),
                        ]),
                      ),
                      SizedBox(height: 360, child: Treemap(node: a.tree, onOpen: (n) => disk.analyze(n.path))),
                    ],
                  ),
                ),
              ),
              SizedBox(width: fx.gap),
              Expanded(
                flex: 2,
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('By file type'),
                      const SizedBox(height: 14),
                      for (final k in a.kinds.take(9))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(k.kind, style: t.bodyMedium)),
                                Text(fmtBytes(k.size), style: t.bodyMedium!.copyWith(fontFeatures: tabular)),
                              ]),
                              const SizedBox(height: 5),
                              UsageBar(fraction: k.size / maxKind, height: 4),
                              const SizedBox(height: 3),
                              Text(plural(k.files, 'file'), style: t.bodySmall!.copyWith(fontFeatures: tabular)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: fx.gap),
        Panel(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(children: [
                  const Expanded(child: Eyebrow('Largest files')),
                  Text('${fmtCount(a.largeFiles)} over ${fmtBytes(app.settings.largeFileMb * 1024 * 1024)}', style: t.bodySmall),
                ]),
              ),
              if (a.topFiles.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('No files here', style: t.bodySmall)),
              for (final f in a.topFiles.take(app.settings.topFiles)) _FileRow(f),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow(this.f);
  final FileEntry f;

  @override
  Widget build(BuildContext context) {
    final disk = context.read<DiskState>();
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(fx.radius),
      onTap: () => app.reveal(f.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name, style: t.titleSmall, overflow: TextOverflow.ellipsis),
                  Text(f.path, style: mono(context, size: 11, color: fx.faint), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: 120, child: Text(f.kind, style: t.bodySmall)),
            SizedBox(width: 100, child: Text(fmtAgo(f.modified), style: t.bodySmall)),
            SizedBox(
              width: 86,
              child: Text(fmtBytes(f.size), textAlign: TextAlign.right, style: t.titleSmall!.copyWith(fontFeatures: tabular)),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Show in Explorer',
              iconSize: 17,
              color: fx.muted,
              onPressed: () => app.reveal(f.path),
              icon: const Icon(Icons.folder_open_outlined),
            ),
            IconButton(
              tooltip: 'Move to Recycle Bin',
              iconSize: 17,
              color: fx.muted,
              onPressed: () async {
                if (await confirm(context,
                    title: 'Move ${f.name} to the Recycle Bin?',
                    body: 'It frees ${fmtBytes(f.size)} once the Recycle Bin is emptied. You can restore it from the Recycle Bin until then.',
                    confirmLabel: 'Move to Recycle Bin')) {
                  await disk.recycle(f);
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
