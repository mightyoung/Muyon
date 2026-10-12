import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'support/conversation_workspace_fixture.dart';

const labels = {
  UiPlanningMode.intelligent: 'Intelligent UI · 本地 Provider',
  UiPlanningMode.motivation: 'Motivation UI · 当前授权模型',
};

void expectLastGlyphFits(WidgetTester tester, Finder label, Rect bounds) {
  expect(label, findsOneWidget);
  final text = tester.widget<Text>(label).data!;
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  final last = boxes.last;
  final origin = paragraph.localToGlobal(Offset.zero);
  expect(origin.dx + last.left, greaterThanOrEqualTo(bounds.left - 1));
  expect(
    origin.dx + last.right,
    lessThanOrEqualTo(bounds.right + 1),
    reason: 'Full option text must fit without ellipsis or horizontal clipping',
  );
  expect(
    origin.dy + last.bottom,
    lessThanOrEqualTo(bounds.bottom + 1),
    reason:
        'Multiline selected text must not be clipped to a fixed item height',
  );
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final presentation in UiPresentationMode.values) {
        testWidgets(
          'all controls readable and selectable ${presentation.name} width=$width scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final root = Directory.systemTemp.createTempSync(
              'linux-settings-layout-',
            );
            final host = (await tester.runAsync(
              () => MuyonHost.open('${root.path}/data'),
            ))!;
            try {
              await workspaceOperation(
                tester,
                () => host.personalAgent.savePresentationMode(presentation),
              );
              await tester.pumpWidget(MuyonApp(host: host));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final preference = find.byType(
                DropdownButtonFormField<UiPresentationMode>,
              );
              expect(preference, findsOneWidget);
              await tester.ensureVisible(preference);
              await tester.pumpAndSettle();
              expect(preference.hitTestable(), findsOneWidget);
              await tester.tap(preference);
              await tester.pumpAndSettle();
              for (final mode in UiPresentationMode.values) {
                expect(
                  find.text(mode.label).last.hitTestable(),
                  findsOneWidget,
                );
              }
              await tester.tap(find.text(presentation.label).last);
              await workspaceReady(tester);
              expect(host.personalAgent.presentationMode, presentation);
              final planner = find.byType(DropdownButton<UiPlanningMode>);
              if (presentation == UiPresentationMode.textOnly) {
                expect(
                  planner,
                  findsNothing,
                  reason: 'Existing text-only planning permission remains off; its three-tier preference control is still accessible',
                );
              } else {
                expect(planner, findsOneWidget);
                await tester.ensureVisible(planner);
                await tester.pumpAndSettle();
                expect(planner.hitTestable(), findsOneWidget);
                for (final selection in UiPlanningMode.values) {
                  await tester.tap(planner);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  for (final label in labels.values) {
                    expect(find.text(label).last.hitTestable(), findsOneWidget);
                  }
                  await tester.tap(find.text(labels[selection]!).last);
                  await tester.pumpAndSettle();
                  expect(host.personalAgent.currentUiPlanningMode, selection);
                  expectLastGlyphFits(
                    tester,
                    find.text(labels[selection]!),
                    tester
                        .getRect(planner)
                        .intersect(
                          tester.getRect(
                            find
                                .ancestor(
                                  of: planner,
                                  matching: find.byType(Scrollable),
                                )
                                .first,
                          ),
                        ),
                  );
                  expect(tester.takeException(), isNull);
                }
              }
              expect(host.personalAgent.presentationMode, presentation);
              expect(host.assistantGrants.list(), isEmpty);
              expect(host.tools.history(), isEmpty);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox());
              await workspaceOperation(tester, host.close);
              root.deleteSync(recursive: true);
            }
          },
        );
      }
    }
  }
}
