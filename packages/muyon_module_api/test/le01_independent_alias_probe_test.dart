import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

class MutableRef implements ObjectRef {
  @override
  String moduleId = 'research';
  @override
  String objectType = 'project';
  @override
  String objectId = 'A';
  @override
  String? nativeProjectId = 'P';
  @override
  String? revisionRef = 'r1';
  @override
  String? contentDigest = 'a' * 64;
  @override
  Map<String, Object?> toJson() => ObjectRef(
    moduleId: moduleId,
    objectType: objectType,
    objectId: objectId,
    nativeProjectId: nativeProjectId,
    revisionRef: revisionRef,
    contentDigest: contentDigest,
  ).toJson();
}

class MutableExclusion implements LocalExportExclusion {
  @override
  String id = 'n1';
  @override
  String reason = 'no_binding';
}

LocalExportPreparation prepare({
  List<ObjectRef> sources = const [],
  List<LocalExportExclusion> exclusions = const [],
}) => LocalExportPreparation(
  kind: LocalExportKind.report,
  formatVersion: 'v1',
  mimeType: 'text/plain',
  generatedAt: DateTime.utc(2026),
  bytes: [1],
  sha256: 'a' * 64,
  sources: sources,
  dedupedObjectCount: 1,
  exclusions: exclusions,
  warnings: [],
  preparationVersion: 1,
  manifestDigest: 'b' * 64,
);
void main() {
  test(
    'I1 local export cannot become a mixed network rule after construction',
    () {
      final hosts = <String>{};
      final spec = ExternalToolSpec(
        name: 'export_probe',
        description: 'd',
        effect: ToolEffect.export,
        destination: DestinationRule(localExport: true, fixedHosts: hosts),
      );
      expect(localExportRuleProblems(spec.effect, spec.destination), isEmpty);
      hosts.add('changed.example');
      expect(spec.destination.fixedHosts, isEmpty);
    },
  );
  test('I1 local export channel keeps a frozen validated destination', () {
    final hosts = <String>{};
    final channel = ChannelSpec(
      name: 'export_channel',
      description: 'd',
      effect: ToolEffect.export,
      destination: DestinationRule(localExport: true, fixedHosts: hosts),
      parameterSchema: const {'type': 'object'},
    );
    hosts.add('changed.example');
    expect(channel.destination.fixedHosts, isEmpty);
    expect(
      localExportRuleProblems(channel.effect, channel.destination),
      isEmpty,
    );
  });
  test('I1 the validated local export hosts cannot be modified directly', () {
    final spec = ExternalToolSpec(
      name: 'export_probe',
      description: 'd',
      effect: ToolEffect.export,
      destination: DestinationRule(localExport: true, fixedHosts: <String>{}),
    );
    expect(
      () => spec.destination.fixedHosts.add('changed.example'),
      throwsUnsupportedError,
    );
  });
  test(
    'I2 source element identity and revision stay frozen after preparation',
    () {
      final source = MutableRef();
      final before = source.toJson();
      final prepared = prepare(sources: [source]);
      source.moduleId = 'changed_module';
      source.objectType = 'changed_type';
      source.nativeProjectId = 'changed_project';
      source.objectId = 'B';
      source.revisionRef = 'r2';
      source.contentDigest = 'c' * 64;
      expect(prepared.sources.single.toJson(), before);
    },
  );
  test('I2 exclusion element reason stays frozen after preparation', () {
    final exclusion = MutableExclusion();
    final prepared = prepare(exclusions: [exclusion]);
    exclusion.id = 'n2';
    exclusion.reason = 'changed_reason';
    expect(
      [prepared.exclusions.single.id, prepared.exclusions.single.reason],
      ['n1', 'no_binding'],
    );
  });
}
