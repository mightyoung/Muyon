import 'collection.dart';
import 'plan.dart';

/// NOT READY (F5b slice 1b scaffold): declarations only. Every check below
/// returns [uiEditSpecNotReady] until the GREEN slice implements the real
/// rules from docs/design/aiui-f5-contract-proposed.md §2. Nothing consults
/// these specs yet (validator and session dispatch are unchanged).
const uiEditSpecNotReady = 'not_ready';

/// Collections visible to membership checks (itemIds).
class UiEditContext {
  UiEditContext({Map<String, UiCollection> collections = const {}})
    : collections = Map.unmodifiable(collections);
  final Map<String, UiCollection> collections;
}

/// Host-declared edit rule for one state key. Never converts or clamps.
sealed class UiEditSpec {
  const UiEditSpec({this.nullable = false, this.view = false});
  final bool nullable;
  final bool view;
  UiValueType get payloadType;
  String? rejectPayload(Object? payload) => uiEditSpecNotReady;
  String? rejectInContext(Object? payload, UiEditContext context) =>
      uiEditSpecNotReady;
  String? validateSpec() => uiEditSpecNotReady;
}

final class UiStringEdit extends UiEditSpec {
  const UiStringEdit({
    this.maxLength = 4096,
    this.accepts,
    super.nullable,
    super.view,
  });
  final int maxLength;
  final bool Function(String)? accepts;
  @override
  UiValueType get payloadType => UiValueType.string;
}

final class UiBoolEdit extends UiEditSpec {
  const UiBoolEdit({super.nullable, super.view});
  @override
  UiValueType get payloadType => UiValueType.boolean;
}

final class UiNumberEdit extends UiEditSpec {
  const UiNumberEdit({
    required this.min,
    required this.max,
    this.step,
    this.integer = false,
    super.nullable,
    super.view,
  });
  final double min, max;
  final double? step;
  final bool integer;
  @override
  UiValueType get payloadType => UiValueType.number;
}

final class UiDateEdit extends UiEditSpec {
  const UiDateEdit({
    required this.first,
    required this.last,
    super.nullable,
    super.view,
  });
  final String first, last; // 'YYYY-MM-DD'
  @override
  UiValueType get payloadType => UiValueType.string;
}

final class UiItemIdsEdit extends UiEditSpec {
  UiItemIdsEdit({
    required this.collectionId,
    this.multiple = false,
    List<String> initial = const [],
    super.view,
  }) : initial = List.unmodifiable(initial);
  final String collectionId;
  final bool multiple;
  final List<String> initial;
  @override
  UiValueType get payloadType => UiValueType.stringList;
}
