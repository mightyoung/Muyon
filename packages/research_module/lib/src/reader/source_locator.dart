import 'package:flutter/painting.dart';

/// What the reader knows about where a quoted source sits in a document.
///
/// A page jump and an exact text highlight are different promises. A
/// [PageOnly] result is always safe to act on; a highlight is only drawn for
/// [ExactMatch], and [AmbiguousMatch] says so instead of guessing.
sealed class QuoteLocation {
  const QuoteLocation();
}

/// The quote could not be searched (no text layer, scanned page, parser too
/// old); the page is still known, so only the page-level jump is offered.
final class PageOnly extends QuoteLocation {
  const PageOnly(this.reason);
  final String reason;
}

/// Exactly one place matches; [rects] are fractions (0..1) of the page size,
/// measured from the top-left.
final class ExactMatch extends QuoteLocation {
  const ExactMatch({required this.pageIndex, required this.rects});
  final int pageIndex;
  final List<Rect> rects;
}

/// The quote occurs [count] times (or context does not break the tie).
final class AmbiguousMatch extends QuoteLocation {
  const AmbiguousMatch(this.count);
  final int count;
}

/// The document is gone or was replaced since the reference was made; neither
/// the page nor the quote can be trusted.
final class SourceUnavailable extends QuoteLocation {
  const SourceUnavailable(this.reason);
  final String reason;
}

/// Resolved by the research domain layer (C3); the UI only renders the result.
abstract interface class QuoteLocator {
  Future<QuoteLocation> locate({
    required int pageIndex,
    required String quote,
    String? contextBefore,
    String? contextAfter,
  });
}
