import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grant_store.dart';
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
  var snapshotRevision = 'a1';
  String? invocationId;
  ToolReceipt? get receipt => invocationId == null
      ? null : loop.tools.receiptFor(invocationId!);

  static Future<PluginFixture> open() async {
    final f = PluginFixture._(await LoopFixture.open());
    f.loop.objects = [equipment];
    f.loop.tools.register(
      providerId: 'synthetic-host',
      descriptor: ToolDescriptor(
        toolId: toolId, moduleId: 'equipment_loan', effect: ToolEffect.read,
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
        // The independent assertion below uses the task ledger rather than a
        // fake premark callback. The returned raw result is deliberately unsafe.
        return ToolCallResult(
          status: ToolCallStatus.succeeded, summary: poison,
          data: {'label': publicLabel, 'private': poison},
          objectRefs: [equipment],
        );
      },
    );
    f.process = PluginContractProcess(
      executable: Platform.environment['MUYON_PLUGIN_CONTRACT_BIN'] ?? '',
    );
    f.bridge = PluginReadBridge(
      registry: f.loop.tools, repository: f.loop.repo, process: f.process,
      snapshot: (request) async => PluginHostSnapshot(
        revision: f.snapshotRevision, allowed: true, bindingRevision: 'b1',
        sourceRevision: 's1', ruleRevision: 'r1',
        scope: const AssistantScope.global(), objects: [equipment],
      ),
      reviewProjection: (value, facts) async {
        f.events.add('projection-review');
        expect(f.receipt?.succeeded, isTrue,
            reason: 'projection must refer to the original recorded result');
        return value['label'] == publicLabel &&
            !jsonEncode(value).contains(poison);
      },
    );
    final file = File('../../experiments/redesign/plugin-contract-lab/fixtures/equipment_loan.json');
    // A refusing enrollment is not a fixture setup error in the RED stage.
    // The positive behavior assertion follows actual Agent dispatch below.
    await f.bridge.enroll(
      Map<String, Object?>.from(jsonDecode(await file.readAsString()) as Map),
      PluginReadBinding(
        toolId: toolId, operation: 'equipment_loan/inspect_equipment@1',
        bindingId: 'host-equipment-read', externalSource: true,
        project: (result) => {
          'equipment': {
            'module_id': equipment.moduleId, 'type': equipment.objectType,
            'key': equipment.objectId, 'revision': equipment.revisionRef,
          },
          'label': result.data['label'], 'loans': <Object?>[],
        },
      ),
    );
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

  Future<PersonalTask> runRead() async {
    loop.replies.addAll([
      LoopReply.sse(sseCalls([('inspect-call', encodeToolName(toolId),
          '{"equipment_key":"e1","include_loans":false}')])),
      LoopReply.sse(sseText('The synthetic equipment is available.')),
    ]);
    return loop.run(agent, await loop.start(agent, loop.profile()), confirmTools: true);
  }
}

class RecordingModelReviewer implements OutboundContentReviewer {
  RecordingModelReviewer(this.events);
  final List<String> events;
  final payloads = <String>[];
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    events.add('model-review');
    payloads.add(utf8.decode(request.content));
    return const ReviewDecision.allow();
  }
}
