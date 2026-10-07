import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// System UI faces keep Chinese and Latin text in the same visual rhythm.
const fontFallback = [
  'Noto Sans SC',
  'PingFang SC',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
];

/// Model numbers and codes: each platform's own monospace face.
const monoFamily = 'Consolas';
const monoFallback = [
  'Menlo',
  'SF Mono',
  'Cascadia Mono',
  'monospace',
  ...fontFallback,
];

const tabular = [FontFeature.tabularFigures()];

ThemeData muyonTheme(Brightness brightness, {TargetPlatform? platform}) {
  final tokens = MuyonTokens.forBrightness(brightness);
  final dark = brightness == Brightness.dark;
  final target = platform ?? defaultTargetPlatform;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: tokens.accent,
    onPrimary: tokens.onAccent,
    secondaryContainer: tokens.accentTint,
    onSecondaryContainer: tokens.accentDeep,
    primaryContainer: tokens.accentTint,
    onPrimaryContainer: tokens.accentDeep,
    secondary: tokens.ink2,
    onSecondary: dark ? tokens.canvas : Colors.white,
    error: tokens.red,
    onError: dark ? tokens.canvas : Colors.white,
    errorContainer: tokens.redBg,
    onErrorContainer: tokens.red,
    surface: tokens.surface,
    onSurface: tokens.ink,
    onSurfaceVariant: tokens.ink2,
    inverseSurface: tokens.ink,
    onInverseSurface: tokens.surface,
    outline: tokens.ruleStrong,
    outlineVariant: tokens.rule,
    surfaceContainerLowest: tokens.surface,
    surfaceContainerLow: tokens.canvas,
    surfaceContainer: tokens.canvas,
    surfaceContainerHigh: tokens.sunken,
    surfaceContainerHighest: tokens.sunken,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(MuyonTokens.radius),
  );
  final text = TextTheme(
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    bodyLarge: TextStyle(fontSize: 14, height: 1.5),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: tokens.ink3),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, color: tokens.ink3),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.canvas,
    // One bundled variable family covers Chinese, Latin and numerals without
    // network font loading or platform-dependent CJK substitutions.
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: [
      if (target == TargetPlatform.windows) 'Segoe UI',
      ...fontFallback,
    ],
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: NoSplash.splashFactory,
    extensions: [tokens],
  );
  final side = BorderSide(color: tokens.ruleStrong);
  return base.copyWith(
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const AccessiblePageTransitions(),
      },
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: tokens.accentTint,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? tokens.accentDeep
              : tokens.ink2,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? tokens.accentDeep
              : tokens.ink2,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.canvas,
      foregroundColor: tokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.nav,
      indicatorColor: tokens.accentTint,
      selectedIconTheme: IconThemeData(color: tokens.accentDeep),
      unselectedIconTheme: IconThemeData(color: tokens.ink2),
      selectedLabelTextStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: tokens.accentDeep,
      ),
      unselectedLabelTextStyle: TextStyle(fontSize: 12, color: tokens.ink2),
    ),
    dividerTheme: DividerThemeData(color: tokens.rule, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          MuyonTokens.minimumTarget,
          MuyonTokens.minimumTarget,
        ),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(
          MuyonTokens.minimumTarget,
          MuyonTokens.minimumTarget,
        ),
        shape: shape,
        side: side,
        foregroundColor: tokens.ink,
        backgroundColor: tokens.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        minimumSize: const Size(
          MuyonTokens.minimumTarget,
          MuyonTokens.minimumTarget,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: tokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MuyonTokens.radius),
        borderSide: side,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MuyonTokens.radius),
        borderSide: side,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MuyonTokens.radius),
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
      labelStyle: TextStyle(color: tokens.ink2),
      hintStyle: TextStyle(color: tokens.ink3),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MuyonTokens.dialogRadius),
      ),
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.ink,
      contentTextStyle: TextStyle(color: tokens.surface, fontSize: 13),
      actionTextColor: dark ? const Color(0xFF1B47C2) : tokens.accentTint,
    ),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
  );
}
