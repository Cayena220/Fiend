import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/format.dart';
import '../../core/release.dart';
import '../../state/update_state.dart';
import '../../theme/theme.dart';
import 'common.dart';
import 'sigil.dart';

/// Shows the "new version" popup. [onClose] defaults to closing the window and exiting,
/// which lets the installer replace Fiend's files.
Future<void> showUpdateDialog(BuildContext context, UpdateState updates, Release release, {Future<void> Function()? onClose}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(updates: updates, release: release, onClose: onClose),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.updates, required this.release, this.onClose});
  final UpdateState updates;
  final Release release;
  final Future<void> Function()? onClose;

  Future<void> _install(BuildContext context) async {
    if (await updates.install(release)) {
      // Give the "closing" message a moment on screen, then get out of the installer's way.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (onClose != null) {
        await onClose!();
      } else {
        await windowManager.destroy();
        exit(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final phase = updates.phase;
        final busy = updates.busy;
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, minWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Sigil(size: 34, color: fx.accent, glow: fx.glow),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Fiend ${release.version} is ready', style: t.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        'You have ${updates.current}'
                        '${release.installer.size > 0 ? '  ·  ${fmtBytes(release.installer.size)} download' : ''}',
                        style: t.bodySmall,
                      ),
                    ]),
                  ),
                ]),
                if (release.notes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Eyebrow('What\'s new'),
                  const SizedBox(height: 8),
                  for (final n in release.notes.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 10),
                          child: Container(width: 5, height: 5, decoration: BoxDecoration(color: fx.accent, shape: BoxShape.circle)),
                        ),
                        Expanded(child: Text(n, style: t.bodyMedium)),
                      ]),
                    ),
                ],
                if (!updates.installedCopy && !busy) ...[
                  const SizedBox(height: 10),
                  Text(
                    'This copy of Fiend runs from a folder you unzipped. Updating installs Fiend to your apps folder and opens that copy.',
                    style: t.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                switch (phase) {
                  UpdatePhase.downloading => _Progress(label: updates.progressLabel, value: updates.progress),
                  UpdatePhase.verifying => const _Progress(label: 'Checking the download against its published SHA-256', value: null),
                  UpdatePhase.installing => const _Progress(label: 'Installing. Fiend will close now and reopen when the update is done.', value: null),
                  UpdatePhase.failed => ErrorBanner(updates.error ?? 'The update didn\'t finish.'),
                  _ => const SizedBox.shrink(),
                },
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: busy
              ? const []
              : [
                  FButton.quiet('Skip this version', dense: true, onPressed: () {
                    updates.skip(release);
                    Navigator.of(context).pop();
                  }),
                  const SizedBox(width: 6),
                  FButton('Later', onPressed: () => Navigator.of(context).pop()),
                  FButton.primary(
                    phase == UpdatePhase.failed ? 'Try again' : 'Update now',
                    icon: Icons.download_rounded,
                    onPressed: () => _install(context),
                  ),
                ],
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label, required this.value});
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: value, minHeight: 5)),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall!.copyWith(fontFeatures: tabular)),
        ],
      );
}
