import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

// CR-CF2-LIB2 review counterexample (plan A recovery). Written to fail on the
// current develop: a failed recompute must still let a constrained local
// editField start the next recompute, while business actions stay refused.

UiPublishToken _token() => UiPublishToken(
  baseSnapshotRef: const SnapshotRef('comparison', 4),
  draftRevision: 15,
  hostGeneration: 1,
  sourceGeneration: 2,
  permissionGeneration: 3,
  scopeKey: 'fixture:comparison',
);

void main() {
  test('after a failed recompute a local editField may start a recompute; business stays refused', () async {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final coordinator = UiPublicationCoordinator(initial);

    expect(
      await coordinator.recompute(
        () async => throw StateError('host unavailable'),
        _token,
      ),
      UiPublishOutcome.invalid,
    );
    expect(coordinator.outdated, isTrue);

    const edit = UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.editField,
    );
    const business = UiActionDefinition(route: UiActionRoute.business);
    expect(
      coordinator.allowsDispatch(edit, readOnly: false, pending: false),
      isTrue,
      reason: 'plan A: editField is the only event that may recompute',
    );
    expect(
      coordinator.allowsDispatch(business, readOnly: false, pending: false),
      isFalse,
    );
  });
}
