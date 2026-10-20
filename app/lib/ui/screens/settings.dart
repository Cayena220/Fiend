import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'dashboard.dart' show dashboardCardLabels;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final fx = Fx.of(context);
    void set(String sec, String key, Object? v) => app.updateSettings((x) => x.set(sec, key, v));

    return ScreenBody(children: [
      const ScreenHeader(title: 'Customize', subtitle: 'Make Fiend look and behave the way you want. Changes apply right away.'),
      _Section(
        title: 'Appearance',
        children: [
          SettingRow(title: 'Accent', description: 'Used for highlights, progress and the sigil.', control: _AccentPicker(s: s, onChanged: set)),
          SettingRow(
            title: 'Depth',
            description: 'How dark the layers behind everything are.',
            control: Row(children: [
              for (final e in depths.entries) ...[
                _DepthSwatch(id: e.key, depth: e.value, selected: s.depth == e.key, onTap: () => set('appearance', 'depth', e.key)),
                const SizedBox(width: 10),
              ],
            ]),
          ),
          SettingRow(
            title: 'Density',
            description: 'Compact fits more on screen.',
            control: Segmented<String>(
              options: const {'comfortable': 'Comfortable', 'compact': 'Compact'},
              value: s.density,
              onChanged: (v) => set('appearance', 'density', v),
            ),
          ),
          SettingRow(
            title: 'Corner radius',
            description: '${s.radius.round()} px',
            control: SizedBox(
              width: 240,
              child: Slider(min: 2, max: 18, divisions: 16, value: s.radius.clamp(2, 18), onChanged: (v) => set('appearance', 'radius', v)),
            ),
          ),
          SettingRow(title: 'Glow', description: 'Soft light around the accent and severity colors.', control: Switch(value: s.glow, onChanged: (v) => set('appearance', 'glow', v))),
          SettingRow(title: 'Reduce motion', description: 'Turn off transitions and animations.', control: Switch(value: s.reduceMotion, onChanged: (v) => set('appearance', 'reduce_motion', v))),
        ],
      ),
      _Section(
        title: 'Overview',
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Drag to reorder the cards on the Overview screen, and switch off the ones you don\'t need.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          _CardOrder(s: s, app: app),
        ],
      ),
      _Section(
        title: 'Cleaner',
        children: [
          SettingRow(
            title: 'Keep recent files',
            description: 'Files newer than this stay put, so running installers and open apps aren\'t disturbed.',
            control: Segmented<int>(
              options: const {0: 'Any age', 1: '1 hour', 24: '1 day', 168: '1 week'},
              value: const [0, 1, 24, 168].contains(s.minAgeHours) ? s.minAgeHours : 24,
              onChanged: (v) => set('cleaner', 'min_age_hours', v),
            ),
          ),
          _CustomCaches(s: s, app: app),
          _PathList(
            title: 'Never clean these folders',
            empty: 'No exclusions.',
            items: s.cleanerExclusions,
            onChanged: (l) => set('cleaner', 'exclusions', l),
          ),
        ],
      ),
      _Section(
        title: 'Shield',
        children: [
          SettingRow(
            title: 'Sensitivity',
            description: switch (s.sensitivity) {
              'low' => 'Relaxed: only strong evidence is reported (score 50+).',
              'paranoid' => 'Paranoid: report anything unusual (score 15+). Expect more false alarms.',
              _ => 'Balanced: report likely problems (score 30+).',
            },
            control: Segmented<String>(
              options: const {'low': 'Relaxed', 'balanced': 'Balanced', 'paranoid': 'Paranoid'},
              value: s.sensitivity,
              onChanged: (v) => set('shield', 'sensitivity', v),
            ),
          ),
          SettingRow(
            title: 'Ask Microsoft Defender',
            description: 'Get a second opinion from Defender on medium and high findings.',
            control: Switch(value: s.useDefender, onChanged: app.system?.defender == true ? (v) => set('shield', 'use_defender', v) : null),
          ),
          SettingRow(
            title: 'Check digital signatures',
            description: 'Signed software from verified publishers scores lower.',
            control: Switch(value: s.verifySignatures, onChanged: (v) => set('shield', 'verify_signatures', v)),
          ),
          SettingRow(
            title: 'Quarantine high-risk files automatically',
            description: 'Files scoring 70 or more are moved to quarantine without asking.',
            control: Switch(value: s.autoQuarantine, onChanged: (v) => set('shield', 'auto_quarantine', v)),
          ),
          SettingRow(
            title: 'Quick scan when Fiend opens',
            control: Switch(value: s.scanOnLaunch, onChanged: (v) => set('shield', 'scan_on_launch', v)),
          ),
          SettingRow(
            title: 'Largest file to hash',
            description: 'Bigger files still get name checks, but aren\'t read in full. ${s.maxFileMb} MB',
            control: SizedBox(
              width: 240,
              child: Slider(
                min: 50,
                max: 1000,
                divisions: 19,
                value: s.maxFileMb.clamp(50, 1000).toDouble(),
                onChanged: (v) => set('shield', 'max_file_mb', v.round()),
              ),
            ),
          ),
          _PathList(
            title: 'Also include in quick scans',
            empty: 'Quick scans cover Downloads, Desktop, Temp, AppData and Public.',
            items: s.extraLocations,
            onChanged: (l) => set('shield', 'extra_locations', l),
          ),
          _PathList(
            title: 'Never scan these folders',
            empty: 'No exclusions.',
            items: s.shieldExclusions,
            onChanged: (l) => set('shield', 'exclusions', l),
          ),
          _PathList(
            title: 'Trusted files',
            empty: 'Files you mark as safe in Shield appear here.',
            items: s.allowlist,
            onChanged: (l) => set('shield', 'allowlist', l),
            addable: false,
          ),
        ],
      ),
      _Section(
        title: 'Disk',
        children: [
          SettingRow(
            title: 'Count a file as large from',
            control: Segmented<int>(
              options: const {100: '100 MB', 500: '500 MB', 1024: '1 GB', 4096: '4 GB'},
              value: const [100, 500, 1024, 4096].contains(s.largeFileMb) ? s.largeFileMb : 500,
              onChanged: (v) => set('disk', 'large_file_mb', v),
            ),
          ),
          SettingRow(
            title: 'Largest files to list',
            control: Segmented<int>(
              options: const {25: '25', 50: '50', 100: '100'},
              value: const [25, 50, 100].contains(s.topFiles) ? s.topFiles : 50,
              onChanged: (v) => set('disk', 'top_files', v),
            ),
          ),
        ],
      ),
      _Section(
        title: 'About',
        children: [
          SettingRow(
            title: 'Fiend 1.0',
            description: 'Engine ${app.system?.coreVersion ?? '?'} · ${app.system?.os ?? ''} build ${app.system?.build ?? ''}',
            control: FButton('Open data folder', icon: Icons.folder_open_outlined, dense: true, onPressed: () => app.reveal(app.system?.dataDir ?? '')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Fiend\'s Shield combines heuristics, a hash blocklist and Microsoft Defender. It catches common tricks, '
              'but it isn\'t a full antivirus. Keep Windows Security turned on.',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: fx.muted),
            ),
          ),
          SettingRow(
            title: 'Reset everything',
            description: 'Puts every option on this screen back to its default.',
            control: FButton.danger('Reset', dense: true, onPressed: () async {
              if (await confirm(context, title: 'Reset all settings?', body: 'Your quarantine and imported signatures are kept.', confirmLabel: 'Reset', danger: true)) {
                await app.resetSettings();
              }
            }),
          ),
        ],
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Eyebrow(title)),
        Panel(
          padding: EdgeInsets.symmetric(horizontal: fx.pad, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(color: fx.border),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AccentPicker extends StatefulWidget {
  const _AccentPicker({required this.s, required this.onChanged});
  final Settings s;
  final void Function(String sec, String key, Object? v) onChanged;

  @override
  State<_AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<_AccentPicker> {
  late final TextEditingController hex = TextEditingController(text: widget.s.customAccent);

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  Widget _dot(String id, Color c, String label) {
    final fx = Fx.of(context);
    final selected = widget.s.accent == id;
    return Tooltip(
      message: label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => widget.onChanged('appearance', 'accent', id),
        child: AnimatedContainer(
          duration: fx.motion,
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? fx.text : Colors.transparent, width: 2)),
          child: Container(decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: fx.glowOf(c, strength: 0.4))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final custom = parseHex(widget.s.customAccent) ?? accents['hellfire']!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in accents.entries) ...[_dot(e.key, e.value, accentLabels[e.key]!), const SizedBox(width: 6)],
        _dot('custom', custom, 'Custom'),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: TextField(
            controller: hex,
            style: mono(context, size: 12.5, color: Fx.of(context).text),
            decoration: const InputDecoration(hintText: '#RRGGBB'),
            onChanged: (v) {
              final c = parseHex(v);
              if (c != null) {
                widget.onChanged('appearance', 'custom_accent', toHex(c));
                widget.onChanged('appearance', 'accent', 'custom');
              }
            },
          ),
        ),
      ],
    );
  }
}

