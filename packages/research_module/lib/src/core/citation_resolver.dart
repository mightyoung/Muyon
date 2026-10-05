import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import '../cards/card_store.dart';
import '../cards/canonical_json.dart';
import '../reader/source_locator.dart';
import '../source_ref.dart';

/// Parser boundary: implementations must parse [original.bytes], never a
/// current document/path or caller-supplied page text. Null means no such page.
abstract interface class CitationPageProvider {
  Future<CitationPage?> loadPage(CitationDocument original, int pageIndex);
}

/// Evidence bound to a byte digest, parser version and zero-based physical page.
/// Character boxes, when supplied, are indexed by UTF-16 code unit in [text].
class CitationPage {
  CitationPage({
    required this.contentDigest,
    required this.pageIndex,
    required this.parserVersion,
    required this.text,
    List<SourceBox?>? characterBoxes,
  }) : characterBoxes = characterBoxes == null
           ? null
           : List.unmodifiable(characterBoxes) {
    if (text != null) validateUnicode(text!);
    validateUnicode(parserVersion);
  }
  final String contentDigest;
  final int pageIndex;
  final String parserVersion;
  final String? text;
  final List<SourceBox?>? characterBoxes;
}

/// Uses the existing pdfrx dependency to extract original PDF bytes and real
/// character geometry. It never installs a parser, normalizes text, or clamps
/// coordinates. A host using the web backend must initialize pdfrx as usual.
class PdfrxCitationPageProvider implements CitationPageProvider {
  const PdfrxCitationPageProvider();
  // Bump on any pdfrx/engine dependency or extraction/geometry change.
  // Installed: pdfrx 2.6.5, pdfrx_engine 0.6.1. Old anchors then remain
  // page-only with parser_version_mismatch; their JSON is never rewritten.
  static const version = 'pdfrx-2.6.5/engine-0.6.1/raw-v1';

  @override
  Future<CitationPage?> loadPage(
    CitationDocument original,
    int pageIndex,
  ) async {
    final document = await PdfDocument.openData(
      original.bytes,
      sourceName: 'citation:${original.contentDigest}',
    );
    try {
      if (pageIndex < 0 || pageIndex >= document.pages.length) return null;
      final page = document.pages[pageIndex];
      final raw = await page.loadText();
      List<SourceBox?>? boxes;
      if (raw != null &&
          page.width.isFinite &&
          page.height.isFinite &&
          page.width > 0 &&
          page.height > 0) {
        SourceBox? convert(PdfRect value) {
          if (value.isEmpty) return null;
          final rect = value.toRect(page: page);
          try {
            return SourceBox(
              left: rect.left / page.width,
              top: rect.top / page.height,
              right: rect.right / page.width,
              bottom: rect.bottom / page.height,
            );
          } on FormatException {
            // Invalid geometry stays unavailable; it is never clamped.
            return null;
          }
        }

        if (raw.charRects.length == raw.fullText.length) {
          boxes = raw.charRects.map(convert).toList();
        } else if (raw.charRects.length == raw.fullText.runes.length) {
          // Native PDFium indexes Unicode scalars, Dart strings use UTF-16.
          boxes = [];
          var index = 0;
          for (final rune in raw.fullText.runes) {
            final box = convert(raw.charRects[index++]);
            boxes.add(box);
            if (rune > 0xffff) boxes.add(box);
          }
        }
      }
      return CitationPage(
        contentDigest: original.contentDigest,
        pageIndex: pageIndex,
        parserVersion: version,
        text: raw?.fullText.isEmpty == true ? null : raw?.fullText,
        characterBoxes: boxes,
      );
    } finally {
      await document.dispose();
    }
  }
}

enum CitationStatus {
  missingSource,
  staleVersion,
  pageUnavailable,
  pageOnly,
  ambiguous,
  uniqueText,
  exact,
}

/// Page jump and highlight are independent promises. Offsets are half-open
/// UTF-16 offsets in the unmodified parser text; boxes are normalized from the
/// physical page's top-left. Unavailable/stale results never contain a page.
class CitationResolution {
  CitationResolution({
    required this.status,
    required this.reason,
    this.pageIndex,
    this.matchCount,
    this.startOffset,
    this.endOffset,
    List<SourceBox> boxes = const [],
  }) : boxes = List.unmodifiable(boxes);
  final CitationStatus status;
  final String reason;
  final int? pageIndex, matchCount, startOffset, endOffset;
  final List<SourceBox> boxes;
}

class CitationResolver {
  CitationResolver(
    this.store,
    this.projectId, {
    this.provider = const PdfrxCitationPageProvider(),
    this.ensureActive,
  });
  final CardStore store;
  final String projectId;
  final CitationPageProvider provider;
  final void Function()? ensureActive;

