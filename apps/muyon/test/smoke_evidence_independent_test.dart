// Independent counter-example tests for the AIUI smoke evidence filter.
// Baseline 9d8a4118de74cda369ddd004c519d01a1e0752ba. Synthetic data only: no
// network, no model, no real smoke run, no Android. Imports the author's real
// support code; nothing is re-implemented here. RED cases are intentional and
// must stay RED until production is fixed (no skip, no relaxed assertion).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/aiui_smoke_config.dart';
import '../integration_test/support/aiui_smoke_evidence.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';
const _run = '01234567-89ab-cdef-0123-456789abcdef';

Map<String, Object?> _sample(num text, num card) => {
  'first_text_visible_ms': text,
  'first_card_visible_ms': card,
  'card_source': 'host_fixed',
  'historical_first_event_ms': 12,
  'confirmation_wait_ms': <num>[3.5],
  'missing_reason': null,
};

Map<String, Object?> _case(String id) => {
  'id': id,
  'status': 'passed',
  'stage': 'handoff',
  'failure_code': null,
  'fact_source_match': true,
  'real_suggestion_present': true,
  'counts': {
    'business_write_tasks': 0,
    'business_write_approvals': 0,
    'business_write_receipts': 0,
    'business_grant_uses': 0,
    'model_grant_uses': 1,
  },
  'evidence_class': id.startsWith('PROTOCOL_')
      ? 'scripted_fixture'
      : 'real_upstream',
};

/// Synthetic, fully complete evidence. Each test mutates a deep copy.
Map<String, Object?> _valid() => {
  'schema': 1,
  'candidate_sha': _sha,
  'run_id': _run,
  'android_version': 14,
  'evidence_class': 'real_upstream',
  'preflight': {'passed': true, 'failure_code': null, 'failure_codes': []},
  'cases': [for (final id in smokeCaseIds) _case(id)],
  'latency': {
    'samples': [
      _sample(410.5, 900),
      _sample(380, 870.25),
      _sample(500, 950),
      _sample(390, 880),
      _sample(420, 910),
    ],
  },
  'manual_checkpoint': {'complete': true},
  'summary': {'passed': true, 'failure_code': null},
};

Map<String, Object?> _copy(Map<String, Object?> m) =>
    (jsonDecode(jsonEncode(m)) as Map).cast<String, Object?>();

bool _passed(Map<String, Object?> f) => (f['summary'] as Map)['passed'] == true;
List _samples(Map<String, Object?> f) => (f['latency'] as Map)['samples'] as List;
List _cases(Map<String, Object?> raw) => raw['cases'] as List;
Map _caseOf(Map<String, Object?> raw, String id) =>
    _cases(raw).cast<Map>().firstWhere((c) => c['id'] == id);
List<Map<String, Object?>> _rawSamples(Map<String, Object?> raw) =>
    ((raw['latency'] as Map)['samples'] as List).cast<Map<String, Object?>>();

