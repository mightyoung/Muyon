import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../test/support/agent_loop_fixture.dart';

import 'support/plugin_fixture.dart';

void main() {
  test('registered read reaches original receipt and reviewed model projection', () async {
    // Removing port dispatch, receipt validation, raw-value isolation or final
    // review must make this fail. The bridge is the actual concrete DUT.
    final f = await PluginFixture.open();
    final task = await f.runRead();
    if (f.handlerCalls == 0) {
      // Fail independently for setup/schema/model/policy failures. Only the
      // concrete bridge's existing refusal may reach the semantic RED marker.
      expect(task.error, contains('plugin_contract_unsupported'),
          reason: 'READ_STUB_REACH_GUARD: a zero handler count alone does not prove bridge dispatch');
      expect(task.state, PersonalTaskState.failed,
          reason: 'READ_STUB_REACH_GUARD: the bridge refusal must settle the real task');
      // Synthetic fixed evidence, emitted only after observing the real task
      // error; no test hook, mocked bridge, or provider payload is involved.
      // ignore: avoid_print
      print('PLUGIN_SLICE_STUB_REACHED code=plugin_contract_unsupported handlerCalls=0');
    }
    expect(f.handlerCalls, 1,
        reason: 'PLUGIN_SLICE_RED_DART_AGENT_READ: registered read must execute through the real Agent port');
    expect(task.state, PersonalTaskState.succeeded);
    final receipt = f.receipt!;
    expect(receipt.succeeded, isTrue);
    expect(receipt.toolId, PluginFixture.toolId);
    expect(receipt.invocationId, f.invocationId);
    expect(receipt.identityDigest, isNotEmpty);
    expect(receipt.result!.summary, PluginFixture.poison,
        reason: 'the original owner retains the original result');
    expect(f.loop.receipts(), hasLength(1), reason: 'no second receipt owner');
    expect(f.loop.repo.authorizationFacts.readTask(task.id).requiresConfirmation,
        isTrue, reason: 'host source facts must survive the successful read');
    expect(f.loop.bodies, hasLength(2));
    final body = jsonEncode(f.loop.bodies.last);
    expect(body, contains(PluginFixture.publicLabel));
    expect(body, isNot(contains(PluginFixture.poison)));
    expect(jsonEncode(task.payload['toolLog']), isNot(contains(PluginFixture.poison)));
    expect(f.events.indexOf('handler'), lessThan(f.events.indexOf('projection-review')));
    expect(f.events.lastIndexOf('model-review'), greaterThan(f.events.indexOf('projection-review')));
    expect(f.reviewer.payloads.any((p) => p.contains(PluginFixture.publicLabel)), isTrue,
        reason: 'final actual payload must pass the original model authority');
    final reviewedBodies = f.reviewer.payloads.map(jsonDecode).toList();
    expect(reviewedBodies, contains(f.loop.bodies.last));
    expect(f.bridge.projectionFor(f.invocationId!, receipt.identityDigest), isNotNull);
  });

  test('renamed third module retains source and purpose gates', () async {
    final f = await PluginFixture.open(renamed: true);
    expect(f.enrolled, isTrue);
    final task = await f.runRead();
    expect(task.state, PersonalTaskState.succeeded);
    expect(f.handlerCalls, 1);
    expect(f.loop.repo.authorizationFacts.readTask(task.id).sourceDigests,
        contains(HostSourceFact.object(f.equipmentRef).identityDigest));
    expect(f.reviewer.payloads.last, contains(PluginFixture.publicLabel));
    expect(f.reviewer.payloads.last, isNot(contains(PluginFixture.poison)));
    expect(f.id, isNot(PluginFixture.toolId));
  });

  test('raw summary result and toolLog cannot leak', () async {
    for (final kind in ['success', 'invalidArguments', 'schema', 'reference']) {
      final f = await PluginFixture.open();
      expect(f.enrolled, isTrue);
      if (kind == 'invalidArguments') f.resultStatus = ToolCallStatus.invalidArguments;
      f.malformedProjection = kind == 'schema';
      f.foreignRef = kind == 'reference';
      final task = await f.runRead();
      expect(f.handlerCalls, 1);
      expect(f.receipt!.result!.summary, PluginFixture.poison);
      expect(jsonEncode(f.loop.bodies), isNot(contains(PluginFixture.poison)));
      expect(jsonEncode(task.payload['toolLog']), isNot(contains(PluginFixture.poison)));
      expect(jsonEncode(task.payload['messages']), isNot(contains(PluginFixture.poison)));
      if (kind != 'success') expect(f.loop.bodies, hasLength(1));
      if (kind == 'success') {
        f.loop.replies.add(LoopReply.sse(sseText('safe follow-up')));
        await f.loop.run(f.agent, await f.loop.start(f.agent, f.loop.profile(),
            conversationId: task.conversationId, prompt: 'Summarize the prior equipment result'));
        expect(f.loop.bodies, hasLength(3));
        expect(jsonEncode(f.loop.bodies.last), isNot(contains(PluginFixture.poison)));
      }
    }
  });

  test('plugin labels cannot clear source facts or classify values', () async {
    for (final failure in ['classification', 'premark', 'postref', 'handler', 'projection']) {
      final f = await PluginFixture.open();
      expect(f.enrolled, isTrue);
      if (failure == 'classification') f.classificationAllowed = false;
      if (failure == 'projection') f.malformedProjection = true;
      if (failure == 'handler') f.failHandler = true;
      if (failure == 'premark') {
        var installed = false;
        f.reviewer.decide = (_) async {
          if (!installed) { f.failFacts(postref: false); installed = true; }
          return const ReviewDecision.allow();
        };
      }
      if (failure == 'postref') f.onHandler = () async => f.failFacts(postref: true);
      final task = await f.runRead();
      expect(f.handlerCalls, failure == 'premark' ? 0 : 1);
      final facts = f.loop.repo.authorizationFacts.readTask(task.id);
      expect(facts.taintState, HostTaintState.tainted,
          reason: 'persist failure or handler/projection refusal cannot clear premark');
      expect(facts.sourceDigests, isNotEmpty);
      expect(f.loop.bodies, hasLength(1));
      expect(jsonEncode(task.payload['messages']), isNot(contains(PluginFixture.poison)));
      if (failure == 'postref' || failure == 'projection' || failure == 'classification') {
        expect(f.receipt!.succeeded, isTrue);
        expect(f.bridge.projectionFor(f.invocationId!, f.receipt!.identityDigest), isNull);
      }
    }
  });

  test('final model payload review remains authoritative', () async {
    for (final revoke in ['model', 'read', 'source', 'binding']) {
      final f = await PluginFixture.open();
      expect(f.enrolled, isTrue);
      final barrier = FixtureBarrier();
      addTearDown(barrier.resume);
      if (revoke == 'model') {
        f.reviewer.decide = (request) async => utf8.decode(request.content)
            .contains(PluginFixture.publicLabel)
            ? const ReviewDecision.block('synthetic final payload denial')
            : const ReviewDecision.allow();
      } else {
        f.beforeSnapshot = () async { if (f.projectionReviewed) await barrier.stop(); };
      }
      final running = f.runRead();
      if (revoke != 'model') {
        await barrier.reached(running);
        if (revoke == 'read') f.allowed = false;
        if (revoke == 'source') f.sourceRevision = 'revoked';
        if (revoke == 'binding') f.bindingRevision = 'revoked';
        barrier.resume();
      }
      await running;
      expect(f.handlerCalls, 1);
      expect(f.receipt!.succeeded, isTrue);
      expect(f.loop.receipts(), hasLength(1));
      expect(f.loop.bodies, hasLength(1), reason: 'no data send after pre-admission revoke');
    }
    // Old result now lives in conversation history, not the latest invocation.
    final f = await PluginFixture.open();
    expect(f.enrolled, isTrue);
    final prior = await f.runRead();
    expect(prior.state, PersonalTaskState.succeeded);
    final identity = f.receipt!.identityDigest;
    f.allowed = false;
    f.loop.replies.add(LoopReply.sse(sseText('must not send prior data')));
    await f.loop.run(f.agent, await f.loop.start(f.agent, f.loop.profile(),
        conversationId: prior.conversationId, prompt: 'Use the prior result'));
    expect(f.loop.bodies, hasLength(2));
    expect(f.receipt!.identityDigest, identity);
    expect(f.handlerCalls, 1);
  });

  test('no port preserves legacy and missing projection fails closed', () async {
    final f = await PluginFixture.open();
    final legacy = PersonalAgent(repository: f.loop.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.loop.ledger), tools: f.loop.tools);
    addTearDown(legacy.close);
    final conversation = await f.loop.repo.createConversation();
    final task = await legacy.startTool(conversationId: conversation.id,
      toolId: f.id, parameters: {'equipment_key': 'e1'});
    expect(task.state, PersonalTaskState.succeeded,
        reason: 'LEGACY_READ_DIAGNOSTIC error=${task.error}; handlerCalls=${f.handlerCalls}; receipts=${f.loop.receipts()}');
    expect(f.handlerCalls, 1);
    // Existing registered but non-enrolled read must not fall through the port.
    final other = await f.loop.repo.createConversation();
    final denied = await f.agent.startTool(conversationId: other.id, toolId: 'read');
    expect(denied.state, PersonalTaskState.failed);
    expect(f.loop.callsOf('read'), 0);
    // Simulate loss of live projection evidence using a fresh concrete port;
    // persisted text/receipts do not recreate read authority.
    final successful = await f.runRead();
    expect(successful.state, PersonalTaskState.succeeded);
    await f.bridge.close();
    f.loop.replies.add(LoopReply.sse(sseText('must not send after close')));
    await f.loop.run(f.agent, await f.loop.start(f.agent, f.loop.profile(),
        conversationId: successful.conversationId));
    expect(f.loop.bodies, hasLength(2));
  });
}
