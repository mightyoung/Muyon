import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'aiui6_stream_production_test.dart' show state;
import 'support/agent_loop_fixture.dart';

void main() {
  for (final native in [false, true]) {
    for (final available in [false, true]) {
      test(
        'real ${native ? 'native' : 'JSON'} read pause resume rebuilds host context available=$available',
        () async {
          final f = await LoopFixture.open();
          final preference = UiPresentationPreference(f.repo);
          await preference.save(UiPresentationMode.automatic);
          var newSource = false;
          final agent = PersonalAgent(
            repository: f.repo,
            tools: f.tools,
            gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
            presentationPreference: preference,
            uiPlanningMode: UiPlanningMode.intelligent,
            uiPlanningProviders: {
              UiPlanningMode.intelligent: FixtureUiPlanningProvider(
                (_) async => UiPlanningResult(
                  decision: UiDisplayDecision.textOnly,
                  reasonCode: 'fixture',
                ),
              ),
            },
            uiPlanningSource: (_) async {
              final old = state(f);
              return UiPlanningHostState(
                snapshot: newSource
                    ? DataSnapshot(
                        ref: const SnapshotRef('resumed-facts', 2),
                        facts: old.snapshot.facts,
                      )
                    : old.snapshot,
                intent: newSource
                    ? InteractionIntent(
                        id: old.intent.id,
                        purpose: old.intent.purpose,
                        snapshotRef: const SnapshotRef('resumed-facts', 2),
                        requiredBindings: old.intent.requiredBindings,
                      )
                    : old.intent,
                catalog: old.catalog,
                allowedActionRefs: old.allowedActionRefs,
                currentView: UiCurrentView(
                  surfaceId: newSource ? 'new-surface' : 'old-surface',
                  revision: 0,
                ),
              );
            },
          );
          addTearDown(agent.close);
          f.replies.add(
            LoopReply.sse(
              native
                  ? sseCalls([('read-call', 'read', '{}')])
                  : sseText('{"type":"tool","toolId":"read","parameters":{}}'),
            ),
          );
          final first = await f.start(
            agent,
            f.profile(
              capabilities: ModelCapabilities(
                nativeTools: native,
                streaming: true,
              ),
            ),
          );
          await agent.confirm(
            first.id,
            requestDigest: first.payload['requestDigest'] as String,
          );
          final checkpoint = f.repo.task(first.id)!;
          final prior = checkpoint.payload['uiPlanningContext'];
          expect(prior, isA<String>());
          expect(f.callsOf('read'), 1);
          expect(checkpoint.stage, 'model');
          final oldIdentity = agent.uiContentIdentity(first.id);
          await agent.pause(first.id);
          newSource = true;
          if (!available)
            await agent.savePresentationMode(UiPresentationMode.textOnly);
          final next = await agent.resume(first.id);
          expect(next.id, isNot(first.id));
          expect(next.previousAttemptId, first.id);
          final messages = next.payload['messages'] as List;
          final systems = messages
              .where((m) => m is Map && m['role'] == 'system')
              .cast<Map>()
              .toList();
          expect(
            systems.where((m) => m['content'] == prior),
            isEmpty,
            reason:
                'The old host planning advertisement must not survive resume',
          );
          expect(
            systems.map((m) => m['content']).join('\n'),
            isNot(contains('old-surface')),
          );
          final ids = (next.payload['candidateIds'] as List).cast<String>();
          final catalog = native
              ? next.payload['nativeTools'] as List
              : (jsonDecode(systems.first['content'] as String) as Map)['tools']
                    as List;
          expect(catalog.map((t) => (t as Map)['toolId']).toSet(), ids.toSet());
          expect(
            ids,
            available
                ? contains('assistant.plan_ui')
                : isNot(contains('assistant.plan_ui')),
          );
          expect(agent.uiContentIdentity(next.id), isNotNull);
          expect(
            identical(agent.uiContentIdentity(next.id), oldIdentity),
            isFalse,
          );
          expect(agent.allowsUiContent(next.id), available);
          if (available) {
            expect(next.payload['uiPlanningContext'], contains('new-surface'));
            expect(
              next.payload['uiPlanningContext'],
              contains('resumed-facts'),
            );
            expect(
              systems.map((m) => m['content']).join('\n'),
              isNot(contains('"snapshotId":"saved"')),
            );
            expect(
              systems.where(
                (m) => m['content'] == next.payload['uiPlanningContext'],
              ),
              hasLength(1),
            );
          } else {
            expect(next.payload['uiPlanningContext'], isNull);
            expect(
              systems.map((m) => m['content']).join('\n'),
              isNot(contains('assistant.plan_ui')),
            );
          }
          expect(
            f.callsOf('read'),
            1,
            reason: 'Completed read must never replay',
          );
          expect(f.callsOf('write'), 0);
          expect(
            f.bodies,
            hasLength(1),
            reason: 'No resumed model request approved',
          );
        },
      );
    }
  }
}
