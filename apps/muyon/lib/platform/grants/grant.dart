enum GrantCategory { model, write, outbound }

enum GrantDuration { once, task, conversation, timed, always }

GrantCategory parseGrantCategory(String category) {
  if (category == 'read') {
    throw ArgumentError('Read operations do not use grants');
  }
  return GrantCategory.values.byName(category);
}

final class GrantRequest {
  GrantRequest({
    required String category,
    required this.toolId,
    required this.scopeDigest,
    required this.destination,
    required DateTime now,
    this.taskId,
    this.conversationId,
    this.taskTainted = false,
  }) : category = parseGrantCategory(category),
       now = now.toUtc();
  final GrantCategory category;
  final String toolId, scopeDigest;
  final String? destination, taskId, conversationId;
  final DateTime now;
  final bool taskTainted;
}

final class GrantDraft {
  GrantDraft({
    required String category,
    required this.toolId,
    required this.scopeDigest,
    required this.destination,
    required this.duration,
    this.taskId,
    this.conversationId,
    this.expiresAt,
    this.maxUses,
  }) : category = parseGrantCategory(category);
  final GrantCategory category;
  final String toolId, scopeDigest;
  final String? destination, taskId, conversationId;
  final GrantDuration duration;
  final DateTime? expiresAt;
  final int? maxUses;
}

final class AssistantGrant {
  AssistantGrant.fromRow(Map<String, Object?> row)
    : id = row['grant_id'] as String,
      category = parseGrantCategory(row['category'] as String),
      toolId = row['tool_id'] as String,
      scopeDigest = row['scope_digest'] as String,
      destination = row['destination'] as String?,
      duration = GrantDuration.values.byName(row['duration_kind'] as String),
      taskId = row['task_id'] as String?,
      conversationId = row['conversation_id'] as String?,
      expiresAt = _date(row['expires_at']),
      maxUses = row['max_uses'] as int?,
      uses = row['uses'] as int,
      createdAt = DateTime.parse(row['created_at'] as String),
      revokedAt = _date(row['revoked_at']);
  final String id, toolId, scopeDigest;
  final GrantCategory category;
  final GrantDuration duration;
  final String? destination, taskId, conversationId;
  final DateTime? expiresAt, revokedAt;
  final DateTime createdAt;
  final int? maxUses;
  final int uses;
  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();

  bool matches(GrantRequest request, {bool checkUseLimit = true}) {
    if (category != request.category ||
        toolId != request.toolId ||
        scopeDigest != request.scopeDigest ||
        destination != request.destination) {
      return false;
    }
    if (revokedAt != null ||
        (expiresAt != null && !request.now.isBefore(expiresAt!)) ||
        (checkUseLimit && maxUses != null && uses >= maxUses!)) {
      return false;
    }
    if (request.taskTainted &&
        (category == GrantCategory.write ||
            category == GrantCategory.outbound)) {
      return false;
    }
    if (duration == GrantDuration.task &&
        (taskId == null || taskId!.isEmpty || request.taskId != taskId)) {
      return false;
    }
    if (duration == GrantDuration.conversation &&
        (conversationId == null ||
            conversationId!.isEmpty ||
            request.conversationId != conversationId)) {
      return false;
    }
    if (duration == GrantDuration.timed && expiresAt == null) {
      return false;
    }
    if (category == GrantCategory.outbound) {
      if (duration == GrantDuration.always ||
          destination == null ||
          destination!.trim().isEmpty) {
        return false;
      }
      // ADR-0002 Q2: even timed or task outbound grants cannot outlive the
      // conversation. Once may lack a conversation, but respects one if bound.
      if ((duration != GrantDuration.once || conversationId != null) &&
          (conversationId == null ||
              conversationId!.isEmpty ||
              request.conversationId != conversationId)) {
        return false;
      }
    }
    return true;
  }
}
