import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/screens/ui_planning_preference_switch.dart';

import 'support/aiui6_snapshot_fixture.dart';

void main() {
  testWidgets('failed UI mode save rolls the selection back; retry commits the actual choice', (tester) async {
    final f = (await tester.runAsync(InquirySnapshotFixture.open))!;
    final agent = f.host.personalAgent;
    try {
      await tester.runAsync(() => f.host.foundation.database.write((db) => db.execute('''
CREATE TRIGGER refuse_mode BEFORE INSERT ON settings
WHEN NEW.key='assistant.uiPresentation.mode.v1'
BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END
''')));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: UiPlanningPreferenceSwitch(agent: agent))));
      Future<void> chooseFew() async {
        await tester.tap(find.byType(DropdownButtonFormField<UiPresentationMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('少用').last);
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
          await tester.pump();
        }
      }
      await chooseFew();
      final field = find.byType(DropdownButtonFormField<UiPresentationMode>);
      expect(tester.state<FormFieldState<UiPresentationMode>>(field).value, UiPresentationMode.textOnly);
      expect(agent.presentationMode, UiPresentationMode.textOnly);
      expect(find.text('设置未保存，请重试'), findsOneWidget);
      expect(f.host.workspaces.setting(UiPresentationPreference.key), isNull);
      await tester.runAsync(() => f.host.foundation.database.write((db) => db.execute('DROP TRIGGER refuse_mode')));
      await chooseFew();
      expect(tester.state<FormFieldState<UiPresentationMode>>(field).value, UiPresentationMode.few);
      expect(agent.presentationMode, UiPresentationMode.few);
      expect(f.host.workspaces.setting(UiPresentationPreference.key), 'few');
      expect(find.text('设置未保存，请重试'), findsNothing);
      expect(f.host.assistantGrants.list(), isEmpty);
      expect(f.host.tools.history(), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    }
  });
}
