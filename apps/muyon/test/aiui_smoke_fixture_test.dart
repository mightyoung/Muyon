import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/screens/assistant_page.dart';

import '../integration_test/support/aiui_smoke_config.dart';
import '../integration_test/support/aiui_smoke_driver.dart';
import '../integration_test/support/aiui_smoke_fixture.dart';
import '../integration_test/support/north_star_records.dart';

void main() {
  testWidgets(
    'offline real app source/preference readiness reports missing observation owners, zero business writes',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('smoke-fixture-');
      final fixture = (await tester.runAsync(
        () => AiuiSmokeFixture.open('${directory.path}/data'),
      ))!;
      try {
        final store = fixture.host.inquiry!.runtime.state.store;
        Map<String, Object?> businessRows() => {
          for (final table in [
            'supplier',
            'project',
            'project_item',
            'inquiry',
            'quotation',
          ])
            table: [
              for (final row in store.db.select(
                'SELECT * FROM $table ORDER BY rowid',
              ))
                Map<String, Object?>.from(row),
            ],
        };
        final before = jsonEncode(businessRows());
        final receipts = receiptRows(fixture.host);
        final approvals = approvalRows(fixture.host);
        final ledger = ledgerRows(fixture.host);
        final configured = AiuiSmokeConfiguration.parse({
          'real': '1',
          'endpoint': 'http://127.0.0.1/v1',
          'model': 'parser-only',
          'key': 'transient-offline-fixture-secret',
          'streaming': '1',
          'candidate': 'a' * 40,
          'build': 'a' * 40,
        });
        await tester.runAsync(() => fixture.configureProfile(configured));
        expect(
          await tester.runAsync(
            () => fixture.host.services.gateway.secrets.read(
              AiuiSmokeConfiguration.credentialReference,
            ),
          ),
          'transient-offline-fixture-secret',
        );
        await fixture.mount(tester);
        expect(find.byType(AssistantPage), findsOneWidget);
        final driver = AiuiSmokeDriver(tester);
        await driver.submit('只读展示当前选定询价的已保存事实');
        for (var frame = 0; frame < 100; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          final tasks = fixture.host.foundation.tasks(
            conversationId: fixture.conversation.id,
          );
          if (tasks.length == 1 && tasks.single.terminal) break;
        }
        final state = await tester.runAsync(fixture.sourceForCurrentTask);
        expect(state?.catalog.version, 'library-2');
        final result = inspectSmokeProduction(fixture.host, state);
        expect(
          result.capabilities['production_stream'],
          isNull,
          reason: 'Source/preference/mode structure does not observe a production stream call',
        );
        expect(result.capabilities['presentation_policy'], isTrue);
        expect(result.capabilities['library_2'], isTrue);
        expect(
          result.capabilities['production_fallback'],
          isNull,
          reason: 'No observation bridge is not proof the existing fallback is absent',
        );
        expect(result.passed, isFalse);
        expect(
          result.failures.first,
          SmokeFailureCode.requestObservabilityMissing,
        );
        expect(
          result.requireReady,
          throwsA(
            isA<SmokeFailure>().having(
              (failure) => failure.code,
              'code',
              SmokeFailureCode.requestObservabilityMissing,
            ),
          ),
        );
        expect(jsonEncode(businessRows()), before);
        expect(receiptRows(fixture.host), receipts);
        expect(approvalRows(fixture.host), approvals);
        expect(ledgerRows(fixture.host), ledger);
        await driver.setPresentationMode(UiPresentationMode.few);
        for (
          var frame = 0;
          frame < 100 &&
              fixture.host.personalAgent.presentationMode !=
                  UiPresentationMode.few;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        expect(
          fixture.host.personalAgent.presentationMode,
          UiPresentationMode.few,
        );
        expect(
          fixture.host.workspaces.setting(UiPresentationPreference.key),
          'few',
        );
        expect(jsonEncode(businessRows()), before);
        expect(
          fixture.host.foundation.tasks().every((task) => task.terminal),
          isTrue,
        );
        expect(ledgerRows(fixture.host), ledger);
        expect(fixture.host.assistantGrants.list(), isEmpty);
      } finally {
        await fixture.close(tester);
        expect(
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .checkMockMessageHandler('com.mightyoung.muyon/secrets', null),
          isTrue,
        );
        // A completed close drains the host and revokes fresh admissions.
        // The test binding also checks for pending timers when this test ends.
        expect(
          () => fixture.host.foundation.database.raw.select('SELECT 1'),
          throwsStateError,
        );
        await expectLater(
          fixture.host.personalAgent.start(
            conversationId: fixture.conversation.id,
            prompt: 'must not start after close',
          ),
          throwsStateError,
        );
        directory.deleteSync(recursive: true);
      }
    },
  );
}
