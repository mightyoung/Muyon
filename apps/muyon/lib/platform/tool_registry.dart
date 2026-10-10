import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'grants/grant.dart';
import 'grants/host_effect_intent.dart';
import 'grants/host_tool_authorization.dart';
import 'grants/grant_store.dart';
import 'grants/tool_grant_context.dart';

/// A replay receipt index, not another task/conversation authority. The host
/// includes this installer in its normal versioned database migration.
void installToolRegistrySchema(Database db) => db.execute('''
CREATE TABLE tool_invocation_receipts(
 replay_key TEXT PRIMARY KEY, invocation_id TEXT NOT NULL UNIQUE,
 identity_digest TEXT NOT NULL, tool_id TEXT NOT NULL,
 state TEXT NOT NULL, result_json TEXT);
CREATE TABLE tool_approvals(
 id TEXT PRIMARY KEY, session_id TEXT NOT NULL, tool_id TEXT NOT NULL,
 identity_digest TEXT NOT NULL, scope_digest TEXT NOT NULL, input_digest TEXT NOT NULL,
 destination TEXT, issued_at TEXT NOT NULL, expires_at TEXT NOT NULL,
 state TEXT NOT NULL, consumed_at TEXT);
''');

/// What the registry recorded for one invocation id.
class ToolReceipt {
  const ToolReceipt({
    required this.invocationId,
    required this.toolId,
    required this.identityDigest,
    required this.state,
    this.result,
  });
  final String invocationId, toolId;

  /// Identity bound when this historical invocation ran, including its
  /// arguments and resolved scope. Never recomputed from today's registry.
  final String identityDigest;

  /// `running` until the outcome is written, then the result status.
  final String state;
  final ToolCallResult? result;

  /// The effect happened and its result is the receipt's.
  bool get succeeded => result?.status == ToolCallStatus.succeeded;

  /// Whether the effect may have happened without a recorded outcome: the
  /// process stopped mid-call, or the call ended `interrupted`.
  bool get unknown =>
      result == null || result!.status == ToolCallStatus.interrupted;
}

class ToolPlatformException implements Exception {
  const ToolPlatformException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class PreparedToolCall {
  const PreparedToolCall._(
    this.request,
    this.info,
    this.resolvedScope,
    this.parameterDigest,
    this.identityDigest,
    this._authority,
    this._generation,
    this.effectIntent,
    this._policyRevision,
  );
  final ToolCallRequest request;
  final RegisteredToolInfo info;
  final ResolvedAssistantScope resolvedScope;
  final String parameterDigest;
  final String identityDigest;
  final HostEffectIntent? effectIntent;
  final Object _authority;
  final int _generation;
  final String? _policyRevision;
}

class _Tool {
  _Tool(
    this.info,
    this.handler,
    this.supportedScopes,
    this.dataModuleIds,
    this.validateResult,
    this.preflight,
    this.effectIntent,
  );
  RegisteredToolInfo info;
  final Future<ToolCallResult> Function(ToolCallContext) handler;
  final Set<AssistantScopeKind> supportedScopes;
  final Set<String>? dataModuleIds;
  final Future<void> Function(ResolvedAssistantScope, ToolCallResult)?
  validateResult;
  final void Function(ToolCallRequest)? preflight;
  final HostEffectIntent? Function(ToolCallRequest, ResolvedAssistantScope)?
  effectIntent;
  int generation = 1;
}

class ToolRegistry {
  ToolRegistry({
    required this.database,
    required this.resolveScope,
    DateTime Function()? clock,
    this.grants,
    this.grantContext,
    this.categoryAllowed,
    this.policyRevision,
  }) : clock = clock ?? DateTime.now;
  final ManagedDatabase database;
  final Future<ResolvedAssistantScope> Function(AssistantScope) resolveScope;
  final DateTime Function() clock;
  final GrantStore? grants;
  final ToolGrantContext? Function(ToolCallRequest)? grantContext;
  final bool Function(ToolEffect)? categoryAllowed;
  final String Function()? policyRevision;
  bool permitsCategory(String toolId) =>
      categoryAllowed?.call(_require(toolId).info.descriptor.effect) ?? true;

  void _checkPolicy(String toolId, String? revision) {
    if (!permitsCategory(toolId)) {
      throw const ToolPlatformException('category_disabled', '该操作类别已关闭，未提出');
    }
    if (revision != policyRevision?.call()) {
      throw const ToolPlatformException(
        'stale_policy',
        'Host authorization policy changed',
      );
    }
  }

  final _authority = Object();
  final String _sessionId = const Uuid().v4();
  final Map<String, _Tool> _tools = {};
  final Map<String, HostReviewOutcome> _reviews = {};
  final Map<String, HostAuthorizationLink> _transportLinks = {};
  final Map<
    String,
    ({
      String identity,
      String providerId,
      ToolCancellationToken cancellation,
      Future<ToolCallResult> result,
    })
  >
  _active = {};

