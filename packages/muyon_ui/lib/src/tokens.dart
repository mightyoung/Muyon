import 'package:flutter/material.dart';

/// v6 semantic colours, see docs/design/muyon-design-system.md.
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
    Color? warn,
    Color? warnBg,
    Color? onAccent,
  }) : _warn = warn,
       _warnBg = warnBg,
       _onAccent = onAccent;

  static const light = MuyonTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFFCFCFC),
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
    warn: Color(0xFF8A5A00),
    warnBg: Color(0xFFFFF1D6),
    onAccent: Color(0xFFFFFFFF),
  );

  static const dark = MuyonTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0A0A0A),
    surface: Color(0xFF141414),
    sunken: Color(0xFF1F1F1F),
    groupRow: Color(0xFF202020),
    rule: Color(0xFF2B2B2B),
    ruleStrong: Color(0xFF3F3F3F),
    ink: Color(0xFFF2F2F2),
    ink2: Color(0xFFC4C4C4),
    ink3: Color(0xFF9A9A9A),
    accent: Color(0xFFF0A649),
    accentDeep: Color(0xFFF5C27A),
    accentTint: Color(0xFF3A2A12),
    nav: Color(0xFF151515),
    navHover: Color(0xFF2E2E2E),
    navInk: Color(0xFFD1D1D1),
    navInk3: Color(0xFFAAAAAA),
    amber: Color(0xFFF0A649),
    amberBg: Color(0xFF3A2A12),
    red: Color(0xFFFF7A70),
    redBg: Color(0xFF3A1F1D),
    green: Color(0xFF4CC38A),
    greenBg: Color(0xFF17301F),
    warn: Color(0xFFE8C547),
    warnBg: Color(0xFF2E2A10),
    onAccent: Color(0xFF0A0A0A),
  );

  static const radius = 8.0;
  static const dialogRadius = 12.0;
  static const inputRadius = 12.0;
  static const optionRadius = 16.0;
  static const cardRadius = 20.0;
  static const groupRadius = 24.0;
  static const composerRadius = 28.0;
  static const pillRadius = 999.0;
  static const minimumTarget = 48.0;
  static const iconSize = 24.0; // Fixed glyph size; target grows independently.
  static const navigationIconSize = 28.0;
  static const tableHeaderHeight = 42.0; // Tabular row alignment exception.
  static const tableRowHeight = 52.0; // Tabular row alignment exception.
  static const switchWidth = 46.0; // Visual thumb geometry, not tap target.
  static const switchHeight = 28.0;
  static const switchThumbSize = 22.0;
  static const masterDetailBreakpoint = 1000.0;

  /// Spacing scale in logical pixels; use these instead of ad-hoc numbers.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0; // Legacy extra retained for source compatibility.
  static const space20 = 20.0;
  static const spacing = [space1, space2, space3, space4, space20, space5];

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

  /// Good outcomes only; the primary colour indicates selection and actions.
  final Color green;
  final Color greenBg;

  final Color? _warn, _warnBg, _onAccent;
  Color get warn => _warn ?? amber;
  Color get warnBg => _warnBg ?? amberBg;
  Color get onAccent =>
      _onAccent ?? (brightness == Brightness.dark ? canvas : Colors.white);

  // v6 names; existing field and constructor names remain source-compatible.
  Color get bg => canvas;
  Color get sf => surface;
  Color get sk => sunken;
  Color get rs => ruleStrong;
  Color get acc => accent;
  Color get onacc => onAccent;
  Color get tint => accentTint;
  Color get deep => accentDeep;
  Color get warnbg => warnBg;
  Color get redbg => redBg;
  Color get greenbg => greenBg;

  /// Every colour keyed by its public name (used by tests).
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
    'warn': warn,
    'warnBg': warnBg,
    'onAccent': onAccent,
  };

  @override
  MuyonTokens copyWith({Brightness? brightness}) =>
      brightness == null ? this : forBrightness(brightness);

  @override
  MuyonTokens lerp(ThemeExtension<MuyonTokens>? other, double t) =>
      t < 0.5 || other is! MuyonTokens ? this : other;
}
