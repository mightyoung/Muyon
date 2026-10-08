import 'package:muyon_module_api/muyon_module_api.dart' show ObjectRef;

enum ReviewAction { allow, confirm, block }

final class OutboundReviewRequest {
  OutboundReviewRequest({
    required this.toolId,
    required this.endpoint,
    required List<int> content,
    required this.scopeDigest,
    Iterable<ObjectRef> sourceObjects = const [],
  }) : content = List.unmodifiable(content),
       sourceObjects = List.unmodifiable(sourceObjects);
  final String toolId, scopeDigest;
  /// Null only for an actual local write; no invented transport identity.
  final Uri? endpoint;
  final List<int> content;
  final List<ObjectRef> sourceObjects;
}

final class ReviewDecision {
  const ReviewDecision.allow({this.reviewed = true})
    : action = ReviewAction.allow,
      reason = null;
  const ReviewDecision.confirm(String this.reason, {this.reviewed = true})
    : action = ReviewAction.confirm;
  const ReviewDecision.block(String this.reason, {this.reviewed = true})
    : action = ReviewAction.block;
  final ReviewAction action;
  final String? reason;
  final bool reviewed;
  String get reviewLabel => reviewed ? '已审查' : '未审查';
}

abstract interface class OutboundContentReviewer {
  Future<ReviewDecision> review(OutboundReviewRequest request);
}

final class NoopReviewer implements OutboundContentReviewer {
  const NoopReviewer();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async =>
      const ReviewDecision.allow(reviewed: false);
}

/// Never grants authority: callers must still require a grant/host confirmation.
/// Content and exception text never enter the fallback reason or any log.
final class ReviewerChain implements OutboundContentReviewer {
  ReviewerChain(
    Iterable<OutboundContentReviewer> reviewers, {
    required this.timeout,
  }) : reviewers = List.unmodifiable(reviewers) {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Reviewer timeout must be positive');
    }
  }
  final List<OutboundContentReviewer> reviewers;
  final Duration timeout;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    var strictest = const ReviewDecision.allow();
    var fullyReviewed = reviewers.isNotEmpty;
    for (final reviewer in reviewers) {
      ReviewDecision decision;
      try {
        decision = await reviewer.review(request).timeout(timeout);
      } catch (_) {
        decision = const ReviewDecision.confirm(
          '内容审查未完成，需要人工确认',
          reviewed: false,
        );
      }
      fullyReviewed = fullyReviewed && decision.reviewed;
      if (decision.action.index > strictest.action.index) {
        strictest = decision;
      }
    }
    return switch (strictest.action) {
      ReviewAction.allow => ReviewDecision.allow(reviewed: fullyReviewed),
      ReviewAction.confirm => ReviewDecision.confirm(
        strictest.reason!,
        reviewed: fullyReviewed,
      ),
      ReviewAction.block => ReviewDecision.block(
        strictest.reason!,
        reviewed: fullyReviewed,
      ),
    };
  }
}
