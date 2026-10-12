// Independent canary tests for the model-request disclosure boundary.
// Baseline 9d8a4118de74cda369ddd004c519d01a1e0752ba. Tests that fail on the
// baseline are intentionally RED (no skip); the disclosure policy was not
// adjusted to make anything pass. Only the model-visible object is checked:
// the prompt string that production providers hand to the model callback
// (MotivationUiPlanningProvider / StreamMotivationUiPlanningProvider), whose
// 'request' member is UiPlanningRequest.toJson(). No real model, no network.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'support/ui_disclosure_independent_helpers.dart';

String _decision(UiDisplayDecision d, String code) =>
    jsonEncode({'decision': d.name, 'reasonCode': code, 'plan': null});

/// Minimal synthetic snapshot following the real toJson shape.
UiPlanningRequest _contractRequest({
  Map<String, SnapshotFact>? facts,
  Map<String, SourceSpanRef> sources = const {},
  Map<String, Object?> viewValues = const {},
  Map<String, Object?> initialUiState = const {},
}) {
  const object = ObjectRef(
    moduleId: 'inquiry',
    objectType: 'quotation',
    objectId: 'q-contract',
    revisionRef: '1',
    contentDigest: 'contract-digest',
  );
  final allFacts =
      facts ??
      {
        'allowed': SnapshotFact(
          object: object,
          field: '允许字段',
          value: DisclosureCanary.allowedVerifiedFact,
          state: FactState.verified,
        ),
      };
  final snapshot = DataSnapshot(
    ref: const SnapshotRef('contract', 1),
    facts: allFacts,
    sources: sources,
    initialUiState: initialUiState,
  );
  final intent = InteractionIntent(
    id: 'contract',
    purpose: 'contract fixture',
    snapshotRef: snapshot.ref,
    requiredBindings: allFacts.keys.map(BindingRef.fact).toSet(),
    allowedActionRefs: const {'detail'},
  );
  return UiPlanningRequest(
    question: 'q',
    answer: 'a',
    conversationMessages: const [],
    conversationVersion: '1',
    coverage: 'contract',
    taskId: 't',
    turnId: 't',
    snapshot: snapshot,
    intent: intent,
    currentView: UiCurrentView(surfaceId: 's', revision: 0, values: viewValues),
    catalog: library2UiCatalog,
    allowedActionRefs: const {'detail'},
    mode: UiPlanningMode.motivation,
  );
}

/// Sends [request] through the real batch provider; returns the model prompt.
Future<String> _outbound(UiPlanningRequest request) async {
  final model = CapturingModel();
  await MotivationUiPlanningProvider(
    model.batch((_) => _decision(UiDisplayDecision.textOnly, 'model_no_card')),
  ).plan(request);
  expect(model.prompts, hasLength(1));
  return model.prompts.single;
}

