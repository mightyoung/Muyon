import 'dart:convert';

import 'aiui_smoke_config.dart';
import 'aiui_smoke_probe.dart';

const smokeCaseIds = {
  'ANDROID1',
  'ANDROID2',
  'ANDROID3_NO_MODEL',
  'ANDROID3_INTERRUPTION',
  'ANDROID3_CANCEL',
  'ANDROID3_TIMEOUT',
  'ANDROID4_SCOPE_VISIBLE',
  'ANDROID4_SCOPE_PLANNING',
  'ANDROID4_VERSION_VISIBLE',
  'ANDROID4_VERSION_PLANNING',
  'ANDROID7',
  'MODE_AUTOMATIC',
  'MODE_FEW',
  'MODE_TEXT_ONLY',
  'PROTOCOL_BAD_LINE',
  'PROTOCOL_MISSING_END',
  'PROTOCOL_LIMIT',
  'PROTOCOL_INVALID_FINAL',
  'PROTOCOL_AFTER_END',
};

final class AiuiSmokeEvidence {
  AiuiSmokeEvidence({required this.runId, this.candidateSha});
  final String runId;
  final String? candidateSha;
  final preflight = <String, Object?>{};
  final cases = <Map<String, Object?>>[];
  final probe = AiuiSmokeProbe();
  SmokeFailureCode? failure;
  bool realUpstreamObserved = false;
  bool checkpointComplete = false;

  Map<String, Object?> filtered() => filterSmokeEvidence({
    'schema': 1,
    'candidate_sha': candidateSha,
    'run_id': runId,
    'device_display': 'unobserved_device',
    'model_display': 'unobserved_model',
    'evidence_class': realUpstreamObserved ? 'real_upstream' : 'not_executed',
    'automated_items': [1, 2, 3, 4, 7],
    'manual_items': [5, 6],
    'preflight': preflight,
    'cases': cases,
    'latency': probe.latencyEvidence(),
    'manual_checkpoint': {'complete': checkpointComplete, 'status': 'pending'},
    'summary': {
      'passed': false,
      'failure_code':
          failure?.code ?? SmokeFailureCode.acceptanceCoverageIncomplete.code,
    },
  });
}

const _capabilityNames = {
  'production_stream',
  'library_2',
  'presentation_policy',
  'conversation_fact_card',
  'production_fallback',
  'failure_diagnostics',
  'request_observability',
  'frame_observability',
  'fault_io_boundary',
  'manual_checkpoint',
};
final _codes = {for (final code in SmokeFailureCode.values) code.code};
String? _code(Object? value) =>
    value is String && _codes.contains(value) ? value : null;
