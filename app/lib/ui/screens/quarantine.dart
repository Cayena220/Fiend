import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../shell.dart';
import '../widgets/common.dart';

class QuarantineScreen extends StatelessWidget {
  const QuarantineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fx = Fx.of(context);
    final total = app.quarantine.fold<int>(0, (a, e) => a + e.size);
    return ScreenBody(children: [
      ScreenHeader(
        title: 'Quarantine',
        subtitle: 'Files here are scrambled so they can\'t run. Restore puts a file back where it was.',
        actions: [FButton('Refresh', icon: Icons.refresh_rounded, onPressed: app.refreshQuarantine)],
      ),
      if (app.quarantine.isEmpty)
        const Panel(
          child: EmptyState(
            icon: Icons.lock_open_rounded,
            title: 'Quarantine is empty',
            body: 'When you quarantine a file from Shield, it lands here. Nothing is deleted until you say so.',
          ),
        )
      else ...[
        Text('${plural(app.quarantine.length, 'file')} · ${fmtBytes(total)}', style: Theme.of(context).textTheme.bodySmall),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < app.quarantine.length; i++) ...[
              if (i > 0) Divider(color: fx.border, indent: 14, endIndent: 14),
              _Row(app.quarantine[i]),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.e);
  final QuarantineEntry e;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final severity = e.score >= 70 ? 'high' : e.score >= 40 ? 'medium' : e.score > 0 ? 'low' : 'none';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (e.score > 0) ...[SeverityPill(severity: severity, score: e.score), const SizedBox(width: 10)],
                  Flexible(child: Text(e.name, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 4),
                Text(e.originalPath, style: mono(context, size: 11.5, color: fx.faint), overflow: TextOverflow.ellipsis),
                if (e.reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(e.reason, style: t.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtBytes(e.size), style: t.titleSmall!.copyWith(fontFeatures: tabular)),
              Text(fmtAgo(e.quarantinedAt), style: t.bodySmall),
            ]),
          ),
          const SizedBox(width: 16),
          FButton('Restore', dense: true, icon: Icons.settings_backup_restore_rounded, onPressed: () async {
            if (await confirm(context,
                title: 'Restore ${e.name}?',
                body: 'The file goes back to ${e.originalPath} and can run again. Only restore files you trust.',
                confirmLabel: 'Restore')) {
              await app.restoreFromQuarantine(e);
            }
          }),
          const SizedBox(width: 8),
          FButton.danger('Delete', dense: true, icon: Icons.delete_forever_outlined, onPressed: () async {
            if (await confirm(context,
                title: 'Delete ${e.name} for good?',
                body: 'This can\'t be undone.',
                confirmLabel: 'Delete forever',
                danger: true)) {
              await app.deleteFromQuarantine(e);
            }
          }),
        ],
      ),
    );
  }
}
