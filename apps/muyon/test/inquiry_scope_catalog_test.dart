import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  late LoopFixture loop;
  late ObjectRef selected;
  late String workspace;

  setUp(() async {
    loop = await LoopFixture.open();
    root = Directory.systemTemp.createTempSync('reg4c-catalog-');
    host = await MuyonHost.open(root.path);
    await host.activateInquiry();
    final id = host.inquiry!.runtime.state.store.save('supplier', {
      for (final field in Supplier.fields) field: null,
      'name': '公开目录范围夹具',
      'aliases': <String>[],
      'categories': <String>[],
    });
    selected = (await resolveAssistantScope(host, const AssistantScope.global()))
        .objects.singleWhere((ref) => ref.objectId == id);
    workspace = (await host.workspaces.create('公开范围夹具')).id;
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  AssistantScope scope(AssistantScopeKind kind) => switch (kind) {
    AssistantScopeKind.global => const AssistantScope.global(),
    AssistantScopeKind.workspace => AssistantScope.workspace(workspace),
    AssistantScopeKind.selectedObjects => AssistantScope.selectedObjects([selected]),
  };

  void register(String suffix, Set<AssistantScopeKind> kinds, {
    bool available = true,
    bool selectable = true,
  }) {
    host.tools.register(
      providerId: 'inquiry',
      descriptor: ToolDescriptor(
        toolId: 'reg4c_scope.$suffix',
        moduleId: 'inquiry',
        effect: ToolEffect.read,
        modelSelectable: selectable,
        parameterSchema: const {
          'type': 'object', 'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      supportedScopes: kinds,
      available: available,
      handler: (_) async => const ToolCallResult(
        status: ToolCallStatus.succeeded, summary: '公开目录夹具',
      ),
    );
  }

  Future<PersonalTask> chat(AssistantScope value) async {
    final conversation = await host.foundation.createConversation(scope: value);
    loop.replies.add(LoopReply.sse(sseText('scope fixture answer')));
    final task = await host.personalAgent.start(
      conversationId: conversation.id,
      prompt: 'answer using the available scope',
      profile: loop.profile(),
    );
    expect(task.state, PersonalTaskState.succeeded, reason: task.error);
    return task;
  }

  Set<String> candidates(PersonalTask task) =>
      (task.payload['candidateIds'] as List).cast<String>().toSet();
  Set<String> native(PersonalTask task) => {
    for (final item in task.payload['nativeTools'] as List)
      (item as Map)['toolId'] as String,
  };
  const generic = {
    'inquiry.create_record', 'inquiry.update_record',
    'inquiry.delete_record', 'inquiry.restore_record',
  };

  for (final kind in AssistantScopeKind.values) {
    test('scope catalog matches declared registration for ${kind.name}', () async {
      for (final declared in AssistantScopeKind.values) {
        register(declared.name, {declared});
      }
      register('all', AssistantScopeKind.values.toSet());
      register('off', {kind}, available: false);
      register('hidden', {kind}, selectable: false);
      final task = await chat(scope(kind));
      final expected = {'reg4c_scope.${kind.name}', 'reg4c_scope.all'};
      for (final ids in [candidates(task), native(task)]) {
        expect(ids.where((id) => id.startsWith('reg4c_scope.')).toSet(), expected);
      }
    });
  }

  test('generic writes stay discoverable only in selected object catalogs', () async {
    final global = await chat(const AssistantScope.global());
    final picked = await chat(AssistantScope.selectedObjects([selected]));
    for (final ids in [candidates(global), native(global)]) {
      expect(ids.intersection(generic), isEmpty);
    }
    for (final ids in [candidates(picked), native(picked)]) {
      expect(ids.intersection(generic), generic);
    }
  });

  test('catalog filtering never replaces invocation scope and approval guards', () async {
    final parameters = {
      'operation_id': newUuid(), 'type': 'supplier', 'id': selected.objectId,
      'expected_version': 1, 'values': {'name': '不得写入'},
    };
    final global = ToolCallRequest(
      invocationId: 'scope-direct-global', toolId: 'inquiry.update_record',
      scope: const AssistantScope.global(), parameters: parameters,
    );
    await expectLater(host.tools.prepare(global), throwsA(
      isA<ToolPlatformException>().having((error) => error.code, 'code', 'scope_mismatch'),
    ));
    await expectLater(host.tools.invoke(global), throwsA(isA<ToolPlatformException>()));
    await expectLater(host.tools.invoke(ToolCallRequest(
      invocationId: 'scope-direct-selected', toolId: 'inquiry.update_record',
      scope: AssistantScope.selectedObjects([selected]), parameters: parameters,
    )), throwsA(isA<ToolPlatformException>()));
    final store = host.inquiry!.runtime.state.store;
    expect(store.get('supplier', selected.objectId)!.version, 1);
    expect(store.db.select("SELECT key FROM meta WHERE key LIKE 'reg4c:%'"), isEmpty);
  });
}
