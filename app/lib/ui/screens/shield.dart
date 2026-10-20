import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../state/shield_state.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../shell.dart';
import '../widgets/common.dart';

enum _Tab { findings, startup, signatures }

class ShieldScreen extends StatefulWidget {
  const ShieldScreen({super.key});

  @override
  State<ShieldScreen> createState() => _ShieldScreenState();
}

class _ShieldScreenState extends State<ShieldScreen> {
  _Tab tab = _Tab.findings;

  @override
  void initState() {
    super.initState();
    final s = context.read<ShieldState>();
    if (s.focusStartup) {
      tab = _Tab.startup;
      s.focusStartup = false;
    }
  }

  Future<void> _custom(ShieldState s) async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder for Fiend to scan');
    if (path != null) await s.scan('custom', paths: [path]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = context.watch<ShieldState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final r = s.report;
    final last = r?.startedAt ?? app.engine.lastScanAt;
    final high = r?.count('high') ?? 0;
    final open = s.openFindings;

    final (color, icon, headline) = s.scanning
        ? (fx.accent, Icons.radar_rounded, 'Hunting…')
        : last == null
            ? (fx.muted, Icons.shield_outlined, 'Not scanned yet')
            : high > 0
                ? (dangerColor, Icons.gpp_maybe_outlined, '${plural(high, 'high-risk file')} need a decision')
                : open > 0
                    ? (warnColor, Icons.policy_outlined, '${plural(open, 'file')} worth a look')
                    : (safeColor, Icons.verified_user_outlined, 'No threats in your last scan');

    final sensitivity = switch (app.settings.sensitivity) { 'low' => 'Relaxed', 'paranoid' => 'Paranoid', _ => 'Balanced' };

    return ScreenBody(children: [
      const ScreenHeader(
        title: 'Shield',
        subtitle: 'Hunts for disguised, packed and known-bad files, and checks what starts with Windows.',
      ),
      Panel(
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(fx.radius + 2),
                border: Border.all(color: color.withValues(alpha: 0.4)),
                boxShadow: fx.glowOf(color, strength: 0.5),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline, style: t.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (last != null) 'Last ${r?.mode ?? app.engine.lastScanMode} scan ${fmtAgo(last)}',
                      if (r != null) '${fmtCount(r.filesExamined)} files examined in ${fmtDuration(r.elapsedMs)}',
                      '${fmtCount(app.signatureCount)} signatures',
                      '$sensitivity sensitivity',
                      app.settings.useDefender && app.system?.defender == true ? 'Defender second opinion on' : 'Defender off',
                    ].join('  ·  '),
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (s.scanning)
        JobPanel(title: '${_modeName(s.scanMode)} scan', progress: s.progress, onCancel: s.cancel)
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.bolt_rounded,
                title: 'Quick scan',
                body: 'Downloads, Desktop, Temp, AppData, Public and startup programs. Usually under a minute.',
                primary: true,
                onStart: () => s.scan('quick'),
              ),
            ),
            SizedBox(width: fx.gap),
            Expanded(
              child: _ModeCard(
                icon: Icons.travel_explore_rounded,
                title: 'Full scan',
                body: 'Every fixed drive, skipping the Windows folder. Can take a long time on big drives.',
                onStart: () => s.scan('full'),
              ),
            ),
            SizedBox(width: fx.gap),
            Expanded(
              child: _ModeCard(
                icon: Icons.folder_special_outlined,
                title: 'Custom scan',
                body: 'Pick one folder, such as a USB stick or a download you aren\'t sure about.',
                startLabel: 'Choose folder',
                onStart: () => _custom(s),
              ),
            ),
          ],
        ),
      if (s.error != null) ErrorBanner(s.error!),
      Row(children: [
        Segmented<_Tab>(
          options: {
            _Tab.findings: 'Findings${r == null ? '' : ' (${r.open.length})'}',
            _Tab.startup: 'Startup programs${s.startupLoaded ? ' (${s.startup.length})' : ''}',
            _Tab.signatures: 'Signatures',
          },
          value: tab,
          onChanged: (v) {
            setState(() => tab = v);
            if (v == _Tab.startup && !s.startupLoaded && !s.loadingStartup) s.loadStartup();
          },
        ),
      ]),
      switch (tab) {
        _Tab.findings => _Findings(report: r),
        _Tab.startup => const _Startup(),
        _Tab.signatures => const _Signatures(),
      },
    ]);
  }
}

String _modeName(String? m) => switch (m) { 'full' => 'Full', 'custom' => 'Custom', _ => 'Quick' };

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.body, required this.onStart, this.primary = false, this.startLabel = 'Start'});
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onStart;
  final bool primary;
  final String startLabel;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primary ? fx.accent : fx.muted, size: 22),
          const SizedBox(height: 12),
          Text(title, style: t.titleMedium),
          const SizedBox(height: 4),
          SizedBox(height: 56, child: Text(body, style: t.bodySmall)),
          const SizedBox(height: 10),
          primary ? FButton.primary(startLabel, icon: Icons.play_arrow_rounded, onPressed: onStart) : FButton(startLabel, onPressed: onStart),
        ],
      ),
    );
  }
}

