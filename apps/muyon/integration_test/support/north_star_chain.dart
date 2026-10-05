// Shared driver for the inquiry (Folio) North Star chain.
//
// Used by `test/north_star_inquiry_test.dart` (headless, `flutter test`) and
// `integration_test/north_star_inquiry_test.dart` (device). It drives the real
// host exactly as the assistant page does: the person sends a prompt, every
// model round and every write is confirmed with the digest the host showed,
// and nothing is written before that confirmation.
//
// Model: `MUYON_EVAL_REAL=1` with `MUYON_EVAL_MODEL_ENDPOINT` +
// `MUYON_EVAL_MODEL_ID` (+ optional `MUYON_EVAL_MODEL_KEY`,
// `MUYON_EVAL_MODEL_LOCATION`), read from `--dart-define` first and the
// process environment second. Without the switch a
// loopback fixture model scripted by this driver answers, and the evidence
// says so: a fixture run is not real-model (M) or real-device (R) evidence.
// See docs/implementation/north-star-inquiry-runbook.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import 'north_star_checks.dart';
import 'north_star_fixture_model.dart';
import 'north_star_records.dart';
import 'north_star_seed.dart';
import 'north_star_settings.dart';

export 'north_star_evidence.dart' show publishNorthStarEvidence;

/// Runs the chain against a fresh data directory [rootPath] and fills
/// [evidence]. Throws (after recording the failure) when an invariant breaks.
class NorthStarInquiryChain {
  NorthStarInquiryChain({
    required this.rootPath,
    required this.evidence,
    this.binding = 'flutter_test',
  });
  final String rootPath;
  final Map<String, Object?> evidence;
  final String binding;

  final _steps = <Map<String, Object?>>[];
  final _taskEvidence = <Map<String, Object?>>[];
  final _clock = Stopwatch();
  MuyonHost? _host;
  FixtureModelServer? _fixture;

  Future<T> _step<T>(String name, Future<T> Function() body) async {
    final watch = Stopwatch()..start();
    final entry = <String, Object?>{'name': name};
    _steps.add(entry);
    try {
      final result = await body();
      entry['ok'] = true;
      return result;
    } catch (error) {
      entry['ok'] = false;
      rethrow;
    } finally {
      entry['ms'] = watch.elapsedMilliseconds;
    }
  }

