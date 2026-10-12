import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/ui_planning_preference_switch.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';

import 'aiui_smoke_config.dart';

/// All supported actions enter actual page controls. No direct agent.confirm,
/// injected plan, test-only card or private enable flag is used.
final class AiuiSmokeDriver {
  AiuiSmokeDriver(this.tester);
  final WidgetTester tester;
  Finder get page => find.byType(AssistantPage);

  Future<void> submit(String prompt) async {
    final input = find.descendant(
      of: page,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '输入消息',
      ),
    );
    final send = find.descendant(
      of: page,
      matching: find.widgetWithText(FilledButton, '发送'),
    );
    if (input.evaluate().length != 1 || send.evaluate().length != 1) {
      throw SmokeFailure(SmokeFailureCode.requestObservabilityMissing);
    }
    await tester.ensureVisible(input);
    await tester.enterText(input, prompt);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump();
  }

  Future<void> setPresentationMode(UiPresentationMode mode) async {
    final control = find.descendant(
      of: find.byType(UiPlanningPreferenceSwitch),
      matching: find.byType(DropdownButtonFormField<UiPresentationMode>),
    );
    if (control.evaluate().length != 1) {
      throw SmokeFailure(SmokeFailureCode.presentationPolicyMissing);
    }
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pump();
    final choice = find.text(mode.label).last;
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pump();
  }

  Future<void> cancelPlanning() async {
    final cancel = find.descendant(
      of: page,
      matching: find.widgetWithText(TextButton, '取消'),
    );
    if (cancel.evaluate().length != 1) {
      throw SmokeFailure(SmokeFailureCode.faultPreconditionUnmet);
    }
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pump();
  }
}
