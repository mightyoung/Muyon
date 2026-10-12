// Independent reviewer regression: original rendering assertions retained.
import 'dart:io' show HttpOverrides;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart' show PersonalTask;
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart' show library2UiCatalog;
import 'support/agent_loop_fixture.dart';
const _end = '{"op":"end"}\n';
UiPlanningHostState _state(LoopFixture f) {
  final snapshot = DataSnapshot(
    ref: const SnapshotRef('cf2-saved', 1),
    facts: {
      'value': SnapshotFact(
        object: f.ref,
        field: 'value',
        value: 42,
        state: FactState.verified,
      ),
    },
  );
  return UiPlanningHostState(
    snapshot: snapshot,
    intent: InteractionIntent(
      id: 'cf2-read-only',
      purpose: 'Display fixture facts',
      snapshotRef: snapshot.ref,
      requiredBindings: {const BindingRef.fact('value')},
    ),
    currentView: UiCurrentView(surfaceId: 'cf2-surface', revision: 0),
    catalog: library2UiCatalog,
    allowedActionRefs: const {},
  );
}

ModelProfile _streamingProfile(LoopFixture f) =>
    f.profile(capabilities: const ModelCapabilities(streaming: true));

LoopReply _answerReply() => LoopReply.sse(
  sseText('{"type":"answer","answer":"CF2宿主回答","citationIds":[]}'),
);

/// Synthetic NDJSON served as streamed text deltas, one delta per line.
LoopReply _streamReply(String ndjson, {Future<void>? hold}) => LoopReply.sse([
  if (hold != null)
    sseChunk({'content': ndjson})
  else
    for (final line in ndjson.split('\n').where((l) => l.isNotEmpty))
      sseChunk({'content': '$line\n'}),
  sseChunk({}, finish: 'stop'),
  'data: [DONE]\n\n',
], hold: hold);

Future<T> _until<T extends Object>(
  T? Function() probe, {
  String what = 'condition',
  int rounds = 4000,
}) async {
  for (var i = 0; i < rounds; i++) {
    final value = probe();
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw TestFailure('timed out waiting for $what');
}

PersonalTask? _child(LoopFixture f) {
  final children = f.repo
      .tasks()
      .where((t) => t.payload['uiPlanningInternal'] == true)
      .toList();
  return children.isEmpty ? null : children.last;
}

Future<PersonalTask> _waitingChild(LoopFixture f) => _until(() {
  final child = _child(f);
  return child != null && child.state.name == 'waitingConfirmation'
      ? child
      : null;
}, what: 'planning child waiting for confirmation');

PersonalAgent _streamAgent(LoopFixture f, UiPresentationPreference preference) =>
    PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      uiPlanningSource: (_) async => _state(f),
      presentationPreference: preference,
      uiPlanningMode: UiPlanningMode.motivation,
    );

/// Drives one real parent turn through finish -> harness.plan -> real stream
/// provider -> planning child -> gateway SSE.
Future<PersonalTask> _runStreamTurn(
  LoopFixture f,
  PersonalAgent agent,
  String ndjson,
) async {
  f.replies.addAll([_answerReply(), _streamReply(ndjson)]);
  final parent = await f.start(agent, _streamingProfile(f));
  final finishing = agent.confirm(
    parent.id,
    requestDigest: parent.payload['requestDigest'] as String,
  );
  final child = await _waitingChild(f);
  await agent.confirm(
    child.id,
    requestDigest: child.payload['requestDigest'] as String,
  );
  await finishing;
  return parent;
}

void main() {
  testWidgets('independent end-only UI has no incomplete fallback card', (tester) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    final f = (await tester.runAsync(LoopFixture.open))!;
    final preference = UiPresentationPreference(f.repo);
    await tester.runAsync(() => preference.save(UiPresentationMode.automatic));
    final agent = _streamAgent(f, preference);
    try {
      final task = (await tester.runAsync(() => _runStreamTurn(f, agent, _end)))!;
      expect(agent.uiPresentation(task.id)!.result.reasonCode, 'model_no_card');
      await tester.pumpWidget(MaterialApp(home: UiStreamTaskView(agent: agent, taskId: task.id)));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('界面未完成'), findsNothing);
      expect(find.byKey(ValueKey('ui-stream-fallback-${task.id}')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(agent.close);
      HttpOverrides.global = previous;
    }
  });
}
