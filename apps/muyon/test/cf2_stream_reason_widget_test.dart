import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';

import 'aiui6_stream_production_test.dart' show state, validStream;
import 'support/agent_loop_fixture.dart';

void main() {
  testWidgets(
    'stream fallback shows fixed host Chinese cause without exception text',
    (tester) async {
      final f = (await tester.runAsync(LoopFixture.open))!;
      final preference = UiPresentationPreference(f.repo);
      await tester.runAsync(
        () => preference.save(UiPresentationMode.automatic),
      );
      final provider = StreamMotivationUiPlanningProvider((
        _,
        _,
        receive,
      ) async {
        receive(validStream.replaceAll('{"op":"end"}\n', ''));
      });
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        uiPlanningSource: (_) async => state(f),
        presentationPreference: preference,
        uiPlanningMode: UiPlanningMode.motivation,
        uiPlanningProviders: {UiPlanningMode.motivation: provider},
      );
      try {
        final taskId = (await tester.runAsync(() async {
          final conversation = await f.repo.createConversation();
          return (await agent.start(
            conversationId: conversation.id,
            prompt: '无配置',
          )).id;
        }))!;
        await tester.runAsync(() => agent.planUi(taskId));
        await tester.pumpWidget(
          MaterialApp(
            home: UiStreamTaskView(agent: agent, taskId: taskId),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.text('界面流未完成，已使用只读事实展示。'), findsOneWidget);
        expect(find.textContaining('value: 42'), findsWidgets);
        expect(find.textContaining('RAW_MODEL_REASON_CANARY'), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(agent.close);
      }
    },
  );
}
