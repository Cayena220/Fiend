import 'package:flutter/material.dart';

import '../core/models.dart';
import 'tokens.dart';

/// Fiend's design values, reachable anywhere with `Fx.of(context)`.
class Fx extends ThemeExtension<Fx> {
  const Fx({
    required this.depth,
    required this.accent,
    required this.radius,
    required this.glow,
    required this.reduceMotion,
    required this.compact,
  });

  final Depth depth;
  final Color accent;
  final double radius;
  final bool glow;
  final bool reduceMotion;
  final bool compact;

  static Fx of(BuildContext context) => Theme.of(context).extension<Fx>()!;

  Color get bg => depth.bg;
  Color get surface => depth.surface;
  Color get surface2 => depth.surface2;
  Color get raised => depth.raised;
  Color get border => depth.border;
  Color get text => depth.text;
  Color get muted => depth.muted;
  Color get faint => depth.faint;
  Color get onAccent =>
      accent.computeLuminance() > 0.4 ? const Color(0xFF0B0A10) : Colors.white;
  Color get accentSoft => accent.withValues(alpha: 0.14);

  double get gap => compact ? 12 : 16;
  double get pad => compact ? 16 : 22;
  Duration get motion =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

  List<BoxShadow> glowOf(Color c, {double strength = 1}) => glow
      ? [
          BoxShadow(
            color: c.withValues(alpha: 0.35 * strength),
            blurRadius: 24 * strength,
            spreadRadius: -6,
          ),
        ]
      : const [];

  Color severity(String s) => switch (s) {
        'high' => dangerColor,
        'medium' => warnColor,
        'low' => infoColor,
        _ => safeColor,
      };

  @override
  Fx copyWith({
    Depth? depth,
    Color? accent,
    double? radius,
    bool? glow,
    bool? reduceMotion,
    bool? compact,
  }) =>
      Fx(
        depth: depth ?? this.depth,
        accent: accent ?? this.accent,
        radius: radius ?? this.radius,
        glow: glow ?? this.glow,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        compact: compact ?? this.compact,
      );

  @override
  Fx lerp(ThemeExtension<Fx>? other, double t) {
    if (other is! Fx) return this;
    return Fx(
      depth: t < 0.5 ? depth : other.depth,
      accent: Color.lerp(accent, other.accent, t)!,
      radius: radius + (other.radius - radius) * t,
      glow: t < 0.5 ? glow : other.glow,
      reduceMotion: t < 0.5 ? reduceMotion : other.reduceMotion,
      compact: t < 0.5 ? compact : other.compact,
    );
  }
}

Color accentFor(Settings s) {
  if (s.accent == 'custom') {
    return parseHex(s.customAccent) ?? accents['hellfire']!;
  }
  return accents[s.accent] ?? accents['hellfire']!;
}

ThemeData buildTheme(Settings s) {
  final d = depths[s.depth] ?? depths['abyss']!;
  final accent = accentFor(s);
  final fx = Fx(
    depth: d,
    accent: accent,
    radius: s.radius.clamp(2, 20).toDouble(),
    glow: s.glow,
    reduceMotion: s.reduceMotion,
    compact: s.density == 'compact',
  );
  final r = BorderRadius.circular(fx.radius);

  TextStyle t(double size, FontWeight w, Color c,
          {String family = uiFont, double? spacing, double? height}) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: spacing,
        height: height,
      );

  final text = TextTheme(
    displayLarge: t(44, FontWeight.w700, d.text, family: displayFont, spacing: -1, height: 1.05),
    displayMedium: t(34, FontWeight.w700, d.text, family: displayFont, spacing: -0.6, height: 1.1),
    headlineSmall: t(24, FontWeight.w600, d.text, family: displayFont, spacing: -0.3),
    titleLarge: t(18, FontWeight.w600, d.text, family: displayFont),
    titleMedium: t(15, FontWeight.w600, d.text),
    titleSmall: t(13, FontWeight.w600, d.text),
    bodyLarge: t(15, FontWeight.w400, d.text, height: 1.45),
    bodyMedium: t(13.5, FontWeight.w400, d.text, height: 1.45),
    bodySmall: t(12, FontWeight.w400, d.muted, height: 1.4),
    labelLarge: t(13, FontWeight.w600, d.text),
    labelMedium: t(11.5, FontWeight.w600, d.muted, spacing: 0.6),
    labelSmall: t(10.5, FontWeight.w600, d.muted, spacing: 0.9),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: uiFont,
    fontFamilyFallback: fontFallback,
    scaffoldBackgroundColor: d.bg,
    canvasColor: d.surface,
    colorScheme: ColorScheme.dark(
      primary: accent,
      onPrimary: fx.onAccent,
      secondary: accent,
      onSecondary: fx.onAccent,
      surface: d.surface,
      onSurface: d.text,
      surfaceContainerHighest: d.raised,
      surfaceContainerHigh: d.surface2,
      surfaceContainer: d.surface2,
      outline: d.border,
      outlineVariant: d.border,
      error: dangerColor,
    ),
    textTheme: text,
    dividerColor: d.border,
    dividerTheme: DividerThemeData(color: d.border, thickness: 1, space: 1),
    visualDensity: fx.compact ? VisualDensity.compact : VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    hoverColor: d.text.withValues(alpha: 0.04),
    focusColor: accent.withValues(alpha: 0.18),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: d.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: d.border),
      ),
      textStyle: t(12, FontWeight.w500, d.text),
      waitDuration: const Duration(milliseconds: 400),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(d.faint.withValues(alpha: 0.6)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(fx.onAccent),
      side: BorderSide(color: d.faint, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? fx.onAccent : d.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? accent : d.surface2),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? accent : d.border),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: d.border,
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.16),
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: d.border,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: d.bg,
      hintStyle: t(13, FontWeight.w400, d.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: d.border)),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: d.border)),
      focusedBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: accent, width: 1.4)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: d.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(fx.radius + 4),
        side: BorderSide(color: d.border),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: d.raised,
      contentTextStyle: t(13, FontWeight.w500, d.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: d.border),
      ),
      width: 460,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: d.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: d.border)),
      textStyle: t(13, FontWeight.w500, d.text),
    ),
    extensions: [fx],
  );
}
