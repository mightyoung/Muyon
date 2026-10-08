import 'package:muyon/platform/grants/outbound_content_reviewer.dart';

/// These fixtures deliberately narrow the model stage to manual confirmation
/// so their later tool/source/card assertions remain isolated. Production
/// default mode_auto is covered separately against the actual host.
final class ConfirmModelReviewer implements OutboundContentReviewer {
  const ConfirmModelReviewer();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async =>
      const ReviewDecision.confirm('fixture requires explicit model review');
}
