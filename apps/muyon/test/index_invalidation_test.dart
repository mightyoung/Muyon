import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('deleted and revoked objects leave the index immediately', () async {
    final temp = Directory.systemTemp.createTempSync('index-drop-');
    final db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in KnowledgeService.schema.migrations) {
      migration.migrate(db.raw);
    }
    final knowledge = KnowledgeService(db, '${temp.path}/files');
    final source = ObjectRef(
      moduleId: 'research',
      objectType: 'document',
      objectId: 'doc-1',
      nativeProjectId: 'p1',
    );
    final file = File('${temp.path}/note.txt')
      ..writeAsStringSync('泵的材料成本 needle');
    final doc = await knowledge.importFile(file.path, source: source);
    await knowledge.index(doc.id);
    expect((await knowledge.search('needle')).single.documentId, doc.id);

    knowledge.invalidateApplied('research', [
      ModuleChange(
        sequence: 1,
        ref: source,
        op: ChangeOp.upsert,
        recordedAt: DateTime.utc(2026, 10, 4),
        summary: 'revoked',
      ),
    ]);
    expect(knowledge.documents(), isEmpty);
    expect(await knowledge.search('needle'), isEmpty);
    expect(db.raw.select('SELECT COUNT(*) AS n FROM page_text').single['n'], 0);

    final again = await knowledge.importFile(file.path, source: source);
    await knowledge.index(again.id);
    knowledge.invalidateApplied('research', [
      ModuleChange(
        sequence: 2,
        ref: ObjectRef(
          moduleId: 'research',
          objectType: 'document',
          objectId: 'doc-1',
          nativeProjectId: 'p1',
          contentDigest: 'different-digest-does-not-keep-the-row',
        ),
        op: ChangeOp.delete,
        recordedAt: DateTime.utc(2026, 10, 4, 1),
      ),
    ]);
    expect(knowledge.documents(), isEmpty);
    expect(await knowledge.search('材料'), isEmpty);
    await db.close();
    temp.deleteSync(recursive: true);
  });

  test(
    'model search rechecks the module and the projection hook is wired',
    () async {
      final root = Directory.systemTemp.createTempSync('index-model-');
      final host = await MuyonHost.open(root.path);
      try {
        expect(host.projections.onApplied, isNotNull);
        final file = File('${root.path}/note.txt')
          ..writeAsStringSync('private needle material');
        final source = ObjectRef(
          moduleId: 'research',
          objectType: 'document',
          objectId: 'missing-from-module',
          nativeProjectId: 'p1',
        );
        final doc = await host.services.knowledge.importFile(
          file.path,
          source: source,
        );
        await host.services.knowledge.index(doc.id);
        expect(await host.services.knowledge.search('needle'), isNotEmpty);

        var invocation = 0;
        Future<List<Object?>> ask() async {
          final result = await host.tools.invoke(
            ToolCallRequest(
              invocationId: 'index-gate-${invocation++}',
              toolId: 'knowledge.search',
              scope: const AssistantScope.global(),
              parameters: {'query': 'needle'},
            ),
          );
          expect(result.status, ToolCallStatus.succeeded);
          return (result.data['hits'] as List).cast<Object?>();
        }

        expect(await ask(), isEmpty, reason: 'module does not have the object');
        host.services.knowledge.confirmSource = (_) async => true;
        expect(await ask(), isNotEmpty);
        host.projections.onApplied!.call('research', [
          ModuleChange(
            sequence: 3,
            ref: doc.source,
            op: ChangeOp.delete,
            recordedAt: DateTime.utc(2026, 10, 4, 2),
          ),
        ]);
        expect(host.services.knowledge.documents(), isEmpty);
        host.services.knowledge.confirmSource = (_) async => true;
        expect(await ask(), isEmpty);
        expect(await host.services.knowledge.search('needle'), isEmpty);
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
