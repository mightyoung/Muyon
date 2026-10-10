import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_ui/dynamic_ui.dart';

import 'support/agent_loop_fixture.dart';
import 'support/aiui6_snapshot_fixture.dart';

String node(String id, String component, {String? parent, Map<String, Object?> props = const {},
    Map<String, Object?> bind = const {}}) => jsonEncode({
  'op': 'node', 'id': id, 'component': component, if (parent != null) 'parent': parent,
  'props': props, 'bind': bind});
String get validStream => '${node('root', 'PageScaffold', props: {'title': '保存事实'})}\n'
  '${node('fact', 'KeyValue', parent: 'root', bind: {'value': {'kind': 'fact', 'id': 'value'}})}\n'
  '{"op":"end"}\n';
UiPlanningHostState state(LoopFixture f) {
  final snapshot = DataSnapshot(ref: const SnapshotRef('saved', 1), facts: {
    'value': SnapshotFact(object: f.ref, field: 'value', value: 42, state: FactState.verified)});
  return UiPlanningHostState(snapshot: snapshot,
    intent: InteractionIntent(id: 'read-only', purpose: 'Display fixture facts',
      snapshotRef: snapshot.ref, requiredBindings: {const BindingRef.fact('value')}),
    currentView: UiCurrentView(surfaceId: 'surface', revision: 0),
    catalog: library2UiCatalog, allowedActionRefs: const {});
}
UiPlanningRequest request(LoopFixture f) {
  final host = state(f);
  return UiPlanningRequest(question: 'read', answer: '42', conversationMessages: const [],
    conversationVersion: '1', coverage: 'fixture', taskId: 'task', turnId: 'task',
    snapshot: host.snapshot, intent: host.intent, currentView: host.currentView,
    catalog: host.catalog, allowedActionRefs: const {}, mode: UiPlanningMode.motivation);
}
void main() {
  for (final fault in ['bad-line', 'missing-end', 'after-end', 'oversize']) {
    test('original stream rejects $fault without a replacement plan', () async {
      final f = await LoopFixture.open();
      final stream = switch (fault) {
        'bad-line' => 'not-json\n$validStream',
        'missing-end' => validStream.replaceAll('{"op":"end"}\n', ''),
        'after-end' => '$validStream{"op":"end"}\n',
        _ => List.filled(UiStreamLimits.v1.lineBytes + 1, 'x').join(),
      };
      final provider = StreamMotivationUiPlanningProvider((_, __, receive) async => receive(stream));
      final input = request(f);
      await expectLater(provider.plan(input), throwsStateError);
      expect(provider.progressFor(input), isNull);
    });
  }
  test('incremental preview has no events; only original completed candidate grants final capability', () async {
    final f = await LoopFixture.open();
    final observations = <HostUiStreamProgress>[];
    final provider = StreamMotivationUiPlanningProvider((_, __, receive) async {
      for (final rune in validStream.runes) { receive(String.fromCharCode(rune)); }
    }, onProgress: observations.add);
    final input = request(f);
    final result = await provider.plan(input);
    expect(result.reasonCode, 'validated_stream_2');
    expect(provider.progressFor(input)!.session.protocolVersion, streamProtocolV2);
    expect(provider.progressFor(input)!.session.catalog, same(library2UiCatalog));
    expect(observations.where((value) => !value.view.complete).every((value) =>
      value.view.finalPlan == null && value.view.previewPlan.nodes.every((node) => node.events.isEmpty)), isTrue);
    expect(provider.progressFor(input)!.view.finalPlan!.plan.nodes, hasLength(2));
  });
  test('production PersonalAgent uses real gateway deltas and whole compiler under confirmation', () async {
    final f = await LoopFixture.open();
    final preference = UiPresentationPreference(f.repo);
    await preference.save(UiPresentationMode.automatic);
    final agent = PersonalAgent(repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger), tools: f.tools,
      presentationPreference: preference, uiPlanningSource: (_) async => state(f),
      uiPlanningMode: UiPlanningMode.motivation);
    addTearDown(agent.close);
    f.replies.addAll([LoopReply.sse(sseText('{"type":"answer","answer":"Saved answer","citationIds":[]}')),
      LoopReply.sse([for (final line in validStream.split('\n').where((line) => line.isNotEmpty))
        sseChunk({'content': '$line\n'}), sseChunk({}, finish: 'stop'), 'data: [DONE]\n\n'])]);
    final parent = await f.start(agent, f.profile(capabilities: const ModelCapabilities(streaming: true)));
    final finishing = agent.confirm(parent.id, requestDigest: parent.payload['requestDigest'] as String);
    for (var turn = 0; turn < 10000; turn++) {
      final children = f.repo.tasks().where((task) => task.payload['uiPlanningInternal'] == true);
      if (children.isNotEmpty && children.single.state.name == 'waitingConfirmation') {
        final child = children.single;
        await agent.confirm(child.id, requestDigest: child.payload['requestDigest'] as String);
        break;
      }
      await Future<void>(() {});
    }
    await finishing;
    final presentation = agent.uiPresentation(parent.id);
    expect(presentation?.validated, isNotNull);
    expect(presentation!.stream!.session.protocolVersion, streamProtocolV2);
    expect(presentation.stream!.view.complete, isTrue);
    expect(f.bodies, hasLength(2));
    expect(f.bodies.last.containsKey('response_format'), isFalse);
    expect(f.bodies.last.containsKey('tools'), isFalse);
    expect(f.repo.messages(parent.conversationId).where((message) => message.role == 'assistant')
      .map((message) => message.content), ['Saved answer']);
    expect(f.callsOf('write'), 0);
  });
  test('real selected SQLite source uses library2 masked facts and rejects changed pin', () async {
    final f = await InquirySnapshotFixture.open();
    try {
      final ref = f.refs['project_item']!;
      final conversation = await f.host.foundation.createConversation(scope: AssistantScope.selectedObjects([ref]));
      final task = await f.host.personalAgent.start(conversationId: conversation.id, prompt: '没有模型');
      final source = InquiryUiPlanningSource(f.host);
      final result = await source.read(task);
      expect(result!.catalog, same(library2UiCatalog));
      expect(result.snapshot.facts['saved-name']!.value, '真实预算行');
      expect(jsonEncode(result.snapshot.facts.values.map((fact) => fact.value).toList()), isNot(contains('987654.123')));
      expect(result.snapshot.facts.values.every((fact) => fact.object == ref), isTrue);
      final store = f.host.inquiry!.runtime.state.store;
      store.save('project_item', {...store.get('project_item', ref.objectId)!.data, 'name': 'changed'}, id: ref.objectId);
      await expectLater(source.read(task), throwsStateError);
      expect(f.host.tools.history(), isEmpty);
    } finally { await f.close(); }
  });
}
