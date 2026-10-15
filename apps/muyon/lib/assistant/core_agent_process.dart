import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../platform/assistant_subconversations.dart';
import '../platform/foundation_repository.dart';
import '../platform/grants/host_authorization_facts.dart';
import '../platform/tool_registry.dart';
import '../services/models/model_gateway.dart';
import 'agent_context.dart';
import 'agent_model_turn.dart';
import 'core_agent_model.dart';
import 'core_agent_lifecycle.dart';
import 'core_agent_protocol.dart';

/// Trusted host configuration. Null or disabled keeps the ordinary Dart path.
final class CoreAgentProcessConfig {
  const CoreAgentProcessConfig({
    this.enabled = false,
    required this.executablePath,
    required this.stateRoot,
  });
  final bool enabled;
  final String executablePath, stateRoot;
  void validate() {
    if (enabled &&
        (!path.isAbsolute(executablePath) ||
            !path.isAbsolute(stateRoot) ||
            executablePath.contains('\u0000') ||
            stateRoot.contains('\u0000'))) {
      throw StateError('core_config_invalid');
    }
  }
}

/// Owns one bounded child session. Rust drives every turn; Dart only services
/// correlated callbacks through its existing gateway and registry authorities.
final class CoreAgentProcess {
  CoreAgentProcess(this.config, this.ctx, AgentModelTurn model)
    : model = CoreAgentModel(ctx, model);
  final CoreAgentProcessConfig config;
  final AgentContext ctx;
  final CoreAgentModel model;
  _Session? _active;

  Future<void> run(PersonalTask task) async {
    if (_active != null) {
      await ctx.fail(task, 'core_busy', code: 'core_busy');
      return;
    }
    final session = _Session(this, task);
    _active = session;
    try {
      await session.run();
    } finally {
      if (identical(_active, session)) _active = null;
    }
  }

  Future<void> cancel(String id, {bool closing = false}) async {
    final session = _active;
    if (session?.task.id == id) session!.stop(closing);
  }

  void close() => _active?.stop(true);
}

final class _Session {
  _Session(this.owner, this.task);
  final CoreAgentProcess owner;
  final PersonalTask task;
  AgentContext get ctx => owner.ctx;
  final attempt = const Uuid().v4();
  final scopeRef = const Uuid().v4();
  final clock = Stopwatch();
  Process? process;
  StreamIterator<Map<String, Object?>>? frames;
  StreamSubscription<List<int>>? stderr;
  final lifecycle = CoreAgentLifecycle();
  bool finishing = false;
  ModelCancellation get modelCancellation => lifecycle.modelCancellation;
  bool get stopped => lifecycle.stopped;
  bool get closing => lifecycle.closing;
  bool get invokeAdmitted => lifecycle.admitted;
  int requestId = 0, turns = 0, invokes = 0, sent = 0, received = 0;
  Map<String, Object?>? proposed;
  Map<String, Object?>? projection;
  String? receiptRef, localFailure, preparedRef;
  ToolCallRequest? invocation;
  PreparedToolCall? prepared;
  late Map<String, Object?> tool;
  late RegisteredToolInfo frozen;
  late List<Map<String, Object?>> history;

  void stop(bool close) {
    if (stopped) return;
    lifecycle.stop(close: close);
    // A dispatched read drains to its genuine registry receipt. Cancelling its
    // token here would replace that real result with a cancellation result.
    if (process != null && !finishing) {
      try {
        write({
          'v': 1,
          'kind': close ? 'close' : 'cancel',
          'task_id': task.id,
          'attempt_id': attempt,
        });
      } catch (_) {}
    }
  }

  Duration get remaining {
    final ms = 30000 - clock.elapsedMilliseconds;
    if (ms <= 0) throw const CoreAgentFailure('callback_timeout');
    return Duration(milliseconds: ms < 5000 ? ms : 5000);
  }

  void current() {
    if (stopped || ctx.closing || finishing) {
      throw const CoreAgentFailure('model_denied');
    }
    final live = ctx.repository.task(task.id);
    final conversation = ctx.repository.conversation(task.conversationId);
    if (live?.state != PersonalTaskState.running ||
        conversation == null ||
        AgentContext.digest(conversation.scope.toJson()) !=
            AgentContext.digest(task.scope.toJson()) ||
        task.payload['memoryDigest'] !=
            AgentContext.digest(ctx.memories(task.scope))) {
      throw const CoreAgentFailure('tool_denied');
    }
    AssistantSubconversations(ctx.repository)
        .validateConversation(task.conversationId);
  }