class _DepthSwatch extends StatelessWidget {
  const _DepthSwatch({required this.id, required this.depth, required this.selected, required this.onTap});
  final String id;
  final Depth depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(fx.radius),
      child: Column(
        children: [
          AnimatedContainer(
            duration: fx.motion,
            width: 74,
            height: 46,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: depth.bg,
              borderRadius: BorderRadius.circular(fx.radius),
              border: Border.all(color: selected ? fx.accent : depth.border, width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Container(width: 14, decoration: BoxDecoration(color: depth.surface, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Expanded(
                child: Column(children: [
                  Expanded(child: Container(decoration: BoxDecoration(color: depth.surface2, borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(height: 3),
                  Container(height: 4, decoration: BoxDecoration(color: fx.accent, borderRadius: BorderRadius.circular(2))),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(depth.label, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: selected ? fx.text : fx.muted)),
        ],
      ),
    );
  }
}

class _CardOrder extends StatelessWidget {
  const _CardOrder({required this.s, required this.app});
  final Settings s;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final order = [
      ...s.dashboardCards.where(dashboardCardLabels.containsKey),
      ...dashboardCardLabels.keys.where((k) => !s.dashboardCards.contains(k)),
    ];
    final hidden = s.dashboardHidden.toSet();
    return ReorderableListView(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      physics: const NeverScrollableScrollPhysics(),
      onReorderItem: (from, to) {
        final list = List.of(order);
        list.insert(to, list.removeAt(from));
        app.updateSettings((x) => x.set('dashboard', 'cards', list));
      },
      children: [
        for (var i = 0; i < order.length; i++)
          Padding(
            key: ValueKey(order[i]),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              ReorderableDragStartListener(
                index: i,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded, color: fx.faint, size: 18)),
                ),
              ),
              Expanded(child: Text(dashboardCardLabels[order[i]]!, style: t.bodyMedium)),
              Switch(
                value: !hidden.contains(order[i]),
                onChanged: (v) => app.updateSettings((x) {
                  final h = x.dashboardHidden.toSet();
                  v ? h.remove(order[i]) : h.add(order[i]);
                  x.set('dashboard', 'hidden', h.toList());
                }),
              ),
            ]),
          ),
      ],
    );
  }
}

class _CustomCaches extends StatelessWidget {
  const _CustomCaches({required this.s, required this.app});
  final Settings s;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final items = s.customPaths;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your own cache folders', style: t.titleSmall),
                const SizedBox(height: 3),
                Text('Add folders an app fills with throwaway files, such as a game\'s shader cache. They appear in Cleaner.', style: t.bodySmall),
              ]),
            ),
            FButton('Add folder…', icon: Icons.add_rounded, dense: true, onPressed: () async {
              final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a cache folder');
              if (path == null) return;
              final name = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).last;
              app.updateSettings((x) => x.set('cleaner', 'custom_paths', [
                    ...x.customPaths,
                    {'name': name, 'path': path},
                  ]));
            }),
          ]),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.folder_outlined, size: 16, color: fx.muted),
                const SizedBox(width: 8),
                SizedBox(width: 160, child: Text('${items[i]['name']}', style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
                Expanded(child: Text('${items[i]['path']}', style: mono(context, size: 11.5), overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: 'Remove',
                  iconSize: 16,
                  color: fx.muted,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => app.updateSettings((x) => x.set('cleaner', 'custom_paths', [...x.customPaths]..removeAt(i))),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _PathList extends StatelessWidget {
  const _PathList({required this.title, required this.empty, required this.items, required this.onChanged, this.addable = true});
  final String title;
  final String empty;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final bool addable;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: t.titleSmall)),
            if (addable)
              FButton('Add folder…', icon: Icons.add_rounded, dense: true, onPressed: () async {
                final path = await FilePicker.getDirectoryPath(dialogTitle: title);
                if (path != null && !items.contains(path)) onChanged([...items, path]);
              }),
          ]),
          const SizedBox(height: 6),
          if (items.isEmpty) Text(empty, style: t.bodySmall),
          for (final p in items)
            Row(children: [
              Expanded(child: Text(p, style: mono(context, size: 11.5, color: fx.text), overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Remove',
                iconSize: 16,
                color: fx.muted,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => onChanged([...items]..remove(p)),
              ),
            ]),
          if (items.length > 3) Text(plural(items.length, 'entry', 'entries'), style: t.bodySmall),
        ],
      ),
    );
  }
}
