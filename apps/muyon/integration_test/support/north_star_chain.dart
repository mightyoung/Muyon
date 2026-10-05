// Shared driver for the inquiry (Folio) North Star chain.
//
// Used by `test/north_star_inquiry_test.dart` (headless, `flutter test`) and
// `integration_test/north_star_inquiry_test.dart` (device). It drives the real
// host exactly as the assistant page does: the person sends a prompt, every
// model round and every write is confirmed with the digest the host showed,
// and nothing is written before that confirmation.
//
// Model: `MUYON_EVAL_MODEL_ENDPOINT` + `MUYON_EVAL_MODEL_ID` (+ optional
// `MUYON_EVAL_MODEL_KEY`, `MUYON_EVAL_MODEL_LOCATION`), read from
// `--dart-define` first and the process environment second. Without them a
// loopback fixture model scripted by this file answers, and the evidence says
// so: a fixture run is not real-model (M) or real-device (R) evidence.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

const _defineEndpoint = String.fromEnvironment('MUYON_EVAL_MODEL_ENDPOINT');
const _defineModel = String.fromEnvironment('MUYON_EVAL_MODEL_ID');
const _defineKey = String.fromEnvironment('MUYON_EVAL_MODEL_KEY');
const _defineLocation = String.fromEnvironment('MUYON_EVAL_MODEL_LOCATION');
const _defineEvidence = String.fromEnvironment('MUYON_EVIDENCE_OUT');
const _defineDevice = String.fromEnvironment('MUYON_EVAL_DEVICE_LABEL');
const _defineCommit = String.fromEnvironment('MUYON_EVAL_COMMIT');

/// `--dart-define` wins (it is the only channel that reaches an app on a
/// device); the process environment is the fallback for desktop and headless.
String? northStarSetting(String name) {
  final defined = switch (name) {
    'MUYON_EVAL_MODEL_ENDPOINT' => _defineEndpoint,
    'MUYON_EVAL_MODEL_ID' => _defineModel,
    'MUYON_EVAL_MODEL_KEY' => _defineKey,
    'MUYON_EVAL_MODEL_LOCATION' => _defineLocation,
    'MUYON_EVIDENCE_OUT' => _defineEvidence,
    'MUYON_EVAL_DEVICE_LABEL' => _defineDevice,
    'MUYON_EVAL_COMMIT' => _defineCommit,
    _ => '',
  };
  if (defined.trim().isNotEmpty) return defined.trim();
  final env = Platform.environment[name];
  return env == null || env.trim().isEmpty ? null : env.trim();
}


/// Real model settings, or null for the fixture.
class NorthStarModelSettings {
  NorthStarModelSettings._(
    this.endpoint,
    this.modelId,
    this.key,
    this.location,
    this.source,
  );
  final Uri endpoint;
  final String modelId;
  final String? key;
  final ModelLocation location;
  final String source;

  static NorthStarModelSettings? fromEnvironment() {
    final endpoint = northStarSetting('MUYON_EVAL_MODEL_ENDPOINT');
    final model = northStarSetting('MUYON_EVAL_MODEL_ID');
    if (endpoint == null && model == null) return null;
    if (endpoint == null || model == null) {
      throw StateError(
        'Set both MUYON_EVAL_MODEL_ENDPOINT and MUYON_EVAL_MODEL_ID, or neither',
      );
    }
    final uri = Uri.parse(endpoint);
    final named = northStarSetting('MUYON_EVAL_MODEL_LOCATION');
    final location = named != null
        ? ModelLocation.values.byName(named)
        : ['localhost', '127.0.0.1', '::1'].contains(uri.host)
        ? ModelLocation.local
        : ModelLocation.remote;
    return NorthStarModelSettings._(
      uri,
      model,
      northStarSetting('MUYON_EVAL_MODEL_KEY'),
      location,
      _defineEndpoint.trim().isNotEmpty ? 'dart-define' : 'environment',
    );
  }
}

/// Reads the eval key from settings only; it never reaches the platform
/// keychain, the database, the evidence or the log.
class EnvSecretStore implements SecretStore {
  EnvSecretStore(this.reference, this.value);
  final String reference;
  final String? value;
  @override
  Future<String?> read(String reference) async =>
      reference == this.reference ? value : null;
}

const northStarCredentialRef = 'north-star-eval-key';

