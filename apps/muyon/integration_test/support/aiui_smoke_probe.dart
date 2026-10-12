import 'aiui_smoke_config.dart';

enum SmokeCardSource { hostFixed, validatedStream }

/// Monotonic times are supplied at production acceptance/first qualifying
/// frame. Merely pumping a test, receiving bytes or observing a draft is not an
/// event. Missing hooks stay missing; they are never synthesized from a timer.
final class SmokeLatencySample {
  SmokeLatencySample(this.index);
  final int index;
  String? _task;
  Duration? submitAt, firstTextVisibleAt, firstCardVisibleAt;
  SmokeCardSource? cardSource;
  SmokeFailureCode? missingReason;
  final List<Duration> confirmationWaits = [];
  int? historicalFirstEventMs;
  String? get taskIdentity => _task;

  bool accept(String task, Duration at) {
    if (_task != null || task.isEmpty || at.isNegative) return false;
    _task = task;
    submitAt = at;
    return true;
  }

  bool textFrame(
    String task,
    Duration at, {
    required bool nonEmpty,
    required bool completeVisibleFrame,
  }) {
    if (task != _task ||
        submitAt == null ||
        at < submitAt! ||
        !nonEmpty ||
        !completeVisibleFrame) {
      return false;
    }
    firstTextVisibleAt ??= at;
    return true;
  }

  bool cardFrame(
    String task,
    Duration at, {
    required SmokeCardSource source,
    required bool currentPin,
    required bool completeVisibleFrame,
    required bool wholeValidated,
    required bool readonly,
    required bool fallback,
  }) {
    if (task != _task ||
        submitAt == null ||
        at < submitAt! ||
        !currentPin ||
        !completeVisibleFrame ||
        !readonly ||
        fallback ||
        (source == SmokeCardSource.validatedStream && !wholeValidated)) {
      return false;
    }
    if (firstCardVisibleAt == null) {
      firstCardVisibleAt = at;
      cardSource = source;
    }
    return true;
  }

  Map<String, Object?> toEvidence() => {
    'sample': index,
    'first_text_visible_ms': submitAt == null || firstTextVisibleAt == null
        ? null
        : (firstTextVisibleAt! - submitAt!).inMicroseconds / 1000,
    'first_card_visible_ms': submitAt == null || firstCardVisibleAt == null
        ? null
        : (firstCardVisibleAt! - submitAt!).inMicroseconds / 1000,
    'card_source': switch (cardSource) {
      SmokeCardSource.hostFixed => 'host_fixed',
      SmokeCardSource.validatedStream => 'validated_stream',
      null => null,
    },
    'historical_first_event_ms': historicalFirstEventMs,
    'confirmation_count': confirmationWaits.length,
    'confirmation_wait_ms': confirmationWaits
        .map((wait) => wait.inMicroseconds / 1000)
        .toList(),
    'missing_reason':
        missingReason?.code ??
        (firstTextVisibleAt == null || firstCardVisibleAt == null
            ? SmokeFailureCode.requestObservabilityMissing.code
            : null),
  };
}

final class AiuiSmokeProbe {
  AiuiSmokeProbe() : _clock = (Stopwatch()..start());
  final Stopwatch _clock;
  Duration get now => _clock.elapsed;
  final List<SmokeLatencySample> samples = List.unmodifiable(
    List.generate(5, (index) => SmokeLatencySample(index + 1)),
  );

  bool accept(int index, String task, Duration at) =>
      !samples.any((sample) => sample.taskIdentity == task) &&
      samples[index].accept(task, at);

  Map<String, Object?> latencyEvidence() {
    final values = samples.map((sample) => sample.toEvidence()).toList();
    final text = values
        .map((sample) => sample['first_text_visible_ms'] as num?)
        .toList();
    final card = values
        .map((sample) => sample['first_card_visible_ms'] as num?)
        .toList();
    final complete =
        text.every((value) => value != null) &&
        card.every((value) => value != null);
    return {
      'samples': values,
      'sample_count': 5,
      'valid_text_samples': text.whereType<num>().length,
      'valid_card_samples': card.whereType<num>().length,
      'complete': complete,
      'first_text_median_ms': exactFiveMedian(text),
      'first_card_median_ms': exactFiveMedian(card),
      'threshold_conclusion': 'not_assessed',
    };
  }
}

num? exactFiveMedian(List<num?> values) {
  if (values.length != 5 ||
      values.any((value) => value == null || !value.isFinite || value < 0)) {
    return null;
  }
  final sorted = values.cast<num>().toList()..sort();
  return sorted[2];
}
