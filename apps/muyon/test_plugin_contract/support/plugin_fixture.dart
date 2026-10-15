import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grant_store.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/platform/grants/host_model_authorization.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/platform/plugin_contract/process.dart';
import 'package:muyon/platform/plugin_contract/read_bridge.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../../test/support/agent_loop_fixture.dart';

/// Real host components with synthetic values and a local scripted model endpoint.
/// No bridge/process/registry/Agent implementation is replaced by a mock.
class PluginFixture {
  PluginFixture._(this.loop);
  final LoopFixture loop;
  static const toolId = 'equipment_loan.inspect_equipment';
  static const poison = 'RAW_PROVIDER_SECRET_MUST_NOT_REACH_MODEL';
  static const publicLabel = 'synthetic drill';
  static const equipment = ObjectRef(
    moduleId: 'equipment_loan', objectType: 'equipment', objectId: 'e1',
    revisionRef: '1',
  );
  final events = <String>[];
  late final PluginContractProcess process;
  late final PluginReadBridge bridge;
  late final PersonalAgent agent;
  late final RecordingModelReviewer reviewer;
  var handlerCalls = 0;
  late String id;
  late String operation;
  late ObjectRef equipmentRef;
  late Map<String, Object?> bundle;
  late PluginReadBinding binding;
  bool enrolled = false;
  bool allowed = true;
  bool classificationAllowed = true;
  bool projectionReviewed = false;
  bool failHandler = false;
  bool malformedProjection = false;
  bool foreignRef = false;
  String sourceRevision = 's1';
  String bindingRevision = 'b1';
  Future<void> Function()? beforeSnapshot;
  Future<void> Function()? onHandler;
  Future<void> Function()? onProjectionReview;
  ToolCallStatus resultStatus = ToolCallStatus.succeeded;
  var snapshotRevision = 'a1';
  String? invocationId;
  ToolReceipt? get receipt => invocationId == null
      ? null : loop.tools.receiptFor(invocationId!);

