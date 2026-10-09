import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  testWidgets('read-only form blocks ready child inputs and semantics actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var changes = 0;
    var submits = 0;
    await mount(
      tester,
      MuyonForm(
        title: '只读表单',
        state: UiComponentState.readOnly,
        onSubmit: () => submits++,
        children: [
          Toggle(label: '子开关', value: false, onChanged: (_) => changes++),
          Choice(
            label: '子选项',
            options: const ['甲'],
            selected: const {},
            allowCustom: true,
            onChanged: (_) => changes++,
          ),
          TextField(
            decoration: const InputDecoration(labelText: '原生子输入'),
            onChanged: (_) => changes++,
          ),
        ],
      ),
      width: 800,
      scale: 1,
    );
    await tester.tap(find.byKey(const ValueKey('toggle')), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('choice-甲')), warnIfMissed: false);
    await tester.tap(find.byType(TextField).last, warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await tester.pump();
    expect(changes, 0);
    expect(submits, 0);
    for (final editable in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(editable.focusNode.hasFocus, isFalse);
      expect(editable.focusNode.canRequestFocus, isFalse);
    }
    // Labels remain available to readers, while accessibility cannot edit.
    expect(find.bySemanticsLabel('子开关'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('toggle'))).getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    for (final editable in find.byType(EditableText).evaluate()) {
      expect(
        tester.getSemantics(find.byWidget(editable.widget)).getSemanticsData()
            .hasAction(SemanticsAction.setText),
        isFalse,
      );
    }
  });

  testWidgets('locking a focused form revokes focus; unlocking allows editing', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var changes = 0;
    var submits = 0;
    Future<void> show(UiComponentState state) => mount(
      tester,
      MuyonForm(
        title: '可锁定表单',
        state: state,
        onSubmit: () => submits++,
        children: [
          TextField(
            controller: controller,
            focusNode: focus,
            onChanged: (_) => changes++,
          ),
        ],
      ),
      width: 800,
      scale: 1,
    );
    await show(UiComponentState.ready);
    await tester.enterText(find.byType(TextField), '草稿');
    expect(focus.hasFocus, isTrue);
    expect(changes, 1);
    await show(UiComponentState.readOnly);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
    expect(controller.text, '草稿');
    await show(UiComponentState.ready);
    await tester.enterText(find.byType(TextField), '新草稿');
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    expect(changes, 2);
    expect(submits, 1);
  });
}