  CitationResolution? _unavailable(SourceRef source) {
    ensureActive?.call();
    final availability = store.sourceAvailability(projectId, source);
    if (availability == SourceAvailability.missing) {
      return CitationResolution(
        status: CitationStatus.missingSource,
        reason: 'missing_source',
      );
    }
    if (availability == SourceAvailability.replaced) {
      return CitationResolution(
        status: CitationStatus.staleVersion,
        reason: 'stale_version',
      );
    }
    return null;
  }

  Future<CitationResolution> resolve(SourceRef source) async {
    final unavailable = _unavailable(source);
    if (unavailable != null) return unavailable;
    final original = store.citationDocument(projectId, source)!;
    CitationPage? page;
    try {
      page = await provider.loadPage(original, source.pageIndex);
    } catch (_) {
      // Parsing may fail, but state/scope revocation still takes precedence.
      final changed = _unavailable(source);
      return changed ??
          CitationResolution(
            status: CitationStatus.pageUnavailable,
            reason: 'parser_unavailable',
          );
    }
    // Never publish geometry from a snapshot made obsolete while awaiting.
    final changed = _unavailable(source);
    if (changed != null) return changed;
    if (page == null) {
      return CitationResolution(
        status: CitationStatus.pageUnavailable,
        reason: 'page_unavailable',
      );
    }
    if (page.contentDigest != source.contentDigest ||
        page.pageIndex != source.pageIndex) {
      return CitationResolution(
        status: CitationStatus.pageUnavailable,
        reason: 'parser_evidence_mismatch',
      );
    }
    CitationResolution pageOnly(String reason, {int? count}) =>
        CitationResolution(
          status: CitationStatus.pageOnly,
          reason: reason,
          pageIndex: source.pageIndex,
          matchCount: count,
        );
    if (source.parserVersion != null &&
        source.parserVersion != page.parserVersion) {
      return pageOnly('parser_version_mismatch');
    }
    if (source.quote.isEmpty) return pageOnly('empty_quote');
    final text = page.text;
    if (text == null) return pageOnly('no_text_layer');
    var count = 0;
    var start = -1;
    var searchFrom = 0;
    while (searchFrom <= text.length) {
      final found = text.indexOf(source.quote, searchFrom);
      if (found < 0) break;
      count++;
      start = found;
      searchFrom = found + 1; // Include overlapping raw occurrences.
    }
    if (count != 1) {
      return CitationResolution(
        status: CitationStatus.ambiguous,
        reason: 'ambiguous',
        pageIndex: source.pageIndex,
        matchCount: count,
      );
    }
    final end = start + source.quote.length;
    if ((source.contextBefore != null &&
            !text.substring(0, start).endsWith(source.contextBefore!)) ||
        (source.contextAfter != null &&
            !text.substring(end).startsWith(source.contextAfter!))) {
      return pageOnly('context_mismatch', count: count);
    }
    final geometry = page.characterBoxes;
    final boxes = <SourceBox>[];
    var complete = geometry != null && geometry.length == text.length;
    if (complete) {
      for (var i = start; i < end; i++) {
        final box = geometry[i];
        if (box != null) {
          boxes.add(box);
        } else if (text[i].trim().isNotEmpty) {
          complete = false;
        }
      }
    }
    final exact = complete && boxes.isNotEmpty;
    return CitationResolution(
      status: exact ? CitationStatus.exact : CitationStatus.uniqueText,
      reason: exact ? 'exact' : 'geometry_unavailable',
      pageIndex: source.pageIndex,
      matchCount: 1,
      startOffset: start,
      endOffset: end,
      boxes: exact ? boxes : const [],
    );
  }
}

/// B's existing QuoteLocator adapter, bound to one immutable citation anchor.
class CitationQuoteLocator implements QuoteLocator {
  const CitationQuoteLocator(this.resolver, this.source);
  final CitationResolver resolver;
  final SourceRef source;
  @override
  Future<QuoteLocation> locate({
    required int pageIndex,
    required String quote,
    String? contextBefore,
    String? contextAfter,
  }) async {
    if (pageIndex != source.pageIndex ||
        quote != source.quote ||
        contextBefore != source.contextBefore ||
        contextAfter != source.contextAfter) {
      return const SourceUnavailable('anchor_mismatch');
    }
    CitationResolution result;
    try {
      result = await resolver.resolve(source);
    } on StateError {
      // B's generic exception handler offers PageOnly. Scope/session denial
      // must instead revoke the page promise as well as the highlight.
      return const SourceUnavailable('scope_or_session_unavailable');
    }
    return switch (result.status) {
      CitationStatus.exact => ExactMatch(
        pageIndex: result.pageIndex!,
        rects: List.unmodifiable(
          result.boxes.map(
            (b) => Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
          ),
        ),
      ),
      CitationStatus.ambiguous => AmbiguousMatch(result.matchCount!),
      CitationStatus.pageOnly ||
      CitationStatus.uniqueText => PageOnly(result.reason),
      _ => SourceUnavailable(result.reason),
    };
  }
}