void main() {
  group('1 valid complete evidence vs formal entry', () {
    // Mutation: drop any conjunct of `passed` (aiui_smoke_evidence.dart:187-213)
    // or break exactFiveMedian -> the positive control flips or median changes.
    test('filter accepts complete synthetic evidence with exact medians', () {
      final f = filterSmokeEvidence(_valid());
      expect(_passed(f), isTrue);
      expect((f['summary'] as Map)['failure_code'], isNull);
      final l = f['latency'] as Map;
      expect(l['complete'], isTrue);
      expect(l['failure_code'], isNull);
      expect(l['first_text_median_ms'], 410.5);
      expect(l['first_card_median_ms'], 900);
      expect(l['threshold_conclusion'], 'not_assessed');
      expect((f['manual_checkpoint'] as Map)['status'], 'pending');
    });

    // Mutation: AiuiSmokeEvidence.filtered() forwarding a caller-chosen
    // summary/evidence_class instead of the hard-coded false (evidence.dart:52-56)
    // -> this flips. The formal entry (integration_test/aiui_smoke_test.dart:63,
    // :122-124) always throws acceptance_coverage_incomplete; filtered() hard-codes
    // passed:false, so the filter's "pass" is unreachable from the real entry.
    test('AiuiSmokeEvidence.filtered never passes even with full raw data', () {
      final e = AiuiSmokeEvidence(runId: _run, candidateSha: _sha)
        ..realUpstreamObserved = true
        ..checkpointComplete = true;
      e.preflight['passed'] = true;
      e.cases.addAll(_cases(_valid()).cast<Map<String, Object?>>());
      final f = e.filtered();
      expect(_passed(f), isFalse);
      expect((f['summary'] as Map)['failure_code'],
          SmokeFailureCode.acceptanceCoverageIncomplete.code);
    });
  });

  group('2 caller summary.passed cannot override case failure', () {
    // Mutation: remove `row['status']=='passed'` (evidence.dart:197).
    for (final status in ['failed', 'not_yet', 'skipped', null]) {
      test('ANDROID2 status=$status -> not passed', () {
        final raw = _copy(_valid());
        _caseOf(raw, 'ANDROID2')['status'] = status;
        expect(_passed(filterSmokeEvidence(raw)), isFalse);
      });
    }
    // Mutation: remove allCasesPresent (evidence.dart:184-186,194).
    test('missing case -> not passed', () {
      final raw = _copy(_valid());
      _cases(raw).removeWhere((c) => (c as Map)['id'] == 'ANDROID3_TIMEOUT');
      expect(_passed(filterSmokeEvidence(raw)), isFalse);
    });
    // Mutation: `.length == 1` -> `>= 1` (evidence.dart:185).
    test('duplicated case (passed+failed) -> not passed', () {
      final raw = _copy(_valid());
      _cases(raw).add({..._case('MODE_FEW'), 'status': 'failed'});
      expect(_passed(filterSmokeEvidence(raw)), isFalse);
    });
    // Mutation: drop `failure_code == null` (evidence.dart:198).
    test('passed status with failure code -> not passed', () {
      final raw = _copy(_valid());
      _caseOf(raw, 'MODE_AUTOMATIC')['failure_code'] =
          SmokeFailureCode.productionFallbackMissing.code;
      final f = filterSmokeEvidence(raw);
      expect(_passed(f), isFalse);
    });
    // Mutation: drop the business-write zero check (evidence.dart:199-204).
    test('business write delta -> not passed', () {
      final raw = _copy(_valid());
      ((_caseOf(raw, 'ANDROID2')['counts']) as Map)['business_write_receipts'] = 1;
      expect(_passed(filterSmokeEvidence(raw)), isFalse);
    });
    // Mutation: drop `preflight['passed']==true` (evidence.dart:189).
    test('preflight failed -> not passed', () {
      final raw = _copy(_valid());
      (raw['preflight'] as Map)['passed'] = false;
      expect(_passed(filterSmokeEvidence(raw)), isFalse);
    });
  });

  group('3 platform identity', () {
    // RED expected. Spec §3 identity group requires the Android version; the
    // filter emits android_version (evidence.dart:220-223) but `passed`
    // (evidence.dart:187-213) never requires it. Mutation caught after fix:
    // removing the android_version conjunct.
    for (final v in <Object?>[null, 'android-14', 0, -1]) {
      test('android_version=$v cannot be an Android acceptance pass', () {
        final raw = _copy(_valid());
        if (v == null) {
          raw.remove('android_version');
        } else {
          raw['android_version'] = v;
        }
        final f = filterSmokeEvidence(raw);
        expect(f['android_version'], isNull);
        expect(_passed(f), isFalse);
      });
    }
  });

  group('4 latency handling', () {
    // Mutation: _number accepting negatives/NaN (evidence.dart:75-76).
    for (final bad in <Object?>[null, -1, double.nan, double.infinity, '400']) {
      test('first_text=$bad -> null, incomplete, no median, not passed', () {
        final raw = _copy(_valid());
        _rawSamples(raw)[2]['first_text_visible_ms'] = bad;
        // jsonEncode would reject NaN; set after the copy.
        final f = filterSmokeEvidence(raw);
        final l = f['latency'] as Map;
        expect((_samples(f)[2] as Map)['first_text_visible_ms'], isNull);
        expect(l['complete'], isFalse);
        expect(l['first_text_median_ms'], isNull);
        expect(l['valid_text_samples'], 4);
        expect(l['failure_code'],
            SmokeFailureCode.latencySamplesInsufficient.code);
        expect(_passed(f), isFalse);
      });
    }
    // Mutation: `exactlyFiveSamples` dropped / `<5` truncation counted
    // (evidence.dart:88-89,181,254).
    for (final n in [0, 4, 6]) {
      test('$n samples -> incomplete, denominator is original count', () {
        final raw = _copy(_valid());
        final s = _rawSamples(raw);
        final list = [for (var i = 0; i < n; i++) _copy(s[i % 5])];
        (raw['latency'] as Map)['samples'] = list;
        final f = filterSmokeEvidence(raw);
        final l = f['latency'] as Map;
        expect(l['sample_count'], n);
        expect(l['retained_sample_count'], n > 5 ? 5 : n);
        expect(l['complete'], isFalse);
        expect(l['first_text_median_ms'], isNull);
        expect(l['first_card_median_ms'], isNull);
        expect(_passed(f), isFalse);
      });
    }
    // RED expected. Spec §3: "缺打点用 null + 原因，绝不填 0". A missing value
    // supplied without a reason must not leave the filtered sample reason-less.
    // Filter only copies the caller's code (evidence.dart:115). Mutation caught
    // after fix: removing the defaulted reason.
    test('missing sample without caller reason still carries a reason', () {
      final raw = _copy(_valid());
      _rawSamples(raw)[1]['first_card_visible_ms'] = null;
      final s = _samples(filterSmokeEvidence(raw))[1] as Map;
      expect(s['first_card_visible_ms'], isNull);
      expect(s['missing_reason'], isNotNull);
    });
    // Ambiguity report (not forced to fail): 0 / 0.0 is accepted as a valid
    // latency (evidence.dart:75-76, `>= 0`). Spec forbids zero placeholders but
    // a real sub-microsecond delta also serialises to 0 (probe.dart: inMicroseconds/1000).
    // This test pins current behaviour only so a change is visible.
    test('zero latency is currently accepted as valid (pinned, ambiguous)', () {
      final raw = _copy(_valid());
      _rawSamples(raw)[0]['first_text_visible_ms'] = 0;
      final f = filterSmokeEvidence(raw);
      expect((_samples(f)[0] as Map)['first_text_visible_ms'], 0);
      expect((f['latency'] as Map)['complete'], isTrue);
    });
    // Mutation: confirmation_count counting non-finite/negatives (evidence.dart:103-108).
    test('confirmation waits filter negatives, NaN and text', () {
      final raw = _copy(_valid());
      _rawSamples(raw)[0]['confirmation_wait_ms'] = [1, -2, double.nan, 'x', 0.5];
      final s = _samples(filterSmokeEvidence(raw))[0] as Map;
      expect(s['confirmation_wait_ms'], [1, 0.5]);
      expect(s['confirmation_count'], 2);
    });
  });

  group('5 fault cases need real upstream provenance', () {
    // RED expected. Spec §4: the four fault scenarios (ANDROID3_*) are real
    // upstream; only the 5 PROTOCOL_* cases may be scripted fixtures. `passed`
    // only checks ANDROID1's class (evidence.dart:206-212). Mutation caught
    // after fix: removing the per-case class requirement.
    for (final id in ['ANDROID3_INTERRUPTION', 'ANDROID3_CANCEL',
        'ANDROID3_TIMEOUT', 'ANDROID4_VERSION_PLANNING']) {
      test('$id as scripted_fixture -> not passed', () {
        final raw = _copy(_valid());
        _caseOf(raw, id)['evidence_class'] = 'scripted_fixture';
        expect(_passed(filterSmokeEvidence(raw)), isFalse);
      });
    }
    // Boundary (GREEN): the filter only validates a label from a closed set;
    // it cannot prove provenance. A synthetic row relabelled real_upstream is
    // indistinguishable. Pinned so nobody reads the label as proof.
    test('relabelled synthetic row is accepted: label is not proof', () {
      final raw = _copy(_valid());
      _caseOf(raw, 'ANDROID3_INTERRUPTION')['evidence_class'] = 'real_upstream';
      final f = filterSmokeEvidence(raw);
      expect(_passed(f), isTrue);
    });
    // Mutation: accepting unknown class strings (evidence.dart:160-167,224-231).
    test('unknown evidence_class collapses to not_executed', () {
      final raw = _copy(_valid());
      raw['evidence_class'] = 'real_upstream_v2';
      _caseOf(raw, 'ANDROID1')['evidence_class'] = 'REAL_UPSTREAM';
      final f = filterSmokeEvidence(raw);
      expect(f['evidence_class'], 'not_executed');
      expect(_passed(f), isFalse);
    });
  });

  group('6 valid sample cannot also carry a missing reason', () {
    // RED expected. evidence.dart:115 copies missing_reason regardless of the
    // sample's validity; the formal entry sets missingReason on every sample
    // (aiui_smoke_test.dart:72-74) and probe.dart:200-204 prefers it.
    // Mutation caught after fix: removing the validity gate.
    test('valid sample + caller reason -> reason dropped', () {
      final raw = _copy(_valid());
      _rawSamples(raw)[0]['missing_reason'] =
          SmokeFailureCode.requestObservabilityMissing.code;
      final f = filterSmokeEvidence(raw);
      final s = _samples(f)[0] as Map;
      expect(s['first_text_visible_ms'], isNotNull);
      expect(s['first_card_visible_ms'], isNotNull);
      expect(s['missing_reason'], isNull);
    });
  });

  group('7 canaries never reach filtered output', () {
    const c = 'CANARY_7f3a91';
    const canaries = [
      'https://$c.example.invalid/v1',
      'sk-$c-secret',
      '/home/$c/muyon/data.db',
      '#0 main ($c.dart:1:1)',
    ];
    Map<String, Object?> poisoned(String v) {
      final raw = _copy(_valid());
      raw['candidate_sha'] = v;
      raw['run_id'] = v;
      raw['device_display'] = v;
      raw['model_display'] = v;
      raw['android_version'] = v;
      raw['evidence_class'] = v;
      raw['endpoint'] = v;
      raw[v] = v;
      raw['preflight'] = {
        'passed': v,
        'failure_code': v,
        'failure_codes': [v, SmokeFailureCode.unexpectedFailure.code],
        'capabilities': {'production_stream': v, v: true},
        'stack': v,
      };
      _cases(raw).add({..._case('ANDROID1'), 'id': v});
      final c0 = _cases(raw)[0] as Map;
      c0['stage'] = v;
      c0['failure_code'] = v;
      c0['status'] = v;
      c0['detail'] = v;
      (c0['counts'] as Map)[v] = v;
      final s0 = _rawSamples(raw)[0];
      s0['card_source'] = v;
      s0['missing_reason'] = v;
      s0['historical_first_event_ms'] = v;
      s0['confirmation_wait_ms'] = [v];
      s0['path'] = v;
      raw['manual_checkpoint'] = {'complete': true, 'status': v, 'path': v};
      raw['summary'] = {'passed': true, 'failure_code': v, 'error': v};
      return raw;
    }

    // Mutation: copying any free string (e.g. `'stage': row['stage']`,
    // `_code` returning value, adding raw keys) -> canary appears.
    for (final v in canaries) {
      test('filter output has no canary: ${v.substring(0, 6)}', () {
        final f = filterSmokeEvidence(poisoned(v));
        expect(jsonEncode(f), isNot(contains(c)));
        expect(_passed(f), isFalse);
      });
    }

    // Mutation: publishing the raw object or the caught write error.
    test('publish path (file/report/chunks) carries no canary', () async {
      final e = AiuiSmokeEvidence(runId: _run, candidateSha: 'sk-$c');
      e.preflight.addAll({'endpoint': 'https://$c.invalid', 'passed': true});
      e.cases.add({..._case('ANDROID1'), 'stage': '/home/$c', 'note': c});
      final written = <String>[];
      final chunks = <String>[];
      Map<String, Object?>? reported;
      await expectLater(
        publishAiuiSmokeEvidence(
          e,
          write: (json) async {
            written.add(json);
            throw StateError('#0 $c (/home/$c/x.dart:1)');
          },
          report: (d) => reported = d,
          emit: chunks.add,
        ),
        throwsA(isA<SmokeFailure>().having((f) => f.code, 'code',
            SmokeFailureCode.evidenceWriteFailed)),
      );
      expect([...written, ...chunks, jsonEncode(reported)].join(),
          isNot(contains(c)));
    });
  });
}
