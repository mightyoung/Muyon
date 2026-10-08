import 'snapshot.dart';

class InteractionIntent {
  InteractionIntent({
    required this.id,
    required this.purpose,
    required this.snapshotRef,
    Set<BindingRef> requiredBindings = const {},
    Set<FactState> mandatoryStates = const {},
    Set<String> allowedActionRefs = const {},
  }) : requiredBindings = Set.unmodifiable(requiredBindings),
       mandatoryStates = Set.unmodifiable(mandatoryStates),
       allowedActionRefs = Set.unmodifiable(allowedActionRefs);
  final String id, purpose;
  final SnapshotRef snapshotRef;
  final Set<BindingRef> requiredBindings;
  final Set<FactState> mandatoryStates;
  final Set<String> allowedActionRefs;
}
