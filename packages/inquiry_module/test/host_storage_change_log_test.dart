import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Run from the host test environment without introducing a host/module dependency cycle.
// ignore: avoid_relative_lib_imports
import '../../../apps/muyon/lib/app/inquiry_plugin.dart';
// ignore: avoid_relative_lib_imports
import '../../../apps/muyon/lib/platform/storage_manager.dart';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../../supplier_core/test/fixtures.dart' as fixture;

import 'package:supplier_core/supplier_core.dart';

void main() {
  test(
    'v1 upgrade seeds stable objects and scopes budget and quote changes',
    () async {
      final root = Directory.systemTemp.createTempSync('inquiry-upgrade');
      var storage = StorageManager(root.path);
      addTearDown(() async {
        await storage.close();
        root.deleteSync(recursive: true);
      });
      final migration = InquiryPlugin.schema.migrations.first;
      final v1 = ModuleSchema(
        version: 1,
        definitionDigest: migration.definitionDigest,
        migrations: [migration],
      );
      final old = await storage.open('inquiry', v1);
      final oldStore = Store.attach(
        old.raw,
        device: 'host',
        backgroundExecutor: <T>(action) => old.exclusiveAsync((_) => action()),
      );
      final supplierId = oldStore.save(
        'supplier',
        fixture.supplier('Existing'),
      );
      await storage.close();
      storage = StorageManager(root.path);
      final db = await storage.open('inquiry', InquiryPlugin.schema);
      final store = Store.attach(
        db.raw,
        device: 'host',
        backgroundExecutor: <T>(action) => db.exclusiveAsync((_) => action()),
      );
      expect(
        ModuleChangeLog.since(db.raw, 'inquiry', 0).single.summary,
        'Existing',
      );
      final projectId = store.save('project', fixture.project('P1'));
      final secondProject = store.save('project', fixture.project('P2'));
      final productId = store.save('product', fixture.product('Valve'));
      final itemId = store.save(
        'project_item',
        fixture.item(projectId, 'material', name: 'Budget valve'),
      );
      final inquiryId = store.save('inquiry', {
        'project_id': projectId,
        'title': 'Valve inquiry',
        'item_ids': [itemId],
        'supplier_ids': [supplierId],
        'due_date': null,
        'status': 'open',
        'notes': null,
      });
      final quoteId = store.save(
        'quotation',
        fixture.quotation(supplierId, productId, projectId, '100'),
      );
      final changes = ModuleChangeLog.since(db.raw, 'inquiry', 0);
      for (final pair in [
        (projectId, 'project'),
        (itemId, 'project_item'),
        (inquiryId, 'inquiry'),
        (quoteId, 'quotation'),
      ]) {
        final change = changes.singleWhere((c) => c.ref.objectId == pair.$1);
        expect(change.ref.objectType, pair.$2);
        expect(change.ref.nativeProjectId, projectId);
        expect(change.ref.revisionRef, '1');
        expect(change.summary, isNotEmpty);
      }
      final before = changes.last.sequence;
      store.save('inquiry', {
        ...store.get('inquiry', inquiryId)!.data,
        'project_id': secondProject,
        'item_ids': <String>[],
      }, id: inquiryId);
      final moved = ModuleChangeLog.since(db.raw, 'inquiry', before);
      expect(moved.map((c) => c.op), [ChangeOp.delete, ChangeOp.upsert]);
      expect(moved.map((c) => c.ref.nativeProjectId), [
        projectId,
        secondProject,
      ]);
      for (final pair in [
        (itemId, 'project_item'),
        (inquiryId, 'inquiry'),
        (quoteId, 'quotation'),
        (projectId, 'project'),
      ]) {
        store.delete(pair.$2, pair.$1);
        expect(
          ModuleChangeLog.since(db.raw, 'inquiry', 0).last.op,
          ChangeOp.delete,
        );
      }
    },
  );
  test(
    'host migration logs edits, imports and replacement in their transaction',
    () async {
      final root = Directory.systemTemp.createTempSync('inquiry-change-log');
      final storage = StorageManager(root.path);
      addTearDown(() async {
        await storage.close();
        root.deleteSync(recursive: true);
      });
      final db = await storage.open('inquiry', InquiryPlugin.schema);
      final store = Store.attach(
        db.raw,
        device: 'host',
        backgroundExecutor: <T>(action) => db.exclusiveAsync((_) => action()),
      );
      Map<String, Object?> supplier(String name) => {
        for (final field in Supplier.fields) field: null,
        'name': name,
        'aliases': <String>[],
        'categories': <String>[],
      };
      final id = store.save('supplier', supplier('First'));
      List<ModuleChange> changes() =>
          ModuleChangeLog.since(db.raw, 'inquiry', 0);
      expect(changes().single.ref.objectId, id);
      expect(changes().single.summary, 'First');
      final snapshot = '${root.path}/snapshot.siq';
      store.exportTo(snapshot);
      store.save('supplier', supplier('Updated'), id: id);
      store.delete('supplier', id);
      store.restore('supplier', id);
      expect(changes().map((c) => c.op), [
        ChangeOp.upsert,
        ChangeOp.upsert,
        ChangeOp.delete,
        ChangeOp.upsert,
      ]);
      final before = changes().length;
      expect(
        () => store.transaction(() {
          store.save('supplier', supplier('Rolled back'));
          throw StateError('abort');
        }),
        throwsStateError,
      );
      expect(changes().length, before);
      final other = Store.open('${root.path}/other.db', device: 'other');
      addTearDown(other.close);
      expect(() => other.previewImport(snapshot), returnsNormally);
      final importedId = other.save('supplier', supplier('Imported'));
      final incoming = '${root.path}/incoming.siq';
      other.exportTo(incoming);
      store.importFrom(incoming);
      expect(changes().last.ref.objectId, importedId);
      expect(changes().last.summary, 'Imported');
      store.replaceFrom(snapshot, safetyBackupPath: '${root.path}/safety.siq');
      expect(
        changes().where((c) => c.ref.objectId == importedId).last.op,
        ChangeOp.delete,
      );
      expect(changes().last.summary, 'First');
      expect(InquiryPlugin.schema.version, 2);
    },
  );
}