class _Findings extends StatelessWidget {
  const _Findings({required this.report});
  final ScanReport? report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r == null) {
      return const Panel(
        child: EmptyState(
          icon: Icons.radar_rounded,
          title: 'No scan in this session',
          body: 'Run a quick scan to see what Fiend finds. Results show here with the reasons behind each one.',
        ),
      );
    }
    final items = r.findings.where((f) => !f.dismissed).toList();
    if (items.isEmpty && r.startup.isEmpty) {
      return Panel(
        child: EmptyState(
          icon: Icons.verified_user_outlined,
          title: 'Nothing suspicious',
          body: 'Fiend examined ${plural(r.filesExamined, 'file')} out of ${fmtCount(r.filesSeen)} and none crossed your sensitivity threshold.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _FindingCard(f)),
        if (r.startup.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 10), child: Eyebrow('Startup programs flagged in this scan')),
          for (final i in r.startup) Padding(padding: const EdgeInsets.only(bottom: 10), child: _StartupCard(i)),
        ],
      ],
    );
  }
}

class _Reasons extends StatelessWidget {
  const _Reasons(this.reasons);
  final List<Reason> reasons;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    r.weight >= 100 ? 'match' : '${r.weight > 0 ? '+' : ''}${r.weight}',
                    style: mono(context, size: 11.5, color: r.weight > 0 ? fx.text : safeColor),
                  ),
                ),
                Expanded(child: Text(r.label, style: t.bodyMedium!.copyWith(color: r.weight > 0 ? fx.text : fx.muted))),
              ],
            ),
          ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard(this.f);
  final Finding f;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ShieldState>();
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final busy = s.working.contains(f.id);
    final quarantined = f.quarantineId != null;
    final d = f.defender;

    return Panel(
      highlight: f.severity == 'high' && !quarantined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SeverityPill(severity: f.severity, score: f.score),
                      const SizedBox(width: 10),
                      Flexible(child: Text(f.name, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 6),
                    SelectableText(f.path, style: mono(context, size: 11.5, color: fx.faint)),
                  ],
                ),
              ),
              if (quarantined) const Pill('In quarantine', color: safeColor, icon: Icons.lock_outline),
            ],
          ),
          const SizedBox(height: 14),
          _Reasons(f.reasons),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill(fmtBytes(f.size), color: fx.muted),
            if (f.modified > 0) Pill('Changed ${fmtAgo(f.modified)}', color: fx.muted),
            if (f.signed != null)
              Pill(
                switch (f.signed) { 'signed' => 'Signed', 'unsigned' => 'Unsigned', 'expired' => 'Signature expired', 'unknown' => 'Signature unknown', _ => 'Bad signature' },
                color: f.signed == 'signed' ? safeColor : (f.signed == 'untrusted' ? dangerColor : fx.muted),
              ),
            if (d != null)
              Pill(
                d.status == 'threat' ? 'Defender: ${d.threat ?? 'threat'}' : d.status == 'clean' ? 'Defender: clean' : 'Defender: no answer',
                color: d.status == 'threat' ? dangerColor : d.status == 'clean' ? safeColor : fx.muted,
                icon: Icons.security_rounded,
              ),
            if (f.sha256 != null) Tooltip(message: f.sha256!, child: Pill('SHA-256 ${f.sha256!.substring(0, 12)}…', color: fx.faint)),
          ]),
          if (!quarantined) ...[
            const SizedBox(height: 14),
            Row(children: [
              FButton.danger('Quarantine', icon: Icons.lock_outline_rounded, dense: true, busy: busy, onPressed: () => s.quarantine(f)),
              const SizedBox(width: 8),
              if (app.system?.defender == true && d == null)
                FButton('Ask Defender', icon: Icons.security_rounded, dense: true, onPressed: busy ? null : () => s.askDefender(f)),
              const SizedBox(width: 8),
              FButton('It\'s safe', icon: Icons.check_rounded, dense: true, onPressed: busy
                  ? null
                  : () async {
                      if (await confirm(context,
                          title: 'Trust ${f.name}?',
                          body: 'Fiend will skip this exact file in future scans. If the file changes, Fiend checks it again.',
                          confirmLabel: 'Trust this file')) {
                        await s.markSafe(f);
                      }
                    }),
              const Spacer(),
              FButton.quiet('Show in folder', icon: Icons.folder_open_outlined, dense: true, onPressed: () => app.reveal(f.path)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _StartupCard extends StatelessWidget {
  const _StartupCard(this.item, {this.compact = false});
  final StartupItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ShieldState>();
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final busy = s.working.contains(item.id);
    final flagged = item.score > 0;

    return Panel(
      padding: EdgeInsets.all(compact ? 14 : fx.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (flagged) ...[SeverityPill(severity: item.severity, score: item.score), const SizedBox(width: 10)],
              Expanded(child: Text(item.name, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
              Pill(item.location, color: fx.muted),
              const SizedBox(width: 6),
              if (item.signed != null)
                Pill(
                  switch (item.signed) { 'signed' => 'Signed', 'unsigned' => 'Unsigned', 'expired' => 'Expired', 'unknown' => 'Store app', _ => 'Bad signature' },
                  color: item.signed == 'signed' || item.signed == 'unknown' ? safeColor : (item.signed == 'untrusted' ? dangerColor : fx.muted),
                ),
              const SizedBox(width: 10),
              if (item.target != null)
                IconButton(
                  tooltip: 'Show in folder',
                  iconSize: 16,
                  color: fx.muted,
                  onPressed: () => app.reveal(item.target!),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              FButton('Turn off', dense: true, busy: busy, onPressed: () async {
                if (await confirm(context,
                    title: 'Stop ${item.name} from starting with Windows?',
                    body: 'Fiend keeps a copy of the entry, so you can turn it back on from this list later.',
                    confirmLabel: 'Turn off')) {
                  await s.disableStartup(item);
                }
              }),
            ],
          ),
          const SizedBox(height: 6),
          Text(item.command, style: mono(context, size: 11.5, color: fx.faint), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (item.reasons.any((r) => r.weight > 0)) ...[
            const SizedBox(height: 10),
            _Reasons(item.reasons),
          ],
        ],
      ),
    );
  }
}

class _Startup extends StatelessWidget {
  const _Startup();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ShieldState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    if (s.loadingStartup && !s.startupLoaded) {
      return const JobPanel(title: 'Reading startup programs', progress: null);
    }
    if (!s.startupLoaded) {
      return Panel(
        child: EmptyState(
          icon: Icons.rocket_launch_outlined,
          title: 'See what starts with Windows',
          body: 'Fiend reads the Run keys, Startup folders and scheduled tasks, and flags anything unusual.',
          action: FButton.primary('Load startup programs', onPressed: s.loadStartup),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('${plural(s.startup.length, 'program')} start with Windows. Flagged ones are listed first.', style: t.bodyMedium!.copyWith(color: fx.muted))),
          FButton('Reload', icon: Icons.refresh_rounded, dense: true, busy: s.loadingStartup, onPressed: s.loadStartup),
        ]),
        const SizedBox(height: 12),
        for (final i in s.startup) Padding(padding: const EdgeInsets.only(bottom: 8), child: _StartupCard(i, compact: true)),
        if (s.disabled.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 10), child: Eyebrow('Turned off by Fiend')),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: [
              for (final d in s.disabled)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.name, style: t.titleSmall),
                        Text('Turned off ${fmtAgo(d.disabledAt)} · ${d.location.isEmpty ? d.source : d.location}', style: t.bodySmall),
                      ]),
                    ),
                    FButton('Turn back on', dense: true, busy: s.working.contains(d.id), onPressed: () => s.restoreStartup(d)),
                  ]),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _Signatures extends StatelessWidget {
  const _Signatures();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = context.watch<ShieldState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtCount(app.signatureCount), style: t.displayMedium!.copyWith(fontFeatures: tabular)),
                Text('known-bad SHA-256 hashes · updated ${fmtAgo(app.signaturesUpdatedAt)}', style: t.bodySmall),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    'Every executable Fiend examines is hashed and checked against this list. '
                    'Pull the newest hashes from MalwareBazaar, a free feed run by abuse.ch, or import your own list '
                    '(one SHA-256 per line; CSV works too).',
                    style: t.bodyMedium!.copyWith(color: fx.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FButton.primary('Update from MalwareBazaar', icon: Icons.cloud_download_outlined, busy: s.updatingSignatures, onPressed: s.updateFromMalwareBazaar),
              const SizedBox(height: 8),
              FButton('Import a list…', icon: Icons.file_open_outlined, onPressed: () async {
                final file = await FilePicker.pickFile(dialogTitle: 'Choose a hash list', type: FileType.custom, allowedExtensions: ['txt', 'csv']);
                final path = file?.path;
                if (path != null) await s.importFile(path);
              }),
              const SizedBox(height: 8),
              FButton.quiet('Remove imported hashes', dense: true, onPressed: () async {
                if (await confirm(context, title: 'Remove imported hashes?', body: 'Fiend keeps only its built-in test signature until you update again.', confirmLabel: 'Remove', danger: true)) {
                  await s.resetSignatures();
                }
              }),
            ],
          ),
        ],
      ),
    );
  }
}
