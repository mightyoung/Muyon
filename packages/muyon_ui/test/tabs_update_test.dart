import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    List<String> labels, {
    int initial = 0,
  }) => mount(
    tester,
    MuyonTabs(
      key: const ValueKey('updating-tabs'),
      labels: labels,
      initial: initial,
      children: [for (final label in labels) Text('$label 内容')],
    ),
    width: 800,
    scale: 1,
  );

  testWidgets('shrinking tabs clamps the selected position to a valid panel', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, ['甲', '乙', '丙']);
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump();
    expect(find.text('丙 内容'), findsOneWidget);
    await show(tester, ['甲', '乙']);
    expect(tester.takeException(), isNull);
    expect(find.text('乙 内容'), findsOneWidget);
    expect(find.text('丙 内容'), findsNothing);
    final selected = tester.widget<Semantics>(
      find.ancestor(
        of: find.byKey(const ValueKey('tab-1')),
        matching: find.byType(Semantics),
      ).first,
    );
    expect(selected.properties.selected, isTrue);
    await show(tester, ['甲']);
    expect(tester.takeException(), isNull);
    expect(find.text('甲 内容'), findsOneWidget);
  });

  testWidgets('empty tabs can mount and then receive panels', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, [], initial: 9);
    expect(tester.takeException(), isNull);
    expect(find.byType(InkWell), findsNothing);
    await show(tester, ['甲', '乙'], initial: 1);
    expect(tester.takeException(), isNull);
    expect(find.text('甲 内容'), findsOneWidget);
  });

  testWidgets('removing every panel and restoring tabs resets to first panel', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, ['甲', '乙']);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    await show(tester, []);
    expect(tester.takeException(), isNull);
    expect(find.text('乙 内容'), findsNothing);
    await show(tester, ['新甲']);
    expect(tester.takeException(), isNull);
    expect(find.text('新甲 内容'), findsOneWidget);
  });

  testWidgets('reordering retains the position and shows its matching content', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, ['甲', '乙', '丙']);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    await show(tester, ['丙', '甲', '乙']);
    expect(tester.takeException(), isNull);
    expect(find.text('甲 内容'), findsOneWidget);
    expect(find.text('乙 内容'), findsNothing);
  });

  testWidgets('initial is mount-only and does not overwrite local selection', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, ['甲', '乙', '丙'], initial: 1);
    expect(find.text('乙 内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump();
    await show(tester, ['甲', '乙', '丙'], initial: 0);
    expect(tester.takeException(), isNull);
    expect(find.text('丙 内容'), findsOneWidget);
  });
}
