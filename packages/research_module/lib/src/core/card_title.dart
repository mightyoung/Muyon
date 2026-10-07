import 'package:characters/characters.dart';

/// Card title (review N4/F10): the first non-empty line of [bodyMarkdown]
/// without heading marks, truncated to [maxLength] characters with an
/// ellipsis; [fallback] when there is no text. Truncation counts grapheme
/// clusters, so surrogate pairs (emoji), CJK text and combining marks are
/// never split.
String cardTitleFromMarkdown(
  String bodyMarkdown, {
  required String fallback,
  int maxLength = 60,
}) {
  for (final line in bodyMarkdown.split('\n')) {
    final trimmed = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    if (trimmed.isNotEmpty) {
      final characters = trimmed.characters;
      return characters.length > maxLength
          ? '${characters.take(maxLength)}…'
          : trimmed;
    }
  }
  return fallback;
}
