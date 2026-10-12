import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/aiui_smoke_config.dart';
import '../integration_test/support/aiui_smoke_evidence.dart';
import '../integration_test/support/aiui_smoke_faults.dart';
import '../integration_test/support/aiui_smoke_probe.dart';

Matcher code(SmokeFailureCode expected) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'stable error code',
    expected.code,
  ),
);

Map<String, String> valid() => {
  'real': '1',
  'endpoint': 'http://127.0.0.1/v1',
  'model': 'offline-parser-only',
  'streaming': '1',
  'candidate': 'a' * 40,
  'build': 'a' * 40,
};

void main() {
  test(
    'formal smoke refuses missing real model configuration with a stable code',
    () {
      expect(
        AiuiSmokeConfiguration.fromDartDefines,
        code(SmokeFailureCode.realModelConfigurationMissing),
      );
    },
  );
  for (final key in ['real', 'endpoint', 'model']) {
    test('missing $key cannot silently choose a fixture', () {
      expect(
        () => AiuiSmokeConfiguration.parse({...valid(), key: ''}),
        code(SmokeFailureCode.realModelConfigurationMissing),
      );
    });
  }
  for (final endpoint in [
    'file:///tmp/private',
    'ftp://localhost',
    'https://name:secret@example.test',
    'https://example.test?key=secret',
    'https://example.test#secret',
  ]) {
    test('invalid endpoint never appears in configuration failure', () {
      expect(
        () => AiuiSmokeConfiguration.parse({...valid(), 'endpoint': endpoint}),
        code(SmokeFailureCode.realModelConfigurationMissing),
      );
    });
  }
  test('nonstreaming profile is refused without sending', () {
    expect(
      () => AiuiSmokeConfiguration.parse({...valid(), 'streaming': ''}),
      code(SmokeFailureCode.streamingModelRequired),
    );
  });
  test('full candidate and independent build identity are mandatory', () {
    expect(
      () => AiuiSmokeConfiguration.parse({...valid(), 'build': ''}),
      code(SmokeFailureCode.candidateIdentityMissing),
    );
    expect(
      () => AiuiSmokeConfiguration.parse({...valid(), 'build': 'b' * 40}),
      code(SmokeFailureCode.candidateIdentityMismatch),
    );
  });
  test(
    'remote credentials and HTTPS required; valid streaming settings do no I/O',
    () {
      expect(
        () => AiuiSmokeConfiguration.parse({
          ...valid(),
          'endpoint': 'https://example.test/v1',
        }),
        code(SmokeFailureCode.realModelConfigurationMissing),
      );
      final settings = AiuiSmokeConfiguration.parse({
        ...valid(),
        'endpoint': 'https://example.test/v1',
        'key': 'private-parser-only',
      });
      expect(settings.profile.capabilities.streaming, isTrue);
      expect(
        settings.profile.credentialRef,
        AiuiSmokeConfiguration.credentialReference,
      );
      expect(settings.secret, 'private-parser-only');
    },
  );
  test(
    'exact five median preserves missing values and rejects invalid values',
    () {
      expect(exactFiveMedian([50, 10, 40, 20, 30]), 30);
      for (final values in <List<num?>>[
        [1, 2, 3, 4],
        [1, 2, null, 4, 5],
        [1, 2, double.nan, 4, 5],
        [1, 2, -1, 4, 5],
      ]) {
        expect(exactFiveMedian(values), isNull);
      }
    },
  );
  test(
    'only current complete text/card frames count, never preview or fallback',
    () {
      final sample = SmokeLatencySample(1);
      expect(sample.accept('one', const Duration(seconds: 1)), isTrue);
      expect(
        sample.textFrame(
          'other',
          const Duration(seconds: 2),
          nonEmpty: true,
          completeVisibleFrame: true,
        ),
        isFalse,
      );
      expect(
        sample.textFrame(
          'one',
          const Duration(seconds: 2),
          nonEmpty: false,
          completeVisibleFrame: true,
        ),
        isFalse,
      );
      expect(
        sample.textFrame(
          'one',
          const Duration(seconds: 2),
          nonEmpty: true,
          completeVisibleFrame: false,
        ),
        isFalse,
      );
      bool card({
        bool current = true,
        bool visible = true,
        bool ended = true,
        bool fallback = false,
      }) => sample.cardFrame(
        'one',
        const Duration(seconds: 2),
        source: SmokeCardSource.validatedStream,
        currentPin: current,
        completeVisibleFrame: visible,
        wholeValidated: ended,
        readonly: true,
        fallback: fallback,
      );
      expect(card(current: false), isFalse);
      expect(card(visible: false), isFalse);
      expect(card(ended: false), isFalse);
      expect(card(fallback: true), isFalse);
      expect(card(), isTrue);
      expect(
        sample.textFrame(
          'one',
          const Duration(milliseconds: 1500),
          nonEmpty: true,
          completeVisibleFrame: true,
        ),
        isTrue,
      );
      expect(
        sample.textFrame(
          'one',
          const Duration(seconds: 3),
          nonEmpty: true,
          completeVisibleFrame: true,
        ),
        isTrue,
      );
      expect(sample.toEvidence()['first_text_visible_ms'], 500);
      expect(sample.toEvidence()['first_card_visible_ms'], 1000);
    },
  );
  test(
    'five new task identities required; no zero replacement or extra samples',
    () {
      final probe = AiuiSmokeProbe();
      expect(probe.accept(0, 'one', Duration.zero), isTrue);
      expect(probe.accept(1, 'one', Duration.zero), isFalse);
      expect(probe.latencyEvidence()['complete'], isFalse);
      expect(probe.latencyEvidence()['first_text_median_ms'], isNull);
      expect((probe.latencyEvidence()['samples'] as List).length, 5);
    },
  );
  test('white list blocks secrets even in allowed text keys and nested values', () {
    const private =
        'https://private.test/sk-secret /home/user/private StackTrace raw-model';
    final filtered = filterSmokeEvidence({
      'schema': private,
      'candidate_sha': private,
      'run_id': private,
      'model_display': private,
      'device_display': private,
      'endpoint': private,
      'exception': private,
      'profile': {'key': private},
      'preflight': {
        'passed': false,
        'failure_code': private,
        'capabilities': {'request_observability': private},
        'stack': private,
      },
      'cases': [
        {
          'id': 'ANDROID1',
          'status': private,
          'failure_code': private,
          'raw_receipts': [private],
          'counts': {'business_write_tasks': private},
        },
      ],
      'latency': {
        'samples': [
          {
            'first_text_visible_ms': private,
            'missing_reason': private,
            'task_payload': private,
          },
        ],
      },
      'summary': {'passed': true, 'failure_code': private},
    });
    final json = jsonEncode(filtered);
    expect(json, isNot(contains(private)));
    for (final key in [
      'endpoint',
      'profile',
      'exception',
      'stack',
      'raw_receipts',
      'task_payload',
    ]) {
      expect(json, isNot(contains('"$key"')));
    }
    expect((filtered['summary'] as Map)['passed'], isFalse);
  });
  test('evidence recomputes five denominators and medians instead of trusting input', () {
    final filtered = filterSmokeEvidence({
      'latency': {
        'complete': true,
        'first_text_median_ms': 0,
        'samples': [
          {'first_text_visible_ms': 4, 'first_card_visible_ms': null},
        ],
      },
    });
    final latency = filtered['latency'] as Map;
    expect(latency['complete'], isFalse);
    expect(latency['valid_text_samples'], 1);
    expect(latency['first_text_median_ms'], isNull);
  });
  test(
    'file, reportData and chunks publish the same filtered object',
    () async {
      final evidence = AiuiSmokeEvidence(
        runId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      )..failure = SmokeFailureCode.requestObservabilityMissing;
      String? file;
      Map<String, Object?>? report;
      final chunks = <String>[];
      final result = await publishAiuiSmokeEvidence(
        evidence,
        write: (json) async => file = json,
        report: (data) => report = data,
        emit: chunks.add,
      );
      expect(identical(report, result), isTrue);
      expect(
        () => (result['preflight'] as Map)['passed'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => (result['automated_items'] as List).add(5),
        throwsUnsupportedError,
      );
      expect(jsonDecode(file!), result);
      // Use stable prefix removal, preserving payload spaces.
      final reconstructed = chunks
          .map(
            (line) =>
                line.replaceFirst(RegExp(r'^AIUI_SMOKE_EVIDENCE \d+ '), ''),
          )
          .join();
      expect(jsonDecode(reconstructed), result);
    },
  );
  test('failed file publisher still reports safe evidence and returns stable failure', () async {
    final evidence = AiuiSmokeEvidence(
      runId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    );
    Map<String, Object?>? report;
    final chunks = <String>[];
    await expectLater(
      publishAiuiSmokeEvidence(
        evidence,
        write: (_) async =>
            throw StateError('secret /home/private https://private.test'),
        report: (value) => report = value,
        emit: chunks.add,
      ),
      code(SmokeFailureCode.evidenceWriteFailed),
    );
    expect(report, isNotNull);
    expect(chunks, isNotEmpty);
    expect(chunks.join(), isNot(contains('https://private.test')));
  });

  test(
    'fault arming rejects parent requests and invalid planning correlation',
    () {
      final faults = AiuiSmokeFaults();
      expect(
        () => faults.arm(
          planningTask: 'parent',
          parentTask: 'parent',
          uiPlanningInternal: true,
          kind: SmokeFaultKind.connectionInterruption,
        ),
        code(SmokeFailureCode.faultPreconditionUnmet),
      );
      expect(
        () => faults.arm(
          planningTask: 'plan',
          parentTask: 'parent',
          uiPlanningInternal: false,
          kind: SmokeFaultKind.connectionInterruption,
        ),
        code(SmokeFailureCode.faultPreconditionUnmet),
      );
    },
  );
  test('interruption requires actual target content and only closes its owned client', () {
    final faults = AiuiSmokeFaults()
      ..arm(
        planningTask: 'plan',
        parentTask: 'parent',
        uiPlanningInternal: true,
        kind: SmokeFaultKind.connectionInterruption,
      );
    final client = HttpClient();
    final other = HttpClient();
    addTearDown(() {
      faults.close();
      other.close(force: true);
    });
    expect(faults.attach('parent', 'parent', other), isFalse);
    expect(faults.attach('plan', 'parent', client), isTrue);
    faults.sent('plan');
    faults.actualContent('parent', 'not target');
    expect(faults.interrupt, code(SmokeFailureCode.faultPreconditionUnmet));
    faults.actualContent('plan', 'upstream content');
    faults.interrupt();
    expect(
      () => client.getUrl(Uri.parse('http://127.0.0.1')),
      throwsStateError,
    );
    // The unrelated client remains usable; creating a request does not send it.
    expect(faults.receivedActualContent, isTrue);
  });
  test(
    'stall releases late I/O on teardown without pretending product timeout',
    () async {
      final faults = AiuiSmokeFaults()
        ..arm(
          planningTask: 'plan',
          parentTask: 'parent',
          uiPlanningInternal: true,
          kind: SmokeFaultKind.stalledPlanning,
        );
      final client = HttpClient();
      faults.attach('plan', 'parent', client);
      faults.sent('plan');
      faults.actualContent('plan', 'actual');
      var completed = false;
      final held = faults.holdCompletion('plan').then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      faults.close();
      await held;
      expect(completed, isTrue);
    },
  );
}
