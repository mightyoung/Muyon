import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'dynamic_fixtures.dart';

void main() {
  test(
    'complete_patch_advances_current_without_changing_snapshot_or_draft',
    () {
      final s = publicSnapshot();
      final i = publicIntent(s);
      final p = publicPlan(s);
      final checked = validateUiPlan(p, s, i, minimalUiCatalog).validatedPlan!;
      final patch = UiPatch(
        patchId: 'p1',
        surfaceId: p.surfaceId,
        baseRevision: 4,
        nextRevision: 5,
        snapshotRevision: s.ref,
        ops: [
          UiPatchOperation.replace(
            p.nodes.first.copyWith(properties: {'title': 'Updated comparison'}),
          ),
        ],
      );
      final result = applyUiPatch(checked, patch, s, i, minimalUiCatalog);
      expect(result.isValid, isTrue);
      expect(result.validatedPlan!.plan.revision, 5);
      expect(
        result.validatedPlan!.plan.nodes.first.properties['title'],
        'Updated comparison',
      );
      expect(identical(result.validatedPlan!.snapshot, s), isTrue);
      expect(s.facts['qty']!.value, 10);
      expect(s.initialUiState['quantity'], '12');
    },
  );
  test('partial_duplicate_and_stale_patch', () {
    final s = publicSnapshot();
    final i = publicIntent(s);
    final p = publicPlan(s), c = minimalUiCatalog;
    final current = validateUiPlan(p, s, i, c).validatedPlan!;
    UiPatch patch({bool complete = true, String id = 'p', int base = 4}) =>
        UiPatch(
          patchId: id,
          surfaceId: p.surfaceId,
          baseRevision: base,
          nextRevision: base + 1,
          snapshotRevision: s.ref,
          complete: complete,
          ops: [
            UiPatchOperation.replace(
              p.nodes.first.copyWith(properties: {'title': 'Updated'}),
            ),
          ],
        );
    expect(
      applyUiPatch(current, patch(complete: false), s, i, c).isValid,
      isFalse,
    );
    final next = applyUiPatch(current, patch(), s, i, c).validatedPlan!;
    final duplicate = applyUiPatch(next, patch(), s, i, c);
    expect(identical(duplicate.validatedPlan, next), isTrue);
    expect(applyUiPatch(next, patch(id: 'stale'), s, i, c).isValid, isFalse);
    expect(next.plan.revision, 5);
  });
  test('invalid_candidate_is_atomic_and_cannot_hide_unknown', () {
    final s = publicSnapshot();
    final i = publicIntent(s);
    final p = publicPlan(s), c = minimalUiCatalog;
    final current = validateUiPlan(p, s, i, c).validatedPlan!;
    final patch = UiPatch(
      patchId: 'bad',
      surfaceId: p.surfaceId,
      baseRevision: 4,
      nextRevision: 5,
      snapshotRevision: s.ref,
      ops: [
        UiPatchOperation.replace(
          p.nodes.first.copyWith(properties: {'title': 'Should not apply'}),
        ),
        const UiPatchOperation.remove('noise'),
      ],
    );
    expect(applyUiPatch(current, patch, s, i, c).isValid, isFalse);
    expect(current.plan.nodes.first.properties['title'], 'Public comparison');
    expect(current.plan.revision, 4);
  });

  test('malformed_patch_is_rejected_without_throwing', () {
    final s = publicSnapshot();
    final i = publicIntent(s);
    final p = publicPlan(s);
    final current = validateUiPlan(p, s, i, minimalUiCatalog).validatedPlan!;
    final patch = UiPatch(
      patchId: 'malformed',
      surfaceId: p.surfaceId,
      baseRevision: 4,
      nextRevision: 5,
      snapshotRevision: s.ref,
      ops: [
        UiPatchOperation.replace(
          p.nodes.first.copyWith(properties: {'title': Object()}),
        ),
      ],
    );
    expect(
      applyUiPatch(current, patch, s, i, minimalUiCatalog).isValid,
      isFalse,
    );
    expect(current.plan.revision, 4);
  });
}
