import 'plan.dart';
import 'recomputation.dart';
import 'validation.dart';

final class UiPublicationCoordinator {
  UiPublicationCoordinator(ValidatedUiPlan initial) : _current = initial;

  final ValidatedUiPlan _current;
  ValidatedUiPlan get current => _current;
  bool get recomputing => false;
  bool get outdated => false;
  List<String> get publicationErrors => const [];

  UiPublishOutcome publish(UiVersionBatch batch, UiPublishTokenProbe probe) =>
      UiPublishOutcome.invalid;

  Future<UiPublishOutcome> recompute(
    Future<UiVersionBatch> Function() prepare,
    UiPublishTokenProbe probe,
  ) async => publish(await prepare(), probe);

  bool allowsDispatch(
    UiActionDefinition action, {
    required bool readOnly,
    required bool pending,
  }) => true;

  void cancelRecompute() {}
  void dispose() {}
}
