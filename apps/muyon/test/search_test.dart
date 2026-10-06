import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/services/knowledge/research_search_adapter.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  test(
    'offline Chinese bigrams, mixed text, scope, stale input and reindex',
    () async {
      final root = Directory.systemTemp.createTempSync('muyon-search-');
      final source = Directory.systemTemp.createTempSync('muyon-text-');
      File('${source.path}/a.md').writeAsStringSync('模型 Evidence recall 数据分析');
      File('${source.path}/b.md').writeAsStringSync('研究另一份未选资料 secret');
      final host = await MuyonHost.open(root.path);
      try {
        await host.activateResearch();
        final workspace = await host.workspaces.create('A');
        final binding = WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'research',
          nativeProjectId: 'A',
        );
        final prepared = await host.research!.prepareImport(
          SelectedInput(path: source.path, displayName: 'A'),
          ImportTarget.create(binding),
        );
        final coordinator = ImportCoordinator(host.workspaces);
        await coordinator.commit(
          host.research!,
          prepared,
          await coordinator.record(prepared),
        );
        final search = ResearchSearchAdapter(
          host.services.knowledge,
          host.workspaces,
          host.research!.store,
        );
        final docs = search.documents(binding);
        final a = docs.firstWhere((d) => d.relativePath.endsWith('a.md'));
        final b = docs.firstWhere((d) => d.relativePath.endsWith('b.md'));
        expect(
          (await search.search(
            binding,
            '模型',
            selectedDocumentIds: {a.id},
          )).unavailable[a.id],
          'not_indexed',
        );
        await search.index(binding, a);
        await search.index(binding, b);
        expect(
          (await search.search(
            binding,
            '模型 Evidence',
            selectedDocumentIds: {a.id},
          )).hits.single.document.id,
          a.id,
        );
        expect(
          (await search.search(
            binding,
            'secret',
            selectedDocumentIds: {a.id},
          )).hits,
          isEmpty,
        );
        expect(
          (await search.search(binding, '模', selectedDocumentIds: {a.id})).hits,
          hasLength(1),
        );
        final changed = File(a.absolutePath);
        changed.writeAsStringSync('完全替换 new');
        expect(
          (await search.search(
            binding,
            '模型',
            selectedDocumentIds: {a.id},
          )).unavailable[a.id],
          'stale',
        );
        await search.index(binding, a);
        expect(
          (await search.search(
            binding,
            '模型',
            selectedDocumentIds: {a.id},
          )).hits,
          isEmpty,
        );
        expect(
          (await search.search(
            binding,
            'new',
            selectedDocumentIds: {a.id},
          )).hits,
          hasLength(1),
        );
        final other = await host.workspaces.create('B');
        await host.workspaces.bind(
          WorkspaceBinding(
            workspaceId: other.id,
            moduleId: 'research',
            nativeProjectId: 'B',
          ),
        );
        await expectLater(
          search.search(
            WorkspaceBinding(
              workspaceId: other.id,
              moduleId: 'research',
              nativeProjectId: 'B',
            ),
            'secret',
            selectedDocumentIds: {b.id},
          ),
          throwsStateError,
        );
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
        source.deleteSync(recursive: true);
      }
    },
  );
}
