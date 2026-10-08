import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import '../tool_registry.dart';
import 'host_authorization_facts.dart';
import 'outbound_content_reviewer.dart';

/// Private construction prevents model input from manufacturing review facts.
final class HostReviewOutcome {
  const HostReviewOutcome._(
    this.action,
    this.reviewed,
    this.reviewDecisionId,
    this.grantId,
    this._issuer,
    this._call,
    this._snapshot,
  );
  final ReviewAction action;
  final bool reviewed;
  final String? reviewDecisionId, grantId;
  final HostToolAuthorization? _issuer;
  final PreparedToolCall? _call;
  final String? _snapshot;

  HostAuthorizationLink transportLink(
    ToolRegistry registry,
    ToolCallRequest request, {
    required bool Function() isActive,
  }) {
    final call = _call;
    if (call == null ||
        request.invocationId != call.request.invocationId ||
        request.replayKey != call.request.replayKey ||
        request.toolId != call.request.toolId ||
        request.approvalId == null ||
        call.effectIntent == null) {
      throw const ToolPlatformException(
        'review_mismatch',
        'Signed host invocation required',
      );
    }
    final rows = registry.database.raw.select(
      'SELECT * FROM tool_approvals WHERE id=?',
      [request.approvalId],
    );
    if (rows.length != 1) {
      throw const ToolPlatformException(
        'approval_required',
        'Current approval required',
      );
    }
    final row = rows.single;
    final source = row['authorization_source'] as String;
    final sourceGrant = row['grant_id'] as String?;
    void guard() {
      if ((source != 'manual' && source != 'grant') ||
          (source == 'manual' && sourceGrant != null) ||
          (source == 'grant' &&
              (sourceGrant == null || sourceGrant != grantId))) {
        throw const ToolPlatformException(
          'source_mismatch',
          'Actual permission source required',
        );
      }
      requireCurrent(registry, call, manual: source == 'manual');
      final current = registry.database.raw.select(
        'SELECT * FROM tool_approvals WHERE id=?',
        [request.approvalId],
      );
      if (!isActive() ||
          current.length != 1 ||
          current.single['state'] != 'consumed' ||
          current.single['identity_digest'] != call.identityDigest ||
          current.single['review_decision_id'] != reviewDecisionId ||
          current.single['authorization_source'] != source ||
          current.single['grant_id'] != sourceGrant ||
          !registry.clock().isBefore(
            DateTime.parse(current.single['expires_at'] as String),
          ) ||
          (sourceGrant != null &&
              !(registry.grants?.permitsIssuedApproval(
                    sourceGrant,
                    registry.authorizationRequest(call),
                  ) ??
                  false))) {
        throw const ToolPlatformException(
          'authorization_invalidated',
          'Transport authority was withdrawn',
        );
      }
    }

    guard();
    return HostAuthorizationLink._(
      database: registry.database,
      grantId: sourceGrant,
      authorizationSource: source,
      reviewDecisionId: reviewDecisionId!,
      taskId: _issuer!._facts(call.request)?.taskId,
      toolId: request.toolId,
      endpoint: call.effectIntent!.endpoint,
      endpointIdentity: call.effectIntent!.endpointIdentity,
      payloadDigest: call.effectIntent!.payloadDigest,
      guard: guard,
    );
  }

  void requireCurrent(
    ToolRegistry registry,
    PreparedToolCall call, {
    bool manual = false,
  }) {
    if (_issuer == null ||
        !identical(_issuer.registry, registry) ||
        _call == null ||
        _call.identityDigest != call.identityDigest ||
        reviewDecisionId == null ||
        action == ReviewAction.block ||
        (!manual && action != ReviewAction.allow) ||
        _issuer._snapshot(call) != _snapshot ||
        registry.currentEffectIntent(call)?.digest !=
            _call.effectIntent?.digest) {
      throw const ToolPlatformException(
        'review_stale',
        'Current host review required',
      );
    }
    final rows = registry.database.raw.select(
      'SELECT * FROM assistant_review_decisions WHERE id=?',
      [reviewDecisionId],
    );
    if (rows.length != 1 ||
        rows.single['decision'] != action.name ||
        rows.single['reviewed'] != (reviewed ? 1 : 0) ||
        rows.single['task_id'] != _issuer._facts(call.request)?.taskId ||
        rows.single['invocation_id'] != call.request.invocationId ||
        rows.single['tool_id'] != call.request.toolId ||
        rows.single['payload_digest'] != call.effectIntent?.payloadDigest ||
        rows.single['destination_identity_digest'] !=
            call.effectIntent?.destinationDigest) {
      throw const ToolPlatformException(
        'review_stale',
        'Persisted review does not match effect',
      );
    }
  }
}

/// Host service, absent from the module registrar and model request schema.
/// Review never consumes permission and never creates a transport attempt.
final class HostToolAuthorization {
  HostToolAuthorization({
    required this.registry,
    required this.reviewer,
    this.taskFacts,
  });
  final ToolRegistry registry;
  final OutboundContentReviewer reviewer;
  final HostTaskFacts? Function(ToolCallRequest)? taskFacts;
  HostTaskFacts? _facts(ToolCallRequest request) => taskFacts?.call(request);

  Future<String?> confirm(HostReviewOutcome outcome) async {
    if (!identical(outcome._issuer, this) ||
        outcome.action == ReviewAction.block ||
        outcome._call == null) {
      return null;
    }
    return registry.approve(outcome._call, review: outcome);
  }

