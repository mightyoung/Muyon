import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);
  test('every business status has its Chinese vocabulary', () {
    for (final status in BusinessStatus.values) {
      expect(
        status.label,
        matches(RegExp(r'[\u4e00-\u9fff]')),
        reason: status.name,
      );
    }
    expect(BusinessStatus.pending.label, '待确认');
    expect(BusinessStatus.expired.label, '授权已过期，需重新确认');
    expect(BusinessStatus.externalContent.label, '因外部内容需逐次确认');
  });
  for (final config in [
    for (final brightness in Brightness.values)
      for (final width in [320.0, 390.0, 1280.0])
        (brightness: brightness, width: width),
  ]) {
    final width = config.width;
    final brightness = config.brightness;
    testWidgets('all primitives grow with 200% text at $width $brightness', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var pressed = 0;
        final cases = <({Widget widget, String label, bool interactive})>[
          for (final status in BusinessStatus.values)
            (
              widget: StatusBadge(status: status),
              label: status.label,
              interactive: false,
            ),
          (
            widget: ObjectChip(
              label: '长对象名称需要完整显示',
              onPressed: () => pressed++,
            ),
            label: '长对象名称需要完整显示',
            interactive: true,
          ),
          (
            widget: ObjectChip(
              label: '原对象',
              missing: true,
              onPressed: () => pressed++,
            ),
            label: '原对象，已不存在',
            interactive: false,
          ),
          (
            widget: ScopeChip(label: '选中 2 个对象', objects: const ['论文一', '报价二']),
            label: '范围：选中 2 个对象，展开',
            interactive: true,
          ),
          (
            widget: SegmentedPill(
              labels: const ['全部内容', '仅当前项目', '已经归档的内容'],
              selected: 0,
              onChanged: (_) => pressed++,
            ),
            label: '仅当前项目',
            interactive: true,
          ),
          (
            widget: RoundIconButton(
              label: '创建一个对象',
              icon: Icons.add,
              onPressed: () => pressed++,
            ),
            label: '创建一个对象',
            interactive: true,
          ),
          (
            widget: TitlePill(
              label: '需要完整显示的长标题胶囊',
              onPressed: () => pressed++,
            ),
            label: '需要完整显示的长标题胶囊',
            interactive: true,
          ),
        ];
        for (final c in cases) {
          await mount(tester, c.widget, width: width, brightness: brightness);
          final target = find.bySemanticsLabel(c.label);
          expect(target, findsOneWidget, reason: c.label);
          expect(tester.takeException(), isNull, reason: c.label);
          if (c.interactive) {
            minimum(tester, target);
            if (c.widget is RoundIconButton) {
              final rect = tester.getRect(target);
              expect(
                rect.width,
                rect.height,
                reason: "round icon target must remain square",
              );
            }
            final before = pressed;
            await tester.tap(target);
            await tester.pump();
            if (c.widget is! ScopeChip) expect(pressed, before + 1);
          }
        }
      } finally {
        semantics.dispose();
      }
    });
  }
  testWidgets('missing objects cannot invoke old callbacks', (tester) async {
    var called = false;
    await mount(
      tester,
      ObjectChip(label: '已删除报价', missing: true, onPressed: () => called = true),
    );
    expect(find.byIcon(Icons.link_off), findsOneWidget);
    await tester.tap(find.text('已删除报价，已不存在'));
    expect(called, isFalse);
    expect(find.byIcon(Icons.link_off), findsOneWidget);
  });
  testWidgets('scope disclosure exposes only supplied objects and collapses', (
    tester,
  ) async {
    await mount(
      tester,
      const ScopeChip(label: '项目', objects: ['可见对象一', '可见对象二']),
    );
    expect(find.text('可见对象一'), findsNothing);
    await tester.tap(find.text('范围：项目'));
    await tester.pump();
    expect(find.text('可见对象一'), findsOneWidget);
    expect(find.text('可见对象二'), findsOneWidget);
    expect(find.text('只读范围内对象，不顺着关系读取'), findsOneWidget);
    await tester.tap(find.text('范围：项目'));
    await tester.pump();
    expect(find.text('可见对象一'), findsNothing);
  });
  testWidgets('filled icon keyboard focus has contrasting ink ring', (
    tester,
  ) async {
    await mount(
      tester,
      RoundIconButton(
        label: '新建',
        icon: Icons.add,
        filled: true,
        onPressed: () {},
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(RoundIconButton),
            matching: find.byType(Material),
          )
          .first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side.width, 2);
    expect(shape.side.color, MuyonTokens.light.ink);
    await tester.binding.setSurfaceSize(null);
  });
}