num? _number(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value : null;
Map _map(Object? value) => value is Map ? value : const {};
String? _sha(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{40}$').hasMatch(value) ? value : null;

/// Reconstruct each nested group from reviewed keys and constrained values.
/// No arbitrary text survives: even allowed-key values cannot smuggle an
/// endpoint, key, local path, exception stack, model response or raw DB row.
Map<String, Object?> filterSmokeEvidence(Map<String, Object?> raw) {
  final preflight = _map(raw['preflight']);
  final latency = _map(raw['latency']);
  final inputSamples = latency['samples'];
  final originalSampleCount = inputSamples is List ? inputSamples.length : 0;
  final exactlyFiveSamples = originalSampleCount == 5;
  final samples = <Map<String, Object?>>[];
  if (inputSamples is List) {
    for (var index = 0; index < 5 && index < inputSamples.length; index++) {
      final row = _map(inputSamples[index]);
      samples.add({
        'sample': index + 1,
        'first_text_visible_ms': _number(row['first_text_visible_ms']),
        'first_card_visible_ms': _number(row['first_card_visible_ms']),
        'card_source':
            {'host_fixed', 'validated_stream'}.contains(row['card_source'])
            ? row['card_source']
            : null,
        'historical_first_event_ms': _number(row['historical_first_event_ms']),
        'confirmation_count': row['confirmation_wait_ms'] is List
            ? (row['confirmation_wait_ms'] as List)
                  .whereType<num>()
                  .where((n) => n.isFinite && n >= 0)
                  .length
            : 0,
        'confirmation_wait_ms': row['confirmation_wait_ms'] is List
            ? (row['confirmation_wait_ms'] as List)
                  .map(_number)
                  .whereType<num>()
                  .toList()
            : <num>[],
        'missing_reason': _code(row['missing_reason']),
      });
    }
  }
  final texts = samples
      .map((sample) => sample['first_text_visible_ms'] as num?)
      .toList();
  final cards = samples
      .map((sample) => sample['first_card_visible_ms'] as num?)
      .toList();
  final cases = <Map<String, Object?>>[];
  if (raw['cases'] case final List inputCases) {
    for (final value in inputCases) {
      final row = _map(value);
      if (!smokeCaseIds.contains(row['id'])) continue;
      final counts = _map(row['counts']);
      cases.add({
        'id': row['id'],
        'status': {'passed', 'failed', 'not_yet'}.contains(row['status'])
            ? row['status']
            : 'failed',
        'stage':
            {
              'preflight',
              'submit',
              'planning',
              'frame',
              'invariants',
              'handoff',
            }.contains(row['stage'])
            ? row['stage']
            : 'preflight',
        'failure_code': _code(row['failure_code']),
        'fact_source_match': row['fact_source_match'] == true,
        'real_suggestion_present': row['real_suggestion_present'] == true,
        'counts': {
          for (final key in [
            'business_write_tasks',
            'business_write_approvals',
            'business_write_receipts',
            'business_grant_uses',
            'model_grant_uses',
          ])
            key: _number(counts[key]),
        },
        'evidence_class':
            {
              'real_upstream',
              'scripted_fixture',
              'not_executed',
            }.contains(row['evidence_class'])
            ? row['evidence_class']
            : 'not_executed',
      });
    }
  }
  final run = raw['run_id'];
  final runId =
      run is String &&
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(run)
      ? run
      : null;
  final summary = _map(raw['summary']);
  final complete =
      exactlyFiveSamples &&
      texts.every((value) => value != null) &&
      cards.every((value) => value != null);
  final allCasesPresent = smokeCaseIds.every(
    (id) => cases.where((row) => row['id'] == id).length == 1,
  );
  final passed =
      summary['passed'] == true &&
      preflight['passed'] == true &&
      _sha(raw['candidate_sha']) != null &&
      runId != null &&
      complete &&
      raw['evidence_class'] == 'real_upstream' &&
      allCasesPresent &&
      cases.every(
        (row) =>
            row['status'] == 'passed' &&
            row['failure_code'] == null &&
            [
              'business_write_tasks',
              'business_write_approvals',
              'business_write_receipts',
              'business_grant_uses',
            ].every((key) => (row['counts'] as Map)[key] == 0),
      ) &&
      cases.any(
        (row) =>
            row['id'] == 'ANDROID1' &&
            row['fact_source_match'] == true &&
            row['real_suggestion_present'] == true &&
            row['evidence_class'] == 'real_upstream',
      ) &&
      _map(raw['manual_checkpoint'])['complete'] == true;
  final result = <String, Object?>{
    'schema': 1, 'candidate_sha': _sha(raw['candidate_sha']), 'run_id': runId,
    // Labels are deliberately generic. Unreviewed device/model labels are free
    // text and may themselves contain credentials or destinations.
    'device_display': 'unobserved_device',
    'model_display': 'unobserved_model',
    'android_version':
        raw['android_version'] is int && (raw['android_version'] as int) > 0
        ? raw['android_version']
        : null,
    'evidence_class':
        {
          'real_upstream',
          'scripted_fixture',
          'not_executed',
        }.contains(raw['evidence_class'])
        ? raw['evidence_class']
        : 'not_executed',
    'automated_items': [1, 2, 3, 4, 7], 'manual_items': [5, 6],
    'preflight': {
      'passed': preflight['passed'] == true,
      'failure_code': _code(preflight['failure_code']),
      'failure_codes': preflight['failure_codes'] is List
          ? (preflight['failure_codes'] as List)
                .map(_code)
                .whereType<String>()
                .toList()
          : <String>[],
      'capabilities': {
        for (final key in _capabilityNames)
          key: _map(preflight['capabilities'])[key] is bool
              ? _map(preflight['capabilities'])[key]
              : null,
      },
    },
    'cases': cases,
    'latency': {
      'samples': samples,
      // Output remains bounded, but completeness and denominators refer to
      // the original attempts. A failed sixth attempt cannot disappear.
      'sample_count': originalSampleCount,
      'retained_sample_count': samples.length,
      'valid_text_samples': inputSamples is List
          ? inputSamples
                .where(
                  (row) => _number(_map(row)['first_text_visible_ms']) != null,
                )
                .length
          : 0,
      'valid_card_samples': inputSamples is List
          ? inputSamples
                .where(
                  (row) => _number(_map(row)['first_card_visible_ms']) != null,
                )
                .length
          : 0,
      'complete': complete,
      'first_text_median_ms': exactlyFiveSamples
          ? exactFiveMedian(texts)
          : null,
      'first_card_median_ms': exactlyFiveSamples
          ? exactFiveMedian(cards)
          : null,
      'failure_code': complete
          ? null
          : SmokeFailureCode.latencySamplesInsufficient.code,
      'threshold_conclusion': 'not_assessed',
    },
    'manual_checkpoint': {
      'complete': _map(raw['manual_checkpoint'])['complete'] == true,
      'status': 'pending',
    },
    // Capability presence or a caller's success flag alone is insufficient.
    'summary': {
      'passed': passed,
      'failure_code': passed
          ? null
          : _code(summary['failure_code']) ??
                SmokeFailureCode.acceptanceCoverageIncomplete.code,
    },
  };
  return _freeze(result) as Map<String, Object?>;
}

Object? _freeze(Object? value) => switch (value) {
  Map map => Map<String, Object?>.unmodifiable({
    for (final entry in map.entries) entry.key as String: _freeze(entry.value),
  }),
  List list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};

/// The file, binding.reportData and chunk output receive this same filtered
/// object. The caller chooses the device-owned directory; no path is emitted.
Future<Map<String, Object?>> publishAiuiSmokeEvidence(
  AiuiSmokeEvidence evidence, {
  required Future<void> Function(String json) write,
  required void Function(Map<String, Object?> data) report,
  required void Function(String chunk) emit,
}) async {
  final filtered = evidence.filtered();
  final encoded = jsonEncode(filtered);
  var written = false;
  try {
    await write(encoded);
    written = true;
  } catch (_) {
    /* Only stable code escapes. */
  }
  report(filtered);
  for (var offset = 0; offset < encoded.length; offset += 1800) {
    final end = offset + 1800 < encoded.length ? offset + 1800 : encoded.length;
    emit(
      'AIUI_SMOKE_EVIDENCE ${offset ~/ 1800 + 1} ${encoded.substring(offset, end)}',
    );
  }
  if (!written) throw SmokeFailure(SmokeFailureCode.evidenceWriteFailed);
  return filtered;
}
