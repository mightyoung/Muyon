import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/theme.dart' as folio;
import 'package:muyon_ui/muyon_ui.dart';

/// Folio's original [folio.Tokens] is the reference; these tests stop the two
/// copies from drifting apart.
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

void main() {
  tearDown(() => folio.Tokens.dark = false);

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    final ours = MuyonTokens.forBrightness(
      dark ? Brightness.dark : Brightness.light,
    );

    test('$name colours equal Folio Tokens', () {
      folio.Tokens.dark = dark;
      final reference = folioColors();
      expect(ours.colors.keys, reference.keys);
      for (final key in reference.keys) {
        expect(ours.colors[key], reference[key], reason: key);
      }
    });

    test('$name theme matches Folio buildTheme()', () {
      folio.Tokens.dark = dark;
      final reference = folio.buildTheme();
      final theme = muyonTheme(
        dark ? Brightness.dark : Brightness.light,
        platform: TargetPlatform.macOS,
      );
      expect(theme.colorScheme, reference.colorScheme);
      expect(theme.scaffoldBackgroundColor, reference.scaffoldBackgroundColor);
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
        expect(a.color, b.color);
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
