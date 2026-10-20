import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';

TextStyle mono(BuildContext context, {double size = 12, Color? color}) => TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFallback,
      fontSize: size,
      color: color ?? Fx.of(context).muted,
      height: 1.35,
    );

const tabular = [FontFeature.tabularFigures()];

/// The one container shape in Fiend: a raised surface with a hairline edge.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.highlight = false, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return AnimatedContainer(
      duration: fx.motion,
      padding: padding ?? EdgeInsets.all(fx.pad),
      decoration: BoxDecoration(
        color: color ?? fx.surface,
        borderRadius: BorderRadius.circular(fx.radius + 2),
        border: Border.all(color: highlight ? fx.accent.withValues(alpha: 0.45) : fx.border),
        boxShadow: highlight ? fx.glowOf(fx.accent, strength: 0.7) : null,
      ),
      child: child,
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(color: color),
      );
}

/// Screen title with a one-line purpose and optional actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, required this.subtitle, this.actions = const []});
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.displayMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: t.bodyMedium!.copyWith(color: Fx.of(context).muted)),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon, this.solid = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? (color.computeLuminance() > 0.4 ? const Color(0xFF0B0A10) : Colors.white) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: solid ? 1 : 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: 0.3,
                fontFeatures: tabular,
              )),
        ],
      ),
    );
  }
}

class SeverityPill extends StatelessWidget {
  const SeverityPill({super.key, required this.severity, required this.score});
  final String severity;
  final int score;

  @override
  Widget build(BuildContext context) {
    final label = switch (severity) { 'high' => 'High', 'medium' => 'Medium', 'low' => 'Low', _ => 'Clean' };
    return Pill('$label · $score', color: Fx.of(context).severity(severity));
  }
}

enum ButtonKind { primary, ghost, danger, quiet }

class FButton extends StatelessWidget {
  const FButton(this.label, {super.key, this.icon, this.onPressed, this.kind = ButtonKind.ghost, this.busy = false, this.dense = false});
  const FButton.primary(this.label, {super.key, this.icon, this.onPressed, this.busy = false, this.dense = false}) : kind = ButtonKind.primary;
  const FButton.danger(this.label, {super.key, this.icon, this.onPressed, this.busy = false, this.dense = false}) : kind = ButtonKind.danger;
  const FButton.quiet(this.label, {super.key, this.icon, this.onPressed, this.busy = false, this.dense = false}) : kind = ButtonKind.quiet;

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final bool busy;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (kind) {
      ButtonKind.primary => (fx.accent, fx.onAccent, fx.accent),
      ButtonKind.danger => (dangerColor.withValues(alpha: 0.12), dangerColor, dangerColor.withValues(alpha: 0.4)),
      ButtonKind.ghost => (fx.surface2, fx.text, fx.border),
      ButtonKind.quiet => (Colors.transparent, fx.muted, Colors.transparent),
    };
    final h = dense ? 30.0 : 36.0;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fx.radius),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
            decoration: kind == ButtonKind.primary && enabled
                ? BoxDecoration(boxShadow: fx.glowOf(fx.accent, strength: 0.6))
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (icon != null)
                  Icon(icon, size: dense ? 15 : 17, color: fg),
                if (busy || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                        fontSize: dense ? 12.5 : 13,
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin capacity bar.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.fraction, this.color, this.height = 6, this.track});
  final double fraction;
  final Color? color;
  final Color? track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final c = color ?? fx.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track ?? fx.border.withValues(alpha: 0.7))),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(height),
                  boxShadow: fx.glowOf(c, strength: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Neutral while a drive has room, amber from 80% and red from 90%, whatever the accent.
Color fullnessColor(BuildContext context, double used) {
  if (used >= 0.9) return dangerColor;
  if (used >= 0.8) return warnColor;
  return Fx.of(context).text.withValues(alpha: 0.72);
}

/// Live progress for a running engine job.
class JobPanel extends StatelessWidget {
  const JobPanel({super.key, required this.title, required this.progress, this.onCancel, this.unit = 'files', this.showBytes = false});
  final String title;
  final JobProgress? progress;
  final VoidCallback? onCancel;
  final String unit;
  final bool showBytes;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    final p = progress;
    final counts = p == null
        ? ''
        : p.total > 0
            ? '${fmtCount(p.done)} of ${fmtCount(p.total)} $unit'
            : p.done > 0
                ? '${fmtCount(p.done)} $unit'
                : '';
    return Panel(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: fx.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: title, style: t.titleMedium),
                  TextSpan(
                    text: p == null || p.phase.isEmpty ? '' : '   ${p.phase}',
                    style: t.bodyMedium!.copyWith(color: fx.muted),
                  ),
                ])),
              ),
              if (counts.isNotEmpty)
                Text(counts, style: t.bodySmall!.copyWith(fontFeatures: tabular)),
              if (showBytes && (p?.bytes ?? 0) > 0) ...[
                const SizedBox(width: 12),
                Text(fmtBytes(p!.bytes), style: t.bodySmall!.copyWith(fontFeatures: tabular)),
              ],
              if ((p?.found ?? 0) > 0) ...[
                const SizedBox(width: 12),
                Pill('${p!.found} flagged', color: warnColor),
              ],
              if (onCancel != null) ...[
                const SizedBox(width: 14),
                FButton('Stop', icon: Icons.stop_rounded, onPressed: onCancel, dense: true),
              ],
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: p?.fraction, minHeight: 4),
          ),
          if ((p?.current ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(p!.current, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, size: 11.5, color: fx.faint)),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: fx.surface2, shape: BoxShape.circle, border: Border.all(color: fx.border)),
            child: Icon(icon, color: fx.muted, size: 24),
          ),
          const SizedBox(height: 14),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(body, style: t.bodyMedium!.copyWith(color: fx.muted), textAlign: TextAlign.center),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Panel(
        color: dangerColor.withValues(alpha: 0.08),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: dangerColor, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

/// In-app confirmation. Returns true only when the user picks the confirm action.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(body)),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      actions: [
        FButton.quiet('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        danger
            ? FButton.danger(confirmLabel, onPressed: () => Navigator.pop(ctx, true))
            : FButton.primary(confirmLabel, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok ?? false;
}

/// Compact segmented control.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: fx.bg,
        borderRadius: BorderRadius.circular(fx.radius),
        border: Border.all(color: fx.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Material(
                color: e.key == value ? fx.raised : Colors.transparent,
                borderRadius: BorderRadius.circular(fx.radius - 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(fx.radius - 3),
                  onTap: () => onChanged(e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: e.key == value ? fx.text : fx.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A label/description on the left and a control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.description, required this.control});
  final String title;
  final String? description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Fx.of(context).compact ? 8 : 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(description!, style: t.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 24),
          control,
        ],
      ),
    );
  }
}
