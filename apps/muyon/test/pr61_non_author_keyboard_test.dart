import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'support/conversation_workspace_fixture.dart';

void main() {
  testWidgets('scaled narrow planner retains keyboard focus and selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final directory = Directory.systemTemp.createTempSync(
      'pr61-keyboard-review-',
    );
    final host = (await tester.runAsync(
      () => MuyonHost.open('${directory.path}/data'),
    ))!;
    try {
      await workspaceOperation(
        tester,
        () => host.personalAgent.savePresentationMode(
          UiPresentationMode.automatic,
        ),
      );
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      final planner = find.byType(DropdownButton<UiPlanningMode>);
      await tester.ensureVisible(planner);
      var focused = false;
      for (var turn = 0; turn < 40; turn++) {
        final context = FocusManager.instance.primaryFocus?.context;
        focused =
            context
                ?.findAncestorWidgetOfExactType<
                  DropdownButton<UiPlanningMode>
                >() !=
            null;
        if (focused) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(
        focused,
        isTrue,
        reason: 'Planner must remain in keyboard traversal',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.text('Motivation UI · 当前授权模型').last.hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        host.personalAgent.currentUiPlanningMode,
        UiPlanningMode.motivation,
      );
      final selected = find.text('Motivation UI · 当前授权模型');
      final text = tester.widget<Text>(selected);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final paragraph = tester.renderObject<RenderParagraph>(selected);
      expect(paragraph.didExceedMaxLines, isFalse);
      final bounds = tester
          .getRect(planner)
          .intersect(
            tester.getRect(
              find
                  .ancestor(of: planner, matching: find.byType(Scrollable))
                  .first,
            ),
          );
      final origin = paragraph.localToGlobal(Offset.zero);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.data!.length),
      );
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        expect(origin.dx + box.left, greaterThanOrEqualTo(bounds.left - 1));
        expect(origin.dx + box.right, lessThanOrEqualTo(bounds.right + 1));
        expect(origin.dy + box.top, greaterThanOrEqualTo(bounds.top - 1));
        expect(origin.dy + box.bottom, lessThanOrEqualTo(bounds.bottom + 1));
      }
      expect(tester.takeException(), isNull);
      expect(host.assistantGrants.list(), isEmpty);
      expect(host.tools.history(), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await workspaceOperation(tester, host.close);
      directory.deleteSync(recursive: true);
    }
  });
}
