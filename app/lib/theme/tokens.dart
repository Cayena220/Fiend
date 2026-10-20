import 'package:flutter/painting.dart';

/// Mirrors design/tokens.json. Change values there first, then here.
class Depth {
  const Depth({
    required this.label,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
  });

  final String label;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
}

const Map<String, Depth> depths = {
  'abyss': Depth(
    label: 'Abyss',
    bg: Color(0xFF0B0A10),
    surface: Color(0xFF13111A),
    surface2: Color(0xFF1B1824),
    raised: Color(0xFF24202F),
    border: Color(0xFF2E2A3B),
    text: Color(0xFFEDEAF4),
    muted: Color(0xFF9690A8),
    faint: Color(0xFF5F5A70),
  ),
  'midnight': Depth(
    label: 'Midnight',
    bg: Color(0xFF080C14),
    surface: Color(0xFF0F1520),
    surface2: Color(0xFF161E2C),
    raised: Color(0xFF1E2838),
    border: Color(0xFF2A3547),
    text: Color(0xFFE8EDF5),
    muted: Color(0xFF8A97AB),
    faint: Color(0xFF566175),
  ),
  'slate': Depth(
    label: 'Slate',
    bg: Color(0xFF121316),
    surface: Color(0xFF1A1B1F),
    surface2: Color(0xFF222328),
    raised: Color(0xFF2B2C32),
    border: Color(0xFF36373E),
    text: Color(0xFFECECEE),
    muted: Color(0xFF9A9AA3),
    faint: Color(0xFF63636B),
  ),
};

const Map<String, Color> accents = {
  'hellfire': Color(0xFFFF3B4E),
  'ember': Color(0xFFFF7A2F),
  'toxic': Color(0xFF7CE85A),
  'spectral': Color(0xFFA77BFF),
  'ice': Color(0xFF4CC9F0),
};

const Map<String, String> accentLabels = {
  'hellfire': 'Hellfire',
  'ember': 'Ember',
  'toxic': 'Toxic',
  'spectral': 'Spectral',
  'ice': 'Ice',
};

const Color safeColor = Color(0xFF3DD68C);
const Color warnColor = Color(0xFFF5B83D);
const Color dangerColor = Color(0xFFFF5A5F);
const Color infoColor = Color(0xFF5AA9FF);

const String uiFont = 'Segoe UI Variable Text';
const String displayFont = 'Segoe UI Variable Display';
const String monoFont = 'Cascadia Mono';
const List<String> fontFallback = ['Segoe UI', 'Arial'];
const List<String> monoFallback = ['Consolas', 'Courier New'];

Color? parseHex(String input) {
  var hex = input.trim().replaceFirst('#', '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

String toHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
