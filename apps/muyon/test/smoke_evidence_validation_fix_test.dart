import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/aiui_smoke_config.dart';
import '../integration_test/support/aiui_smoke_evidence.dart';
import '../integration_test/support/aiui_smoke_probe.dart';

const _caps = [
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
];

// Policy-calibrated derivative: structural validity does not prove Android acceptance.
// Original independent file and every negative test are preserved.
Map<String, Object?> _syntheticTemplate() => {
  'schema': 1,
  'candidate_sha': 'a' * 40,
  'run_id': 'c28997a1-6374-4b9e-8e5d-0940f61dbab9',
  'android_version': 35,
  'platform': 'android',
  'evidence_class': 'real_upstream',
  'preflight': {
    'passed': true,
    'failure_code': null,
    'failure_codes': <String>[],
    'capabilities': <String, Object?>{for (final key in _caps) key: true},
  },
  'cases': [
    for (final id in smokeCaseIds)
      {
        'id': id,
        'status': 'passed',
        'stage': 'invariants',
        'failure_code': null,
        'fact_source_match': true,
        'real_suggestion_present': true,
        'evidence_class': 'real_upstream',
        'counts': {
          'business_write_tasks': 0,
          'business_write_approvals': 0,
          'business_write_receipts': 0,
          'business_grant_uses': 0,
          'model_grant_uses': 1,
        },
      },
  ],
  'latency': {
    'samples': [
      for (var i = 0; i < 5; i++)
        {
          'first_text_visible_ms': 10.125 + i,
          'first_card_visible_ms': 20.25 + i,
          'card_source': 'validated_stream',
          'missing_reason': null,
          'confirmation_wait_ms': [0.5],
        },
    ],
  },
  'manual_checkpoint': {'complete': true},
  'summary': {'passed': true, 'failure_code': null},
};

Map<String, Object?> _completeSynthetic() =>
    (jsonDecode(jsonEncode(_syntheticTemplate())) as Map)
        .cast<String, Object?>();

bool _passed(Map<String, Object?> raw) =>
    (filterSmokeEvidence(raw)['validation'] as Map?)?['structurally_valid'] ==
    true;