void main() {
  group('C1-C3 contract level (UiPlanningRequest.toJson via provider)', () {
    test(
      'C1 notDisclosed fact with residual raw value is not outbound',
      () async {
        const object = ObjectRef(
          moduleId: 'inquiry',
          objectType: 'quotation',
          objectId: 'q',
          revisionRef: '1',
          contentDigest: 'd',
        );
        final prompt = await _outbound(
          _contractRequest(
            facts: {
              'price': SnapshotFact(
                object: object,
                field: '单价',
                value: DisclosureCanary.notDisclosedResidual,
                state: FactState.notDisclosed,
              ),
            },
          ),
        );
        expect(
          prompt,
          contains('"state":"notDisclosed"'),
          reason: 'structure must remain',
        );
        expect(
          leaked(prompt, {'fact.value': DisclosureCanary.notDisclosedResidual}),
          isEmpty,
        );
      },
    );

    test(
      'C2 sources.originalText of a restricted span is not outbound',
      () async {
        const object = ObjectRef(
          moduleId: 'inquiry',
          objectType: 'quotation',
          objectId: 'q',
          revisionRef: '1',
          contentDigest: 'd',
        );
        final prompt = await _outbound(
          _contractRequest(
            facts: {
              'price': SnapshotFact(
                object: object,
                field: '单价',
                value: null,
                state: FactState.notDisclosed,
                sourceRefs: const ['span-1'],
              ),
            },
            sources: {
              'span-1': SourceSpanRef(
                artifact: const ArtifactRef(
                  moduleId: 'inquiry',
                  artifactId: 'a',
                  contentDigest: 'ad',
                ),
                originalText:
                    'price is ${DisclosureCanary.restrictedSourceText}',
                start: 0,
                end: 10,
              ),
            },
          ),
        );
        expect(
          prompt,
          contains('span-1'),
          reason: 'reference structure remains',
        );
        expect(
          leaked(prompt, {
            'sources.originalText': DisclosureCanary.restrictedSourceText,
          }),
          isEmpty,
        );
      },
    );

    test(
      'C3 unclassified currentView/initialUiState values are not outbound',
      () async {
        final prompt = await _outbound(
          _contractRequest(
            viewValues: {'x_unknown_view': DisclosureCanary.unknownViewValue},
            initialUiState: {
              'x_unknown_state': DisclosureCanary.unknownInitialUiState,
            },
          ),
        );
        expect(
          leaked(prompt, {
            'currentView.values': DisclosureCanary.unknownViewValue,
            'snapshot.initialUiState': DisclosureCanary.unknownInitialUiState,
          }),
          isEmpty,
        );
      },
    );

    test(
      'C4 contract: verified allowed fact and structure still serialize',
      () async {
        final prompt = await _outbound(_contractRequest());
        final body = jsonDecode(prompt) as Map<String, Object?>;
        final request = body['request']! as Map<String, Object?>;
        final snapshot = request['snapshot']! as Map<String, Object?>;
        final fact = (snapshot['facts']! as Map)['allowed'] as Map;
        expect(fact['field'], '允许字段');
        expect(fact['state'], 'verified');
        expect(fact['object'], isA<Map>());
        // Registration of allowed values is not part of the baseline public
        // contract; the value check is done on the real source (C4 real).
        expect(request['intent'], isA<Map>());
        expect((request['catalog']! as Map)['version'], 'library-2');
        expect(request['allowedActionRefs'], ['detail']);
      },
    );
  });

  group('real source: InquiryUiPlanningSource -> UiPlanningHarness -> provider', () {
    late DisclosureInquiryFixture f;
    setUp(() async => f = await DisclosureInquiryFixture.open());
    tearDown(() async => f.close());

    Future<PersonalTask> taskFor(String type) async {
      final conversation = await f.host.foundation.createConversation(
        scope: AssistantScope.selectedObjects([f.refs[type]!]),
      );
      return f.host.personalAgent.start(
        conversationId: conversation.id,
        prompt: '只读展示本地已保存事实',
      );
    }

    /// Real preference set to the most permissive local display mode.
    Future<UiPlanningHarness> harness(
      UiPlanningPort provider, {
      UiPresentationMode mode = UiPresentationMode.automatic,
    }) async {
      final preference = UiPresentationPreference(f.host.foundation);
      await preference.save(mode);
      final request = UiPresentationRequest.ordinary();
      final policy = preference.freezeFor(request);
      return UiPlanningHarness(
        repository: f.host.foundation,
        source: InquiryUiPlanningSource(f.host).read,
        mode: UiPlanningMode.motivation,
        providers: {UiPlanningMode.motivation: provider},
        allowsPresentation: (_) => policy.allowsPlanningFor(request),
      );
    }

    Future<(String, UiPlannedPresentation, CapturingModel)> batchPlan(
      String type, {
      String Function(UiPlanningRequest)? reply,
    }) async {
      final task = await taskFor(type);
      final model = CapturingModel();
      final h = await harness(
        MotivationUiPlanningProvider(
          model.batch(
            reply ??
                (_) => _decision(UiDisplayDecision.textOnly, 'model_no_card'),
          ),
        ),
      );
      final result = await h.plan(task.id);
      expect(
        model.prompts,
        hasLength(1),
        reason: 'one outbound; result=${result.result.reasonCode}',
      );
      return (model.prompts.single, result, model);
    }

    test(
      'wiring: real source reaches the model callback for all 3 types',
      () async {
        for (final type in ['project_item', 'quotation', 'inquiry']) {
          final (prompt, _, model) = await batchPlan(type);
          expect(jsonDecode(prompt), isA<Map>());
          expect(
            model.requests.single.snapshot.facts,
            isNotEmpty,
            reason: type,
          );
        }
      },
    );

    test(
      'C1 real: masked commercial/personal values are not outbound',
      () async {
        for (final type in ['project_item', 'quotation']) {
          final (prompt, _, _) = await batchPlan(type);
          expect(
            leaked(prompt, DisclosureCanary.masked),
            isEmpty,
            reason: type,
          );
          expect(prompt, contains('notDisclosed'), reason: type);
        }
      },
    );

    test(
      'C2 real: inquiry source wires no sources (originalText path unwired)',
      () async {
        final (_, _, model) = await batchPlan('quotation');
        // Documented wiring fact, not a pass of C2: the real source supplies no
        // SourceSpanRef, so the originalText bypass is only covered at contract
        // level (C2 contract).
        expect(model.requests.single.snapshot.sources, isEmpty);
      },
    );

    for (final type in ['project_item', 'quotation', 'inquiry']) {
      test(
        'C3 real $type: free text not outbound with local display on',
        () async {
          final (prompt, _, _) = await batchPlan(type);
          final own = {
            for (final e in DisclosureCanary.freeText.entries)
              if (e.key.startsWith('$type.')) e.key: e.value,
          };
          expect(own, isNotEmpty);
          expect(
            leaked(prompt, own),
            isEmpty,
            reason: 'local display != model disclosure',
          );
        },
      );
    }

    test('C3 real: unknown stored field is not outbound', () async {
      final (prompt, _, _) = await batchPlan('project_item');
      debugPrintUnknown(f.unknownStored);
      expect(prompt, isNot(contains(DisclosureCanary.unknownField)));
    });

    test(
      'C4 real: allowed non-sensitive values and structure still outbound',
      () async {
        final (item, _, _) = await batchPlan('project_item');
        expect(item, contains(DisclosureCanary.allowedItemName));
        expect(item, contains(DisclosureCanary.allowedItemUnit));
        final (quote, _, _) = await batchPlan('quotation');
        expect(quote, contains('${DisclosureCanary.allowedQuoteLeadDays}'));
        final (inquiry, _, _) = await batchPlan('inquiry');
        expect(inquiry, contains(DisclosureCanary.allowedInquiryTitle));
        final request = (jsonDecode(item) as Map)['request'] as Map;
        final facts = (request['snapshot'] as Map)['facts'] as Map;
        expect(facts.keys, contains('saved-source'));
        expect(
          facts.keys,
          contains('saved-requirement'),
          reason: 'withheld field keeps its slot/state, not its value',
        );
        expect((request['intent'] as Map)['requiredBindings'], isNotEmpty);
        expect(request['allowedActionRefs'], containsAll(['detail', 'back']));
      },
    );

    test('C5 accept path (batch decision accepted): no restricted canary, '
        'single outbound', () async {
      final (prompt, result, _) = await batchPlan('quotation');
      expect(result.result.reasonCode, isNot(startsWith('host_')));
      expect(
        leaked(prompt, {
          ...DisclosureCanary.freeText,
          ...DisclosureCanary.masked,
        }),
        isEmpty,
      );
    });

    test('C5 reject path (malformed model reply): no restricted canary, '
        'no retry outbound', () async {
      final (prompt, result, _) = await batchPlan(
        'quotation',
        reply: (_) => 'not-json',
      );
      expect(result.validated, isNull);
      expect(
        leaked(prompt, {
          ...DisclosureCanary.freeText,
          ...DisclosureCanary.masked,
        }),
        isEmpty,
      );
    });

    for (final accept in [true, false]) {
      test('C5 stream ${accept ? 'accept' : 'reject'} path: no restricted '
          'canary', () async {
        final task = await taskFor('project_item');
        final model = CapturingModel();
        final h = await harness(
          StreamMotivationUiPlanningProvider(
            model.stream((r) => accept ? validStreamFor(r) : 'not-json\n'),
          ),
        );
        final result = await h.plan(task.id);
        expect(model.prompts, hasLength(1));
        expect(
          result.validated == null,
          !accept,
          reason: result.result.reasonCode,
        );
        expect(
          leaked(model.prompts.single, {
            ...DisclosureCanary.freeText,
            ...DisclosureCanary.masked,
          }),
          isEmpty,
        );
      });
    }

    test(
      'C5 recovery context: generic checkpoint values are not outbound',
      () async {
        final task = await taskFor('project_item');
        final store = HostUiWorkspaceStore(f.host.foundation, taskId: task.id);
        final saved = await store.save(
          StoredUiWorkspace(
            taskId: task.id,
            surfaceId: 'task-${task.id}',
            scopeKey: store.scopeKey!,
            revision: 1,
            schemaVersion: 2,
            catalogVersion: 'library-2',
            snapshotRef: const SnapshotRef('checkpoint', 1),
            intentRef: 'readonly',
            planRevision: 5,
            draftRevision: 1,
            extracted: const {'a': DisclosureCanary.checkpointExtracted},
            userOverrides: const {'b': DisclosureCanary.checkpointOverride},
            viewValues: const {'c': DisclosureCanary.checkpointView},
            readableDraft: const {'d': DisclosureCanary.checkpointDraft},
            nodeIds: const ['a'],
          ),
          expectedRevision: 0,
        );
        expect(saved, isTrue);
        final model = CapturingModel();
        final h = await harness(
          MotivationUiPlanningProvider(
            model.batch(
              (_) => _decision(UiDisplayDecision.textOnly, 'model_no_card'),
            ),
          ),
        );
        await h.plan(task.id);
        expect(model.prompts, hasLength(1));
        expect(
          model.requests.single.currentView.revision,
          5,
          reason: 'recovery reached the request',
        );
        expect(
          leaked(model.prompts.single, DisclosureCanary.checkpoint),
          isEmpty,
        );
      },
    );

    test(
      'C6 fingerprint: the host pin is the SHA-256 of the raw row and stays '
      'host-side; outbound carries an opaque handle instead',
      () async {
        final (prompt, _, model) = await batchPlan('quotation');
        final raw = f.rawRow('quotation');
        expect(
          raw,
          contains(DisclosureCanary.quotePrice),
          reason: 'host-internal row',
        );
        final digest = sha256Hex(raw);
        // Host-internal: the pin is computed over the full row (incl. price,
        // inquirer, notes, award_note) and stays that way. Outbound (C6-REDO):
        // the digest never leaves; the object carries an opaque host handle.
        expect(
          model
              .requests
              .single
              .snapshot
              .facts
              .values
              .first
              .object
              .contentDigest,
          digest,
        );
        expect(prompt, isNot(contains(digest)));
        expect(prompt, contains('"modelRef":"mr1_'));
        expect(prompt, isNot(contains(DisclosureCanary.quotePrice)));
      },
    );

    test('C6 fingerprint: restricted low-entropy price must not be recoverable '
        'from outbound digest when other row fields are known', () async {
      final (prompt, _, _) = await batchPlan('quotation');
      final raw = f.rawRow('quotation');
      final outbound = RegExp('"contentDigest":"([0-9a-f]{64})"')
          .allMatches(prompt)
          .map((m) => m.group(1)!)
          .toSet();
      // Attacker model: knows every other field of the row (strong assumption)
      // and that price has the form NNNNN.NN in a small known band.
      String? recovered;
      for (
        var cents = 6184000;
        cents <= 6184500 && recovered == null;
        cents++
      ) {
        final guess =
            '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
        final candidate = raw.replaceFirst(DisclosureCanary.quotePrice, guess);
        if (outbound.contains(sha256Hex(candidate))) recovered = guess;
      }
      expect(
        recovered,
        isNull,
        reason:
            'outbound unsalted digest lets a guesser confirm the masked '
            'price ($recovered)',
      );
    });
  });
}

void debugPrintUnknown(bool stored) =>
    // ignore: avoid_print
    print('UNKNOWN_FIELD_STORED_BY_PUBLIC_STORE=$stored');
