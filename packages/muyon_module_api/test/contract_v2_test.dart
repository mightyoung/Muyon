import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

class _NoImport with NoImportRuntime {
  @override
  Future<ModuleSession> openSession(WorkspaceBinding binding) =>
      throw UnimplementedError();
}

void main() {
  group('manifest', () {
    test('v1 construction keeps its defaults', () {
      final manifest = ModuleManifest(id: 'm');
      expect(manifest.apiVersion, 1);
      expect(manifest.capabilities, isEmpty);
      expect(manifest.features, isEmpty);
      expect(manifest.network.publicWeb, isFalse);
      expect(manifest.network.fixedHosts, isEmpty);
      expect(manifest.displayName, isNull);
    });

    test('capability requests and features are frozen', () {
      final manifest = ModuleManifest(
        id: 'm',
        apiVersion: 2,
        capabilities: {
          const CapabilityRequest(id: 'ocr', reason: 'reads scans'),
        },
        features: {ModuleFeature.objectPages},
      );
      expect(
        () => manifest.features.add(ModuleFeature.exchange),
        throwsUnsupportedError,
      );
      expect(manifest.capabilities.single.required, isFalse);
    });
  });

  group('ontology', () {
    test('fields start unreviewed and are listed until reviewed', () {
      final ontology = ModuleOntology(
        objectTypes: [
          ObjectTypeSpec(
            name: 'note',
            label: 'Note',
            description: 'A note',
            iconKey: 'note',
            titleField: 'title',
            fields: const [
              OntologyFieldSpec(
                name: 'title',
                label: 'Title',
                description: 'Title',
                kind: FieldKind.text,
                sensitivity: Sensitivity.none,
              ),
              OntologyFieldSpec(
                name: 'phone',
                label: 'Phone',
                description: 'Phone',
                kind: FieldKind.text,
              ),
            ],
          ),
        ],
      );
      expect(Sensitivity.values.map((s) => s.name), [
        'unreviewed',
        'none',
        'personal',
        'commercial',
        'credential',
      ]);
      expect(ontology.unreviewedFields, ['note.phone']);
      expect(ontology.type('note')!.page.kind, ObjectPageKind.unbound);
      expect(() => ontology.objectTypes.clear(), throwsUnsupportedError);
      expect(ModuleOntology.empty().objectTypes, isEmpty);
    });

    test('a page-less type must say why', () {
      const none = ObjectPageSupport.none('web content only');
      expect(none.hasPage, isFalse);
      expect(none.reason, 'web content only');
      expect(const ObjectPageSupport.bound().hasPage, isTrue);
    });
  });

  group('tool specs', () {
    test('an external tool is export or network, never read or write', () {
      for (final effect in [ToolEffect.read, ToolEffect.write]) {
        expect(
          () => ExternalToolSpec(
            name: 'x',
            description: 'd',
            effect: effect,
            destination: const DestinationRule(),
          ),
          throwsArgumentError,
        );
      }
      expect(
        ExternalToolSpec(
          name: 'x',
          description: 'd',
          effect: ToolEffect.network,
          destination: const DestinationRule(publicWeb: true),
        ).destination.publicWeb,
        isTrue,
      );
    });

    test('write spec declares what it touches and freezes it', () {
      final spec = WriteToolSpec(
        name: 'award',
        description: 'd',
        targetTypes: {'quotation'},
        affectsTypes: {'budget_line'},
      );
      expect(spec.scopes, isNull);
      expect(spec.createsTypes, isEmpty);
      expect(() => spec.targetTypes.add('x'), throwsUnsupportedError);
    });
  });

  group('tool result', () {
    test('changes are kept but do not enter the receipt json', () {
      const ref = ObjectRef(
        moduleId: 'm',
        objectType: 't',
        objectId: '1',
        nativeProjectId: 'p',
      );
      final result = ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: 's',
        objectRefs: const [ref],
        changes: const [ObjectChange(ref, ChangeOp.upsert)],
      );
      expect(result.changes.single.op, ChangeOp.upsert);
      expect(result.forInvocation('i').changes, hasLength(1));
      expect(result.toJson().containsKey('changes'), isFalse);
      expect(ToolCallResult.fromJson(result.toJson()).changes, isEmpty);
      expect(() => result.changes.clear(), throwsUnsupportedError);
    });
  });

  group('storage and runtime additions', () {
    test('auxiliary database ids follow the physical id rule', () {
      ModuleSchema schema() => ModuleSchema(
        version: 1,
        definitionDigest: 'd',
        migrations: [
          ModuleMigration(
            version: 1,
            id: 'one',
            definitionDigest: 'd',
            migrate: (_) {},
          ),
        ],
      );
      expect(AuxiliarySchema('inquiry_jobs', schema()).id, 'inquiry_jobs');
      expect(() => AuxiliarySchema('Bad-Id', schema()), throwsArgumentError);
    });

    test('NoImportRuntime reports no pipeline', () async {
      final runtime = _NoImport();
      expect(await runtime.receipt('op'), isNull);
      await expectLater(
        runtime.prepareImport(
          const SelectedInput(path: '/x', displayName: 'x'),
          const ImportTarget.create(
            WorkspaceBinding(
              workspaceId: 'w',
              moduleId: 'm',
              nativeProjectId: 'p',
            ),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('capabilities remember what the host declined', () {
      final registry = CapabilityRegistry()..register('ocr', Object());
      final granted = registry.forModule(
        'm',
        allowed: {'ocr'},
        denied: {'models'},
      );
      expect(granted.denied, {'models'});
      expect(granted.available, {'ocr'});
      expect(registry.forModule('m', allowed: {}).denied, isEmpty);
    });
  });

  group('coverage and sections', () {
    test('an operation cannot have both tools and a not-exposed reason', () {
      expect(
        () => Operation(
          id: 'a',
          kind: OpKind.write,
          tools: ['m.a'],
          notExposed: const NotExposed(
            NotExposedKind.humanOnly,
            'only the person should do this',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a section builder is carried as declared', () {
      final section = ModuleSection(
        id: 's',
        label: 'S',
        builder: (_, _) => const SizedBox(),
      );
      expect(section.requiresWorkspace, isFalse);
      expect(section.showInModuleMenu, isTrue);
    });
  });
}
