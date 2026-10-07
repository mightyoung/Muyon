import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

const destinations = ['AI 助手', '业务插件', '工作台', '数据交换', '设置'];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);
  for (final config in [
    for (final brightness in Brightness.values)
      for (final width in [320.0, 390.0, 1280.0])
        (brightness: brightness, width: width),
  ]) {
    final width = config.width;
    final brightness = config.brightness;
    for (final rail in [false, true]) {
      testWidgets(
        '${rail ? 'rail' : 'bottom'} five semantic 48px actions at $width/200% $brightness',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            var selected = -1;
            await mount(
              tester,
              rail
                  ? IconRail(selected: 2, onChanged: (v) => selected = v)
                  : BottomIconBar(selected: 2, onChanged: (v) => selected = v),
              width: width,
              brightness: brightness,
            );
            for (var i = 0; i < 5; i++) {
              final item = find.bySemanticsLabel(destinations[i]);
              expect(item, findsOneWidget);
              minimum(tester, item);
              expect(
                tester.getSemantics(item),
                matchesSemantics(
                  label: destinations[i],
                  isButton: true,
                  isEnabled: true,
                  hasEnabledState: true,
                  hasSelectedState: true,
                  isSelected: i == 2,
                  hasTapAction: true,
                ),
              );
              expect(find.text(destinations[i]), findsNothing);
              await tester.tap(item);
              await tester.pump();
              expect(selected, i);
            }
            expect(find.byIcon(Icons.space_dashboard), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
            await tester.binding.setSurfaceSize(null);
          }
        },
      );
    }
    for (final state in [
      PageState.loading,
      PageState.empty,
      PageState.filteredEmpty,
      PageState.error,
    ]) {
      testWidgets('PageScaffold $state at $width/200% $brightness', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var calls = 0;
        await mount(
          tester,
          PageScaffold(
            title: '需要完整显示的页面标题',
            description: '说明文字随字号增高',
            state: state,
            onAction: () => calls++,
          ),
          width: width,
          brightness: brightness,
        );
        final copy = switch (state) {
          PageState.loading => '进行中',
          PageState.empty => '暂无内容',
          PageState.filteredEmpty => '没有符合筛选条件的内容',
          _ => '加载失败',
        };
        expect(find.text(copy), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (state != PageState.loading) {
          final button = find.byType(TextButton);
          minimum(tester, button);
          await tester.tap(button);
          expect(calls, 1);
        }
      });
    }
    testWidgets(
      'MasterDetail proportional or separate narrow page at $width/200% $brightness',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var closed = false;
        await mount(
          tester,
          MasterDetail(
            master: const Text('主列表'),
            detail: const Text('需要完整显示的长详情内容'),
            onClose: () => closed = true,
          ),
          width: width,
          brightness: brightness,
        );
        expect(find.text('主列表'), findsOneWidget);
        if (width < 1000) {
          expect(find.text('需要完整显示的长详情内容'), findsNothing);
          await tester.tap(find.text('打开详情'));
          await tester.pumpAndSettle();
        }
        expect(find.text('需要完整显示的长详情内容'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭详情'));
        await tester.pumpAndSettle();
        expect(closed, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('keyboard activates the navigation target', (tester) async {
    var chosen = -1;
    await mount(
      tester,
      BottomIconBar(selected: 0, onChanged: (v) => chosen = v),
      scale: 1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chosen, 0);
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('page states announce Chinese headings and recovery actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final state in [
        PageState.loading,
        PageState.empty,
        PageState.filteredEmpty,
        PageState.error,
      ]) {
        await mount(
          tester,
          PageScaffold(title: '语义页面', state: state, onAction: () {}),
        );
        expect(
          tester.getSemantics(find.text('语义页面')),
          matchesSemantics(label: '语义页面', isHeader: true),
        );
        expect(find.bySemanticsLabel(RegExp(state.label)), findsWidgets);
      }
    } finally {
      semantics.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
  testWidgets('narrow detail exposes accessible open and close targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(
        tester,
        const MasterDetail(master: Text('对象列表'), detail: Text('对象详情')),
      );
      final open = find.bySemanticsLabel('打开详情');
      expect(open, findsOneWidget);
      minimum(tester, open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final close = find.bySemanticsLabel('关闭详情');
      expect(close, findsOneWidget);
      minimum(tester, close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('对象详情'), findsNothing);
    } finally {
      semantics.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
