import 'package:flutter/material.dart';

/// Folio colours for one brightness, see docs/design/DESIGN.md.
///
/// Instances are immutable; read the active one with [MuyonTokens.of] so a
/// brightness change rebuilds only what depends on the theme.
@immutable
class MuyonTokens extends ThemeExtension<MuyonTokens> {
  const MuyonTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.sunken,
    required this.groupRow,
    required this.rule,
    required this.ruleStrong,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accentDeep,
    required this.accentTint,
    required this.nav,
    required this.navHover,
    required this.navInk,
    required this.navInk3,
    required this.amber,
    required this.amberBg,
    required this.red,
    required this.redBg,
    required this.green,
    required this.greenBg,
  });

  static const light = MuyonTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFF1F3F6),
    groupRow: Color(0xFFF6F8FB),
    rule: Color(0xFFE2E6EC),
    ruleStrong: Color(0xFFC3CAD6),
    ink: Color(0xFF111827),
    ink2: Color(0xFF4B5565),
    ink3: Color(0xFF636C7E),
    accent: Color(0xFF2458D3),
    accentDeep: Color(0xFF1B47C2),
    accentTint: Color(0xFFE8EFFF),
    nav: Color(0xFFEEF1F5),
    navHover: Color(0xFFE2E8F2),
    navInk: Color(0xFF374357),
    navInk3: Color(0xFF5B677B),
    amber: Color(0xFF9A5000),
    amberBg: Color(0xFFFFF2DF),
    red: Color(0xFFB8302A),
    redBg: Color(0xFFFDE8E6),
    green: Color(0xFF17693F),
    greenBg: Color(0xFFE6F4EC),
  );

  static const dark = MuyonTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF111111),
    surface: Color(0xFF191919),
    sunken: Color(0xFF242424),
    groupRow: Color(0xFF202020),
    rule: Color(0xFF333333),
    ruleStrong: Color(0xFF484848),
    ink: Color(0xFFEEEEEE),
    ink2: Color(0xFFC2C2C2),
    ink3: Color(0xFFAAAAAA),
    accent: Color(0xFF7BA2FF),
    accentDeep: Color(0xFF93B2FF),
    accentTint: Color(0xFF1C2A4D),
    nav: Color(0xFF151515),
    navHover: Color(0xFF2E2E2E),
    navInk: Color(0xFFD1D1D1),
    navInk3: Color(0xFFAAAAAA),
    amber: Color(0xFFF0A649),
    amberBg: Color(0xFF3A2A12),
    red: Color(0xFFFF7A70),
    redBg: Color(0xFF3D1B1B),
    green: Color(0xFF4CC38A),
    greenBg: Color(0xFF14301F),
  );

  static const radius = 8.0;
  static const dialogRadius = 12.0;

  /// Spacing scale in logical pixels; use these instead of ad-hoc numbers.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;

  static MuyonTokens forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Tokens of the nearest [Theme]; falls back to its brightness.
  static MuyonTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MuyonTokens>() ?? forBrightness(theme.brightness);
  }

  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color sunken;
  final Color groupRow;
  final Color rule;
  final Color ruleStrong;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color accent;
  final Color accentDeep;
  final Color accentTint;
  final Color nav;
  final Color navHover;
  final Color navInk;
  final Color navInk3;
  final Color amber;
  final Color amberBg;
  final Color red;
  final Color redBg;

  /// Good outcomes only; blue stays for what can be clicked or is selected.
  final Color green;
  final Color greenBg;

  /// Every colour in declaration order, keyed by name (used by tests).
  Map<String, Color> get colors => {
    'canvas': canvas,
    'surface': surface,
    'sunken': sunken,
    'groupRow': groupRow,
    'rule': rule,
    'ruleStrong': ruleStrong,
    'ink': ink,
    'ink2': ink2,
    'ink3': ink3,
    'accent': accent,
    'accentDeep': accentDeep,
    'accentTint': accentTint,
    'nav': nav,
    'navHover': navHover,
    'navInk': navInk,
    'navInk3': navInk3,
    'amber': amber,
    'amberBg': amberBg,
    'red': red,
    'redBg': redBg,
    'green': green,
    'greenBg': greenBg,
  };

  @override
  MuyonTokens copyWith({Brightness? brightness}) =>
      brightness == null ? this : forBrightness(brightness);

  @override
  MuyonTokens lerp(ThemeExtension<MuyonTokens>? other, double t) =>
      t < 0.5 || other is! MuyonTokens ? this : other;
}
