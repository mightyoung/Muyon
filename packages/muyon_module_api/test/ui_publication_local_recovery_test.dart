import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

void main() {
  test(
    'outdated recovery admission stays local, explicit and readonly-safe',
    () {
      final fixture = ContractFixture();
      final owner = UiPublicationCoordinator(
        fixture.validate(fixture.plan).validatedPlan!,
      );
      final request = owner.beginRecompute()!;
      expect(owner.failRecompute(request), UiPublishOutcome.invalid);
      const edit = UiActionDefinition(
        route: UiActionRoute.local,
        localAction: UiLocalAction.editField,
      );
      const view = UiActionDefinition(
        route: UiActionRoute.local,
        localAction: UiLocalAction.sortRows,
      );
      const business = UiActionDefinition(
        route: UiActionRoute.business,
        localAction: UiLocalAction.editField,
      );
      bool allows(
        UiActionDefinition action, {
        bool readonly = false,
        bool recovery = true,
      }) => owner.allowsDispatch(
        action,
        readOnly: readonly,
        pending: false,
        allowLocalEditRecovery: recovery,
      );
      expect(allows(edit, recovery: false), isFalse);
      expect(allows(edit), isTrue);
      expect(allows(edit, readonly: true), isFalse);
      expect(allows(view), isFalse);
      expect(allows(business), isFalse);
      expect(owner.outdated, isTrue);
      expect(owner.recomputing, isFalse);
      final newer = owner.beginRecompute()!;
      expect(allows(view), isFalse);
      expect(allows(business), isFalse);
      owner.cancelRecompute();
      expect(owner.isCurrentRequest(newer), isFalse);
      expect(owner.outdated, isTrue);
      owner.dispose();
      expect(allows(edit), isFalse);
    },
  );
}