/// The host reads credentials through `MethodChannelSecretStore`
/// (`com.mightyoung.muyon/secrets`). For the test run that channel is answered
/// by [EnvSecretStore], so the key is used for this run only. Windows keeps
/// credentials through FFI and is not covered by this binding.
void bindEnvSecretStore(EnvSecretStore store) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.mightyoung.muyon/secrets'),
        (call) async => call.method == 'read'
            ? store.read((call.arguments as Map)['reference'] as String)
            : null,
      );
}

void unbindEnvSecretStore() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.mightyoung.muyon/secrets'),
        null,
      );
}

typedef FixtureTurn =
    Map<String, Object?> Function(List<Map<String, Object?>> messages);

/// Loopback OpenAI-compatible endpoint that answers from a script. It only
/// returns protocol JSON the assistant expects; it never touches the host.
class FixtureModelServer {
  FixtureModelServer._(this._server) {
    _server.listen(_handle);
  }
  final HttpServer _server;
  final _turns = <FixtureTurn>[];
  final bodies = <String>[];
  final errors = <String>[];

  static Future<FixtureModelServer> start() async => FixtureModelServer._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}/v1');
  int get pending => _turns.length;

  void script(List<FixtureTurn> turns) => _turns.addAll(turns);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    bodies.add(body);
    try {
      if (_turns.isEmpty) throw StateError('fixture has no scripted turn');
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final messages = [
        for (final m in decoded['messages'] as List)
          Map<String, Object?>.from(m as Map),
      ];
      final reply = _turns.removeAt(0)(messages);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': jsonEncode(reply)},
            },
          ],
        }),
      );
    } catch (error) {
      errors.add('$error');
      request.response.statusCode = 500;
      request.response.write('fixture: $error');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);

  /// The model's system message lists the tools it was offered.
  static List<String> offeredTools(List<Map<String, Object?>> messages) {
    final system = jsonDecode(messages.first['content'] as String) as Map;
    return [for (final t in system['tools'] as List) (t as Map)['toolId']];
  }

  /// Proposes [toolId] only if the host offered it in this request.
  static FixtureTurn tool(String toolId, Map<String, Object?> parameters) =>
      (messages) {
        if (!offeredTools(messages).contains(toolId)) {
          throw StateError('$toolId was not offered to the model');
        }
        return {'type': 'tool', 'toolId': toolId, 'parameters': parameters};
      };

  /// Answers citing the latest tool result's citations of [objectType].
  static FixtureTurn answer(String text, {String? citeType}) => (messages) {
    final last = jsonDecode(messages.last['content'] as String) as Map;
    if (last['trustedToolResult'] == null) {
      throw StateError('answer turn expects a tool result first');
    }
    final citations = [
      for (final c in last['citations'] as List)
        if (citeType == null ||
            ((c as Map)['reference'] as Map)['objectType'] == citeType)
          (c as Map)['citationId'] as String,
    ];
    return {
      'type': 'answer',
      'answer': '[夹具回答，不是真实模型] $text',
      'citationIds': citations.take(3).toList(),
    };
  };
}

/// Ids of the seeded inquiry data.
class NorthStarFixtureData {
  NorthStarFixtureData({
    required this.projectId,
    required this.supplierA,
    required this.supplierB,
    required this.cableItem,
    required this.trayItem,
    required this.cableProduct,
    required this.firstInquiry,
  });
  final String projectId, supplierA, supplierB, cableItem, trayItem;
  final String cableProduct, firstInquiry;
}