  bool get supportsAuthorizationLinks =>
      database.raw
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='assistant_review_decisions'",
          )
          .isNotEmpty &&
      database.raw
          .select('PRAGMA table_info(tool_approvals)')
          .any((row) => row['name'] == 'review_decision_id');

  bool _closing = false;
  Future<void>? _closeFuture;

  void _ensureOpen() {
    if (_closing) throw StateError('Tool registry is closing');
  }

  /// Cancellation is owned by the host, never exposed by ToolRegistrar.
  void cancelProvider(String providerId) {
    for (final call in _active.values.toList()) {
      if (call.providerId == providerId) call.cancellation.cancel();
    }
  }

  /// Withdraw synchronously, then drain terminal receipts before DB shutdown.
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    for (final id in _tools.keys.toList()) {
      setAvailability(id, available: false, reason: 'Host is closing');
    }
    final active = _active.values.toList();
    for (final call in active) {
      call.cancellation.cancel();
    }
    await Future.wait(
      active.map(
        (call) => call.result.then<void>(
          (_) {},
          // The invocation still delivers its error to its own caller. Draining
          // one failed call must not abandon the remaining calls.
          onError: (Object error, StackTrace stack) {},
        ),
      ),
    );
  }

  void register({
    required String providerId,
    required ToolDescriptor descriptor,
    required Future<ToolCallResult> Function(ToolCallContext) handler,
    Set<AssistantScopeKind> supportedScopes = const {
      ...AssistantScopeKind.values,
    },
    Set<String>? dataModuleIds,
    Future<void> Function(ResolvedAssistantScope, ToolCallResult)?
    validateResult,
    void Function(ToolCallRequest)? preflight,
    HostEffectIntent? Function(ToolCallRequest, ResolvedAssistantScope)?
    effectIntent,
    bool available = true,
    String? unavailableReason,
  }) {
    _ensureOpen();
    if (providerId.isEmpty ||
        descriptor.toolId.isEmpty ||
        descriptor.apiVersion < 1 ||
        _tools.containsKey(descriptor.toolId) ||
        supportedScopes.isEmpty) {
      throw const ToolPlatformException(
        'invalid_registration',
        'Unique tool/provider identity and supported scopes required',
      );
    }
    _Schema.check(descriptor.parameterSchema, root: true);
    if (descriptor.resultSchema.isNotEmpty) {
      _Schema.check(descriptor.resultSchema, root: true);
    }
    _tools[descriptor.toolId] = _Tool(
      RegisteredToolInfo(
        providerId: providerId,
        descriptor: descriptor,
        available: available,
        unavailableReason: unavailableReason,
      ),
      handler,
      Set.unmodifiable(supportedScopes),
      dataModuleIds == null ? null : Set.unmodifiable(dataModuleIds),
      validateResult,
      preflight,
      effectIntent,
    );
  }

  List<RegisteredToolInfo> list() =>
      List.unmodifiable(_tools.values.map((tool) => tool.info));
  RegisteredToolInfo? inspect(String toolId) => _tools[toolId]?.info;

  Set<String> authorityModules(String toolId) {
    final tool = _require(toolId);
    return Set.unmodifiable(
      tool.dataModuleIds ?? {tool.info.descriptor.moduleId},
    );
  }

  bool isPureLocalWrite(ToolCallRequest request) {
    final tool = _require(request.toolId);
    if (tool.info.accessLevel != ToolAccessLevel.write ||
        request.destination != null) {
      return false;
    }
    // Only the host's producer can establish this lane, never tool JSON.
    final scope = ResolvedAssistantScope(
      requested: request.scope,
      objects: request.scope.objects,
    );
    return tool.effectIntent?.call(request, scope)?.isTransport == false;
  }

  void setAvailability(
    String toolId, {
    required bool available,
    String? reason,
  }) {
    final tool = _require(toolId);
    tool.info = RegisteredToolInfo(
      providerId: tool.info.providerId,
      descriptor: tool.info.descriptor,
      available: available && !_closing,
      unavailableReason: _closing ? 'Host is closing' : reason,
    );
    tool.generation++;
  }

  _Tool _require(String id) =>
      _tools[id] ??
      (throw const ToolPlatformException(
        'unknown_tool',
        'Tool is not registered',
      ));

  Future<PreparedToolCall> prepare(ToolCallRequest request) async {
    _ensureOpen();
    final tool = _require(request.toolId);
    final policy = policyRevision?.call();
    _checkPolicy(request.toolId, policy);
    if (!tool.info.available) {
      throw ToolPlatformException(
        'unavailable',
        tool.info.unavailableReason ?? 'Tool is unavailable',
      );
    }
    if (!tool.supportedScopes.contains(request.scope.kind)) {
      throw const ToolPlatformException(
        'scope_mismatch',
        'Unsupported scope kind',
      );
    }
    _Schema.validate(tool.info.descriptor.parameterSchema, request.parameters);
    if (tool.info.accessLevel == ToolAccessLevel.external &&
        (request.destination == null || request.destination!.trim().isEmpty)) {
      throw const ToolPlatformException(
        'destination_required',
        'External calls require an explicit destination',
      );
    }
    // Host-set request rule (a module's destination policy); throws to refuse
    // before any scope work and long before an approval can be issued.
    tool.preflight?.call(request);
    var scope = await resolveScope(request.scope);
    _ensureOpen();
    _checkPolicy(request.toolId, policy);
    if (!tool.info.available) {
      throw const ToolPlatformException('unavailable', 'Tool was withdrawn');
    }
    if (_canonical(scope.requested.toJson()) !=
        _canonical(request.scope.toJson())) {
      throw const ToolPlatformException(
        'scope_mismatch',
        'Resolved data does not match requested scope or allowed modules',
      );
    }
    if (tool.dataModuleIds != null &&
        !tool.dataModuleIds!.containsAll(scope.moduleIds)) {
      if (request.scope.kind == AssistantScopeKind.selectedObjects) {
        throw const ToolPlatformException(
          'scope_mismatch',
          'Selected objects include unsupported modules',
        );
      }
      scope = ResolvedAssistantScope(
        requested: request.scope,
        objects: scope.objects
            .where((ref) => tool.dataModuleIds!.contains(ref.moduleId))
            .toList(),
      );
    }
    final intent = tool.effectIntent?.call(request, scope);
    if (intent != null &&
        (intent.toolId != request.toolId ||
            intent.invocationId != request.invocationId ||
            (intent.isTransport
                ? intent.endpoint.toString() != request.destination
                : tool.info.accessLevel != ToolAccessLevel.write ||
                      request.destination != null))) {
      throw const ToolPlatformException(
        'intent_mismatch',
        'Host transport identity mismatch',
      );
    }
    final parameterDigest = _digest(request.parameters);
    final identity = _digest({
      'invocationId': request.invocationId,
      'replayKey': request.replayKey,
      'toolId': request.toolId,
      'providerId': tool.info.providerId,
      'apiVersion': tool.info.descriptor.apiVersion,
      'effect': tool.info.descriptor.effect.name,
      'parameterSchema': tool.info.descriptor.parameterSchema,
      'resultSchema': tool.info.descriptor.resultSchema,
      'generation': tool.generation,
      'scope': scope.toJson(),
      'parameterDigest': parameterDigest,
      'destination': request.destination,
      'effectIntent': intent?.digest,
      'policyRevision': ?policy,
    });
    return PreparedToolCall._(
      request,
      tool.info,
      scope,
      parameterDigest,
      identity,
      _authority,
      tool.generation,
      intent,
      policy,
    );
  }

  /// Host UI calls this only after displaying and confirming this exact preview.
  /// Never register this method as a model-callable tool or parse grants from text.
  Future<String> approve(
    PreparedToolCall prepared, {
    Duration ttl = const Duration(minutes: 2),
    HostReviewOutcome? review,
  }) async {
    final tool = _require(prepared.request.toolId);
    _checkReview(prepared, review, manual: true);
    if (!identical(prepared._authority, _authority) ||
        prepared._generation != tool.generation ||
        !tool.info.available ||
        ttl <= Duration.zero ||
        ttl > const Duration(minutes: 10)) {
      throw const ToolPlatformException(
        'invalid_approval',
        'Approval preview is stale or lifetime invalid',
      );
    }
    final current = await prepare(prepared.request);
    if (current.identityDigest != prepared.identityDigest) {
      throw const ToolPlatformException(
        'stale_scope',
        'Approval preview no longer matches current data',
      );
    }
    final now = clock().toUtc();
    final id = const Uuid().v4();
    await database.write((db) {
      _checkReview(prepared, review, manual: true);
      db.execute(
        "UPDATE tool_approvals SET state='invalidated' WHERE session_id<>? AND state='issued'",
        [_sessionId],
      );
      final sourceColumn = db
          .select('PRAGMA table_info(tool_approvals)')
          .any((row) => row['name'] == 'authorization_source');
      db.execute(
        'INSERT INTO tool_approvals(id,session_id,tool_id,identity_digest,scope_digest,input_digest,destination,issued_at,expires_at,state,consumed_at'
        "${sourceColumn ? ',authorization_source' : ''}${review == null ? '' : ',review_decision_id'}) VALUES(?,?,?,?,?,?,?,?,?,?,NULL"
        "${sourceColumn ? ',?' : ''}${review == null ? '' : ',?'})",
        [
          id,
          _sessionId,
          prepared.request.toolId,
          prepared.identityDigest,
          _digest(prepared.resolvedScope.toJson()),
          prepared.parameterDigest,
          prepared.effectIntent?.destinationDigest ??
              (prepared.request.destination == null
                  ? null
                  : _digest(prepared.request.destination)),
          now.toIso8601String(),
          now.add(ttl).toIso8601String(),
          'issued',
          if (sourceColumn) 'manual',
          if (review != null) review.reviewDecisionId,
        ],
      );
      if (review != null) _reviews[review.reviewDecisionId!] = review;
    });
    return id;
  }

  /// A permission request built entirely from the host's prepared call and facts.
  /// A coarse scope key never replaces the revision-bound identityDigest.
  GrantRequest authorizationRequest(PreparedToolCall prepared) {
    if (!identical(prepared._authority, _authority) ||
        grantContext == null ||
        prepared.info.accessLevel == ToolAccessLevel.read) {
      throw const ToolPlatformException(
        'invalid_grant_request',
        'Trusted host effect context required',
      );
    }
    final context = grantContext!(prepared.request);
    if (context == null ||
        !context.allowedModuleIds.containsAll(
          prepared.resolvedScope.moduleIds,
        )) {
      throw const ToolPlatformException(
        'scope_mismatch',
        'Host permission boundary excludes resolved objects',
      );
    }
    return GrantRequest(
      category: prepared.info.accessLevel == ToolAccessLevel.external
          ? 'outbound'
          : 'write',
      toolId: prepared.request.toolId,
      scopeDigest: toolGrantScopeDigest(
        prepared.request.scope,
        context.allowedModuleIds,
      ),
      // Full permission identity, not the redacted host/path audit display.
      destination: prepared.request.destination == null
          ? null
          : prepared.effectIntent?.destinationDigest ??
                _digest(prepared.request.destination),
      now: clock(),
      taskId: context.taskId,
      conversationId: context.conversationId,
      taskTainted: context.taskTainted,
    );
  }

  HostAuthorizationLink? authorizationLink(ToolCallRequest request) {
    if (request.approvalId == null) return null;
    final rows = database.raw.select(
      'SELECT * FROM tool_approvals WHERE id=?',
      [request.approvalId],
    );
    if (rows.length != 1 || !rows.single.containsKey('review_decision_id')) {
      return null;
    }
    final proof = _reviews[rows.single['review_decision_id']];
    if (proof == null) return null;
    return _transportLinks.putIfAbsent(
      request.approvalId!,
      () => proof.transportLink(
        this,
        request,
        isActive: () =>
            _active[request.replayKey]?.identity ==
                rows.single['identity_digest'] &&
            !(_active[request.replayKey]?.cancellation.isCancelled ?? true),
      ),
    );
  }

  HostEffectIntent? currentEffectIntent(PreparedToolCall prepared) {
    final tool = _require(prepared.request.toolId);
    if (!identical(prepared._authority, _authority) ||
        _closing ||
        !tool.info.available ||
        prepared._generation != tool.generation) {
      return null;
    }
    return tool.effectIntent?.call(prepared.request, prepared.resolvedScope);
  }

  void _checkReview(
    PreparedToolCall prepared,
    HostReviewOutcome? review, {
    bool manual = false,
  }) {
    _checkPolicy(prepared.request.toolId, prepared._policyRevision);
    if (prepared.effectIntent != null && review == null) {
      throw const ToolPlatformException(
        'review_required',
        'Host transport review required',
      );
    }
    review?.requireCurrent(this, prepared, manual: manual);
  }

  static String _grantContextDigest(GrantRequest request) => _digest({
    'taskId': request.taskId,
    'conversationId': request.conversationId,
    'scopeDigest': request.scopeDigest,
  });

  /// Foundational host API; A does not wire it into the agent's decision path.
  /// Consumption, audit and signing are one transaction, never two writes.
  Future<String?> approveWithGrant(
    PreparedToolCall prepared, {
    required String grantId,
    HostReviewOutcome? review,
  }) async {
    _checkReview(prepared, review);
    if (review != null && review.grantId != grantId) {
      throw const ToolPlatformException(
        'review_mismatch',
        'Reviewed permission source required',
      );
    }
    if (grants == null ||
        grantContext == null ||
        !identical(grants!.database, database)) {
      throw const ToolPlatformException(
        'invalid_grant_store',
        'Same host owner required',
      );
    }
    final tool = _require(prepared.request.toolId);
    if (!identical(prepared._authority, _authority) ||
        prepared._generation != tool.generation ||
        !tool.info.available) {
      throw const ToolPlatformException(
        'invalid_approval',
        'Approval preview is stale',
      );
    }
    final scopeRevision = grantContext!(prepared.request)?.scopeRevision;
    if (scopeRevision == null || scopeRevision.isEmpty) {
      throw const ToolPlatformException(
        'invalid_grant_request',
        'Host scope revision required',
      );
    }
    final current = await prepare(prepared.request);
    if (current.identityDigest != prepared.identityDigest) {
      throw const ToolPlatformException(
        'stale_scope',
        'Approval preview no longer matches current data',
      );
    }
    return database.write((db) {
      _checkReview(prepared, review);
      _ensureOpen();
      if (!tool.info.available || tool.generation != prepared._generation) {
        throw const ToolPlatformException(
          'invalid_approval',
          'Tool was withdrawn before signing',
        );
      }
      // Resolving under the write queue would deadlock lazy activation and
      // projection work. The host revision fences intervening writes instead.
      if (grantContext!(prepared.request)?.scopeRevision != scopeRevision) {
        throw const ToolPlatformException(
          'stale_scope',
          'Scope changed while signing was queued',
        );
      }
      final bound = authorizationRequest(prepared);
      final previous = db.select(
        'SELECT * FROM tool_approvals WHERE grant_id IS NOT NULL AND (invocation_id=? OR replay_key=?)',
        [prepared.request.invocationId, prepared.request.replayKey],
      );
      if (previous.isNotEmpty) {
        final row = previous.single;
        if (row['identity_digest'] != prepared.identityDigest ||
            row['grant_id'] != grantId ||
            row['session_id'] != _sessionId ||
            row['grant_context_digest'] != _grantContextDigest(bound) ||
            row['review_decision_id'] != review?.reviewDecisionId) {
          throw const ToolPlatformException(
            'idempotency_conflict',
            'Approval identity already used',
          );
        }
        final receipt = db.select(
          'SELECT identity_digest FROM tool_invocation_receipts WHERE replay_key=?',
          [prepared.request.replayKey],
        );
        if (row['state'] == 'consumed' &&
            receipt.isNotEmpty &&
            receipt.single['identity_digest'] == prepared.identityDigest) {
          return row['id'] as String;
        }
        if (row['state'] == 'issued' &&
            clock().isBefore(DateTime.parse(row['expires_at'] as String)) &&
            grants!.permitsIssuedApproval(grantId, bound)) {
          return row['id'] as String;
        }
        return null;
      }
      if (db.select(
        'SELECT 1 FROM tool_invocation_receipts WHERE replay_key=? OR invocation_id=?',
        [prepared.request.replayKey, prepared.request.invocationId],
      ).isNotEmpty) {
        throw const ToolPlatformException(
          'idempotency_conflict',
          'Invocation already has a receipt',
        );
      }
      final used = grants!.recordUseInTransaction(db, grantId, bound);
      if (used == null) return null;
      final id = const Uuid().v4();
      final deadline = bound.now.add(const Duration(minutes: 2));
      final expires =
          used.expiresAt != null && used.expiresAt!.isBefore(deadline)
          ? used.expiresAt!
          : deadline;
      db.execute(
        'INSERT INTO tool_approvals(id,session_id,tool_id,identity_digest,scope_digest,input_digest,destination,issued_at,expires_at,state,grant_id,authorization_source,grant_context_digest,invocation_id,replay_key,review_decision_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          _sessionId,
          prepared.request.toolId,
          prepared.identityDigest,
          _digest(prepared.resolvedScope.toJson()),
          prepared.parameterDigest,
          bound.destination,
          bound.now.toIso8601String(),
          expires.toIso8601String(),
          'issued',
          grantId,
          'grant',
          _grantContextDigest(bound),
          prepared.request.invocationId,
          prepared.request.replayKey,
          review?.reviewDecisionId,
        ],
      );
      if (review != null) _reviews[review.reviewDecisionId!] = review;
      return id;
    });
  }

  Future<ToolCallResult> invoke(
    ToolCallRequest request, {
    ToolCancellationToken? cancellation,
  }) async {
    final token = cancellation ?? ToolCancellationToken();
    token.throwIfCancelled();
    final before = inspect(request.toolId);
    late PreparedToolCall prepared;
    try {
      prepared = await prepare(request);
    } on ToolPlatformException catch (error) {
      // A read module may fail lazy activation during scope resolution. Keep
      // every prepare/authorization refusal intact; report this transition as
      // a failed read without dispatching a handler or issuing an approval.
      if (before?.available == true &&
          before?.accessLevel == ToolAccessLevel.read &&
          error.code == 'unavailable') {
        return ToolCallResult(
          status: ToolCallStatus.failed,
          summary: 'Tool is unavailable; no action was executed.',
        ).forInvocation(request.invocationId);
      }
      rethrow;
    }
    token.throwIfCancelled();
    final active = _active[request.replayKey];
    if (active != null) {
      if (active.identity != prepared.identityDigest) {
        throw const ToolPlatformException(
          'idempotency_conflict',
          'Replay key belongs to another request',
        );
      }
      return active.result;
    }
    final completer = Completer<ToolCallResult>();
    _active[request.replayKey] = (
      identity: prepared.identityDigest,
      providerId: _require(request.toolId).info.providerId,
      cancellation: token,
      result: completer.future,
    );
    try {
      final result = await _dispatch(prepared, token);
      completer.complete(result);
    } catch (error, stack) {
      completer.completeError(error, stack);
    } finally {
      _active.remove(request.replayKey);
    }
    return completer.future;
  }

  Future<ToolCallResult> _dispatch(
    PreparedToolCall prepared,
    ToolCancellationToken token,
  ) async {
    final request = prepared.request;
    final tool = _require(request.toolId);
    final generation = tool.generation;
    final scopeRevision = grantContext?.call(request)?.scopeRevision;
    DateTime? approvalDeadline;
    String? sourceGrantId;
    String? sourceContextDigest;
    String? sourceReviewId, authorizationSource;
    HostReviewOutcome? reviewProof;
    void checkAuthorization() {
      _checkPolicy(request.toolId, prepared._policyRevision);
      if (reviewProof != null) {
        _checkReview(
          prepared,
          reviewProof,
          manual: authorizationSource == 'manual',
        );
      }
      if (_closing || !tool.info.available || tool.generation != generation) {
        throw const ToolPlatformException(
          'unavailable',
          'Tool authority was withdrawn',
        );
      }
      if (sourceGrantId != null) {
        if (scopeRevision == null ||
            scopeRevision.isEmpty ||
            grantContext?.call(request)?.scopeRevision != scopeRevision) {
          throw const ToolPlatformException(
            'stale_scope',
            'Scope changed before the authorized effect',
          );
        }
        final bound = authorizationRequest(prepared);
        if (sourceContextDigest != _grantContextDigest(bound) ||
            grants == null ||
            !grants!.permitsIssuedApproval(sourceGrantId!, bound)) {
          throw const ToolPlatformException(
            'grant_invalidated',
            'Source authorization no longer permits this effect',
          );
        }
      }
      if (approvalDeadline != null && !clock().isBefore(approvalDeadline!)) {
        throw const ToolPlatformException(
          'approval_expired',
          'Host approval expired before the effect',
        );
      }
    }

    final cached = await database.write((db) {
      token.throwIfCancelled();
      checkAuthorization();
      final rows = db.select(
        'SELECT * FROM tool_invocation_receipts WHERE replay_key=? OR invocation_id=?',
        [request.replayKey, request.invocationId],
      );
      if (rows.isNotEmpty) {
        if (rows.length != 1 ||
            rows.single['identity_digest'] != prepared.identityDigest) {
          throw const ToolPlatformException(
            'idempotency_conflict',
            'Invocation identity was already used',
          );
        }
        final payload = rows.single['result_json'];
        return payload == null
            ? ToolCallResult(
                status: ToolCallStatus.interrupted,
                summary: 'Previous attempt may have executed; inspect its result before starting a new operation.',
                executionId: request.invocationId,
              )
            : ToolCallResult.fromJson(
                Map<String, Object?>.from(jsonDecode(payload as String) as Map),
              );
      }
      if (tool.info.accessLevel != ToolAccessLevel.read) {
        final grants = db.select('SELECT * FROM tool_approvals WHERE id=?', [
          request.approvalId,
        ]);
        if (grants.length != 1 ||
            grants.single['session_id'] != _sessionId ||
            grants.single['state'] != 'issued' ||
            grants.single['identity_digest'] != prepared.identityDigest ||
            !clock().isBefore(
              DateTime.parse(grants.single['expires_at'] as String),
            )) {
          throw const ToolPlatformException(
            'approval_required',
            'A current one-use host confirmation is required',
          );
        }
        sourceReviewId = grants.single.containsKey('review_decision_id')
            ? grants.single['review_decision_id'] as String?
            : null;
        authorizationSource = grants.single.containsKey('authorization_source')
            ? grants.single['authorization_source'] as String?
            : null;
        reviewProof = _reviews[sourceReviewId];
        _checkReview(
          prepared,
          reviewProof,
          manual: authorizationSource == 'manual',
        );
        sourceGrantId = grants.single.containsKey('grant_id')
            ? grants.single['grant_id'] as String?
            : null;
        sourceContextDigest = grants.single.containsKey('grant_context_digest')
            ? grants.single['grant_context_digest'] as String?
            : null;
        checkAuthorization();
        db.execute(
          "UPDATE tool_approvals SET state='consumed',consumed_at=? WHERE id=?",
          [clock().toUtc().toIso8601String(), request.approvalId],
        );
        approvalDeadline = DateTime.parse(
          grants.single['expires_at'] as String,
        );
      }
      db.execute(
        'INSERT INTO tool_invocation_receipts(replay_key,invocation_id,identity_digest,tool_id,state,result_json'
        "${authorizationSource == null ? '' : ',grant_id,authorization_source,review_decision_id'}) VALUES(?,?,?,?,?,NULL"
        "${authorizationSource == null ? '' : ',?,?,?'})",
        [
          request.replayKey,
          request.invocationId,
          prepared.identityDigest,
          request.toolId,
          'running',
          if (authorizationSource != null) ...[
            sourceGrantId,
            authorizationSource,
            sourceReviewId,
          ],
        ],
      );
      return null;
    });
    if (cached != null) return cached;
    ToolCallResult result;
    var effectReached = false;
    final effectful = tool.info.accessLevel != ToolAccessLevel.read;
    try {
      token.throwIfCancelled();
      // Re-resolve immediately before dispatch, including after queue waits.
      final current = await prepare(request);
      if (current.identityDigest != prepared.identityDigest) {
        throw const ToolPlatformException(
          'stale_scope',
          'Data changed before execution',
        );
      }
      token.throwIfCancelled();
      checkAuthorization();
      result = await tool.handler(
        ToolCallContext(
          request: request,
          resolvedScope: current.resolvedScope,
          cancellation: token,
          // Passing this check means the provider is about to cause its effect.
          checkAuthorization: () {
            checkAuthorization();
            effectReached = true;
          },
        ),
      );
      token.throwIfCancelled();
      if (result.status == ToolCallStatus.succeeded) {
        if (tool.info.descriptor.resultSchema.isNotEmpty) {
          _Schema.validate(tool.info.descriptor.resultSchema, result.data);
        }
      }
      if (tool.validateResult != null) {
        await tool.validateResult!(current.resolvedScope, result);
      } else if (result.objectRefs.any(
            (ref) => !current.resolvedScope.contains(ref),
          ) ||
          result.artifactRefs.isNotEmpty) {
        throw const ToolPlatformException(
          'result_scope_mismatch',
          'Result references require host-verified scope',
        );
      }
      token.throwIfCancelled();
    } on ToolCancelled {
      result = effectful && effectReached
          ? _uncertain('Cancelled after the effect started')
          : ToolCallResult(
              status: ToolCallStatus.cancelled,
              summary: 'Cancelled. No write or external action was executed.',
            );
    } catch (error) {
      final reason = error is ToolPlatformException
          ? error.toString()
          : 'Tool execution failed';
      result = effectful && effectReached
          ? _uncertain(reason)
          : ToolCallResult(status: ToolCallStatus.failed, summary: reason);
    }
    result = result.forInvocation(request.invocationId);
    await database.write(
      (db) => db.execute(
        'UPDATE tool_invocation_receipts SET state=?,result_json=? WHERE replay_key=?',
        [result.status.name, jsonEncode(result.toJson()), request.replayKey],
      ),
    );
    return result;
  }

  /// Outcome unknown: the write/external effect may have happened. A local
  /// cancel cannot undo it, so the caller must verify before any retry.
  static ToolCallResult _uncertain(String reason) => ToolCallResult(
    status: ToolCallStatus.interrupted,
    summary:
        '$reason. The write or external action may already have happened and '
        'is not undone by cancelling here; verify its actual result before '
        'starting a new attempt.',
  );

  /// The receipt of one invocation, if any (read only). A resumed task asks
  /// this before it would run anything again.
  ToolReceipt? receiptFor(String invocationId) {
    final rows = database.raw.select(
      'SELECT tool_id,identity_digest,state,result_json FROM tool_invocation_receipts WHERE invocation_id=?',
      [invocationId],
    );
    if (rows.isEmpty) return null;
    final json = rows.first['result_json'] as String?;
    return ToolReceipt(
      invocationId: invocationId,
      toolId: rows.first['tool_id'] as String,
      identityDigest: rows.first['identity_digest'] as String,
      state: rows.first['state'] as String,
      result: json == null
          ? null
          : ToolCallResult.fromJson(
              Map<String, Object?>.from(jsonDecode(json) as Map),
            ),
    );
  }

  List<ToolCallResult> history({String? toolId}) => [
    for (final row in database.raw.select(
      'SELECT result_json FROM tool_invocation_receipts WHERE result_json IS NOT NULL'
      '${toolId == null ? '' : ' AND tool_id=?'} ORDER BY rowid DESC',
      toolId == null ? [] : [toolId],
    ))
      ToolCallResult.fromJson(
        Map<String, Object?>.from(
          jsonDecode(row['result_json'] as String) as Map,
        ),
      ),
  ];
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(_canonical(value))).toString();
String _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonical(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

/// Deliberately bounded JSON Schema subset. Unknown keywords fail registration
/// instead of silently skipping validation. No remote refs or coercions.
class _Schema {
  static const _keywords = {
    'type',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'enum',
    'minimum',
    'maximum',
    'minLength',
    'maxLength',
    'minItems',
    'maxItems',
    'description',
    'title',
  };
  static const _types = {
    'object',
    'array',
    'string',
    'integer',
    'number',
    'boolean',
    'null',
  };
  static void check(
    Map<String, Object?> schema, {
    bool root = false,
    int depth = 0,
  }) {
    if (depth > 24 ||
        schema.keys.any((key) => !_keywords.contains(key)) ||
        (root && schema['type'] != 'object')) {
      throw const ToolPlatformException(
        'invalid_schema',
        'Unsupported schema keyword or root type',
      );
    }
    final types = schema['type'] is String ? [schema['type']] : schema['type'];
    if (types is! List ||
        types.isEmpty ||
        types.any((type) => !_types.contains(type))) {
      throw const ToolPlatformException(
        'invalid_schema',
        'Explicit supported JSON type required',
      );
    }
    if (schema['properties'] != null) {
      final properties = Map<String, Object?>.from(schema['properties'] as Map);
      for (final child in properties.values) {
        check(Map<String, Object?>.from(child as Map), depth: depth + 1);
      }
    }
    if (schema['items'] != null) {
      check(
        Map<String, Object?>.from(schema['items'] as Map),
        depth: depth + 1,
      );
    }
    if (types.contains('array') && schema['items'] == null) {
      throw const ToolPlatformException(
        'invalid_schema',
        'Array item schema required',
      );
    }
    if (schema['additionalProperties'] != null &&
        schema['additionalProperties'] is! bool) {
      throw const ToolPlatformException(
        'invalid_schema',
        'additionalProperties must be boolean',
      );
    }
    final required = schema['required'];
    if (required != null &&
        (required is! List ||
            required.any(
              (field) =>
                  field is! String ||
                  !(schema['properties'] as Map? ?? {}).containsKey(field),
            ))) {
      throw const ToolPlatformException(
        'invalid_schema',
        'Required fields must have declared properties',
      );
    }
    if (schema['enum'] != null &&
        (schema['enum'] is! List || (schema['enum'] as List).isEmpty)) {
      throw const ToolPlatformException(
        'invalid_schema',
        'Enum must have allowed values',
      );
    }
    for (final key in [
      'minimum',
      'maximum',
      'minLength',
      'maxLength',
      'minItems',
      'maxItems',
    ]) {
      final bound = schema[key];
      if (bound != null &&
          (bound is! num ||
              !bound.isFinite ||
              (key != 'minimum' &&
                  key != 'maximum' &&
                  (bound is! int || bound < 0)))) {
        throw const ToolPlatformException(
          'invalid_schema',
          'Invalid schema bound',
        );
      }
    }
  }

  static void validate(
    Map<String, Object?> schema,
    Object? value, {
    int depth = 0,
  }) {
    Never invalid() => throw const ToolPlatformException(
      'invalid_parameters',
      'Value does not match the declared JSON schema',
    );
    if (depth > 24) invalid();
    final types = schema['type'] is String
        ? [schema['type']]
        : schema['type'] as List;
    bool matches(Object? type) => switch (type) {
      'null' => value == null,
      'object' => value is Map<String, Object?>,
      'array' => value is List,
      'string' => value is String,
      'integer' => value is int && value.abs() <= 9007199254740991,
      'number' =>
        value is num &&
            value.isFinite &&
            (value is! int || value.abs() <= 9007199254740991),
      'boolean' => value is bool,
      _ => false,
    };
    if (!types.any(matches)) invalid();
    if (schema['enum'] is List &&
        !(schema['enum'] as List).any(
          (allowed) => _canonical(allowed) == _canonical(value),
        )) {
      invalid();
    }
    if (value is Map<String, Object?>) {
      final properties = Map<String, Object?>.from(
        schema['properties'] as Map? ?? {},
      );
      if (value.length > 1024 ||
          (schema['required'] as List? ?? []).any(
            (key) => !value.containsKey(key),
          )) {
        invalid();
      }
      for (final entry in value.entries) {
        if (!properties.containsKey(entry.key)) {
          if (schema['additionalProperties'] != true) invalid();
        } else {
          validate(
            Map<String, Object?>.from(properties[entry.key] as Map),
            entry.value,
            depth: depth + 1,
          );
        }
      }
    }
    if (value is List) {
      if (value.length > 4096 ||
          value.length < (schema['minItems'] as int? ?? 0) ||
          value.length > (schema['maxItems'] as int? ?? 4096)) {
        invalid();
      }
      for (final item in value) {
        validate(
          Map<String, Object?>.from(schema['items'] as Map),
          item,
          depth: depth + 1,
        );
      }
    }
    if (value is String &&
        (value.length > 65536 ||
            value.length < (schema['minLength'] as int? ?? 0) ||
            value.length > (schema['maxLength'] as int? ?? 65536))) {
      invalid();
    }
    if (value is num &&
        ((schema['minimum'] != null && value < (schema['minimum'] as num)) ||
            (schema['maximum'] != null &&
                value > (schema['maximum'] as num)))) {
      invalid();
    }
  }
}
