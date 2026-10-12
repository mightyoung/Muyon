// CF-2 independent production-path regression tests (engineer2).
//
// Baseline: 9d8a4118de74cda369ddd004c519d01a1e0752ba. Tests only; no product
// code is changed here. Every model input is synthetic: either a fake
// requestModel callback on the real provider classes, or SSE served by the
// local LoopFixture endpoint through the real OpenAiModelGateway. No real
// model, no business write.
//
// Some cases are expected to be RED on the baseline. They are kept RED on
// purpose (no skip, no loosened assertion) and are re-run by Leader B on the
// fixed combination.
//
// Contract note for N1: the stream protocol has no operation that expresses
// "no card" (docs/design/aiui-stream-contract.md:13 root node required,
// :26/:44 five ops and `end` triggers final validation, :64 whole-candidate
// validateUiPlan; stream_protocol.dart:159 accepts only text/node/patch/
// action/end), and the stream provider only ever returns `supplement`
// (stream_ui_planning.dart:118-119). N1a/N1b assert
// the CF-2 expectation (model_no_card) and are RED by contract conflict until
// Leader B decides the protocol semantics.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_planning_reason.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart' show PersonalTask;
import 'package:muyon/platform/ui_planning_tool.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart'
    show AssistantScope, ToolCallRequest, ToolCallResult;
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart' show library2UiCatalog;

import 'support/agent_loop_fixture.dart';

// ---------------------------------------------------------------------------
// Task-local synthetic fixtures (deliberately not imported from author tests).
// ---------------------------------------------------------------------------

String _node(
  String id,
  String component, {
  String? parent,
  Map<String, Object?> props = const {},
  Map<String, Object?> bind = const {},
}) => jsonEncode({
  'op': 'node',
  'id': id,
  'component': component,
  'parent': ?parent,
  'props': props,
  'bind': bind,
});

const _end = '{"op":"end"}\n';
String get _validStream =>
    '${_node('root', 'PageScaffold', props: {'title': 'CF2独立事实'})}\n'
    '${_node('fact', 'KeyValue', parent: 'root', bind: {
      'value': {'kind': 'fact', 'id': 'value'},
    })}\n'
    '$_end';

/// A whole-plan validation failure: the binding names a fact that the host
/// snapshot does not contain. Lines are well-formed.
String get _invalidPlanStream =>
    '${_node('root', 'PageScaffold', props: {'title': 'CF2独立事实'})}\n'
    '${_node('bad', 'KeyValue', parent: 'root', bind: {
      'value': {'kind': 'fact', 'id': 'not_in_snapshot'},
    })}\n'
    '$_end';

/// A protocol failure: one line is not JSON.
String get _malformedStream => 'not-json\n$_validStream';

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

Map<String, Object?> _expected() => const {
  'snapshotId': 'cf2-saved',
  'expectedSnapshotRevision': 1,
  'surfaceId': 'cf2-surface',
  'expectedSurfaceRevision': 0,
};

ToolCallRequest _toolRequest() => ToolCallRequest(
  invocationId: 'cf2-planning',
  toolId: uiPlanningToolId,
  scope: AssistantScope.global(),
  parameters: _expected(),
);

/// Every host-side failure description ends with this suffix in the baseline
/// table (ui_planning_reason.dart:56-112).
const _failureSuffix = '已使用只读事实展示。';
const _incompleteCopy = '界面流未完成，已使用只读事实展示。';

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

Map<String, Object?> _planningEvent(LoopFixture f, String taskId) => f.repo
    .taskEvents(taskId)
    .singleWhere((e) => e.type == 'ui_planning')
    .data;

/// Production stream wiring: preference present, default provider is the real
/// StreamMotivationUiPlanningProvider over the real gateway (personal_agent.dart:97-105).
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

Future<ToolCallResult> _toolOverStream(LoopFixture f, String ndjson) async {
  final agent = f.agent();
  final conversation = await f.repo.createConversation();
  final task = await agent.start(conversationId: conversation.id, prompt: '无配置');
  final harness = UiPlanningHarness(
    repository: f.repo,
    source: (_) async => _state(f),
    mode: UiPlanningMode.motivation,
    providers: {
      UiPlanningMode.motivation: StreamMotivationUiPlanningProvider(
        (_, _, receive) async => receive(ndjson),
      ),
    },
  );
  final tool = await runUiPlanningTool(harness, task.id, _toolRequest());
  expect(harness.presentation(task.id)?.validated, isNull);
  return tool;
}

// ---------------------------------------------------------------------------
// Negative 4 inputs: model-authored reasonCode values for the batch provider.
// ---------------------------------------------------------------------------

const _marker = 'CF2_INDEPENDENT_CANARY_7f3a';
final String _canary = () {
  final b = StringBuffer(_marker);
  var i = 0;
  while (b.length < 10000) {
    b.write(switch (i % 4) {
      0 => '\n/private/export credential=secret',
      1 => '\r',
      2 => '\u2028',
      _ => ' user_text_only $_marker',
    });
    i++;
  }
  return b.toString().substring(0, 10000);
}();

final class _ReasonInput {
  const _ReasonInput(this.name, this.encoded, this.allowed);
  final String name;
  final Object? encoded;

  /// Stable host-table codes acceptable for this input. A malformed or absent
  /// reason must never be echoed; the set only admits table codes that are a
  /// truthful description of the decision contract outcome.
  final Set<String> allowed;
}

final _reasonInputs = <_ReasonInput>[
  const _ReasonInput('null', null, {'invalid_decision', 'planner_unavailable'}),
  const _ReasonInput('number', 4242, {'invalid_decision', 'planner_unavailable'}),
  const _ReasonInput('blank', ' \t  ', {'invalid_decision', 'model_no_card'}),
  _ReasonInput('10k canary with LF/CR/U+2028', _canary, {'model_no_card'}),
];

String _rawBatch(Object? reasonCode) => jsonEncode({
  'decision': UiDisplayDecision.textOnly.name,
  'reasonCode': reasonCode,
  'plan': null,
});

void _expectNoCanary(String text, String where) {
  expect(text, isNot(contains(_marker)), reason: '$where leaked canary marker');
  expect(text, isNot(contains('credential=secret')), reason: where);
  expect(text, isNot(contains('\u2028')), reason: '$where carries raw U+2028');
}

void _expectStableReason(
  Map<String, Object?> data,
  _ReasonInput input,
  String where,
) {
  final code = data['reasonCode'];
  expect(code, isA<String>(), reason: where);
  expect(input.allowed, contains(code), reason: '$where code=$code');
  final fixed = UiPlanningReason.forCode(code! as String);
  expect(fixed.code, code, reason: '$where code must be a table key');
  expect(data['reasonDescription'], fixed.description, reason: where);
  expect(data['reasonCategory'], fixed.category.name, reason: where);
}

String _databaseDump(LoopFixture f) {
  final raw = f.repo.database.raw;
  final out = StringBuffer();
  for (final t in raw.select(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )) {
    final name = t['name'] as String;
    for (final row in raw.select('SELECT * FROM "$name"')) {
      out.writeln('$name ${row.values.map((v) => '$v').join('|')}');
    }
  }
  return out.toString();
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