/// Seeds through the inquiry module's own Store functions, the same way
/// `inquiry_write_tools_test` and `business_tools_test` do.
NorthStarFixtureData seedInquiry(Store store) {
  Map<String, Object?> supplier(String name) => {
    'name': name,
    'aliases': <String>[],
    'address': null,
    'categories': <String>[],
    'notes': null,
    'merged_into': null,
    'rating': null,
    'rating_note': null,
  };
  Map<String, Object?> item(
    String projectId,
    String name,
    String qty,
    String unitCost,
  ) => {
    'project_id': projectId,
    'category': 'material',
    'product_id': null,
    'name': name,
    'qty': qty,
    'unit': '米',
    'quotation_id': null,
    'unit_cost': unitCost,
    'unit_price': null,
    'notes': null,
  };
  final supplierA = store.save('supplier', supplier('北极星甲电气'));
  final supplierB = store.save('supplier', supplier('北极星乙线缆'));
  final projectId = store.save('project', {
    'code': 'NS-1',
    'name': '北极星验收项目',
    'status': 'active',
    'type': 'market',
    'level': 'A',
    'customer': null,
    'contract_no': null,
    'contract_amount': null,
    'department': null,
    'leader': null,
    'start_date': null,
    'end_date': null,
    'currency': 'CNY',
    'tax_mode': 'included',
    'markup_rate': '0',
    'notes': null,
  });
  final cable = store.save('project_item', item(projectId, '电缆', '100', '11.80'));
  final tray = store.save('project_item', item(projectId, '桥架', '20', '45.00'));
  final inquiry = store.createInquiry(
    projectId,
    '首轮询价',
    itemIds: [cable, tray],
    supplierIds: [supplierA, supplierB],
  );
  const context = (inquirer: '北极星验收', asOf: null);
  for (final (itemId, supplierId, price) in [
    (cable, supplierA, '12.50'),
    (cable, supplierB, '11.80'),
    (tray, supplierA, '45.00'),
    (tray, supplierB, '47.20'),
  ]) {
    store.quoteForInquiry(
      inquiry,
      itemId,
      supplierId,
      price: price,
      context: context,
    );
  }
  return NorthStarFixtureData(
    projectId: projectId,
    supplierA: supplierA,
    supplierB: supplierB,
    cableItem: cable,
    trayItem: tray,
    cableProduct: store.get('project_item', cable)!.data['product_id']!
        as String,
    firstInquiry: inquiry,
  );
}

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
    final settings = NorthStarModelSettings.fromEnvironment();
    final real = settings != null;
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
      if (!real) _fixture = await FixtureModelServer.start();
      if (settings?.key != null) {
        bindEnvSecretStore(EnvSecretStore(northStarCredentialRef, settings!.key));
      }
      await _chain(settings);
      evidence['passed'] = true;
    } catch (error, stack) {
      evidence['passed'] = false;
      evidence['failure'] = '$error';
      evidence['failureStack'] = stack.toString().split('\n').take(8).join('\n');
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
      'suppliers': 2,
      'budgetLines': 2,
      'quotations': _count(store, 'quotation'),
      'inquiries': _count(store, 'inquiry'),
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
      'endpoint': profile.endpoint.toString(),
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
      FixtureModelServer.answer('电缆最低可用报价来自北极星乙线缆。', citeType: 'product'),
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
    final readReceipts = _receipts(host);
    expect(
      readReceipts.where((r) => r['state'] == 'succeeded'),
      isNotEmpty,
      reason: 'Read questions must be answered through a registered tool',
    );
    expect(
      _approvals(host),
      isEmpty,
      reason: 'Read tools never need or receive a write approval',
    );
    expect(_count(store, 'inquiry'), 1, reason: 'Reads must not write');
    _checkReadResults(readReceipts, data);

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
    expect(_count(store, 'inquiry'), 2);
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
      _checkInvariants(host, registered);
      return _snapshot(host);
    });
    evidence['beforeReopen'] = _counts(before);

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
      final after = _snapshot(host);
      evidence['afterReopen'] = _counts(after);
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
        if (phase != 'write' || info == null || toolId != 'inquiry.create_inquiry') {
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
      ..['tools'] = _proposedTools(task)
      ..['answerPreview'] = _preview(task.summary)
      ..['answerReferences'] = host.foundation
          .messages(conversationId)
          .last
          .references
          .length;
    return task;
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
    final inquiries = _count(store, 'inquiry');
    expect(task.payload['toolIdentityDigest'], digest);
    expect(
      _receipts(host).where((r) => r['invocation_id'] == invocation),
      isEmpty,
      reason: 'Nothing ran before approval',
    );
    expect(_approvals(host), isEmpty, reason: 'No approval before the person');
    // A confirmation for any other preview is refused and writes nothing.
    await expectLater(
      host.personalAgent.confirm(task.id, requestDigest: '0' * 64),
      throwsStateError,
    );
    expect(_count(store, 'inquiry'), inquiries);
    expect(
      host.foundation.task(task.id)!.state,
      PersonalTaskState.waitingConfirmation,
    );
    final watch = Stopwatch()..start();
    await host.personalAgent.confirm(task.id, requestDigest: digest);
    entry['toolConfirmations'] = (entry['toolConfirmations'] as int) + 1;
    final approvals = _approvals(host);
    expect(approvals, hasLength(1));
    expect(approvals.single['state'], 'consumed');
    expect(approvals.single['identity_digest'], digest);
    final receipt = _receipts(host)
        .where((r) => r['invocation_id'] == invocation)
        .single;
    expect(receipt['state'], 'succeeded', reason: '${receipt['result_json']}');
    expect(receipt['identity_digest'], digest);
    evidence['write'] = {
      'toolId': call['toolId'],
      'inquiriesBeforeApproval': inquiries,
      'inquiriesAfterApproval': _count(store, 'inquiry'),
      'wrongDigestRefused': true,
      'approvalToResultMs': watch.elapsedMilliseconds,
    };
  }

  /// Whatever the model asked, the registered tools return the module's own
  /// numbers: cable is cheapest at 北极星乙线缆 11.8; budget cost 100×11.80 +
  /// 20×45.00 = 2080. Checked on every matching receipt.
  void _checkReadResults(
    List<Map<String, Object?>> receipts,
    NorthStarFixtureData data,
  ) {
    final checked = <String>[];
    for (final receipt in receipts) {
      final result = jsonDecode(receipt['result_json'] as String) as Map;
      final output = result['data'] as Map?;
      if (output == null) continue;
      if (receipt['tool_id'] == 'inquiry.compare_quotes' &&
          jsonEncode(output).contains(data.cableProduct) == false) {
        final groups = output['result'] as List?;
        final quotes = [
          for (final g in groups ?? const [])
            ...((g as Map)['quotes'] as List),
        ];
        if (quotes.length == 2) {
          final lowest = quotes.singleWhere((q) => (q as Map)['lowest'] == true);
          expect((lowest as Map)['supplier'], '北极星乙线缆');
          expect(double.parse(lowest['price'] as String), 11.8);
          checked.add('compare_quotes');
        }
      }
      if (receipt['tool_id'] == 'inquiry.project_budget' &&
          output['cost'] != null &&
          output['total'] == 2) {
        expect(double.parse(output['cost'] as String), 2080);
        checked.add('project_budget');
      }
    }
    evidence['readResultsChecked'] = checked;
  }

  void _checkInvariants(MuyonHost host, Set<String> registered) {
    final tasks = host.foundation.tasks();
    final modelRounds = <String>[];
    for (final task in tasks) {
      expect(task.state, PersonalTaskState.succeeded, reason: task.id);
      final system =
          jsonDecode(
                ((task.payload['messages'] as List).first as Map)['content']
                    as String,
              )
              as Map;
      for (final offered in system['tools'] as List) {
        expect(registered, contains((offered as Map)['toolId']));
      }
      for (final toolId in _proposedTools(task)) {
        expect(registered, contains(toolId), reason: 'proposed tool');
      }
      modelRounds.add('${task.payload['round']}');
    }
    final receipts = _receipts(host);
    for (final receipt in receipts) {
      expect(registered, contains(receipt['tool_id']));
      expect(receipt['state'], 'succeeded');
    }
    final writes = receipts.where(
      (r) =>
          host.tools.inspect(r['tool_id'] as String)!.accessLevel !=
          ToolAccessLevel.read,
    );
    expect(writes, hasLength(1), reason: 'Exactly one approved write');
    final ledger = _ledger(host);
    final confirmations = _taskEvidence.fold<int>(
      0,
      (n, t) => n + (t['modelConfirmations'] as int),
    );
    expect(ledger, hasLength(confirmations), reason: 'One row per model send');
    for (final row in ledger) {
      expect(row['status'], 'succeeded', reason: '${row['error']}');
      expect(row['caller'], 'assistant');
      expect(row['http_status'], 200);
    }
    if (_fixture != null) {
      expect(_fixture!.errors, isEmpty);
      expect(_fixture!.pending, 0, reason: 'Every scripted turn was used');
      // The ledger digests exactly the bytes the endpoint received.
      expect(
        ledger.map((r) => r['payload_sha256']).toSet(),
        _fixture!.bodies
            .map((b) => sha256.convert(utf8.encode(b)).toString())
            .toSet(),
      );
    }
    evidence['ledger'] = {
      'rows': ledger.length,
      'statuses': _histogram(ledger.map((r) => '${r['status']}')),
      'bytesSent': ledger.fold<int>(0, (n, r) => n + (r['payload_bytes'] as int)),
    };
    evidence['receipts'] = {
      'rows': receipts.length,
      'byTool': _histogram(receipts.map((r) => '${r['tool_id']}')),
    };
  }

  static List<String> _proposedTools(PersonalTask task) => [
    for (final m in task.payload['messages'] as List)
      if ((m as Map)['role'] == 'assistant')
        if (_tryJson(m['content'] as String) case {
          'type': 'tool',
          'toolId': final String id,
        })
          id,
  ];

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static String? _preview(String? text) => text == null
      ? null
      : text.length > 200
      ? '${text.substring(0, 200)}…'
      : text;

  static Map<String, int> _histogram(Iterable<String> values) {
    final out = <String, int>{};
    for (final v in values) {
      out[v] = (out[v] ?? 0) + 1;
    }
    return out;
  }

  static int _count(Store store, String type) =>
      store.db
              .select('SELECT COUNT(*) c FROM $type WHERE deleted=0')
              .first['c']
          as int;

  static List<Map<String, Object?>> _rows(MuyonHost host, String sql) => [
    for (final row in host.foundation.database.raw.select(sql))
      Map<String, Object?>.from(row),
  ];

  static List<Map<String, Object?>> _receipts(MuyonHost host) =>
      _rows(host, 'SELECT * FROM tool_invocation_receipts ORDER BY rowid');
  static List<Map<String, Object?>> _approvals(MuyonHost host) =>
      _rows(host, 'SELECT * FROM tool_approvals ORDER BY rowid');
  static List<Map<String, Object?>> _ledger(MuyonHost host) =>
      _rows(host, 'SELECT * FROM outbound_requests ORDER BY rowid');

  /// Everything that must be identical after close and reopen.
  static Map<String, Object?> _snapshot(MuyonHost host) => {
    'conversations': [
      for (final c in host.foundation.conversations())
        {
          'id': c.id,
          'title': c.title,
          'scope': c.scope.toJson(),
          'messages': [
            for (final m in host.foundation.messages(c.id))
              {
                'id': m.id,
                'role': m.role,
                'content': m.content,
                'references': m.references.map((r) => r.toJson()).toList(),
              },
          ],
        },
    ],
    'tasks': [for (final t in host.foundation.tasks()) t.payload],
    'receipts': _receipts(host),
    'approvals': _approvals(host),
    'outboundRequests': _ledger(host),
  };

  static Map<String, Object?> _counts(Map<String, Object?> snapshot) => {
    'conversations': (snapshot['conversations'] as List).length,
    'messages': (snapshot['conversations'] as List).fold<int>(
      0,
      (n, c) => n + ((c as Map)['messages'] as List).length,
    ),
    'tasks': (snapshot['tasks'] as List).length,
    'receipts': (snapshot['receipts'] as List).length,
    'approvals': (snapshot['approvals'] as List).length,
    'outboundRequests': (snapshot['outboundRequests'] as List).length,
  };
}

/// Writes [evidence] to `MUYON_EVIDENCE_OUT` when set (relative paths resolve
/// against [baseDir] when given) and prints it in numbered chunks so it
/// survives device log line limits. Returns the written path, if any.
Future<String?> publishNorthStarEvidence(
  Map<String, Object?> evidence, {
  String? baseDir,
  void Function(String line) log = print,
}) async {
  final text = jsonEncode(evidence);
  const size = 700;
  final chunks = (text.length + size - 1) ~/ size;
  for (var i = 0; i < chunks; i++) {
    final end = (i + 1) * size < text.length ? (i + 1) * size : text.length;
    log('MUYON_NORTH_STAR_EVIDENCE[${i + 1}/$chunks] ${text.substring(i * size, end)}');
  }
  final out = northStarSetting('MUYON_EVIDENCE_OUT');
  if (out == null) return null;
  final path = File(out).isAbsolute || baseDir == null ? out : '$baseDir/$out';
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
  log('MUYON_NORTH_STAR_EVIDENCE_FILE $path');
  return path;
}
