import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child) =>
      mount(tester, child, width: 800, scale: 1);

  testWidgets('Choice identifies duplicate labels by stable IDs', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <Set<String>>[];
    Choice choice(List<String> ids, Set<String> selected) => Choice(
      key: const ValueKey('ids'),
      label: '供应商',
      options: const ['同名', '同名'],
      optionIds: ids,
      selectedIds: selected,
      multiple: true,
      onChangedIds: changes.add,
      selected: const {'legacy'},
      onChanged: (_) => fail('ID mode must not call the legacy label callback'),
    );
    await show(tester, choice(['a', 'b'], {'a'}));
    expect(find.byKey(const ValueKey('choice-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-b')));
    await tester.pump();
    expect(changes, [
      {'a', 'b'},
    ]);
    await show(tester, choice(['b', 'a'], {'a'}));
    await tester.tap(find.byKey(const ValueKey('choice-a')));
    await tester.pump();
    expect(changes.last, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Choice ID mode disables custom entry and maps reading to labels',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final choice = Choice(
        label: '选项',
        options: const ['甲'],
        optionIds: const ['internal-a'],
        selectedIds: const {'internal-a'},
        allowCustom: true,
        onChangedIds: (_) {},
      );
      await show(tester, choice);
      expect(find.byKey(const ValueKey('choice-custom')), findsNothing);
      expect(choice.textEquivalent, contains('已选 甲'));
      expect(choice.textEquivalent, isNot(contains('internal-a')));
    },
  );

  testWidgets('controlled Tabs request change and wait for host selection', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <int>[];
    MuyonTabs tabs(int selected) => MuyonTabs(
      key: const ValueKey('controlled-tabs'),
      labels: const ['甲', '乙'],
      initial: 1,
      selectedIndex: selected,
      onChanged: changes.add,
      children: const [Text('甲内容'), Text('乙内容')],
    );
    await show(tester, tabs(0));
    expect(find.text('甲内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    expect(changes, [1]);
    expect(find.text('甲内容'), findsOneWidget);
    expect(find.text('乙内容'), findsNothing);
    await show(tester, tabs(1));
    expect(find.text('乙内容'), findsOneWidget);
  });

  testWidgets(
    'controlled Disclosure requests change and waits for host state',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = <bool>[];
      Disclosure disclosure(bool expanded) => Disclosure(
        key: const ValueKey('controlled-disclosure'),
        title: '详情',
        expanded: expanded,
        onChanged: changes.add,
        child: const Text('详情内容'),
      );
      await show(tester, disclosure(true));
      expect(find.text('详情内容'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('disclosure-toggle')));
      await tester.pump();
      expect(changes, [false]);
      expect(find.text('详情内容'), findsOneWidget);
      await show(tester, disclosure(false));
      expect(find.text('详情内容'), findsNothing);
    },
  );

  testWidgets('controlled layouts without callbacks stay read only', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(
      tester,
      MuyonTabs(
        labels: ['甲', '乙'],
        selectedIndex: 0,
        children: [Text('甲内容'), Text('乙内容')],
      ),
    );
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('tab-1'))).onTap,
      isNull,
    );
    await show(
      tester,
      const Disclosure(title: '详情', expanded: true, child: Text('详情内容')),
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('disclosure-toggle')))
          .onTap,
      isNull,
    );
    expect(find.text('详情内容'), findsOneWidget);
  });
}
