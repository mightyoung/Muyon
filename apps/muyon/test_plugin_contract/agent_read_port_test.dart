import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';

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
}