void main() {
  final corruptions = <String, void Function(Map<String, Object?>)>{
    'summary failure': (r) => (r['summary'] as Map)['failure_code'] = 'CANARY',
    'case unknown failure': (r) =>
        ((r['cases'] as List).first as Map)['failure_code'] = 'CANARY',
    'negative count': (r) =>
        (((r['cases'] as List).first as Map)['counts']
                as Map)['model_grant_uses'] =
            -1,
    'fractional count': (r) =>
        (((r['cases'] as List).first as Map)['counts']
                as Map)['model_grant_uses'] =
            0.5,
    'duplicate case': (r) =>
        (r['cases'] as List).add((r['cases'] as List).first),
    'unknown case': (r) =>
        ((r['cases'] as List).first as Map)['id'] = 'UNKNOWN',
    'unobserved stage': (r) =>
        ((r['cases'] as List).first as Map)['stage'] = 'CANARY',
    'invalid wait': (r) =>
        (((r['latency'] as Map)['samples'] as List).first
            as Map)['confirmation_wait_ms'] = [
          0.1,
          'CANARY',
        ],
  };
  for (final entry in corruptions.entries) {
    test('original contradictory field rejects structure: ${entry.key}', () {
      final raw = _completeSynthetic();
      entry.value(raw);
      final filtered = filterSmokeEvidence(raw);
      expect((filtered['validation'] as Map)['structurally_valid'], isFalse);
      expect((filtered['summary'] as Map)['passed'], isFalse);
      expect(jsonEncode(filtered), isNot(contains('CANARY')));
    });
  }

  for (final id in smokeCaseIds) {
    test('fixture evidence remains explicitly graded for $id', () {
      final raw = _completeSynthetic();
      (raw['cases'] as List).cast<Map>().singleWhere(
        (row) => row['id'] == id,
      )['evidence_class'] = 'scripted_fixture';
      expect(
        _passed(raw),
        !{'ANDROID1', 'ANDROID7', 'ANDROID3_INTERRUPTION'}.contains(id),
      );
      expect((filterSmokeEvidence(raw)['summary'] as Map)['passed'], isFalse);
    });
  }

  test('caller supplied complete evidence cannot prove Android execution', () {
    final output = filterSmokeEvidence(_completeSynthetic());
    expect((output['summary'] as Map)['passed'], isFalse);
    expect((output['acceptance'] as Map?)?['status'], 'unknown');
  });
  for (final schema in [null, 0, 2, '1']) {
    test('unknown schema $schema cannot be structurally valid', () {
      expect(_passed(_completeSynthetic()..['schema'] = schema), isFalse);
    });
  }
  test('unrecognized failure string cannot be filtered into success', () {
    final raw = _completeSynthetic();
    (raw['preflight'] as Map)['failure_code'] = '/private/CANARY';
    expect(_passed(raw), isFalse);
    expect(jsonEncode(filterSmokeEvidence(raw)), isNot(contains('CANARY')));
  });
  test('probe preserves observed samples when later run failure is marked', () {
    final sample = SmokeLatencySample(1)..accept('t', Duration.zero);
    sample.textFrame(
      't',
      Duration.zero,
      nonEmpty: true,
      completeVisibleFrame: true,
    );
    sample.cardFrame(
      't',
      const Duration(microseconds: 1),
      source: SmokeCardSource.hostFixed,
      currentPin: true,
      completeVisibleFrame: true,
      wholeValidated: false,
      readonly: true,
      fallback: false,
    );
    sample.missingReason = SmokeFailureCode.unexpectedFailure;
    expect(sample.toEvidence()['missing_reason'], isNull);
    expect(sample.toEvidence()['first_text_visible_ms'], 0);
    expect(sample.toEvidence()['first_card_visible_ms'], 0.001);
  });

  test('complete synthetic positive is accepted without claiming real observations', () {
    final raw = _completeSynthetic();
    expect(_passed(raw), isTrue);
    expect(
      (filterSmokeEvidence(raw)['latency'] as Map)['first_text_median_ms'],
      12.125,
    );
  });
  for (final id in smokeCaseIds) {
    test('not executed $id cannot be called passed', () {
      final raw = _completeSynthetic();
      final row = (raw['cases'] as List).cast<Map>().singleWhere(
        (row) => row['id'] == id,
      );
      row['evidence_class'] = 'not_executed';
      expect(_passed(raw), isFalse);
    });
  }
  for (final key in ['failure_code', 'failure_codes']) {
    test('preflight $key contradicts passed', () {
      final raw = _completeSynthetic();
      (raw['preflight'] as Map)[key] = key == 'failure_code'
          ? SmokeFailureCode.requestObservabilityMissing.code
          : [SmokeFailureCode.requestObservabilityMissing.code];
      expect(_passed(raw), isFalse);
    });
  }
  for (final capability in _caps) {
    for (final value in [null, false]) {
      test(
        'unobserved capability $capability=$value cannot pass preflight',
        () {
          final raw = _completeSynthetic();
          ((raw['preflight'] as Map)['capabilities'] as Map)[capability] =
              value;
          expect(_passed(raw), isFalse);
        },
      );
    }
  }
  test(
    'latency failure reason cannot accompany complete successful measurements',
    () {
      final raw = _completeSynthetic();
      (((raw['latency'] as Map)['samples'] as List).first
              as Map)['missing_reason'] =
          SmokeFailureCode.requestObservabilityMissing.code;
      expect(_passed(raw), isFalse);
    },
  );
  test(
    'missing timing retains explicit stable reason on every affected row',
    () {
      final raw = _completeSynthetic();
      for (final row in (raw['latency'] as Map)['samples'] as List) {
        (row as Map)['first_text_visible_ms'] = null;
      }
      final output = filterSmokeEvidence(raw);
      expect((output['summary'] as Map)['passed'], isFalse);
      for (final row in (output['latency'] as Map)['samples'] as List) {
        expect(
          (row as Map)['missing_reason'],
          SmokeFailureCode.requestObservabilityMissing.code,
        );
      }
    },
  );
  test('missing card source cannot form a complete observation', () {
    final raw = _completeSynthetic();
    (((raw['latency'] as Map)['samples'] as List).first as Map)['card_source'] =
        null;
    expect(_passed(raw), isFalse);
  });
  for (final value in [null, 0, -1]) {
    test(
      'absent invalid Android version $value cannot pass Android acceptance',
      () {
        final raw = _completeSynthetic()..['android_version'] = value;
        expect(_passed(raw), isFalse);
      },
    );
  }
  test('explicit desktop platform cannot pass Android acceptance', () {
    final raw = _completeSynthetic()..['platform'] = 'linux';
    expect(_passed(raw), isFalse);
  });
  test('high resolution real zero elapsed and submillisecond observation are not truncated', () {
    final sample = SmokeLatencySample(1);
    expect(sample.accept('task', Duration.zero), isTrue);
    expect(
      sample.textFrame(
        'task',
        Duration.zero,
        nonEmpty: true,
        completeVisibleFrame: true,
      ),
      isTrue,
    );
    expect(
      sample.cardFrame(
        'task',
        const Duration(microseconds: 1),
        source: SmokeCardSource.validatedStream,
        currentPin: true,
        completeVisibleFrame: true,
        wholeValidated: true,
        readonly: true,
        fallback: false,
      ),
      isTrue,
    );
    final measured = sample.toEvidence();
    expect(measured['first_text_visible_ms'], 0);
    expect(measured['first_card_visible_ms'], 0.001);
    expect(measured['missing_reason'], isNull);
  });
  test('failed immutable output retains no arbitrary text', () {
    final raw = _completeSynthetic();
    (raw['summary'] as Map)['passed'] = false;
    (raw['preflight'] as Map)['failure_code'] = 'CANARY_RAW_ERROR_64ca';
    expect(
      jsonEncode(filterSmokeEvidence(raw)),
      isNot(contains('CANARY_RAW_ERROR_64ca')),
    );
  });
}
