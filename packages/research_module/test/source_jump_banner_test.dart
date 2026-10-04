import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:research_module/src/reader/source_jump_banner.dart';
import 'package:research_module/src/reader/source_locator.dart';

Widget _host(
  QuoteLocation? location, {
  double scale = 1,
  VoidCallback? onDismiss,
}) => MaterialApp(
  theme: muyonTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SourceJumpBanner(
      pageNumber: 7,
      location: location,
      onDismiss: onDismiss ?? () {},
    ),
  ),
);

void main() {
  testWidgets('searching state does not claim a highlight', (tester) async {
    await tester.pumpWidget(_host(null));
    expect(find.text('已回到第 7 页'), findsOneWidget);
    expect(find.text('正在查找原文…'), findsOneWidget);
    expect(find.textContaining('已精确定位'), findsNothing);
  });

  testWidgets('exact match reports a highlight', (tester) async {
    await tester.pumpWidget(
      _host(
        const ExactMatch(pageIndex: 6, rects: [Rect.fromLTWH(0, 0, 1, .1)]),
      ),
    );
    expect(find.text('已精确定位并高亮原文'), findsOneWidget);
  });

  testWidgets('ambiguous match says it cannot be located uniquely', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AmbiguousMatch(3)));
    expect(find.textContaining('无法唯一定位'), findsOneWidget);
    expect(find.textContaining('3 处'), findsOneWidget);
    expect(find.text('已回到第 7 页（页级回跳）'), findsOneWidget);
    expect(find.textContaining('已精确定位'), findsNothing);
  });

  testWidgets('page-only keeps the jump but promises no highlight', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const PageOnly('此页没有文字层')));
    expect(find.text('已回到第 7 页（页级回跳）'), findsOneWidget);
    expect(find.textContaining('未做文字高亮：此页没有文字层'), findsOneWidget);
  });

  testWidgets('replaced or missing source is not a page jump', (tester) async {
    await tester.pumpWidget(_host(const SourceUnavailable('文档已被替换，原位置不可信')));
    expect(find.text('无法回到来源'), findsOneWidget);
    expect(find.textContaining('已回到第'), findsNothing);
    expect(find.text('文档已被替换，原位置不可信'), findsOneWidget);
  });

  testWidgets('dismiss callback fires', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(const AmbiguousMatch(2), onDismiss: () => closed++),
    );
    await tester.tap(find.byTooltip('关闭提示'));
    expect(closed, 1);
  });

  for (final width in [320.0, 390.0, 430.0, 1280.0]) {
    testWidgets('long messages fit at $width and 200% text', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(const AmbiguousMatch(12), scale: 2));
      expect(tester.takeException(), isNull);
    });
  }
}
