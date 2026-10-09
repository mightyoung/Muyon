import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

/// AIUI-2 goldens, same convention as component_goldens_test (UI-1a): light
/// and dark, 390/100% and 320/200%, macOS only. One image per library
/// component with all five states stacked; one image for the states the
/// UI-1a components gained.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);

  const item = ConfirmItem(
    kind: ConfirmationKind.write,
    what: '新增询价单',
    who: '当前项目',
    payload: '完整内容',
    digest: 'd',
    consequence: '写入本地',
  );

  Widget states(Widget Function(UiComponentState) build) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final state in libraryStates)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: build(state),
        ),
    ],
  );

  final samples = <String, Widget Function()>{
    for (final name in libraryGalleryNames)
      'lib_${name.toLowerCase()}': () =>
          states((state) => librarySample(name, state)),
    'lib_ui1a_states': () => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final state in libraryStates.skip(1))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatusBadge(status: BusinessStatus.pending, uiState: state),
                ObjectChip(label: '项目', onPressed: () {}, uiState: state),
                ScopeChip(label: '项目', uiState: state),
                WarnBanner(uiState: state),
                ConfirmCard(item: item, onDecision: (_) {}, uiState: state),
                BatchConfirmCard(items: const [item], uiState: state),
              ],
            ),
          ),
      ],
    ),
  };

  for (final brightness in Brightness.values) {
    for (final config in [
      (width: 390.0, scale: 1.0, suffix: ''),
      (width: 320.0, scale: 2.0, suffix: '_320_200'),
    ]) {
      for (final entry in samples.entries) {
        testWidgets('library ${brightness.name} ${entry.key}${config.suffix}', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(config.width, 2400));
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: muyonTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(config.scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: RepaintBoundary(
                      key: const ValueKey('golden'),
                      child: ColoredBox(
                        color: MuyonTokens.forBrightness(brightness).canvas,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: entry.value(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('golden')),
              matchesGoldenFile(
                'goldens/${brightness.name}_${entry.key}${config.suffix}.png',
              ),
            );
          } finally {
            await tester.binding.setSurfaceSize(null);
          }
        }, skip: !Platform.isMacOS);
      }
    }
  }
}