  Future<void> run() async {
    _clock.start();
    // Decided before parsing so a bad configuration still yields evidence of
    // the run that was asked for.
    final real = NorthStarModelSettings.realRequested;
    if (!real && NorthStarModelSettings.modelVariablesSet) {
      debugPrint(
        'North Star: model variables found but MUYON_EVAL_REAL=1 is not set; '
        'running with the fixture model.',
      );
    }
    NorthStarModelSettings? settings;
    evidence
      ..['kind'] = 'muyon-north-star-inquiry'
      ..['schema'] = 1
      ..['startedAt'] = DateTime.now().toUtc().toIso8601String()
      ..['evidenceClass'] = real ? 'real-model' : 'fixture'
      ..['realModelEvidence'] = real
      ..['note'] = real
          ? 'Real model endpoint; assertions are invariants only (registered '
                'tools, write only after approval, survives reopen, ledger rows).'
          : 'Loopback fixture model scripted by the test. NOT real-model (M) '
                'evidence and, unless run on a device, NOT real-device (R) '
                'evidence. It proves the host wiring: confirmations, tool '
                'registry, approval-gated write, ledger and reopen persistence.'
      ..['commit'] = northStarSetting('MUYON_EVAL_COMMIT')
      ..['device'] = {
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'dart': Platform.version.split(' ').first,
        'processors': Platform.numberOfProcessors,
        'label': northStarSetting('MUYON_EVAL_DEVICE_LABEL'),
        'binding': binding,
      }
      ..['steps'] = _steps
      ..['tasks'] = _taskEvidence;
    try {
      settings = NorthStarModelSettings.fromEnvironment();
      if (!real) _fixture = await FixtureModelServer.start();
      if (settings?.key != null) {
        bindEnvSecretStore(
          EnvSecretStore(northStarCredentialRef, settings!.key),
        );
      }
      await _chain(settings);
      evidence['passed'] = true;
    } catch (error, stack) {
      evidence['passed'] = false;
      evidence['failure'] = '$error';
      evidence['failureStack'] = stack
          .toString()
          .split('\n')
          .take(8)
          .join('\n');
      rethrow;
    } finally {
      try {
        await _host?.close();
      } catch (_) {}
      await _fixture?.close();
      if (settings?.key != null) unbindEnvSecretStore();
      evidence['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      evidence['totalMs'] = _clock.elapsedMilliseconds;
    }
  }

  Future<void> _chain(NorthStarModelSettings? settings) async {
    var host = await _step('host.open', () => MuyonHost.open(rootPath));
    _host = host;
    await _step('inquiry.activate', () async {
      await host.activateInquiry();
      expect(host.inquiry, isNotNull, reason: host.inquiryError);
    });
    final store = host.inquiry!.runtime.state.store;
    final data = await _step('inquiry.seed', () async => seedInquiry(store));
    evidence['seed'] = {
      'suppliers': countRows(store, 'supplier'),
      'budgetLines': countRows(store, 'project_item'),
      'quotations': countRows(store, 'quotation'),
      'inquiries': countRows(store, 'inquiry'),
    };

    final profile = await _step('model.profile', () async {
      final ModelProfile profile;
      if (settings == null) {
        profile = ModelProfile(
          id: 'north-star-fixture',
          endpoint: _fixture!.endpoint,
          location: ModelLocation.local,
          modelId: 'north-star-fixture',
          endpointIdentity: 'north-star loopback fixture',
        );
      } else {
        profile = ModelProfile(
          id: 'north-star-eval',
          endpoint: settings.endpoint,
          location: settings.location,
          modelId: settings.modelId,
          endpointIdentity: 'north-star eval ${settings.endpoint.host}',
          credentialRef: settings.key == null ? null : northStarCredentialRef,
        );
      }
      // Saved as the profile page does, then read back like the assistant.
      final profiles = ProfileRepository(host.workspaces);
      await profiles.save(profile);
      await host.workspaces.setSetting('activeModelProfileId', profile.id);
      return profiles.all().singleWhere((p) => p.id == profile.id);
    });
    evidence['model'] = {
      'endpoint': evidenceEndpoint(profile.endpoint),
      'modelId': profile.modelId,
      'location': profile.location.name,
      'credential': profile.credentialRef == null ? 'none' : 'env (not stored)',
      if (settings != null) 'configuredBy': settings.source,
      if (settings == null) 'fixture': true,
    };

    final registered = {for (final t in host.tools.list()) t.descriptor.toolId};
    evidence['registeredTools'] = registered.length;

    // Read-only questions in the main (global) conversation.
    final main = await host.foundation.createConversation(title: '主对话');
    _fixture?.script([
      FixtureModelServer.tool('inquiry.compare_quotes', {
        'product_id': data.cableProduct,
      }),
      FixtureModelServer.answer('电缆最低可用报价来自北极星乙线缆。', citeType: 'quotation'),
    ]);
    final compare = await _step(
      'assistant.read.compare_quotes',
      () => _drive(
        host,
        phase: 'read',
        conversationId: main.id,
        profile: profile,
        prompt:
            '比较物料「电缆」（product_id=${data.cableProduct}）各供应商的报价，'
            '哪家最低？请用已注册工具查询，不要修改数据。',
      ),
    );
    _fixture?.script([
      FixtureModelServer.tool('inquiry.project_budget', {
        'project_id': data.projectId,
      }),
      FixtureModelServer.answer('项目成本合计见预算明细。', citeType: 'project'),
    ]);
    final budget = await _step(
      'assistant.read.project_budget',
      () => _drive(
        host,
        phase: 'read',
        conversationId: main.id,
        profile: profile,
        prompt:
            '项目「北极星验收项目」（project_id=${data.projectId}）的成本预算是多少？'
            '请用已注册工具查询，不要修改数据。',
      ),
    );
    for (final task in [compare, budget]) {
      expect(task.state, PersonalTaskState.succeeded, reason: task.error);
    }
    if (settings == null) {
      for (final entry in _taskEvidence) {
        expect(
          entry['answerReferences'],
          greaterThan(0),
          reason: 'Fixture answer for ${entry['id']} cites its tool result',
        );
      }
    }
    final readReceipts = receiptRows(host);
    expect(
      approvalRows(host),
      isEmpty,
      reason: 'Read tools never need or receive a write approval',
    );
    expect(countRows(store, 'inquiry'), 1, reason: 'Reads must not write');
    checkReadResults(readReceipts, evidence, requireAll: settings == null);

    // Write: a topic conversation over the records the person selected.
    final selected = await _step('scope.select', () async {
      final ids = {
        data.projectId,
        data.cableItem,
        data.trayItem,
        data.supplierA,
        data.supplierB,
      };
      final all = await resolveAssistantScope(
        host,
        const AssistantScope.global(),
      );
      return [
        for (final ref in all.objects)
          if (ref.moduleId == 'inquiry' && ids.contains(ref.objectId)) ref,
      ];
    });
    expect(selected, hasLength(5));
    final topic = await host.foundation.createConversation(
      title: '专题对话',
      scope: AssistantScope.selectedObjects(selected),
    );
    const title = '北极星复核询价';
    _fixture?.script([
      FixtureModelServer.tool('inquiry.create_inquiry', {
        'project_id': data.projectId,
        'title': title,
        'item_ids': [data.cableItem],
        'supplier_ids': [data.supplierA, data.supplierB],
      }),
      FixtureModelServer.answer('已创建询价单「$title」。', citeType: 'inquiry'),
    ]);
    final write = await _step(
      'assistant.write.create_inquiry',
      () => _drive(
        host,
        phase: 'write',
        conversationId: topic.id,
        profile: profile,
        store: store,
        prompt:
            '为项目（project_id=${data.projectId}）的预算行「电缆」'
            '（item_id=${data.cableItem}）向两家供应商（supplier_ids='
            '${data.supplierA},${data.supplierB}）发起一张新的询价单，标题「$title」。'
            '使用工具 inquiry.create_inquiry，参数只用这里给出的 id。',
      ),
    );
    expect(write.state, PersonalTaskState.succeeded, reason: write.error);
    final created = write.objectRefs
        .where((r) => r.moduleId == 'inquiry' && r.objectType == 'inquiry')
        .toList();
    expect(
      created,
      hasLength(1),
      reason: 'The write result must reference the created inquiry',
    );
    final inquiryId = created.single.objectId;
    final record = store.get('inquiry', inquiryId);
    expect(record, isNotNull);
    expect(record!.data['project_id'], data.projectId);
    expect(record.data['status'], 'open');
    if (settings == null) expect(record.data['title'], title);
    expect(countRows(store, 'inquiry'), 2);
    expect(evidence['write'], isNotNull, reason: 'The write was approved');
    final lastAnswer = host.foundation.messages(topic.id).last;
    expect(lastAnswer.role, 'assistant');
    (evidence['write'] as Map)['inquiryId'] = inquiryId;
    (evidence['write'] as Map)['answerCitesInquiry'] = lastAnswer.references
        .any((r) => r.objectId == inquiryId);
    if (settings == null) {
      expect(lastAnswer.references.map((r) => r.objectId), contains(inquiryId));
    }

    // Invariants over everything this run recorded.
    final before = await _step('invariants', () async {
      checkInvariants(
        host,
        registered,
        taskEvidence: _taskEvidence,
        fixture: _fixture,
        evidence: evidence,
      );
      return recordSnapshot(host);
    });
    evidence['beforeReopen'] = snapshotCounts(before);

    await _step('host.close', host.close);
    _host = null;
    host = await _step('host.reopen', () => MuyonHost.open(rootPath));
    _host = host;
    await _step('reopen.verify', () async {
      await host.activateInquiry();
      final reopenedStore = host.inquiry!.runtime.state.store;
      final reopened = reopenedStore.get('inquiry', inquiryId);
      expect(reopened, isNotNull, reason: 'Written inquiry survives reopen');
      expect(reopened!.data, record.data);
      final after = recordSnapshot(host);
      evidence['afterReopen'] = snapshotCounts(after);
      for (final key in before.keys) {
        expect(
          jsonEncode(after[key]),
          jsonEncode(before[key]),
          reason: '$key changed across close/reopen',
        );
      }
      expect(
        ProfileRepository(host.workspaces).all().map((p) => p.id),
        contains(profile.id),
      );
      evidence['reopenIdentical'] = true;
    });
  }

  /// Sends [prompt] and confirms like the assistant page: each model round
  /// with its digest; in the write phase, the write once, after checking that
  /// nothing was written before approval. Never confirms a write while reading.
  Future<PersonalTask> _drive(
    MuyonHost host, {
    required String phase,
    required String conversationId,
    required ModelProfile profile,
    required String prompt,
    Store? store,
  }) async {
    final agent = host.personalAgent;
    final receiptsBefore = receiptRows(host).length;
    var task = await agent.start(
      conversationId: conversationId,
      prompt: prompt,
      profile: profile,
    );
    final entry = <String, Object?>{
      'phase': phase,
      'id': task.id,
      'modelConfirmations': 0,
      'toolConfirmations': 0,
    };
    _taskEvidence.add(entry);
    var guard = 0;
    while (!task.terminal) {
      if (++guard > 3 * agent.maxRounds) {
        throw StateError('Task ${task.id} did not settle (${task.state})');
      }
      if (task.state != PersonalTaskState.waitingConfirmation) {
        throw StateError(
          'Unexpected ${task.state}/${task.stage} after a confirmation',
        );
      }
      final digest = task.payload['requestDigest'] as String;
      if (task.stage == 'model') {
        final preview = task.payload['preview'] as Map;
        expect(preview['endpoint'], profile.endpoint.toString());
        expect(PersonalAgent.digest(preview), digest);
        await agent.confirm(task.id, requestDigest: digest);
        entry['modelConfirmations'] = (entry['modelConfirmations'] as int) + 1;
      } else {
        final call = task.payload['toolCall'] as Map;
        final toolId = call['toolId'] as String;
        final info = host.tools.inspect(toolId);
        if (phase != 'write' ||
            info == null ||
            toolId != 'inquiry.create_inquiry') {
          await agent.cancel(task.id);
          throw StateError(
            'Model proposed $toolId in the $phase phase; not approved',
          );
        }
        await _approveWrite(host, task, store!, entry);
      }
      task = host.foundation.task(task.id)!;
    }
    entry
      ..['state'] = task.state.name
      ..['stage'] = task.stage
      ..['rounds'] = task.payload['round']
      ..['error'] = task.error
      ..['tools'] = proposedTools(task)
      ..['answerPreview'] = previewText(task.summary)
      ..['answerReferences'] = host.foundation
          .messages(conversationId)
          .last
          .references
          .length;
    if (phase == 'read') _requireReadTool(host, task, entry, receiptsBefore);
    return task;
  }

  /// Each read question on its own must have gone through a registered
  /// read-only tool that succeeded; an answer from the model alone fails the
  /// run, so it can never be booked as evidence that tools answered.
  void _requireReadTool(
    MuyonHost host,
    PersonalTask task,
    Map<String, Object?> entry,
    int receiptsBefore,
  ) {
    final reads = [
      for (final r in receiptRows(host).skip(receiptsBefore))
        if (r['state'] == 'succeeded' &&
            host.tools.inspect(r['tool_id'] as String)?.accessLevel ==
                ToolAccessLevel.read)
          r['tool_id'] as String,
    ];
    entry['readReceipts'] = reads;
    if (proposedTools(task).isEmpty || reads.isEmpty) {
      throw StateError(
        'Read question ${task.id} was answered without a registered read '
        'tool (proposed ${proposedTools(task)}, succeeded read receipts '
        '$reads)',
      );
    }
  }

  Future<void> _approveWrite(
    MuyonHost host,
    PersonalTask task,
    Store store,
    Map<String, Object?> entry,
  ) async {
    final call = task.payload['toolCall'] as Map;
    final invocation = call['invocationId'] as String;
    final digest = task.payload['requestDigest'] as String;
    final inquiries = countRows(store, 'inquiry');
    expect(task.payload['toolIdentityDigest'], digest);
    expect(
      receiptRows(host).where((r) => r['invocation_id'] == invocation),
      isEmpty,
      reason: 'Nothing ran before approval',
    );
    expect(
      approvalRows(host),
      isEmpty,
      reason: 'No approval before the person',
    );
    // A confirmation for any other preview is refused and writes nothing.
    await expectLater(
      host.personalAgent.confirm(task.id, requestDigest: '0' * 64),
      throwsStateError,
    );
    expect(countRows(store, 'inquiry'), inquiries);
    expect(
      host.foundation.task(task.id)!.state,
      PersonalTaskState.waitingConfirmation,
    );
    final watch = Stopwatch()..start();
    await host.personalAgent.confirm(task.id, requestDigest: digest);
    entry['toolConfirmations'] = (entry['toolConfirmations'] as int) + 1;
    final approvals = approvalRows(host);
    expect(approvals, hasLength(1));
    expect(approvals.single['state'], 'consumed');
    expect(approvals.single['identity_digest'], digest);
    final receipt = receiptRows(host)
        .where((r) => r['invocation_id'] == invocation)
        .single;
    expect(receipt['state'], 'succeeded', reason: '${receipt['result_json']}');
    expect(receipt['identity_digest'], digest);
    final approvalMs = watch.elapsedMilliseconds;
    final afterApproval = countRows(store, 'inquiry');
    // The approval is single-use: confirming the same preview again is
    // refused and writes nothing more.
    await expectLater(
      host.personalAgent.confirm(task.id, requestDigest: digest),
      throwsStateError,
    );
    expect(countRows(store, 'inquiry'), afterApproval);
    expect(approvalRows(host), hasLength(1));
    expect(
      receiptRows(host).where((r) => r['tool_id'] == call['toolId']),
      hasLength(1),
    );
    evidence['write'] = {
      'toolId': call['toolId'],
      'inquiriesBeforeApproval': inquiries,
      'inquiriesAfterApproval': afterApproval,
      'wrongDigestRefused': true,
      'repeatConfirmRefused': true,
      'approvalToResultMs': approvalMs,
    };
  }
}
