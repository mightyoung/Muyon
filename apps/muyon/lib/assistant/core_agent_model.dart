import 'dart:convert';

import '../platform/foundation_repository.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/tool_names.dart';
import 'agent_context.dart';
import 'agent_model_turn.dart';
import 'core_agent_protocol.dart';
import 'model_request_gate.dart';

/// One exact, host-authorized request. This is a callback, never an Agent loop.
final class CoreAgentModel {
  CoreAgentModel(this.ctx, this.model);
  final AgentContext ctx;
  final AgentModelTurn model;

  Future<String> safeText(PersonalTask task, String text) async {
    final profile = ctx.profile(task);
    var safe = await ctx.gateway.mask(profile, text);
    for (final value in _profileValues(profile)) {
      safe = safe.replaceAll(value, '<redacted>');
    }
    return safe;
  }

  Future<Map<String, Object?>> reply(
    PersonalTask task,
    List<Map<String, Object?>> messages,
    Map<String, Object?> tool,
    int turn,
    ModelCancellation cancellation,
  ) async {
    final profile = ctx.profile(task);
    final byName = toolIdsByFunctionNameOf(['inquiry.object']);
    final encoded = encodeToolName('inquiry.object');
    final typed = <ModelMessage>[];
    for (final message in messages) {
      final converted = Map<String, Object?>.from(message);
      if (message['tool_calls'] case final List calls) {
        converted['tool_calls'] = [
          for (final raw in calls)
            {
              ...(raw as Map),
              'function': {...raw['function'] as Map, 'name': encoded},
            },
        ];
      }
      typed.add(ModelMessage.fromJson(converted));
    }
    final specs = turn == 1
        ? [
            ModelToolSpec(
              name: encoded,
              description: tool['description'] as String,
              parameters: Map<String, Object?>.from(tool['parameters'] as Map),
            ),
          ]
        : <ModelToolSpec>[];
    final preview = <String, Object?>{
      'messages': typed.map((m) => m.toJson()).toList(),
      'tools': [
        for (final t in specs)
          {
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
          },
      ],
      'mode': 'native',
      'scope': task.scope.toJson(),
      'profile': profile.toJson(),
    };
    final digest = AgentContext.digest(preview);
    final request = ModelRequest(
      profile: profile,
      messages: typed,
      tools: specs,
      caller: 'assistant',
      requestDigest: digest,
    );
    final gate = await ctx.gate.decide(
      ModelRequestFacts(
        location: profile.location,
        endpoint: profile.endpoint.toString(),
        endpointIdentity: profile.endpointIdentity,
        scopeDigest: AgentContext.digest(task.scope.toJson()),
        requestDigest: digest,
        dataCategories: const {'conversation', 'tool_results'},
        step: turn,
      ),
    );
    if (gate is GateDenied) throw const CoreAgentFailure('model_denied');
    final exactTask = task.copy({
      'requestDigest': digest,
      'preview': preview,
      'round': turn,
      'authorizationPolicyRevision': gate is GateConfirm
          ? gate.policyRevision
          : null,
      'expiresAt': ctx
          .clock()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    });
    void current() {
      cancellation.check();
      model.checkPermissionTask(exactTask);
      if (ctx.gate case ModelPolicyGuard guard) {
        guard.checkPolicy(
          exactTask.payload['authorizationPolicyRevision'] as String?,
        );
      }
    }

    current();
    final authority = ctx.modelAuthorization;
    if (authority == null) {
      throw const CoreAgentFailure('model_confirmation_required');
    }
    final review = await model.preparePermission(
      exactTask,
      exactRequest: request,
    );
    current();
    if (review.decision.action == ReviewAction.block) {
      throw const CoreAgentFailure('model_denied');
    }
    if (!review.automatic) {
      throw const CoreAgentFailure('model_confirmation_required');
    }
    final permission = authority.take(
      task.id,
      manual: false,
      requestDigest: digest,
      now: ctx.clock().toUtc(),
    );
    return permission.run(() async {
      final text = StringBuffer();
      final calls = <ToolCallComplete>[];
      Done? done;
      var finished = false;
      await for (final event in ctx.gateway.chatStream(
        provider: ctx.provider,
        request: request,
        cancellation: cancellation,
        beforeSend: () async {
          current();
        },
      )) {
        cancellation.check();
        if (finished && event is! Usage) {
          throw const CoreAgentFailure('model_failed');
        }
        if (event is TextDelta) {
          text.write(event.text);
          if (utf8.encode(text.toString()).length > 16384) {
            throw const CoreAgentFailure('model_failed');
          }
        } else if (event is ToolCallComplete) {
          calls.add(event);
          if (calls.length > 1) throw const CoreAgentFailure('model_failed');
        } else if (event is ModelError) {
          throw CoreAgentFailure(
            turn == 2 && event.code == 'unknown_tool'
                ? 'unsupported_tool_turn'
                : 'model_failed',
          );
        } else if (event is Done) {
          done = event;
          finished = true;
        }
      }
      current();
      if (calls.isNotEmpty) {
        if (turn != 1) throw const CoreAgentFailure('unsupported_tool_turn');
        final call = calls.single;
        if (!call.valid ||
            byName[call.name] != 'inquiry.object' ||
            done?.reason != FinishReason.toolCalls ||
            text.toString().isNotEmpty ||
            call.callId.isEmpty ||
            utf8.encode(call.callId).length > 128 ||
            call.callId.runes.any((r) => r < 32 || r == 127)) {
          throw const CoreAgentFailure('model_failed');
        }
        final args = call.arguments!;
        try {
          coreKeys(args, {'type', 'id'});
          coreMetadata(args['id']);
        } catch (_) {
          throw const CoreAgentFailure('model_failed');
        }
        if (args['type'] is! String ||
            !RegExp(r'^[a-z][a-z0-9_]{0,31}$')
                .hasMatch(args['type'] as String)) {
          throw const CoreAgentFailure('model_failed');
        }
        final reply = <String, Object?>{
          'kind': 'tool',
          'call_id': call.callId,
          'name': 'inquiry.object',
          'arguments': args,
        };
        // Check raw scalar values before JSON escaping: credentials may contain
        // quotes or backslashes. A tool identity must never be rewritten.
        final raw = [
          call.callId,
          'inquiry.object',
          args['type'],
          args['id'],
        ].join('\u0000');
        if (await ctx.gateway.mask(profile, raw) != raw ||
            _containsProfile(profile, raw)) {
          throw const CoreAgentFailure('model_failed');
        }
        current();
        return reply;
      }
      if (done?.reason != FinishReason.stop || text.toString().trim().isEmpty) {
        throw const CoreAgentFailure('model_failed');
      }
      final answer = await safeText(task, text.toString());
      current();
      return {'kind': 'answer', 'text': answer};
    });
  }

  Iterable<String> _profileValues(ModelProfile profile) => [
    profile.id,
    profile.endpoint.toString(),
    profile.endpointIdentity,
    profile.modelId,
    if (profile.credentialRef != null) profile.credentialRef!,
  ].where((value) => value.isNotEmpty);

  bool _containsProfile(ModelProfile profile, String text) =>
      _profileValues(profile).any(text.contains);
}
