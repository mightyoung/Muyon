import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../services/models/model_gateway.dart';
import '../foundation_repository.dart';
import 'grant.dart';
import 'grant_store.dart';
import 'host_authorization_policy.dart';
import 'outbound_content_reviewer.dart';
import 'tool_grant_context.dart';

String modelEndpointIdentity(ModelProfile profile) => jsonEncode({
  'profileId': profile.id,
  'endpoint': profile.endpoint.toString(),
  'endpointIdentity': profile.endpointIdentity,
  'location': profile.location.name,
  'cloudProxy': profile.cloudProxy,
  'model': profile.modelId,
  'purpose': profile.purpose.name,
  'credentialRef': profile.credentialRef,
});

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

/// This authority is reachable only through the actual host actor, never
/// decoded from a task payload, module result or model argument.
final class HostModelAuthorization {
  HostModelAuthorization({
    required this.repository,
    required this.policy,
    required this.grants,
    required this.reviewer,
    this.configuredProfiles,
  });
  final FoundationRepository repository;
  final HostAuthorizationPolicy policy;
  final GrantStore grants;
  final OutboundContentReviewer reviewer;
  final Iterable<ModelProfile> Function()? configuredProfiles;
  final _profiles = <String, String>{};
  final _reviews = <String, HostModelReview>{};
  bool hasReview(String taskId) => _reviews.containsKey(taskId);
  void bindLiveProfile(String taskId, ModelProfile profile) {
    _profiles[taskId] = _hash(jsonEncode(profile.toJson()));
  }

  Future<HostModelReview> prepare({
    required PersonalTask task,
    required ModelProfile profile,
    required String payload,
    required String requestDigest,
    required Set<String> modules,
    required DateTime now,
    required void Function() checkCurrent,
    bool summary = false,
    String? compatiblePayload,
  }) async {
    checkCurrent();
    final snapshot = policy.current;
    if (!snapshot.allows(AssistantAuthorizationCategory.model)) {
      throw StateError('model_category_disabled');
    }
    final profileDigest = _hash(jsonEncode(profile.toJson()));
    var bound = _profiles[task.id] == profileDigest;
    if (!bound) {
      try {
        bound =
            configuredProfiles?.call().any(
              (p) => _hash(jsonEncode(p.toJson())) == profileDigest,
            ) ==
            true;
      } catch (_) {
        // Malformed current configuration is not profile authority.
      }
    }
    final destination = modelEndpointIdentity(profile);
    final scope = toolGrantScopeDigest(task.scope, modules);
    final request = GrantRequest(
      category: 'model',
      toolId: 'assistant.model',
      scopeDigest: scope,
      destination: destination,
      taskId: task.id,
      taskTainted: repository.authorizationFacts
          .readTask(task.id)
          .requiresConfirmation,
      conversationId: task.conversationId,
      now: now,
    );
    final known = repository.database.raw.select(
      'SELECT 1 FROM outbound_requests o JOIN assistant_review_decisions r '
      'ON r.id=o.review_decision_id WHERE o.authorization_source=\'manual\' '
      'AND r.destination_identity_digest=? AND r.payload_digest=o.payload_sha256 '
      "AND r.decision IN ('allow','confirm') LIMIT 1",
      [_hash(destination)],
    ).isNotEmpty;
    final selected = bound && known ? grants.findMatching(request) : null;
    final local =
        profile.location == ModelLocation.local &&
        !profile.cloudProxy &&
        ['127.0.0.1', 'localhost', '::1'].contains(profile.endpoint.host);
    // Restored JSON is not evidence of an own-device or local profile choice.
    final automatic =
        bound &&
        (selected != null ||
            (snapshot.mode != AssistantAuthorizationMode.custom &&
                (local ||
                    (profile.location == ModelLocation.ownDevice &&
                        !profile.cloudProxy))));
    final decision = await reviewer.review(
      OutboundReviewRequest(
        toolId: summary ? 'assistant.model.summary' : 'assistant.model',
        endpoint: profile.endpoint,
        content: utf8.encode(payload),
        scopeDigest: scope,
        sourceObjects: task.scope.objects,
      ),
    );
    checkCurrent();
    if (policy.current.revision != snapshot.revision ||
        !policy.current.allows(AssistantAuthorizationCategory.model)) {
      throw StateError('model_policy_changed');
    }
    final id = const Uuid().v4();
    await repository.database.write((db) {
      checkCurrent();
      if (policy.current.revision != snapshot.revision) {
        throw StateError('model_policy_changed');
      }
      db.execute(
        'INSERT INTO assistant_review_decisions('
        'id,task_id,invocation_id,tool_id,destination_identity_digest,'
        'payload_digest,decision,reviewed,reason,created_at) '
        'VALUES(?,?,NULL,?,?,?,?,?,?,?)',
        [
          id,
          task.id,
          summary ? 'assistant.model.summary' : 'assistant.model',
          _hash(destination),
          _hash(payload),
          decision.action.name,
          decision.reviewed ? 1 : 0,
          switch (decision.action) {
            ReviewAction.allow => null,
            ReviewAction.confirm => '内容审查需要人工确认',
            ReviewAction.block => '内容审查阻止发送',
          },
          now.toUtc().toIso8601String(),
        ],
      );
    });
    final review = HostModelReview._(
      this,
      task.id,
      profile,
      payload,
      requestDigest,
      snapshot.revision,
      request,
      id,
      decision,
      automatic,
      selected?.id,
      now.add(const Duration(minutes: 5)),
      checkCurrent,
      compatiblePayload: compatiblePayload,
      toolId: summary ? 'assistant.model.summary' : 'assistant.model',
    );
    _reviews[task.id] = review;
    return review;
  }

