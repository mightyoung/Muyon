import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/theme.dart' as folio;
import 'package:muyon_ui/muyon_ui.dart';

/// Keep the original Folio palette frozen while the shared kit advances to v6.
Map<String, Color> folioColors() => {
  'canvas': folio.Tokens.canvas,
  'surface': folio.Tokens.surface,
  'sunken': folio.Tokens.sunken,
  'groupRow': folio.Tokens.groupRow,
  'rule': folio.Tokens.rule,
  'ruleStrong': folio.Tokens.ruleStrong,
  'ink': folio.Tokens.ink,
  'ink2': folio.Tokens.ink2,
  'ink3': folio.Tokens.ink3,
  'accent': folio.Tokens.accent,
  'accentDeep': folio.Tokens.accentDeep,
  'accentTint': folio.Tokens.accentTint,
  'nav': folio.Tokens.nav,
  'navHover': folio.Tokens.navHover,
  'navInk': folio.Tokens.navInk,
  'navInk3': folio.Tokens.navInk3,
  'amber': folio.Tokens.amber,
  'amberBg': folio.Tokens.amberBg,
  'red': folio.Tokens.red,
  'redBg': folio.Tokens.redBg,
  'green': folio.Tokens.green,
  'greenBg': folio.Tokens.greenBg,
};

const legacyFolioSnapshot = <Brightness, Map<String, Color>>{
  Brightness.light: {
    'canvas': Color(0xFFF7F8FA),
    'surface': Color(0xFFFFFFFF),
    'sunken': Color(0xFFF1F3F6),
    'groupRow': Color(0xFFF6F8FB),
    'rule': Color(0xFFE2E6EC),
    'ruleStrong': Color(0xFFC3CAD6),
    'ink': Color(0xFF111827),
    'ink2': Color(0xFF4B5565),
    'ink3': Color(0xFF636C7E),
    'accent': Color(0xFF2458D3),
    'accentDeep': Color(0xFF1B47C2),
    'accentTint': Color(0xFFE8EFFF),
    'nav': Color(0xFFEEF1F5),
    'navHover': Color(0xFFE2E8F2),
    'navInk': Color(0xFF374357),
    'navInk3': Color(0xFF5B677B),
    'amber': Color(0xFF9A5000),
    'amberBg': Color(0xFFFFF2DF),
    'red': Color(0xFFB8302A),
    'redBg': Color(0xFFFDE8E6),
    'green': Color(0xFF17693F),
    'greenBg': Color(0xFFE6F4EC),
  },
  Brightness.dark: {
    'canvas': Color(0xFF111111),
    'surface': Color(0xFF191919),
    'sunken': Color(0xFF242424),
    'groupRow': Color(0xFF202020),
    'rule': Color(0xFF333333),
    'ruleStrong': Color(0xFF484848),
    'ink': Color(0xFFEEEEEE),
    'ink2': Color(0xFFC2C2C2),
    'ink3': Color(0xFFAAAAAA),
    'accent': Color(0xFF7BA2FF),
    'accentDeep': Color(0xFF93B2FF),
    'accentTint': Color(0xFF1C2A4D),
    'nav': Color(0xFF151515),
    'navHover': Color(0xFF2E2E2E),
    'navInk': Color(0xFFD1D1D1),
    'navInk3': Color(0xFFAAAAAA),
    'amber': Color(0xFFF0A649),
    'amberBg': Color(0xFF3A2A12),
    'red': Color(0xFFFF7A70),
    'redBg': Color(0xFF3D1B1B),
    'green': Color(0xFF4CC38A),
    'greenBg': Color(0xFF14301F),
  },
};

void main() {
  tearDown(() => folio.Tokens.dark = false);

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    final ours = MuyonTokens.forBrightness(
      dark ? Brightness.dark : Brightness.light,
    );

    test('$name legacy Folio remains unchanged and old names compile', () {
      folio.Tokens.dark = dark;
      final reference = folioColors();
      expect(reference, legacyFolioSnapshot[ours.brightness]);
      expect(ours.colors.keys.take(reference.length), reference.keys);
      expect(ours.bg, ours.canvas);
      expect(ours.sf, ours.surface);
      expect(ours.sk, ours.sunken);
      expect(ours.rs, ours.ruleStrong);
      expect(ours.acc, ours.accent);
      expect(ours.deep, ours.accentDeep);
      expect(ours.tint, ours.accentTint);
      expect(ours.warnbg, ours.warnBg);
      expect(ours.onacc, ours.onAccent);
    });

    test('$name v6 theme preserves Folio typography and legacy shapes', () {
      folio.Tokens.dark = dark;
      final reference = folio.buildTheme();
      final theme = muyonTheme(
        dark ? Brightness.dark : Brightness.light,
        platform: TargetPlatform.macOS,
      );
      expect(theme.colorScheme.primary, ours.accent);
      expect(theme.colorScheme.onPrimary, ours.onAccent);
      expect(theme.colorScheme.surface, ours.surface);
      expect(theme.colorScheme.error, ours.red);
      expect(theme.scaffoldBackgroundColor, ours.canvas);
      expect(
        theme.textTheme.bodyMedium!.fontFamily,
        reference.textTheme.bodyMedium!.fontFamily,
      );
      for (final style in [
        (TextTheme t) => t.titleLarge,
        (TextTheme t) => t.titleMedium,
        (TextTheme t) => t.titleSmall,
        (TextTheme t) => t.bodyLarge,
        (TextTheme t) => t.bodyMedium,
        (TextTheme t) => t.bodySmall,
        (TextTheme t) => t.labelLarge,
        (TextTheme t) => t.labelMedium,
      ]) {
        final a = style(theme.textTheme)!;
        final b = style(reference.textTheme)!;
        expect(a.fontSize, b.fontSize);
        expect(a.fontWeight, b.fontWeight);
        expect(a.height, b.height);
        expect(
          a.color,
          b.color == folio.Tokens.ink
              ? ours.ink
              : b.color == folio.Tokens.ink2
              ? ours.ink2
              : b.color == folio.Tokens.ink3
              ? ours.ink3
              : b.color,
        );
      }
      final shape = theme.filledButtonTheme.style!.shape!.resolve({});
      final referenceShape = reference.filledButtonTheme.style!.shape!.resolve(
        {},
      );
      expect(shape, referenceShape);
      expect(theme.dialogTheme.shape, reference.dialogTheme.shape);
      expect(
        theme.snackBarTheme.actionTextColor,
        reference.snackBarTheme.actionTextColor,
      );
      expect(MuyonTokens.radius, folio.Tokens.radius);
    });
  }

  test('theme exposes tokens through the extension', () {
    expect(
      muyonTheme(Brightness.dark).extension<MuyonTokens>(),
      same(MuyonTokens.dark),
    );
    expect(
      muyonTheme(Brightness.light).extension<MuyonTokens>(),
      same(MuyonTokens.light),
    );
  });

  testWidgets('reduced motion removes page transitions', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(AppMotion.reduced(captured), isTrue);
    expect(AppMotion.duration(captured), Duration.zero);
  });
}
