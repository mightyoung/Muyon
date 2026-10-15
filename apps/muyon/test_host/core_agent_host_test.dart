import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/core_agent_process.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:path/path.dart' as p;

import 'support/host_fixture.dart';
import 'support/offline_model.dart';

class FixedReviewer implements OutboundContentReviewer {
  FixedReviewer(this.decision);
  final ReviewDecision decision;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async => decision;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A missing binary is a load error, never a skipped or passing test.
  requiredBinary();

  test('real facade real Rust registered inquiry roundtrip', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    f.transport.replies.add((_) => toolReply(f.supplierId));
    f.transport.replies.add((body) {
      final messages = body['messages'] as List;
      final tool = messages.where((m) => (m as Map)['role'] == 'tool').single as Map;
      expect(jsonDecode(tool['content'] as String), f.projection);
      return answerReply('Verified selected metadata ${f.selected.objectId}.');
    });
    final task = await f.start();
    // FIRST semantic assertion: compiling stub must fail here, not time out
    // waiting for a frame or model request that the stub never emits.
    expect(task.state, PersonalTaskState.succeeded, reason: 'real core roundtrip must complete');
    expect(task.summary, contains('Verified selected metadata ${f.selected.objectId}.'));
    expect(f.transport.bodies, hasLength(2));
    final firstTools = f.transport.bodies.first['tools'] as List;
    expect(firstTools, hasLength(1));
    expect((firstTools.single as Map)['function']['name'], 'inquiry__object');
    expect(f.transport.bodies.last['tools'] ?? [], isEmpty);
    final second = f.transport.bodies.last['messages'] as List;
    final assistant = second.where((m) => (m as Map)['tool_calls'] != null).single as Map;
    final call = (assistant['tool_calls'] as List).single as Map;
    expect(call['id'], modelCallId);
    expect(call['function']['name'], 'inquiry__object');
    expect(jsonDecode(call['function']['arguments'] as String), {'type': 'supplier', 'id': f.supplierId});
    final toolMessage = second.where((m) => (m as Map)['role'] == 'tool').single as Map;
    expect(toolMessage['tool_call_id'], modelCallId);
    expect(jsonDecode(toolMessage['content'] as String), f.projection);

    expect(f.receiptRows, hasLength(1));
    final invocation = f.receiptRows.single['invocation_id'] as String;
    expect(invocation, isNot(modelCallId));
    final receipt = f.host.tools.receiptFor(invocation)!;
    expect(receipt.succeeded, isTrue);
    expect(receipt.toolId, 'inquiry.object');
    expect(receipt.identityDigest, isNotEmpty);
    expect(receipt.result!.executionId, invocation);
    expect(receipt.result!.data['record'], containsPair('name', privateName));
    expect(receipt.result!.data['record'], containsPair('notes', privateNotes));
    expect(receipt.result!.objectRefs, [f.selected]);
    expect(f.host.inquiry!.runtime.state.store.get('supplier', f.supplierId)!.version, 1);

    final hostFrames = f.frames('host.bin');
    final coreFrames = f.frames('core.bin');
    expect(coreFrames.where((frame) => frame['kind'] == 'invoke'), hasLength(1));
    expect(coreFrames.where((frame) => frame['kind'] == 'model_request'), hasLength(2));
    final prepared = coreFrames.singleWhere((frame) => frame['kind'] == 'prepare');
    final invoked = coreFrames.singleWhere((frame) => frame['kind'] == 'invoke');
    expect(prepared['call_id'], modelCallId);
    expect(invoked['invocation_id'], invocation);
    expect(invoked['call_id'], modelCallId);
    final result = hostFrames.singleWhere((frame) => frame['kind'] == 'tool_result');
    expect(result['projection'], f.projection);
    expect(result['invocation_id'], invocation);
    expect(result['prepared_ref'], invoked['prepared_ref']);
    expect(result['receipt_ref'], isNotEmpty);
    final terminal = coreFrames.singleWhere((frame) => frame['kind'] == 'terminal');
    expect(terminal['status'], 'completed');
    expect(terminal['model_turns'], 2);
    expect(terminal['tool_invocations'], 1);
    expect(terminal['receipt_ref'], result['receipt_ref']);
    expect(terminal['projection'], f.projection);
    final rows = f.host.outbound.recent();
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row['authorization_source'], 'mode_auto');
      expect(row['status'], 'succeeded');
      expect(row['request_digest'], isNotEmpty);
      final review = f.host.foundation.database.raw.select('SELECT * FROM assistant_review_decisions WHERE id=?', [row['review_decision_id']]).single;
      expect(review['payload_digest'], row['payload_sha256']);
    }
    expect(f.secrets.reads, 2);
    f.assertPrivateBoundary();
    f.assertReaped();
    expect(Directory(f.stateRoot).listSync(recursive: true).where((entry) => p.basename(entry.path) == 'effects.db'), isEmpty);
  });

  test('disabled configuration preserves legacy and never launches Rust', () async {
    final f = await HostFixture.open(enabled: false);
    addTearDown(f.dispose);
    f.transport.replies.add((_) => answerReply('legacy remains available'));
    final task = await f.start();
    expect(task.state, PersonalTaskState.succeeded);
    expect(task.summary, contains('legacy remains available'));
    expect(f.evidence.existsSync(), isFalse);
    expect(f.transport.bodies, hasLength(1));
  });

  test('invalid enabled config fails before transport and never falls back', () async {
    final root = Directory.systemTemp.createTempSync('core-invalid-');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final paths in [('relative-binary', root.path), (requiredBinary(), 'relative-state')]) {
      await expectLater(MuyonHost.open(root.path,
        coreAgentProcess: CoreAgentProcessConfig(enabled: true, executablePath: paths.$1, stateRoot: paths.$2),
        modelClientFactory: () => throw StateError('unexpected_model_transport'),
      ), throwsA(isA<StateError>().having((e) => e.message, 'code', 'core_config_invalid')));
    }
  });

  test('unsupported profile fails without capability probing or legacy fallback', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final task = await f.start(withProfile: f.profile(native: false));
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('core_profile_unsupported'));
    expect(f.transport.bodies, isEmpty);
    expect(f.receiptRows, isEmpty);
  });

  test('scope denial never invokes the real registered tool', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    f.transport.replies.add((_) => toolReply(f.otherId));
    final task = await f.start();
    expect(task.state, PersonalTaskState.failed);
    expect(f.transport.bodies, hasLength(1));
    expect(f.receiptRows, isEmpty);
    expect(f.frames('core.bin').where((frame) => frame['kind'] == 'invoke'), isEmpty);
    f.assertReaped();
  });

  for (final confirmation in [true, false]) {
    test('effective model review ${confirmation ? 'confirmation' : 'denial'} sends nothing', () async {
      final f = await HostFixture.open(modelReviewer: FixedReviewer(confirmation
        ? const ReviewDecision.confirm('synthetic confirmation')
        : const ReviewDecision.block('synthetic denial')));
      addTearDown(f.dispose);
      final task = await f.start();
      expect(task.state, PersonalTaskState.failed);
      if (confirmation) expect(task.error, contains('core_confirmation_required'));
      expect(f.transport.bodies, isEmpty);
      expect(f.host.outbound.recent(), isEmpty);
      expect(f.receiptRows, isEmpty);
      f.assertReaped();
    });
  }

  test('remote profile confirmation requirement cannot auto approve', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final task = await f.start(withProfile: f.profile(remote: true));
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('core_confirmation_required'));
    expect(f.transport.bodies, isEmpty);
    expect(f.receiptRows, isEmpty);
  });

  for (final extra in [
    <String, Object?>{'approved': true}, {'scope': 'global'}, {'credentialRef': credentialRefCanary},
  ]) {
    test('forged model arguments ${extra.keys.single} reject before invoke', () async {
      final f = await HostFixture.open();
      addTearDown(f.dispose);
      f.transport.replies.add((_) => toolReply(f.supplierId, extra: extra));
      final task = await f.start();
      expect(task.state, PersonalTaskState.failed);
      expect(f.transport.bodies, hasLength(1));
      expect(f.receiptRows, isEmpty);
      expect(f.frames('core.bin').where((frame) => frame['kind'] == 'invoke'), isEmpty);
    });
  }

  for (final finish in ['stop', 'length', 'content_filter']) {
    test('incomplete or mismatched tool finish $finish never invokes', () async {
      final f = await HostFixture.open();
      addTearDown(f.dispose);
      f.transport.replies.add((_) => toolReply(f.supplierId, finish: finish));
      final task = await f.start();
      expect(task.state, PersonalTaskState.failed);
      expect(f.receiptRows, isEmpty);
      expect(f.transport.bodies, hasLength(1));
    });
  }

  test('a second tool proposal stops without another invocation', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    f.transport.replies.addAll([(_) => toolReply(f.supplierId), (_) => toolReply(f.supplierId)]);
    final task = await f.start();
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('unsupported_tool_turn'));
    expect(f.transport.bodies, hasLength(2));
    expect(f.receiptRows, hasLength(1));
    expect(f.host.tools.receiptFor(f.receiptRows.single['invocation_id'] as String)!.succeeded, isTrue);
    f.assertReaped();
  });

  test('cancel while first model pending settles and reaps child', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final entered = Completer<void>();
    final release = Completer<String>();
    addTearDown(() { if (!release.isCompleted) release.complete(answerReply('late')); });
    f.transport.replies.add((_) { entered.complete(); return release.future; });
    final pending = f.start();
    await entered.future;
    final task = f.host.foundation.tasks().single;
    await f.host.personalAgent.cancel(task.id);
    final result = await pending;
    expect(result.state, PersonalTaskState.cancelled);
    expect(f.transport.bodies, hasLength(1));
    expect(f.receiptRows, isEmpty);
    expect(f.transport.clients.every((client) => client.closed), isTrue);
    f.assertReaped();
  });

  test('one active core session rejects a concurrent start without another process', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final entered = Completer<void>();
    final release = Completer<String>();
    addTearDown(() { if (!release.isCompleted) release.complete(answerReply('late')); });
    f.transport.replies.add((_) { entered.complete(); return release.future; });
    final pending = f.start();
    await entered.future;
    final second = await f.start(prompt: 'Concurrent request');
    expect(second.state, PersonalTaskState.failed);
    expect(second.error, contains('core_busy'));
    expect(f.transport.bodies, hasLength(1));
    final first = f.host.foundation.tasks().singleWhere((task) => task.id != second.id);
    await f.host.personalAgent.cancel(first.id);
    expect((await pending).state, PersonalTaskState.cancelled);
    f.assertReaped();
  });

  test('close while model pending interrupts task and reaps actual child', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final entered = Completer<void>();
    final release = Completer<String>();
    addTearDown(() { if (!release.isCompleted) release.complete(answerReply('late')); });
    f.transport.replies.add((_) { entered.complete(); return release.future; });
    final pending = f.start();
    await entered.future;
    // PersonalAgent.close preserves the readable repository for assertions.
    await f.host.personalAgent.close();
    final result = await pending;
    expect(result.state, PersonalTaskState.interrupted);
    expect(f.transport.bodies, hasLength(1));
    expect(f.receiptRows, isEmpty);
    f.assertReaped();
  });

  test('cancel during second model preserves original successful receipt', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final entered = Completer<void>();
    final release = Completer<String>();
    addTearDown(() { if (!release.isCompleted) release.complete(answerReply('late')); });
    f.transport.replies.add((_) => toolReply(f.supplierId));
    f.transport.replies.add((body) {
      final message = (body['messages'] as List).singleWhere((m) => (m as Map)['role'] == 'tool') as Map;
      expect(jsonDecode(message['content'] as String), f.projection);
      entered.complete(); return release.future;
    });
    final pending = f.start();
    await entered.future;
    final before = f.receiptRows.single;
    await f.host.personalAgent.cancel(f.host.foundation.tasks().single.id);
    expect((await pending).state, PersonalTaskState.cancelled);
    expect(f.receiptRows, [before]);
    final receipt = f.host.tools.receiptFor(before['invocation_id'] as String)!;
    expect(receipt.succeeded, isTrue);
    expect(receipt.result!.data['record'], containsPair('notes', privateNotes));
    expect(f.transport.bodies, hasLength(2));
    final terminal = f.frames('core.bin').lastWhere((frame) => frame['kind'] == 'terminal');
    expect(terminal['projection'], f.projection);
    expect(terminal['receipt_ref'], isNotNull);
    f.assertPrivateBoundary();
    f.assertReaped();
  });

  test('core continuations reject explicitly even after host restart', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    f.transport.replies.add((_) => answerReply('completed'));
    final task = await f.start();
    expect(task.state, PersonalTaskState.succeeded);
    Future<void> unsupported() async {
      for (final action in <Future<dynamic> Function()>[
        () => f.host.personalAgent.resume(task.id),
        () => f.host.personalAgent.pause(task.id),
        () => f.host.personalAgent.compactNow(task.id),
        () => f.host.personalAgent.confirm(task.id, requestDigest: 'unsupported'),
      ]) {
        await expectLater(action(), throwsA(isA<StateError>().having((e) => '${e.message}', 'code', contains('core_'))));
      }
    }
    await unsupported();
    await f.host.close();
    f.host = await MuyonHost.open(p.join(f.root.path, 'business'),
      coreAgentProcess: CoreAgentProcessConfig(enabled: true, executablePath: f.launcher, stateRoot: f.stateRoot),
      modelClientFactory: f.transport.client,
    );
    await unsupported();
    expect(f.transport.bodies, hasLength(1));
    expect(f.host.foundation.tasks(), hasLength(1));
  });
}
