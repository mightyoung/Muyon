import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/aiui6_snapshot_fixture.dart';

void main() {
  test('actual bootstrap stays text-only and restores explicit three-tier choice across close/reopen', () async {
    final root = Directory.systemTemp.createTempSync('aiui8-host-mode-');
    var host = await MuyonHost.open('${root.path}/data');
    try {
      expect(host.personalAgent.presentationMode, UiPresentationMode.textOnly);
      expect(host.personalAgent.uiPlanningEnabled, isFalse);
      await host.personalAgent.savePresentationMode(UiPresentationMode.few);
      await host.close(); host = await MuyonHost.open('${root.path}/data');
      expect(host.personalAgent.presentationMode, UiPresentationMode.few);
      await host.personalAgent.savePresentationMode(UiPresentationMode.automatic);
      await host.close(); host = await MuyonHost.open('${root.path}/data');
      expect(host.personalAgent.presentationMode, UiPresentationMode.automatic);
      await host.personalAgent.savePresentationMode(UiPresentationMode.textOnly);
      await host.close(); host = await MuyonHost.open('${root.path}/data');
      expect(host.personalAgent.presentationMode, UiPresentationMode.textOnly);
      expect(host.assistantGrants.list(), isEmpty);
      expect(host.tools.history(), isEmpty);
    } finally { await host.close(); root.deleteSync(recursive: true); }
  });
  test('few ordinary production task does not plan or expose source context to a model request', () async {
    final f = await InquirySnapshotFixture.open();
    try {
      await f.host.personalAgent.savePresentationMode(UiPresentationMode.few);
      final conversation = await f.host.foundation.createConversation(
        scope: AssistantScope.selectedObjects([f.refs['project_item']!]));
      final task = await f.host.personalAgent.start(conversationId: conversation.id, prompt: '没有模型');
      expect(f.host.personalAgent.uiPresentation(task.id), isNull);
      expect(f.host.personalAgent.uiStreamProgress(task.id), isNull);
      expect((await f.host.personalAgent.planUi(task.id)).result.reasonCode, 'planning_disabled');
      expect(f.host.foundation.tasks(), hasLength(1));
      expect(f.host.tools.history(), isEmpty);
      expect(f.host.assistantGrants.list(), isEmpty);
    } finally { await f.close(); }
  });
}
