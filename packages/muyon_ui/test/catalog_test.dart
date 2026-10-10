import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);
  test('debug route exposes only the standalone catalog', () {
    expect(muyonDebugRoutes().keys, ['/debug/components']);
    expect(componentNames, hasLength(15));
    expect(componentNames.toSet(), hasLength(15));
    for (final status in PageState.values) {
      expect(status.label, matches(RegExp(r'[\u4e00-\u9fff]')));
    }
    for (final status in BatchState.values) {
      expect(status.label, matches(RegExp(r'[\u4e00-\u9fff]')));
    }
    for (final status in ConfirmationKind.values) {
      expect(status.label, matches(RegExp(r'[\u4e00-\u9fff]')));
    }
    for (final status in ConfirmationChoice.values) {
      expect(status.label, matches(RegExp(r'[\u4e00-\u9fff]')));
    }
  });
  for (final config in [
    for (final brightness in Brightness.values)
      for (final width in [320.0, 390.0, 1280.0])
        (brightness: brightness, width: width),
  ]) {
    final width = config.width;
    final brightness = config.brightness;
    testWidgets(
      'catalog exposes all 15 components at $width/200% $brightness',
      (tester) async {
        await loadUiTestFont();
        await tester.binding.setSurfaceSize(Size(width, 1000));
        try {
          for (final name in componentNames) {
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey(name),
                theme: muyonTheme(brightness),
                home: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: ComponentCatalog(
                    initialComponent: name,
                    initialBrightness: brightness,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('组件目录'), findsOneWidget);
            expect(find.text(name), findsWidgets);
            expect(tester.takeException(), isNull, reason: name);
          }
        } finally {
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  }
  testWidgets('catalog theme toggle uses v6 dark amber', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: const ComponentCatalog(),
      ),
    );
    await tester.tap(find.byTooltip('切换深色'));
    await tester.pump();
    final context = tester.element(find.text('组件目录'));
    expect(MuyonTokens.of(context).accent, const Color(0xfff0a649));
    await tester.scrollUntilVisible(
      find.text(BusinessStatus.externalContent.label),
      300,
    );
    expect(find.text(BusinessStatus.externalContent.label), findsOneWidget);
  });
}
