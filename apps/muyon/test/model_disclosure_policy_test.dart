import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/platform/inquiry_model_disclosure.dart';
import 'package:supplier_core/supplier_core.dart' show Quotation;

import 'support/aiui6_snapshot_fixture.dart';

const object = ObjectRef(
  moduleId: 'inquiry',
  objectType: 'project_item',
  objectId: 'item',
);
const ref = SnapshotRef('safe-ref', 1);
UiPlanningRequest request(
  DataSnapshot snapshot, {
  Set<String> facts = const {},
  Set<String> computed = const {},
  Set<String> uiState = const {},
}) => UiPlanningRequest(
  modelDisclosedFactRefs: facts,
  modelDisclosedComputedRefs: computed,
  modelDisclosedUiStateRefs: uiState,
  question: 'display',
  answer: '',
  conversationMessages: const [],
  conversationVersion: '1',
  coverage: 'selected',
  taskId: 'task',
  turnId: 'turn',
  snapshot: snapshot,
  intent: InteractionIntent(
    id: 'intent',
    purpose: 'display',
    snapshotRef: snapshot.ref,
  ),
  currentView: UiCurrentView(surfaceId: 'surface', revision: 1),
  catalog: library2UiCatalog,
  allowedActionRefs: const {},
  mode: UiPlanningMode.intelligent,
);

void main() {
  test('only explicitly registered ordinary fields are eligible and masking still wins', () {
    for (final type in ['project_item', 'quotation', 'inquiry']) {
      for (final field in [
        'unknown_future_field',
        'notes',
        'award_note',
        'requirement',
      ]) {
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: false),
          isFalse,
        );
      }
      for (final field in inquiryModelDisclosedFields[type]!) {
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: false),
          isTrue,
        );
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: true),
          isFalse,
        );
      }
    }
    expect(
      inquiryFieldDisclosedToModel('new-type', 'name', masked: false),
      isFalse,
    );
  });
  for (final type in ['project_item', 'quotation', 'inquiry']) {
    test(
      'real $type source denies free text while local record retains it',
      () async {
        final f = await InquirySnapshotFixture.open();
        try {
          final store = f.host.inquiry!.runtime.state.store;
          final old = f.refs[type]!;
          final row = store.db.select('SELECT data FROM $type WHERE id=?', [
            old.objectId,
          ]).single;
          final data = Map<String, Object?>.from(
            jsonDecode(row['data'] as String) as Map,
          );
          for (final field in [
            'notes',
            if (type == 'quotation') 'award_note',
            if (type == 'project_item') 'requirement',
          ]) {
            data[field] = 'FREE-TEXT-SECRET-$field-18ac';
          }
          if (type == 'quotation') {
            for (final field in Quotation.fields) {
              data.putIfAbsent(field, () => null);
            }
          }
          store.save(type, data, id: old.objectId);
          final source = f.host.scopeResolver.sources.singleWhere(
            (s) => s.moduleId == 'inquiry',
          );
          final live = (await source.resolve(
            ObjectRef(
              moduleId: 'inquiry',
              objectType: type,
              objectId: old.objectId,
              nativeProjectId: old.nativeProjectId,
            ),
          ))!;
          final c = await f.host.foundation.createConversation(
            scope: AssistantScope.selectedObjects([live]),
          );
          final task = await f.host.personalAgent.start(
            conversationId: c.id,
            prompt: 'local',
          );
          final state = (await InquiryUiPlanningSource(f.host).read(task))!;
          await f.host.foundation.updateTask(
            task.copy({'summary': 'Saved ordinary answer'}),
          );
          UiPlanningRequest? actual;
          final harness = UiPlanningHarness(
            repository: f.host.foundation,
            source: InquiryUiPlanningSource(f.host).read,
            providers: {
              UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
                actual = r;
                return const UiPlanningResult(
                  decision: UiDisplayDecision.textOnly,
                  reasonCode: 'model_no_card',
                );
              }),
            },
          );
          await harness.plan(task.id);
          expect(
            actual,
            isNotNull,
            reason: 'actual source-to-harness request carries host disclosure registration',
          );
          expect(
            jsonEncode(actual!.toJson()),
            isNot(contains('FREE-TEXT-SECRET')),
          );
          if (type == 'project_item') {
            expect(jsonEncode(actual!.toJson()), contains('真实预算行'));
          }
          expect(
            jsonEncode(
              request(
                state.snapshot,
                facts: state.modelDisclosedFactRefs,
              ).toJson(),
            ),
            isNot(contains('FREE-TEXT-SECRET')),
          );
          for (final field in [
            'notes',
            if (type == 'quotation') 'award_note',
            if (type == 'project_item') 'requirement',
          ]) {
            expect(
              state.snapshot.facts['saved-$field']!.state,
              FactState.notDisclosed,
            );
          }
          expect(
            store.db.select('SELECT data FROM $type WHERE id=?', [
              old.objectId,
            ]).single['data'],
            contains('FREE-TEXT-SECRET'),
          );
          if (type == 'project_item') {
            expect(state.snapshot.facts['saved-name']!.value, '真实预算行');
            expect(
              state.snapshot.facts['saved-unit_cost']!.state,
              FactState.notDisclosed,
            );
          }
        } finally {
          await f.close();
        }
      },
    );
  }
}
