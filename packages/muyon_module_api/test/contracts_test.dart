import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  ObjectRef ref({String digest = 'digest', String project = 'project'}) =>
      ObjectRef(
        moduleId: 'research',
        objectType: 'paper',
        objectId: 'paper-1',
        nativeProjectId: project,
        revisionRef: 'r1',
        contentDigest: digest,
      );
  ContextRef context({
    String digest = 'digest',
    String workspace = 'workspace',
  }) => ContextRef(
    workspaceId: workspace,
    moduleId: 'research',
    nativeProjectId: 'project',
    selectedObjectRefs: [ref(digest: digest)],
  );

  test(
    'context freezes selection and rejects objects from another project',
    () {
      final selected = [ref()];
      final snapshot = ContextRef(
        workspaceId: 'workspace',
        moduleId: 'research',
        nativeProjectId: 'project',
        selectedObjectRefs: selected,
      );
      selected.clear();
      expect(snapshot.selectedObjectRefs, hasLength(1));
      expect(() => snapshot.selectedObjectRefs.clear(), throwsUnsupportedError);
      expect(
        () => ContextRef(
          workspaceId: 'workspace',
          moduleId: 'research',
          nativeProjectId: 'project',
          selectedObjectRefs: [ref(project: 'other')],
        ),
        throwsArgumentError,
      );
    },
  );

  test('nested schemas are immutable snapshots', () {
    final properties = <String, Object?>{
      'name': <String, Object?>{'type': 'string'},
    };
    final descriptor = ToolDescriptor(
      toolId: 'research.read',
      moduleId: 'research',
      effect: ToolEffect.read,
      parameterSchema: {'properties': properties},
    );
    properties.clear();
    final snapshot = descriptor.parameterSchema['properties'] as Map;
    expect(snapshot.keys, ['name']);
    expect(
      () => (snapshot['name'] as Map)['type'] = 'number',
      throwsUnsupportedError,
    );
  });

  test('permission binds exact evidence endpoint destination and input', () {
    final now = DateTime.utc(2026, 10, 4);
    final tool = ToolDescriptor(
      toolId: 'research.ask',
      moduleId: 'research',
      effect: ToolEffect.network,
    );
    final decision = PermissionDecision(
      id: 'permission',
      toolId: tool.toolId,
      effect: tool.effect,
      contextSnapshot: context(),
      inputDigest: 'question',
      authority: PermissionAuthority.userAction,
      expiresAt: now.add(const Duration(minutes: 1)),
      allowed: true,
      endpoint: 'https://chosen.example/v1',
      destination: 'answer',
      dataCategories: {'question', 'selected-quotes'},
    );
    Invocation invocation({
      String digest = 'digest',
      String workspace = 'workspace',
      String endpoint = 'https://chosen.example/v1',
      String destination = 'answer',
      String input = 'question',
      Set<String> categories = const {'question', 'selected-quotes'},
    }) => Invocation(
      invocationId: 'call',
      toolId: tool.toolId,
      contextSnapshot: context(digest: digest, workspace: workspace),
      inputDigest: input,
      permissionDecisionId: 'permission',
      endpoint: endpoint,
      destination: destination,
      dataCategories: categories,
    );
    expect(decision.authorizes(invocation(), tool, now: now), isTrue);
    for (final changed in [
      invocation(digest: 'edited'),
      invocation(workspace: 'other'),
      invocation(endpoint: 'https://other.example'),
      invocation(destination: 'file'),
      invocation(input: 'other-question'),
      invocation(categories: {'question'}),
    ]) {
      expect(decision.authorizes(changed, tool, now: now), isFalse);
    }
    expect(
      decision.authorizes(invocation(), tool, now: decision.expiresAt),
      isFalse,
    );
  });

  test('host read policy cannot authorize a write', () {
    final now = DateTime.utc(2026);
    final tool = ToolDescriptor(
      toolId: 'research.save',
      moduleId: 'research',
      effect: ToolEffect.write,
    );
    final decision = PermissionDecision(
      id: 'p',
      toolId: tool.toolId,
      effect: tool.effect,
      contextSnapshot: context(),
      inputDigest: 'i',
      authority: PermissionAuthority.hostReadPolicy,
      expiresAt: DateTime.utc(2027),
      allowed: true,
    );
    expect(
      decision.authorizes(
        Invocation(
          invocationId: 'i',
          toolId: tool.toolId,
          contextSnapshot: context(),
          inputDigest: 'i',
          permissionDecisionId: 'p',
        ),
        tool,
        now: now,
      ),
      isFalse,
    );
  });

  test('second module reuses provider with isolated grant snapshots', () {
    final registry = CapabilityRegistry();
    final shared = Object();
    registry.register('documents', shared);
    registry.register('research.private', Object());
    final grants = {'documents'};
    final second = registry.forModule('inquiry', allowed: grants);
    final research = registry.forModule(
      'research',
      allowed: {'documents', 'research.private'},
    );
    grants.add('research.private');
    expect(
      identical(
        second.require<Object>('documents'),
        research.require<Object>('documents'),
      ),
      isTrue,
    );
    expect(second.moduleId, 'inquiry');
    expect(() => second.require<Object>('research.private'), throwsStateError);
    expect(() => registry.register('documents', Object()), throwsStateError);
    expect(
      () => second.available.add('research.private'),
      throwsUnsupportedError,
    );
  });

  test(
    'prepared import matches frozen identity including target and token',
    () {
      const binding = WorkspaceBinding(
        workspaceId: 'w',
        moduleId: 'research',
        nativeProjectId: 'p',
      );
      const prepared = PreparedImport(
        target: ImportTarget.create(binding),
        inputDigest: 'digest',
        stagingToken: 'frozen',
      );
      ImportIntent intent({
        ImportKind kind = ImportKind.create,
        String token = 'frozen',
      }) => ImportIntent(
        operationId: 'op',
        workspaceId: 'w',
        moduleId: 'research',
        targetProjectId: 'p',
        kind: kind,
        inputDigest: 'digest',
        stagingToken: token,
      );
      expect(prepared.matches(intent()), isTrue);
      expect(prepared.matches(intent(kind: ImportKind.refresh)), isFalse);
      expect(prepared.matches(intent(token: 'changed')), isFalse);
      expect(intent().sameIdentity(intent(token: 'changed')), isFalse);
    },
  );

  test('schema rejects gaps and same version mismatched digest', () {
    final migration = ModuleMigration(
      version: 1,
      id: 'initial',
      definitionDigest: 'v1',
      migrate: (_) {},
    );
    expect(
      ModuleSchema(
        version: 1,
        definitionDigest: 'v1',
        migrations: [migration],
      ).migrations,
      hasLength(1),
    );
    expect(
      () => ModuleSchema(
        version: 2,
        definitionDigest: 'v1',
        migrations: [migration],
      ),
      throwsArgumentError,
    );
    expect(
      () => ModuleSchema(
        version: 1,
        definitionDigest: 'drift',
        migrations: [migration],
      ),
      throwsArgumentError,
    );
  });
}
