/// Conservative token estimate for budgets and context windows (ADR-0005
/// §6.1). ASCII text counts bytes ÷ 4; every non-ASCII character counts 1
/// token, since bytes ÷ 4 would put Chinese text at about half its real size.
int estimateTokens(String text) {
  var ascii = 0;
  var other = 0;
  for (final rune in text.runes) {
    if (rune < 0x80) {
      ascii++;
    } else {
      other++;
    }
  }
  return (ascii / 4).ceil() + other;
}

/// Reserved for K-3 (budgets and compaction); not used by K-2a.
///
/// Tokens of a request: the provider's own count when it reported one, else
/// the estimate of [text].
int tokensOf(String text, {int? reported}) => reported ?? estimateTokens(text);

/// Reserved for K-3.
///
/// Tokens of a prompt that grew since the last report: the reported prompt
/// size plus an estimate of only the content added after it.
int tokensSinceReport({required int reported, required String added}) =>
    reported + estimateTokens(added);