  static Future<PluginFixture> open({bool renamed = false}) async {
    final f = PluginFixture._(await LoopFixture.open());
    // Fixed seed produces names without any production-name allowlist.
    final seed = (0x1357 * 1664525 + 1013904223) & 0xffffffff;
    final module = renamed ? 'module_${seed.toRadixString(16)}' : 'equipment_loan';
    final operationName = renamed ? 'read_${seed.toRadixString(16)}' : 'inspect_equipment';
    final equipmentType = renamed ? 'asset' : 'equipment';
    f.id = '$module.$operationName';
    f.operation = '$module/$operationName@1';
    f.equipmentRef = ObjectRef(moduleId: module, objectType: equipmentType,
      objectId: 'e1', revisionRef: '1');
    f.loop.objects = [f.equipmentRef];
    f.loop.tools.register(
      providerId: 'synthetic-host',
      descriptor: ToolDescriptor(
        toolId: f.id, moduleId: module, effect: ToolEffect.read,
        description: 'Inspect synthetic equipment in the selected scope',
        parameterSchema: {
          'type': 'object',
          'properties': {
            'equipment_key': {'type': 'string'},
            'include_loans': {'type': 'boolean'},
          },
          'required': ['equipment_key'], 'additionalProperties': false,
        },
      ),
      handler: (call) async {
        f.events.add('handler');
        f.handlerCalls++;
        f.invocationId = call.request.invocationId;
        await f.onHandler?.call();
        if (f.failHandler) throw StateError('synthetic handler refusal');
        return ToolCallResult(
          status: f.resultStatus, summary: poison,
          data: {'label': publicLabel, 'private': poison},
          objectRefs: [f.foreignRef
            ? const ObjectRef(moduleId: 'foreign', objectType: 'secret', objectId: 'x')
            : f.equipmentRef],
        );
      },
    );
    f.process = PluginContractProcess(
      executable: Platform.environment['MUYON_PLUGIN_CONTRACT_BIN'] ?? '',
    );
    f.bridge = PluginReadBridge(
      registry: f.loop.tools, repository: f.loop.repo, process: f.process,
      snapshot: (request) async {
        await f.beforeSnapshot?.call();
        final revision = f.snapshotRevision;
        final binding = f.bindingRevision;
        final source = f.sourceRevision;
        return PluginHostSnapshot(
          revision: revision, allowed: f.allowed, bindingRevision: binding,
          sourceRevision: source, ruleRevision: 'r1',
          scope: request.scope, objects: f.loop.objects,
          requireCurrent: () {
            if (!f.allowed || revision != f.snapshotRevision ||
                binding != f.bindingRevision || source != f.sourceRevision) {
              throw StateError('synthetic_authority_revoked');
            }
          },
        );
      },
      reviewProjection: (value, facts) async {
        f.events.add('projection-review');
        await f.onProjectionReview?.call();
        f.projectionReviewed = true;
        expect(f.receipt?.succeeded, isTrue,
            reason: 'projection must refer to the original recorded result');
        return f.classificationAllowed && value['label'] == publicLabel &&
            !jsonEncode(value).contains(poison);
      },
    );
    final file = File('../../experiments/redesign/plugin-contract-lab/fixtures/equipment_loan.json');
    var encoded = await file.readAsString();
    if (renamed) {
      encoded = encoded.replaceAll('equipment_loan', module)
          .replaceAll('inspect_equipment', operationName)
          .replaceAll('loan_equipment', 'random_relation')
          .replaceAll('host-equipment-read', 'random-binding')
          .replaceAll('"equipment"', '"asset"').replaceAll('/equipment@', '/asset@')
          .replaceAll('"loan"', '"lease"').replaceAll('/loan@', '/lease@');
    }
    f.bundle = Map<String, Object?>.from(jsonDecode(encoded) as Map);
    f.binding = PluginReadBinding(
      toolId: f.id, operation: f.operation,
      bindingId: renamed ? 'random-binding' : 'host-equipment-read', externalSource: true,
      project: (result) => {
        equipmentType: {
          'module_id': f.equipmentRef.moduleId, 'type': f.equipmentRef.objectType,
          'key': f.equipmentRef.objectId, 'revision': f.equipmentRef.revisionRef,
        },
        'label': f.malformedProjection ? 17 : result.data['label'], 'loans': <Object?>[],
      },
    );
    // Refused enrollment is observable, not a fixture setup exception.
    f.enrolled = await f.bridge.enroll(f.bundle, f.binding);
    f.reviewer = RecordingModelReviewer(f.events);
    final profile = f.loop.profile();
    final authority = HostModelAuthorization(
      repository: f.loop.repo, policy: HostAuthorizationPolicy(f.loop.repo.database),
      grants: GrantStore(f.loop.repo.database), reviewer: f.reviewer,
      configuredProfiles: () => [profile],
    );
    f.agent = PersonalAgent(
      repository: f.loop.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.loop.ledger),
      tools: f.loop.tools, modelAuthorization: authority, pluginReadPort: f.bridge,
    );
    addTearDown(() async { await f.agent.close(); await f.bridge.close(); });
    return f;
  }

  ToolCallRequest request({String invocation = 'direct-fixture'}) => ToolCallRequest(
    invocationId: invocation, toolId: id, scope: const AssistantScope.global(),
    parameters: {'equipment_key': 'e1', 'include_loans': false},
  );

  void failFacts({required bool postref}) {
    final match = postref
        ? "NEW.key = 'auth1b:source:${HostSourceFact.object(equipmentRef).identityDigest}'"
        : "NEW.key LIKE 'auth1b:task:%' AND NEW.value LIKE '%tainted%'";
    loop.repo.database.raw.execute(
      "CREATE TEMP TRIGGER plugin_fact_failure BEFORE INSERT ON settings WHEN $match BEGIN SELECT RAISE(ABORT,'synthetic fact persistence failure'); END");
  }

  Future<PersonalTask> runRead({String? conversationId}) async {
    loop.replies.addAll([
      LoopReply.sse(sseCalls([('inspect-call', encodeToolName(id),
          '{"equipment_key":"e1","include_loans":false}')])),
      LoopReply.sse(sseText('The synthetic equipment is available.')),
    ]);
    return loop.run(agent, await loop.start(agent, loop.profile(), conversationId: conversationId), confirmTools: true);
  }
}

class RecordingModelReviewer implements OutboundContentReviewer {
  RecordingModelReviewer(this.events);
  final List<String> events;
  final payloads = <String>[];
  Future<ReviewDecision> Function(OutboundReviewRequest)? decide;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    events.add('model-review');
    payloads.add(utf8.decode(request.content));
    return await decide?.call(request) ?? const ReviewDecision.allow();
  }
}

/// A deterministic dependency barrier. If the task ends before reaching it,
/// fail immediately rather than turning an unrelated refusal into a timeout.
class FixtureBarrier {
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> stop() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
  Future<void> reached(Future<PersonalTask> running) async {
    await Future.any([entered.future, running.then((_) {})]);
    expect(entered.isCompleted, isTrue, reason: 'required authority boundary was not reached');
  }
  void resume() { if (!release.isCompleted) release.complete(); }
}