  HostModelPermission take(
    String taskId, {
    required bool manual,
    required String requestDigest,
    required DateTime now,
  }) {
    final review = _reviews.remove(taskId);
    if (review == null ||
        review.requestDigest != requestDigest ||
        review.decision.action == ReviewAction.block ||
        (!manual && !review.automatic) ||
        !now.isBefore(review.expiresAt)) {
      throw StateError('model_permission_unavailable');
    }
    review.checkCurrent();
    return HostModelPermission._(
      review,
      manual
          ? 'manual'
          : review.grantId == null
          ? 'mode_auto'
          : 'grant',
    );
  }
}

final class HostModelReview {
  HostModelReview._(
    this.owner,
    this.taskId,
    this.profile,
    this.payload,
    this.requestDigest,
    this.policyRevision,
    this.request,
    this.id,
    this.decision,
    bool automatic,
    this.grantId,
    this.expiresAt,
    this.checkCurrent, {
    this.compatiblePayload,
    this.withoutJsonObject = false,
    this.toolId = 'assistant.model',
  }) : automatic = automatic && decision.action == ReviewAction.allow;
  final HostModelAuthorization owner;
  final String taskId, payload, requestDigest, policyRevision, id;
  final ModelProfile profile;
  final GrantRequest request;
  final ReviewDecision decision;
  final bool automatic;
  final String? grantId;
  final DateTime expiresAt;
  final void Function() checkCurrent;
  final String? compatiblePayload;
  final bool withoutJsonObject;
  final String toolId;
}

/// An ephemeral, one-use capability for an exact wire body and host owner.
/// Its private constructor and private Zone key provide no JSON import path.
final class HostModelPermission {
  HostModelPermission._(this._review, this.source);
  final HostModelReview _review;
  final String source;
  static final _zoneKey = Object();
  static HostModelPermission? get current =>
      Zone.current[_zoneKey] as HostModelPermission?;
  int _attempts = 0;
  bool _retryAllowed = false, _variantReady = false;
  late String _wirePayload = _review.payload;
  late String _wireReviewId = _review.id;
  late String _wireToolId = _review.toolId;
  late ReviewDecision _wireDecision = _review.decision;
  bool get prefersWithoutJsonObject => _review.withoutJsonObject;
  void allowCompatibilityRetry() {
    if (_attempts != 1 || _wirePayload != _review.payload) {
      throw StateError('model_retry_unavailable');
    }
    _retryAllowed = true;
  }