  void write(Map<String, Object?> value) {
    final bytes = utf8.encode(jsonEncode(value));
    sent += bytes.length + 4;
    if (bytes.isEmpty || bytes.length > 65536 || sent + received > 262144) {
      throw const CoreAgentFailure('host_budget');
    }
    final header = ByteData(4)..setUint32(0, bytes.length);
    process!.stdin.add([...header.buffer.asUint8List(), ...bytes]);
  }

  Map<String, Object?> replyTo(Map<String, Object?> frame, String kind) => {
    'v': 1,
    'kind': kind,
    'request_id': frame['request_id'],
    'task_id': task.id,
    'attempt_id': attempt,
    'turn': frame['turn'],
  };

  Future<void> run() async {
    clock.start();
    try {
      owner.config.validate();
      if (task.profileId == null ||
          !ctx.profile(task).capabilities.nativeTools) {
        throw const CoreAgentFailure('core_profile_unsupported');
      }
      final info = ctx.tools.inspect('inquiry.object');
      if (info == null ||
          !info.available ||
          info.providerId != 'inquiry' ||
          info.descriptor.effect != ToolEffect.read ||
          !(task.payload['candidateIds'] as List).contains('inquiry.object')) {
        throw const CoreAgentFailure('tool_denied');
      }
      frozen = info;
      tool = {
        'name': 'inquiry.object',
        'description': info.descriptor.description,
        'parameters': jsonDecode(jsonEncode(info.descriptor.parameterSchema)),
      };
      if (utf8.encode(task.prompt).length > 8192) {
        throw const CoreAgentFailure('host_budget');
      }
      final prompt = await owner.model.safeText(task, task.prompt);
      history = [
        {'role': 'user', 'content': prompt},
      ];
      await ctx.commit(
        task.copy({
          'state': 'running',
          'stage': 'core',
          'coreAttemptId': attempt,
          'uiPlanningDisabled': true,
        }),
        expected: {PersonalTaskState.queued},
      );
      current();
      final root = Directory(owner.config.stateRoot);
      await root.create(recursive: true);
      final attemptRoot = path.join(root.path, task.id, attempt);
      if (await FileSystemEntity.type(attemptRoot, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const CoreAgentFailure('core_state_reused');
      }
      process = await Process.start(
        owner.config.executablePath,
        ['host-session', '--root', root.path],
        environment: const {'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: false,
      );
      stderr = process!.stderr.listen((_) {});
      unawaited(process!.stdin.done.catchError((Object _) {}));
      frames = StreamIterator(
        coreFrames(
          process!.stdout,
          onBytes: (count) {
            received += count;
            if (sent + received > 262144) {
              throw const CoreAgentFailure('host_budget');
            }
          },
        ),
      );
      write({
        'v': 1,
        'kind': 'start',
        'task_id': task.id,
        'attempt_id': attempt,
        'scope_ref': scopeRef,
        'prompt': prompt,
        'tool': tool,
      });
      if (stopped) {
        write({
          'v': 1,
          'kind': closing ? 'close' : 'cancel',
          'task_id': task.id,
          'attempt_id': attempt,
        });
      }
      var terminal = false;
      while (!terminal) {
        if (!await frames!.moveNext().timeout(remaining)) {
          throw const CoreAgentFailure('host_eof');
        }
        final frame = frames!.current;
        if (frame['v'] is! int || frame['v'] != 1) {
          throw const CoreAgentFailure('host_protocol');
        }
        if (frame['task_id'] != task.id || frame['attempt_id'] != attempt) {
          throw const CoreAgentFailure('callback_mismatch');
        }
        if (frame['kind'] == 'terminal') {
          // A terminal is not committed until stdout ends cleanly. A child
          // cannot append another callback after claiming completion.
          unawaited(process!.stdin.close().catchError((Object _) {}));
          if (await frames!.moveNext().timeout(remaining)) {
            throw const CoreAgentFailure('callback_mismatch');
          }
          if (await process!.exitCode.timeout(remaining) != 0) {
            throw const CoreAgentFailure('core_backend_unavailable');
          }
          await settle(frame);
          terminal = true;
        } else {
          await callback(frame).timeout(remaining);
        }
      }
    } catch (error) {
      finishing = true;
      modelCancellation.cancel();
      final code = error is CoreAgentFailure
          ? error.code
          : error is TimeoutException
          ? 'callback_timeout'
          : 'core_backend_unavailable';
      await fail(localFailure ?? code);
    } finally {
      finishing = true;
      modelCancellation.cancel();
      ctx.modelTokens.remove(task.id);
      final pendingRead = lifecycle.pending;
      final drainMs = 30000 - clock.elapsedMilliseconds;
      if (pendingRead != null && drainMs > 0) {
        try {
          await pendingRead.timeout(Duration(milliseconds: drainMs));
        } catch (_) {
          // The registry retains its own authoritative receipt independently.
        }
      }
      if (process != null) {
        // Closing stdin lets the child and a transparent recorder finish their
        // normal reap. Kill only when that bounded cleanup cannot complete.
        unawaited(process!.stdin.close().catchError((Object _) {}));
        try {
          await process!.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {
          process!.kill(ProcessSignal.sigkill);
          await process!.exitCode;
        }
      }
      await frames?.cancel();
      await stderr?.cancel();
      if (invocation != null) {
        ctx.invocationTasks.remove(invocation!.invocationId);
        ctx.invocationRequests.remove(invocation!.invocationId);
      }
    }
  }

  Future<void> callback(Map<String, Object?> frame) async {
    final kind = frame['kind'];
    final base = {'v', 'kind', 'request_id', 'task_id', 'attempt_id', 'turn'};
    final extras = switch (kind) {
      'model_request' => {'messages', 'tools'},
      'prepare' => {'invocation_id', 'call_id', 'tool', 'arguments'},
      'invoke' => {
        'invocation_id',
        'call_id',
        'tool',
        'arguments',
        'prepared_ref',
      },
      _ => throw const CoreAgentFailure('host_protocol'),
    };
    coreKeys(frame, {...base, ...extras});
    if (frame['request_id'] is! int || frame['turn'] is! int) {
      throw const CoreAgentFailure('host_protocol');
    }
    if (frame['request_id'] != requestId + 1 ||
        (frame['request_id'] as int) > 16 ||
        (frame['turn'] as int) < 1 ||
        (frame['turn'] as int) > 2) {
      throw const CoreAgentFailure('callback_mismatch');
    }
    requestId++;
    if (stopped) throw const CoreAgentFailure('callback_mismatch');
    try {
      if (kind == 'model_request') {
        await modelRequest(frame);
      } else if (kind == 'prepare') {
        await prepare(frame);
      } else {
        await invoke(frame);
      }
    } on CoreAgentFailure catch (error) {
      if (finishing) return;
      if (stopped && kind != 'invoke') return;
      localFailure = error.code;
      final wireCode =
          const {
            'model_denied',
            'model_confirmation_required',
            'model_failed',
            'tool_denied',
            'tool_confirmation_required',
            'tool_failed',
            'projection_rejected',
          }.contains(error.code)
          ? error.code
          : kind == 'model_request'
          ? 'model_failed'
          : 'tool_failed';
      write({...replyTo(frame, 'callback_error'), 'code': wireCode});
    } catch (_) {
      if (finishing) return;
      if (stopped && kind != 'invoke') return;
      localFailure = kind == 'model_request' ? 'model_failed' : 'tool_failed';
      write({...replyTo(frame, 'callback_error'), 'code': localFailure});
    }
  }

  Future<void> modelRequest(Map<String, Object?> frame) async {
    if (frame['turn'] != turns + 1 ||
        turns >= 2 ||
        (turns == 1 && projection == null) ||
        !coreHistoryMatches(frame['messages'], history) ||
        !coreSame(frame['tools'], turns == 0 ? [tool] : [])) {
      throw const CoreAgentFailure('callback_mismatch');
    }
    current();
    turns++;
    ctx.modelTokens[task.id] = modelCancellation;
    final reply = await owner.model.reply(
      task,
      [
        for (final message in frame['messages'] as List)
          Map<String, Object?>.from(message as Map),
      ],
      tool,
      turns,
      modelCancellation,
    );
    if (stopped) return;
    if (reply['kind'] == 'tool') {
      proposed = reply;
      history.add({
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': reply['call_id'],
            'type': 'function',
            'function': {
              'name': 'inquiry.object',
              'arguments': jsonEncode(reply['arguments']),
            },
          },
        ],
      });
    } else {
      proposed = reply;
    }
    write({...replyTo(frame, 'model_reply'), 'reply': reply});
  }

  void checkProposal(Map<String, Object?> frame) {
    if (turns != 1 ||
        frame['turn'] != 1 ||
        proposed?['kind'] != 'tool' ||
        frame['call_id'] != proposed!['call_id'] ||
        frame['tool'] != 'inquiry.object' ||
        !coreSame(frame['arguments'], proposed!['arguments']) ||
        frame['invocation_id'] is! String ||
        !RegExp(r'^[A-Za-z0-9_.:-]{1,128}$')
            .hasMatch(frame['invocation_id'] as String) ||
        frame['invocation_id'] == frame['call_id']) {
      throw const CoreAgentFailure('callback_mismatch');
    }
  }

  Future<void> prepare(Map<String, Object?> frame) async {
    checkProposal(frame);
    if (invocation != null) throw const CoreAgentFailure('callback_mismatch');
    current();
    final info = ctx.tools.inspect('inquiry.object');
    if (info == null ||
        !identical(info.descriptor, frozen.descriptor) ||
        info.providerId != frozen.providerId) {
      throw const CoreAgentFailure('tool_denied');
    }
    final request = ToolCallRequest(
      invocationId: frame['invocation_id'] as String,
      toolId: 'inquiry.object',
      scope: task.scope,
      parameters: Map<String, Object?>.from(frame['arguments'] as Map),
    );
    invocation = request;
    ctx.invocationTasks[request.invocationId] = task.id;
    ctx.invocationRequests[request.invocationId] = request;
    AssistantSubconversations(ctx.repository)
        .checkTool(task.conversationId, ToolEffect.read);
    try {
      prepared = await ctx.tools.prepare(request);
    } catch (_) {
      throw const CoreAgentFailure('tool_denied');
    }
    current();
    final p = prepared!;
    if (p.info.accessLevel != ToolAccessLevel.read ||
        !p.resolvedScope.objects.any(
          (ref) =>
              ref.moduleId == 'inquiry' &&
              ref.objectType == request.parameters['type'] &&
              ref.objectId == request.parameters['id'],
        )) {
      throw const CoreAgentFailure('tool_denied');
    }
    preparedRef = const Uuid().v4();
    write({
      ...replyTo(frame, 'decision'),
      'invocation_id': request.invocationId,
      'decision': 'permit',
      'prepared_ref': preparedRef,
    });
  }

  Future<void> invoke(Map<String, Object?> frame) async {
    checkProposal(frame);
    if (invokes != 0 ||
        preparedRef == null ||
        frame['prepared_ref'] != preparedRef ||
        frame['invocation_id'] != invocation?.invocationId) {
      throw const CoreAgentFailure('callback_mismatch');
    }
    current();
    final refreshed = await ctx.tools.prepare(invocation!);
    current();
    if (refreshed.identityDigest != prepared!.identityDigest) {
      throw const CoreAgentFailure('tool_denied');
    }
    final before = ctx.repository.task(task.id)!;
    await ctx.repository.updateTask(
      before.copy({
        'coreInvocationId': invocation!.invocationId,
        'coreToolIdentityDigest': prepared!.identityDigest,
      }),
    );
    // Match the existing inquiry dispatcher provenance rule before invocation;
    // local business reads are still source facts, never model authority.
    await ctx.repository.authorizationFacts.markExternal(
      task.id,
      HostSourceFact.object(
        ObjectRef(
          moduleId: 'inquiry',
          objectType: 'tool_invocation',
          objectId: invocation!.invocationId,
        ),
      ),
    );
    current();
    invokes++;
    final result = await lifecycle.invoke(ctx.tools, invocation!);
    if (finishing) return;
    for (final ref in result.objectRefs) {
      await ctx.repository.authorizationFacts.markExternal(
        task.id,
        HostSourceFact.object(ref),
      );
    }
    final receipt = ctx.tools.receiptFor(invocation!.invocationId);
    if (receipt == null ||
        !receipt.succeeded ||
        receipt.toolId != 'inquiry.object' ||
        receipt.identityDigest != prepared!.identityDigest ||
        receipt.result?.executionId != invocation!.invocationId ||
        !coreSame(receipt.result?.toJson(), result.toJson())) {
      throw const CoreAgentFailure('tool_failed');
    }
    final candidate = projectCoreInquiryResult(
      result,
      prepared!.resolvedScope,
      invocation!.parameters,
    );
    final encodedProjection = jsonEncode(candidate);
    if (await owner.model.safeText(task, encodedProjection) !=
        encodedProjection) {
      throw const CoreAgentFailure('projection_rejected');
    }
    projection = candidate;
    receiptRef = const Uuid().v4();
    // Persist only typed references and the opaque receipt link. Raw result and
    // summary remain solely in the registry's original authoritative receipt.
    final latest = ctx.repository.task(task.id)!;
    await ctx.repository.updateTask(
      latest.copy({
        'coreReceiptRef': receiptRef,
        'coreInvocationId': invocation!.invocationId,
        'references': [for (final ref in result.objectRefs) ref.toJson()],
      }),
    );
    history.add({
      'role': 'tool',
      'content': jsonEncode(projection),
      'tool_call_id': proposed!['call_id'],
    });
    write({
      ...replyTo(frame, 'tool_result'),
      'invocation_id': invocation!.invocationId,
      'prepared_ref': preparedRef,
      'receipt_ref': receiptRef,
      'projection': projection,
    });
  }

  Future<void> settle(Map<String, Object?> frame) async {
    coreKeys(frame, {
      'v',
      'kind',
      'task_id',
      'attempt_id',
      'status',
      'reason',
      'answer',
      'receipt_ref',
      'projection',
      'model_turns',
      'tool_invocations',
    });
    if (frame['reason'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$')
            .hasMatch(frame['reason'] as String) ||
        frame['model_turns'] is! int ||
        frame['model_turns'] != turns ||
        frame['tool_invocations'] is! int ||
        frame['tool_invocations'] != invokes ||
        frame['receipt_ref'] != receiptRef ||
        !coreSame(frame['projection'], projection)) {
      throw const CoreAgentFailure('callback_mismatch');
    }
    final status = frame['status'];
    if (!const {
      'completed',
      'denied',
      'cancelled',
      'interrupted',
      'failed',
      'budget_exhausted',
    }.contains(status)) {
      throw const CoreAgentFailure('callback_mismatch');
    }
    if (status == 'completed') {
      if (stopped ||
          proposed?['kind'] != 'answer' ||
          frame['answer'] != proposed!['text']) {
        throw const CoreAgentFailure('callback_mismatch');
      }
      final refs = invocation == null
          ? <ObjectRef>[]
          : ctx.tools.receiptFor(invocation!.invocationId)!.result!.objectRefs;
      final latest = ctx.repository.task(task.id)!;
      await ctx.finish(latest, frame['answer'] as String, refs);
    } else {
      if (frame['answer'] != null) {
        throw const CoreAgentFailure('callback_mismatch');
      }
      await fail(localFailure ?? frame['reason'] as String);
    }
  }

  Future<void> fail(String code) async {
    final latest = ctx.repository.task(task.id);
    if (latest == null || latest.terminal) return;
    final transportFailure = const {
      'host_protocol',
      'callback_mismatch',
      'host_eof',
      'callback_timeout',
      'core_backend_unavailable',
      'tool_outcome_unknown',
    }.contains(code);
    if (invokeAdmitted && projection == null && transportFailure) {
      await ctx.settle(
        latest,
        PersonalTaskState.interrupted,
        'tool_outcome_unknown',
      );
      return;
    }
    if (invokeAdmitted && code == 'projection_rejected') {
      await ctx.fail(latest, code, code: code);
      return;
    }
    if (stopped || ctx.closing) {
      await ctx.settle(
        latest,
        closing || ctx.closing
            ? PersonalTaskState.interrupted
            : PersonalTaskState.cancelled,
        closing || ctx.closing ? 'host_closed' : null,
      );
    } else {
      final mapped =
          code == 'model_confirmation_required' ||
              code == 'tool_confirmation_required'
          ? 'core_confirmation_required'
          : code;
      await ctx.fail(latest, mapped, code: mapped);
    }
  }
}
