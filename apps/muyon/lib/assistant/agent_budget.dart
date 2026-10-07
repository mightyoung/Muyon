/// Budgets of one assistant task (ADR-0005 §6.1). Only host configuration
/// sets them: a model reply, a document or a tool result cannot raise or
/// reset one. Usage lives in the task payload, so it survives restarts and
/// can be replayed.
library;

import 'dart:math' as math;

/// Which budget ran out first.
enum BudgetKind { steps, activeTime, tokens }

class Budget {
  const Budget({
    this.maxSteps = 4,
    this.maxActive = const Duration(minutes: 10),
    this.maxTokens = 200000,
    this.maxCallsPerStep = 8,
    this.maxCardCalls = 5,
    this.requestCap = const Duration(minutes: 5),
  });

  /// One step is one model request with its tool calls and their results; a
  /// corrective round counts as a step. 4 until graded authorization (AUTH-1)
  /// exists.
  final int maxSteps;

  /// Time the task is actually running (a model stream, a tool call). Time
  /// spent waiting for the person's confirmation is never counted.
  final Duration maxActive;

  /// Prompt plus completion tokens, as reported by the endpoint or, when it
  /// does not report, estimated conservatively.
  final int maxTokens;

  /// Calls of one reply that are looked at; the rest come back "not run".
  final int maxCallsPerStep;

  /// Write / export calls on one confirmation card.
  final int maxCardCalls;

  /// Absolute limit of one request, whatever is left of [maxActive].
  final Duration requestCap;

  /// Old name of [maxSteps].
  int get maxRounds => maxSteps;

  /// The first budget [usage] has used up, or null.
  BudgetKind? exhausted(BudgetUsage usage) {
    if (usage.steps >= maxSteps) return BudgetKind.steps;
    if (usage.active >= maxActive) return BudgetKind.activeTime;
    if (usage.tokens >= maxTokens) return BudgetKind.tokens;
    return null;
  }

  int remainingTokens(BudgetUsage usage) => maxTokens - usage.tokens;

  /// What one request may take: the smaller of what is left of the active
  /// budget and [requestCap] (a slow trickle cannot outlast the budget).
  Duration requestLimit(BudgetUsage usage) {
    final left = maxActive - usage.active;
    final limit = left < requestCap ? left : requestCap;
    return limit < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : limit;
  }
}

/// What a task has used so far; read from and written to its payload.
class BudgetUsage {
  const BudgetUsage({
    this.steps = 0,
    this.active = Duration.zero,
    this.tokens = 0,
    this.estimated = false,
  });
  final int steps;
  final Duration active;
  final int tokens;

  /// True when any part of [tokens] is an estimate, not an endpoint report.
  final bool estimated;

  factory BudgetUsage.fromPayload(Map<String, Object?> payload) => BudgetUsage(
    steps: payload['round'] as int? ?? 0,
    active: Duration(milliseconds: payload['activeMs'] as int? ?? 0),
    tokens: payload['tokensUsed'] as int? ?? 0,
    estimated: payload['tokensEstimated'] == true,
  );

  /// The payload keys that change with usage (`round` is the step count and
  /// keeps its old name).
  Map<String, Object?> toPayload() => {
    'round': steps,
    'activeMs': active.inMilliseconds,
    'tokensUsed': tokens,
    'tokensEstimated': estimated,
  };

  BudgetUsage plus({
    Duration active = Duration.zero,
    int tokens = 0,
    bool estimated = false,
  }) => BudgetUsage(
    steps: steps,
    active: this.active + active,
    tokens: this.tokens + math.max(0, tokens),
    estimated: this.estimated || estimated,
  );
}
