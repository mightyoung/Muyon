import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child) =>
      mount(tester, child, width: 800, scale: 1);

  Choice choice({
    bool allowCustom = true,
    required ValueChanged<Set<String>> onChanged,
  }) => Choice(
    label: '选项',
    options: const ['甲'],
    allowCustom: allowCustom,
    multiple: true,
    selected: const {},
    onChanged: onChanged,
  );

  testWidgets('custom_entry_is_reported_through_onChanged', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <Set<String>>[];
    await show(tester, choice(onChanged: changes.add));
    await tester.enterText(
      find.byKey(const ValueKey('choice-custom')),
      '  乙  ',
    );
    await tester.tap(find.byKey(const ValueKey('choice-custom-add')));
    await tester.pump();
    expect(changes.last, {'乙'});
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('choice-custom')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank_custom_entry_is_ignored', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <Set<String>>[];
    await show(tester, choice(onChanged: changes.add));
    await tester.enterText(find.byKey(const ValueKey('choice-custom')), '   ');
    await tester.tap(find.byKey(const ValueKey('choice-custom-add')));
    await tester.pump();
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom_entry_absent_without_allow_custom', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <Set<String>>[];
    await show(tester, choice(allowCustom: false, onChanged: changes.add));
    expect(find.byKey(const ValueKey('choice-custom')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
