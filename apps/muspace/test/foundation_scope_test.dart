import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/app/bootstrap.dart';
import 'package:muspace/platform/business_tools.dart';
import 'package:muspace_module_api/muspace_module_api.dart';

void main() {
  test(
    'empty workspace cannot inherit global knowledge or unbound supplier refs',
    () async {
      final root = Directory.systemTemp.createTempSync('foundation-scope-');
      final host = await MuSpaceHost.open(root.path);
      try {
        final workspace = await host.workspaces.create('Empty workspace');
        final file = File('${root.path}/private.txt')
          ..writeAsStringSync('private needle material');
        final doc = await host.services.knowledge.importFile(file.path);
        await host.services.knowledge.index(doc.id);
        await host.activateInquiry();
        final id = host.inquiry!.runtime.state.store.save('supplier', {
          'name': 'Global supplier',
          'aliases': <String>[],
          'categories': <String>[],
          'address': null,
          'notes': null,
          'merged_into': null,
          'rating': null,
          'rating_note': null,
        });
        final global = await resolveAssistantScope(
          host,
          const AssistantScope.global(),
        );
        expect(global.objects, contains(doc.source));
        expect(
          global.objects.any(
            (ref) => ref.moduleId == 'inquiry' && ref.objectId == id,
          ),
          isTrue,
        );
        final scoped = await resolveAssistantScope(
          host,
          AssistantScope.workspace(workspace.id),
        );
        expect(scoped.objects, isEmpty);
        final search = await host.tools.invoke(
          ToolCallRequest(
            invocationId: 'empty-workspace-search',
            toolId: 'knowledge.search',
            scope: AssistantScope.workspace(workspace.id),
            parameters: {'query': 'needle'},
          ),
        );
        expect(search.status, ToolCallStatus.succeeded);
        expect(search.data['hits'], isEmpty);
        await expectLater(
          resolveAssistantScope(
            host,
            AssistantScope.selectedObjects([
              doc.source,
            ], workspaceId: workspace.id),
          ),
          throwsStateError,
        );
        final selected = await resolveAssistantScope(
          host,
          AssistantScope.selectedObjects([doc.source]),
        );
        expect(selected.objects, [doc.source]);
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );
  test(
    'changed knowledge source is absent from global and selected scope',
    () async {
      final root = Directory.systemTemp.createTempSync('foundation-stale-');
      final host = await MuSpaceHost.open(root.path);
      try {
        final file = File('${root.path}/private.txt')
          ..writeAsStringSync('before');
        final doc = await host.services.knowledge.importFile(file.path);
        File(doc.path).writeAsStringSync('after');
        final global = await resolveAssistantScope(
          host,
          const AssistantScope.global(),
        );
        expect(global.objects, isNot(contains(doc.source)));
        await expectLater(
          resolveAssistantScope(
            host,
            AssistantScope.selectedObjects([doc.source]),
          ),
          throwsStateError,
        );
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );
  test('legacy inquiry get cannot return soft-deleted objects outside resolved scope', () async {
    final root = Directory.systemTemp.createTempSync('foundation-deleted-');
    final host = await MuSpaceHost.open(root.path);
    try {
      await host.activateInquiry();
      final store = host.inquiry!.runtime.state.store;
      final id = store.save('supplier', {
        'name': 'deleted secret',
        'aliases': <String>[],
        'categories': <String>[],
        'address': null,
        'notes': null,
        'merged_into': null,
        'rating': null,
        'rating_note': null,
      });
      store.delete('supplier', id);
      final scope = await resolveAssistantScope(
        host,
        const AssistantScope.global(),
      );
      expect(scope.objects.any((ref) => ref.objectId == id), isFalse);
      final result = await host.tools.invoke(
        ToolCallRequest(
          invocationId: 'deleted-read',
          toolId: 'inquiry.get',
          scope: const AssistantScope.global(),
          parameters: {'type': 'supplier', 'id': id},
        ),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(result.data.toString(), isNot(contains('deleted secret')));
      for (final entry in <String, Map<String, Object?>>{
        'related': {'link': 'quotation.supplier_id', 'id': id},
        'compare_quotes': {'product_id': id},
        'quote_options': {'project_id': id, 'product_id': id},
        'project_budget': {'project_id': id},
        'inquiry_matrix': {'inquiry_id': id},
        'match_item': {'item_id': id},
      }.entries) {
        final blocked = await host.tools.invoke(
          ToolCallRequest(
            invocationId: 'blocked-${entry.key}',
            toolId: 'inquiry.${entry.key}',
            scope: const AssistantScope.global(),
            parameters: entry.value,
          ),
        );
        expect(blocked.status, ToolCallStatus.failed, reason: entry.key);
        expect(blocked.data, isEmpty, reason: entry.key);
      }
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
}
