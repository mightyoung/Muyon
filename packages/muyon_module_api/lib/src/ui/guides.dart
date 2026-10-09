enum UiGuideValidation { proposed, evaluated }

enum UiGuideSplit { train, dev }

class UiGuideQuery {
  const UiGuideQuery({
    required this.purpose,
    required this.catalogVersion,
    this.dataProfile = const {},
  });
  final String purpose, catalogVersion;
  final Map<String, Object?> dataProfile;
}

class UiGuideEntry {
  UiGuideEntry({
    required this.guideId,
    required this.revision,
    required this.conditions,
    required this.counterexamples,
    required this.evidenceIds,
    required this.validation,
    required this.split,
    required this.catalogVersion,
  });
  final String guideId, revision, catalogVersion;
  final List<String> conditions, counterexamples, evidenceIds;
  final UiGuideValidation validation;
  final UiGuideSplit split;
  Map<String, Object?> toJson() => {
    'guideId': guideId,
    'revision': revision,
    'conditions': conditions,
    'counterexamples': counterexamples,
    'evidenceIds': evidenceIds,
    'validation': validation.name,
    'split': split.name,
    'catalogVersion': catalogVersion,
  };
}

abstract interface class UiGuideSource {
  Future<List<UiGuideEntry>> lookup(UiGuideQuery query);
}

class EmptyUiGuideSource implements UiGuideSource {
  const EmptyUiGuideSource();
  @override
  Future<List<UiGuideEntry>> lookup(UiGuideQuery query) async => const [];
}
