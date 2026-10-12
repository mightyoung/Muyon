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
  // This file contains testWidgets, so TestWidgetsFlutterBinding installs a
  // mock HttpOverrides that answers 400. The real gateway must reach the local
  // LoopFixture endpoint (same pattern as assistant_subconversation_running_test).
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
  });

  // =========================================================================
  // Negative 1: stream with only `end` vs. an illegal stream.
  // =========================================================================
  group('N1 end-only stream', () {
    // RED expected on baseline (contract conflict, see report).
    // Mutation caught once fixed: a classifier that maps every terminal
    // rejection with zero nodes to invalid_plan (stream_ui_planning.dart:72,
    // :114-116) instead of the model no-card cause.
    test('N1a tool path: end-only stream is model_no_card, not a host refusal',
        () async {
      final f = await LoopFixture.open();
      final tool = await _toolOverStream(f, _end);
      // Safety half (must hold regardless of classification).
      expect(tool.data['surfaceId'], isNull);
      expect(tool.data['revision'], isNull);
      expect(tool.data['decision'], UiDisplayDecision.textOnly.name);
      // Classification half.
      expect(tool.data['reasonCode'], 'model_no_card');
      expect(tool.data['reasonCategory'], 'model');
      expect(tool.summary, UiPlanningReason.forCode('model_no_card').description);
      expect(f.bodies, isEmpty);
    });

    // RED expected on baseline. Same mutation as N1a, observed through the
    // production PersonalAgent -> real gateway -> persisted ui_planning event.
    test('N1b agent path: persisted ui_planning event for end-only stream',
        () async {
      final f = await LoopFixture.open();
      final preference = UiPresentationPreference(f.repo);
      await preference.save(UiPresentationMode.automatic);
      final agent = _streamAgent(f, preference);
      addTearDown(agent.close);
      final parent = await _runStreamTurn(f, agent, _end);
      expect(agent.uiPresentation(parent.id)?.validated, isNull);
      final event = _planningEvent(f, parent.id);
      expect(event['surfaceId'], isNull);
      expect(event['reasonCode'], 'model_no_card');
      expect(event['reasonCategory'], 'model');
      expect(f.bodies, hasLength(2));
      expect(f.callsOf('write'), 0);
    });

    // Control, GREEN expected. Mutation caught: any change that relabels a
    // real validation/protocol failure as model_no_card (e.g. replacing
    // 'invalid_plan'/'malformed_stream' in stream_ui_planning.dart:72/:114-116
    // or ui_planning.dart:653 with a model code; UiPlanningReason.host would
    // then yield planner_unavailable, and a direct label would yield
    // model_no_card - both fail the exact host code below).
    for (final (name, stream, code) in [
      ('invalid binding', _invalidPlanStream, 'invalid_plan'),
      ('bad line', _malformedStream, 'malformed_stream'),
    ]) {
      test('N1c control: $name stays host $code, never model_no_card',
          () async {
        final f = await LoopFixture.open();
        final tool = await _toolOverStream(f, stream);
        expect(tool.data['reasonCode'], code);
        expect(tool.data['reasonCategory'], 'host');
        expect(tool.data['reasonCode'], isNot('model_no_card'));
        expect(tool.data['surfaceId'], isNull);
        expect(tool.summary, UiPlanningReason.forCode(code).description);
      });
    }
  });

  // =========================================================================
  // Negative 2: automatic start, planning suspended, user switches to textOnly,
  // then the suspended planning is released.
  // =========================================================================
  Future<(LoopFixture, PersonalAgent, PersonalTask)> suspendedThenTextOnly()
      async {
    final f = await LoopFixture.open();
    final preference = UiPresentationPreference(f.repo);
    await preference.save(UiPresentationMode.automatic);
    final agent = _streamAgent(f, preference);
    addTearDown(agent.close);
    f.replies.addAll([_answerReply(), _streamReply(_validStream)]);
    final parent = await f.start(agent, _streamingProfile(f));
    final finishing = agent.confirm(
      parent.id,
      requestDigest: parent.payload['requestDigest'] as String,
    );
    // Planning is now suspended on the planning child's confirmation card.
    final child = await _waitingChild(f);
    expect(f.bodies, hasLength(1), reason: 'only the answer request so far');
    await agent.savePresentationMode(UiPresentationMode.textOnly);
    // Release the suspended planning.
    try {
      await agent.confirm(
        child.id,
        requestDigest: child.payload['requestDigest'] as String,
      );
    } catch (_) {
      // A refused release is acceptable; the assertions below decide.
    }
    await finishing;
    return (f, agent, parent);
  }

  group('N2 automatic -> textOnly while planning is suspended', () {
    // RED expected on baseline: the persisted cause is a generic host drift
    // (host_state_changed), not the user's choice.
    // Mutation caught once fixed: dropping the user cause in the drift branch
    // of UiPlanningHarness.plan (ui_planning.dart:387-402) back to
    // host_state_changed, or PersonalAgent.savePresentationMode
    // (personal_agent.dart:231-238) not carrying the user's new mode.
    test('N2a released planning records the user text-only cause', () async {
      final (f, agent, parent) = await suspendedThenTextOnly();
      expect(agent.uiPresentation(parent.id)?.validated, isNull);
      final event = _planningEvent(f, parent.id);
      expect(event['surfaceId'], isNull);
      expect(event['reasonCode'], 'user_text_only');
      expect(event['reasonCategory'], 'user');
      expect(
        event['reasonDescription'],
        UiPlanningReason.forCode('user_text_only').description,
      );
    });

    // GREEN expected. Mutation caught (verified locally):
    // - freezeFor's `generation == _generation` removed
    //   (ui_presentation_preference.dart:106) -> the old turn's frozen
    //   automatic policy is current again -> allowsUiContent true.
    // Verified NOT caught here, because a second fence still holds:
    // - UiPresentationPolicy._allows textOnly => true
    //   (ui_presentation_preference.dart:53): the old policy is already stale;
    // - uiModelChecks presentation clause removed (personal_agent.dart:357):
    //   isCurrentRequest is false after invalidate, request still refused.
    test('N2b no card, no planning request, old turn authority not restored',
        () async {
      final (f, agent, parent) = await suspendedThenTextOnly();
      expect(agent.allowsUiContent(parent.id), isFalse);
      expect(agent.uiPresentation(parent.id), isNull);
      expect(agent.uiStreamProgress(parent.id), isNull);
      expect(f.bodies, hasLength(1),
          reason: 'released planning must not reach the model after textOnly');
      // Switching back must not revive the old turn's frozen presentation.
      await agent.savePresentationMode(UiPresentationMode.automatic);
      expect(agent.allowsUiContent(parent.id), isFalse);
      final again = await agent.planUi(parent.id);
      expect(again.validated, isNull);
      expect(again.result.plan, isNull);
      expect(agent.uiPresentation(parent.id), isNull);
      expect(f.bodies, hasLength(1));
      expect(f.callsOf('write'), 0);
    });
  });

  // =========================================================================
  // Negative 3: complete stream with failureCode == null must not render the
  // "stream incomplete" failure copy.
  // =========================================================================
  // RED expected on baseline: ui_stream_task_view.dart:286-293 renders
  // UiPlanningReason.host(progress.failureCode ?? 'incomplete') for every
  // non-streaming phase, including complete with a null failureCode.
  // Mutation caught once fixed: restoring the `?? 'incomplete'` default for a
  // complete phase.
  testWidgets('N3 complete stream without failureCode shows no incomplete copy',
      (tester) async {
    final f = (await tester.runAsync(LoopFixture.open))!;
    final preference = UiPresentationPreference(f.repo);
    await tester.runAsync(() => preference.save(UiPresentationMode.automatic));
    final agent = _streamAgent(f, preference);
    final hold = Completer<void>();
    Future<void>? finishing;
    try {
      final parentId = (await tester.runAsync(() async {
        f.replies.addAll([_answerReply(), _streamReply(_validStream, hold: hold.future)]);
        final parent = await f.start(agent, _streamingProfile(f));
        finishing = agent.confirm(
          parent.id,
          requestDigest: parent.payload['requestDigest'] as String,
        );
        final child = await _waitingChild(f);
        unawaited(agent
            .confirm(child.id,
                requestDigest: child.payload['requestDigest'] as String)
            .catchError((Object _) {}));
        // The whole NDJSON including `end` has arrived; the gateway stream is
        // held open, so the harness has not produced a presentation yet.
        await _until(() {
          final p = agent.uiStreamProgress(parent.id);
          return p != null && p.view.phase == UiStreamPhase.complete ? p : null;
        }, what: 'complete stream progress');
        return parent.id;
      }))!;
      final progress = agent.uiStreamProgress(parentId)!;
      expect(progress.view.phase, UiStreamPhase.complete);
      expect(progress.failureCode, isNull);
      expect(agent.uiPresentation(parentId), isNull);

      await tester.pumpWidget(
        MaterialApp(home: UiStreamTaskView(agent: agent, taskId: parentId)),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      // Non-vacuous: the preview branch for this progress is on screen.
      expect(find.byKey(ValueKey('ui-stream-preview-$parentId')), findsOneWidget);
      expect(find.text('CF2独立事实'), findsWidgets);
      // The assertion under test.
      expect(find.text(_incompleteCopy), findsNothing);
      expect(find.textContaining('界面流未完成'), findsNothing);
      expect(find.textContaining(_failureSuffix), findsNothing);
    } finally {
      if (!hold.isCompleted) hold.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        try {
          await finishing;
        } catch (_) {}
        await agent.close();
      });
    }
  });

  // =========================================================================
  // Negative 4: model reasonCode null / number / blank / 10k canary.
  // =========================================================================
  group('N4 model reasonCode never leaks', () {
    for (final input in _reasonInputs) {
      // GREEN expected. Mutations caught:
      // - UiPlanningReason.modelResult passing value.reasonCode through
      //   (ui_planning_reason.dart:147-159) -> canary in tool JSON;
      // - UiPlanningReason.forCode returning an ad-hoc reason for unknown codes
      //   (ui_planning_reason.dart:135-136) together with the pass-through
      //   -> raw canary becomes the code (caught by the allowed-code set);
      // - runUiPlanningTool exposing result.reasonCode instead of reason.code
      //   (ui_planning_tool.dart:42) - caught only together with the
      //   modelResult pass-through; alone, result.reasonCode is already a
      //   table code.
      test('N4 tool JSON: ${input.name}', () async {
        final f = await LoopFixture.open();
        final agent = f.agent();
        final conversation = await f.repo.createConversation();
        final task = await agent.start(
          conversationId: conversation.id,
          prompt: '无配置',
        );
        final harness = UiPlanningHarness(
          repository: f.repo,
          source: (_) async => _state(f),
          mode: UiPlanningMode.motivation,
          providers: {
            UiPlanningMode.motivation: MotivationUiPlanningProvider(
              (_, _) async => _rawBatch(input.encoded),
            ),
          },
        );
        final first = await runUiPlanningTool(harness, task.id, _toolRequest());
        _expectStableReason(first.data, input, 'tool data');
        expect(first.summary, first.data['reasonDescription']);
        expect(first.data['surfaceId'], isNull);
        _expectNoCanary(jsonEncode(first.toJson()), 'tool JSON');
        _expectNoCanary(_databaseDump(f), 'database');
        expect(f.bodies, isEmpty);
      });

      // GREEN expected. Same mutations as above, observed through the
      // persisted ui_planning event (agent_context.dart:220-227), every table
      // in the database, and the actual UiStreamTaskView fallback text
      // (ui_stream_task_view.dart:264-273).
      testWidgets('N4 task event + database + rendered view: ${input.name}',
          (tester) async {
        final f = (await tester.runAsync(LoopFixture.open))!;
        final agent = PersonalAgent(
          repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          tools: f.tools,
          uiPlanningSource: (_) async => _state(f),
          uiPlanningMode: UiPlanningMode.motivation,
          uiPlanningProviders: {
            UiPlanningMode.motivation: MotivationUiPlanningProvider(
              (_, _) async => _rawBatch(input.encoded),
            ),
          },
        );
        try {
          final taskId = (await tester.runAsync(() async {
            f.replies.add(_answerReply());
            final task = await f.start(agent, _streamingProfile(f));
            await f.run(agent, task);
            return task.id;
          }))!;
          final event = _planningEvent(f, taskId);
          _expectStableReason(event, input, 'ui_planning event');
          expect(event.keys, isNot(contains('rawReason')));
          final allEvents = jsonEncode([
            for (final e in f.repo.taskEvents(taskId)) {'t': e.type, 'd': e.data},
          ]);
          _expectNoCanary(allEvents, 'task events');
          _expectNoCanary(_databaseDump(f), 'database');
          final presentation = agent.uiPresentation(taskId);
          expect(presentation, isNotNull);
          expect(presentation!.validated, isNull);

          await tester.pumpWidget(
            MaterialApp(home: UiStreamTaskView(agent: agent, taskId: taskId)),
          );
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
          // Non-vacuous: the fallback branch is on screen with fixed copy.
          expect(
            find.byKey(ValueKey('ui-stream-fallback-$taskId')),
            findsOneWidget,
          );
          expect(find.text(event['reasonDescription']! as String), findsOneWidget);
          expect(find.textContaining(_marker), findsNothing);
          expect(find.textContaining('credential=secret'), findsNothing);
          final semantics = tester.ensureSemantics();
          try {
            expect(find.bySemanticsLabel(RegExp(_marker)), findsNothing);
          } finally {
            semantics.dispose();
          }
          expect(f.bodies, hasLength(1));
          expect(f.callsOf('write'), 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(agent.close);
        }
      });
    }
  });
}