  Future<String?> sign(HostReviewOutcome outcome) async {
    if (!identical(outcome._issuer, this) ||
        outcome.action != ReviewAction.allow ||
        outcome.grantId == null ||
        outcome._call == null) {
      return null;
    }
    return registry.approveWithGrant(
      outcome._call,
      grantId: outcome.grantId!,
      review: outcome,
    );
  }

  String _snapshot(PreparedToolCall call) {
    final context = registry.grantContext?.call(call.request);
    final facts = _facts(call.request);
    final modules = context?.allowedModuleIds.toList() ?? <String>[];
    final sources = facts?.sourceDigests.toList() ?? <String>[]
      ..sort();
    modules.sort();
    return jsonEncode([
      facts?.taskId,
      facts?.conversationId,
      facts?.taintState.name,
      sources,
      context?.taskId,
      context?.conversationId,
      context?.scopeRevision,
      context?.taskTainted,
      modules,
    ]);
  }

  String? _authority(PreparedToolCall call) {
    final context = registry.grantContext?.call(call.request);
    final facts = _facts(call.request);
    if (context == null ||
        facts == null ||
        context.scopeRevision.isEmpty ||
        context.taskTainted ||
        facts.requiresConfirmation ||
        context.taskId != facts.taskId ||
        context.conversationId != facts.conversationId) {
      return null;
    }
    final modules = context.allowedModuleIds.toList()..sort();
    return jsonEncode([
      context.taskId,
      context.conversationId,
      context.scopeRevision,
      modules,
    ]);
  }

  Future<HostReviewOutcome> review(PreparedToolCall call) async {
    final intent = call.effectIntent;
    if (intent == null) {
      return const HostReviewOutcome._(
        ReviewAction.confirm,
        false,
        null,
        null,
        null,
        null,
        null,
      );
    }
    final snapshot = _snapshot(call);
    final authority = _authority(call);
    final candidate = authority == null
        ? null
        : registry.grants?.findMatching(registry.authorizationRequest(call));
    ReviewDecision decision;
    try {
      decision = await reviewer.review(
        OutboundReviewRequest(
          toolId: intent.toolId,
          endpoint: intent.endpoint,
          content: intent.content,
          scopeDigest: call.identityDigest,
          sourceObjects: intent.sourceObjects,
        ),
      );
    } catch (_) {
      decision = const ReviewDecision.confirm(
        'review unavailable',
        reviewed: false,
      );
    }
    return registry.database.write((db) {
      final currentIntent = registry.currentEffectIntent(call);
      final currentGrant =
          authority == null ||
              candidate == null ||
              _authority(call) != authority ||
              currentIntent?.digest != intent.digest
          ? null
          : registry.grants?.findMatching(registry.authorizationRequest(call));
      final grantId = currentGrant?.id == candidate?.id
          ? currentGrant?.id
          : null;
      final action = decision.action == ReviewAction.allow && grantId == null
          ? ReviewAction.confirm
          : decision.action;
      final reason = switch (decision.action) {
        ReviewAction.block => 'review_block',
        ReviewAction.confirm => 'review_confirm',
        ReviewAction.allow =>
          grantId == null ? 'authority_unavailable' : 'review_allow',
      };
      final id = const Uuid().v4();
      db.execute(
        'INSERT INTO assistant_review_decisions('
        'id,task_id,invocation_id,tool_id,destination_identity_digest,payload_digest,'
        'decision,reviewed,reason,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          _facts(call.request)?.taskId,
          call.request.invocationId,
          call.request.toolId,
          intent.destinationDigest,
          intent.payloadDigest,
          action.name,
          decision.reviewed ? 1 : 0,
          reason,
          registry.clock().toUtc().toIso8601String(),
        ],
      );
      return HostReviewOutcome._(
        action,
        decision.reviewed,
        id,
        action == ReviewAction.allow ? grantId : null,
        this,
        call,
        snapshot,
      );
    });
  }
}

/// A live host capability for one reviewed transport request. No JSON decoder.
final class HostAuthorizationLink {
  HostAuthorizationLink._({
    required this.database,
    required this.grantId,
    required this.authorizationSource,
    required this.reviewDecisionId,
    required this.taskId,
    required this.toolId,
    required this._endpoint,
    required this._endpointIdentity,
    required this._payloadDigest,
    required this._guard,
  });
  final ManagedDatabase database;
  final String? grantId;
  final String authorizationSource, reviewDecisionId, toolId;
  final String? taskId;
  final Uri _endpoint;
  final String _endpointIdentity;
  final String _payloadDigest;
  final void Function() _guard;
  var _reserved = false;

  /// Bind the transport's actual TLS/config identity, including its pin.
  void checkEndpointIdentity(String actualIdentity) {
    if (actualIdentity != _endpointIdentity) {
      throw const ToolPlatformException(
        'transport_identity_mismatch',
        'Actual transport identity differs from reviewed destination',
      );
    }
    _guard();
  }

  void check(
    ManagedDatabase owner,
    String tool,
    Uri endpoint,
    String payloadDigest,
  ) {
    if (!identical(owner, database) ||
        tool != toolId ||
        endpoint != _endpoint ||
        payloadDigest != _payloadDigest) {
      throw const ToolPlatformException(
        'transport_mismatch',
        'Reviewed transport bytes and destination required',
      );
    }
    _guard();
  }

  void reserve(
    ManagedDatabase owner,
    String tool,
    Uri endpoint,
    String payloadDigest,
  ) {
    check(owner, tool, endpoint, payloadDigest);
    if (_reserved) {
      throw const ToolPlatformException(
        'transport_replay',
        'Transport capability already submitted',
      );
    }
    _reserved = true;
  }
}