  Future<void> prepareAttempt(String payload) async {
    if (payload == _wirePayload) return;
    if (payload != _review.compatiblePayload ||
        !(_attempts == 0 || (_attempts == 1 && _retryAllowed))) {
      throw StateError('model_wire_binding_changed');
    }
    _review.checkCurrent();
    final decision = await _review.owner.reviewer.review(
      OutboundReviewRequest(
        toolId: 'assistant.model',
        endpoint: _review.profile.endpoint,
        content: utf8.encode(payload),
        scopeDigest: _review.request.scopeDigest,
        sourceObjects: _review.owner.repository
            .task(_review.taskId)!
            .scope
            .objects,
      ),
    );
    _review.checkCurrent();
    final id = const Uuid().v4();
    await _review.owner.repository.database.write((db) {
      _review.checkCurrent();
      if (_review.owner.policy.current.revision != _review.policyRevision) {
        throw StateError('model_policy_changed');
      }
      db.execute(
        'INSERT INTO assistant_review_decisions(id,task_id,invocation_id,tool_id,destination_identity_digest,payload_digest,decision,reviewed,reason,created_at) VALUES(?,?,NULL,?,?,?,?,?,?,?)',
        [
          id,
          _review.taskId,
          'assistant.model',
          _hash(modelEndpointIdentity(_review.profile)),
          _hash(payload),
          decision.action.name,
          decision.reviewed ? 1 : 0,
          switch (decision.action) {
            ReviewAction.allow => null,
            ReviewAction.confirm => '内容审查需要人工确认',
            ReviewAction.block => '内容审查阻止发送',
          },
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    });
    if (decision.action == ReviewAction.block) {
      throw StateError('model_retry_review_blocked');
    }
    if (decision.action == ReviewAction.confirm && source != 'manual') {
      _review.owner._reviews[_review.taskId] = HostModelReview._(
        _review.owner,
        _review.taskId,
        _review.profile,
        payload,
        _review.requestDigest,
        _review.policyRevision,
        _review.request,
        id,
        decision,
        false,
        null,
        _review.expiresAt,
        _review.checkCurrent,
        withoutJsonObject: true,
      );
      throw const HostModelWireReviewRequired._();
    }
    _wirePayload = payload;
    _wireReviewId = id;
    _wireToolId = 'assistant.model';
    _wireDecision = decision;
    _retryAllowed = false;
    _variantReady = true;
  }

  String? get grantId => source == 'grant' ? _review.grantId : null;
  String get reviewId => _wireReviewId;
  T run<T>(T Function() operation) =>
      runZoned(operation, zoneValues: {_zoneKey: this});
  void check({
    required ManagedDatabase database,
    required ModelProfile profile,
    required String payload,
    bool beforeBegin = false,
  }) {
    if (!identical(database, _review.owner.repository.database) ||
        modelEndpointIdentity(profile) !=
            modelEndpointIdentity(_review.profile) ||
        _hash(jsonEncode(profile.toJson())) !=
            _hash(jsonEncode(_review.profile.toJson())) ||
        payload != _wirePayload ||
        (beforeBegin &&
            (_attempts >= 2 || (_attempts == 1 && !_variantReady))) ||
        !DateTime.now().toUtc().isBefore(_review.expiresAt)) {
      throw StateError('model_wire_binding_changed');
    }
    _review.checkCurrent();
    if (_review.owner.repository.task(_review.taskId)?.state !=
        PersonalTaskState.running) {
      throw StateError('model_task_not_running');
    }
    final records = database.raw.select(
      'SELECT * FROM assistant_review_decisions WHERE id=?',
      [reviewId],
    );
    if (records.length != 1 ||
        records.single['task_id'] != _review.taskId ||
        records.single['tool_id'] != _wireToolId ||
        records.single['payload_digest'] != _hash(_wirePayload) ||
        records.single['destination_identity_digest'] !=
            _hash(modelEndpointIdentity(profile)) ||
        records.single['decision'] != _wireDecision.action.name ||
        records.single['reviewed'] != (_wireDecision.reviewed ? 1 : 0) ||
        _wireDecision.action == ReviewAction.block ||
        (source != 'manual' && _wireDecision.action != ReviewAction.allow)) {
      throw StateError('model_review_changed');
    }
    final id = grantId;
    if (id != null) {
      final request = GrantRequest(
        category: 'model',
        toolId: 'assistant.model',
        scopeDigest: _review.request.scopeDigest,
        destination: _review.request.destination,
        taskId: _review.request.taskId,
        taskTainted: _review.owner.repository.authorizationFacts
            .readTask(_review.taskId)
            .requiresConfirmation,
        conversationId: _review.request.conversationId,
        now: DateTime.now().toUtc(),
      );
      final permitted = _attempts == 0
          ? _review.owner.grants.permitsUse(id, request)
          : _review.owner.grants.permitsIssuedApproval(id, request);
      if (!permitted) {
        throw StateError('model_grant_unavailable');
      }
    }
    final snapshot = _review.owner.policy.current;
    if (snapshot.revision != _review.policyRevision ||
        !snapshot.allows(AssistantAuthorizationCategory.model)) {
      throw StateError('model_policy_changed');
    }
  }

  void commitInTransaction(
    ManagedDatabase database,
    Database db,
    ModelProfile profile,
    String payload,
  ) {
    check(
      database: database,
      profile: profile,
      payload: payload,
      beforeBegin: true,
    );
    if (!identical(db, database.raw) || db.autocommit) {
      throw StateError('model_permission_owner_transaction_required');
    }
    if (_attempts == 0 &&
        grantId != null &&
        _review.owner.grants.recordUseInTransaction(
              db,
              grantId!,
              GrantRequest(
                category: 'model',
                toolId: 'assistant.model',
                scopeDigest: _review.request.scopeDigest,
                destination: _review.request.destination,
                taskId: _review.request.taskId,
                taskTainted: _review.owner.repository.authorizationFacts
                    .readTask(_review.taskId)
                    .requiresConfirmation,
                conversationId: _review.request.conversationId,
                now: DateTime.now().toUtc(),
              ),
            ) ==
            null) {
      throw StateError('model_grant_unavailable');
    }
  }

  void Function() watch(ModelCancellation token) {
    final id = grantId;
    return id == null
        ? () {}
        : _review.owner.grants.onRevocation(id, token.cancel);
  }

  void committed() {
    _attempts++;
    _variantReady = false;
  }
}

final class HostModelWireReviewRequired implements Exception {
  const HostModelWireReviewRequired._();
}
