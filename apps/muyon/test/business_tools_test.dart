import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

/// Coverage for the host-side scope resolver and the registered inquiry /
/// research tool handlers: success paths must return scoped records and refs,
/// while unknown workspaces and changed selections are rejected.
void main() {
  late Directory root;
  late Directory source;
  late MuyonHost host;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('business-tools-');
    source = Directory.systemTemp.createTempSync('business-source-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (source.existsSync()) source.deleteSync(recursive: true);
  });

  Future<String> saveSupplier(String name) async {
    await host.activateInquiry();
    return host.inquiry!.runtime.state.store.save('supplier', {
      'name': name,
      'aliases': <String>[],
      'categories': <String>[],
      'address': null,
      'notes': null,
      'merged_into': null,
      'rating': null,
      'rating_note': null,
    });
  }

  Future<String> saveProject() async {
    await host.activateInquiry();
    return host.inquiry!.runtime.state.store.save('project', {
      'code': 'P-1',
      'name': '测试项目',
      'status': 'active',
      'type': 'market',
      'level': 'A',
      'customer': null,
      'contract_no': null,
      'contract_amount': null,
      'department': null,
      'leader': null,
      'start_date': null,
      'end_date': null,
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
      'notes': null,
    });
  }

  Future<ObjectRef> importResearch() async {
    File(p.join(source.path, 'paper.md')).writeAsStringSync('研究内容 摘要');
    await host.activateResearch();
    final workspace = await host.workspaces.create('W');
    final binding = WorkspaceBinding(
      workspaceId: workspace.id,
      moduleId: 'research',
      nativeProjectId: 'W',
    );
    final prepared = await host.research!.prepareImport(
      SelectedInput(path: source.path, displayName: 'W'),
      ImportTarget.create(binding),
    );
    final coordinator = ImportCoordinator(host.workspaces);
    await coordinator.commit(
      host.research!,
      prepared,
      await coordinator.record(prepared),
    );
    return host.research!.store
        .documents('W')
        .map(
          (document) => ObjectRef(
            moduleId: 'research',
            objectType: 'document',
            objectId: document.id,
            nativeProjectId: 'W',
          ),
        )
        .first;
  }

  test('scope includes inquiry projects and research documents', () async {
    final supplierId = await saveSupplier('范围供应商');
    final projectId = await saveProject();
    final documentRef = await importResearch();

    final global = await resolveAssistantScope(
      host,
      const AssistantScope.global(),
    );
    final inquiryProject = global.objects.singleWhere(
      (ref) =>
          ref.moduleId == 'inquiry' &&
          ref.objectType == 'project' &&
          ref.objectId == projectId,
    );
    expect(inquiryProject.nativeProjectId, projectId);
    expect(
      global.objects.any(
        (ref) => ref.moduleId == 'inquiry' && ref.objectId == supplierId,
      ),
      isTrue,
    );
    final researchProject = global.objects.singleWhere(
      (ref) => ref.moduleId == 'research' && ref.objectType == 'project',
    );
    expect(researchProject.nativeProjectId, 'W');
    final document = global.objects.singleWhere(
      (ref) =>
          ref.moduleId == 'research' &&
          ref.objectType == 'document' &&
          ref.objectId == documentRef.objectId,
    );
    expect(document.contentDigest, isNotNull);

    await expectLater(
      resolveAssistantScope(
        host,
        AssistantScope.workspace('missing-workspace'),
      ),
      throwsStateError,
    );

    final stale = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'supplier',
      objectId: supplierId,
      revisionRef: '999',
    );
    await expectLater(
      resolveAssistantScope(host, AssistantScope.selectedObjects([stale])),
      throwsStateError,
    );

    // A removed original file still resolves, but as a missing digest.
    File(host.research!.store.documents('W').single.absolutePath).deleteSync();
    final afterDelete = await resolveAssistantScope(
      host,
      const AssistantScope.global(),
    );
    expect(
      afterDelete.objects
          .singleWhere((ref) => ref.objectId == documentRef.objectId)
          .contentDigest,
      'missing',
    );
  });

  test('inquiry and research tools return scoped records and refs', () async {
    final supplierId = await saveSupplier('工具供应商');
    final projectId = await saveProject();
    await importResearch();

    final get = await host.tools.invoke(
      ToolCallRequest(
        invocationId: 'tool-get',
        toolId: 'inquiry.get',
        scope: const AssistantScope.global(),
        parameters: {'type': 'supplier', 'id': supplierId},
      ),
    );
    expect(get.status, ToolCallStatus.succeeded);
    expect(get.summary, isNotEmpty);
    expect(get.objectRefs.any((ref) => ref.objectId == supplierId), isTrue);

    final budget = await host.tools.invoke(
      ToolCallRequest(
        invocationId: 'tool-budget',
        toolId: 'inquiry.project_budget',
        scope: const AssistantScope.global(),
        parameters: {'project_id': projectId},
      ),
    );
    expect(budget.status, ToolCallStatus.succeeded);
    expect(
      budget.objectRefs.any(
        (ref) => ref.objectType == 'project' && ref.objectId == projectId,
      ),
      isTrue,
    );

    final object = await host.tools.invoke(
      ToolCallRequest(
        invocationId: 'tool-object',
        toolId: 'inquiry.object',
        scope: const AssistantScope.global(),
        parameters: {'type': 'supplier', 'id': supplierId},
      ),
    );
    expect(object.status, ToolCallStatus.succeeded);
    expect(object.summary, contains('工具供应商'));

    final research = await host.tools.invoke(
      ToolCallRequest(
        invocationId: 'tool-research',
        toolId: 'research.objects',
        scope: const AssistantScope.global(),
        parameters: {'query': 'paper'},
      ),
    );
    expect(research.status, ToolCallStatus.succeeded);
    expect(research.summary, contains('找到'));
    expect(research.objectRefs, isNotEmpty);
  });
}
