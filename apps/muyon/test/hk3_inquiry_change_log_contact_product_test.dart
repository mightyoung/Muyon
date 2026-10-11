import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/inquiry_plugin.dart';
import 'package:muyon/platform/projection_service.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

/// HK-3 / GB-3 G1: `contact` and `product` writes must reach the host change
/// log (`muyon_change_log`) so the projection catalogue sees them.
void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedConnection db;

  // The store registers SQL functions on every connection it opens; the
  // product search triggers call `pinyin_initials`, so raw opens must too.
  Future<ManagedConnection> openInquiry(
    StorageManager s,
    ModuleSchema schema,
  ) async {
    final c = await s.open('inquiry', schema);
    await c.write(registerFunctions);
    return c;
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('hk3-change-log-');
    storage = StorageManager(root.path);
    db = await openInquiry(storage, InquiryPlugin.schema);
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  Future<void> insertContact(
    ManagedConnection c, {
    required String id,
    required int version,
    String name = '张三',
    int deleted = 0,
  }) => c.write(
    (d) => d.execute(
      'INSERT INTO contact(id,version,updated_at,updated_by,deleted,data) '
      'VALUES(?,?,?,?,?,?)',
      [
        id,
        version,
        '2026-10-11T00:00:00Z',
        'test',
        deleted,
        jsonEncode({
          'supplier_id': 'sup-1',
          'name': name,
          'phone': '13800000000',
          'wechat': null,
          'email': null,
          'notes': null,
        }),
      ],
    ),
  );

  Future<void> insertProduct(
    ManagedConnection c, {
    required String id,
    required int version,
    String name = '离心水泵',
  }) => c.write(
    (d) => d.execute(
      'INSERT INTO product(id,version,updated_at,updated_by,deleted,data) '
      'VALUES(?,?,?,?,?,?)',
      [
        id,
        version,
        '2026-10-11T00:00:00Z',
        'test',
        0,
        jsonEncode({'name': name, 'unit': '台'}),
      ],
    ),
  );

  Future<void> setProductVersion(
    ManagedConnection c, {
    required String id,
    required int version,
    required String name,
  }) => c.write(
    (d) => d.execute('UPDATE product SET version=?,data=? WHERE id=?', [
      version,
      jsonEncode({'name': name, 'unit': '台'}),
      id,
    ]),
  );

  List<Map<String, Object?>> changesFor(
    ManagedConnection c,
    String objectType,
  ) => [
    for (final row in c.raw.select(
      'SELECT object_id,native_project_id,revision_ref,op,summary '
      'FROM ${ModuleChangeLog.table} WHERE object_type=? ORDER BY sequence',
      [objectType],
    ))
      Map<String, Object?>.from(row),
  ];

  test('creating a contact writes an upsert change record', () async {
    await insertContact(db, id: 'c-1', version: 1);
    final changes = changesFor(db, 'contact');
    expect(changes, hasLength(1));
    expect(changes.single['object_id'], 'c-1');
    expect(changes.single['op'], 'upsert');
    expect(changes.single['native_project_id'], isNull);
    expect(changes.single['summary'], '张三');
  });

  test('updating a product records the new revision', () async {
    await insertProduct(db, id: 'p-1', version: 1);
    await setProductVersion(db, id: 'p-1', version: 2, name: '新名称');
    final changes = changesFor(db, 'product');
    expect(changes.last['op'], 'upsert');
    expect(changes.last['revision_ref'], '2');
    expect(changes.last['summary'], '新名称');
  });

  test('soft delete of a contact records op delete', () async {
    await insertContact(db, id: 'c-2', version: 1);
    await db.write(
      (d) => d.execute('UPDATE contact SET version=2,deleted=1 WHERE id=?', [
        'c-2',
      ]),
    );
    final changes = changesFor(db, 'contact');
    expect(changes.last['op'], 'delete');
    expect(changes.last['revision_ref'], '2');
  });

  test(
    'upgrading from v2 backfills existing contact and product rows',
    () async {
      // A separate library: the setUp library is already at v3 and cannot go back.
      final upRoot = Directory.systemTemp.createTempSync('hk3-upgrade-');
      // StorageManager.close is one-shot, so the reopen uses a new instance.
      var upgradeStorage = StorageManager(upRoot.path);
      addTearDown(() async {
        await upgradeStorage.close();
        upRoot.deleteSync(recursive: true);
      });
      final v2 = ModuleSchema(
        version: 2,
        definitionDigest: InquiryPlugin.schema.migrations[1].definitionDigest,
        migrations: InquiryPlugin.schema.migrations.take(2).toList(),
      );
      final old = await openInquiry(upgradeStorage, v2);
      await insertContact(old, id: 'c-old', version: 1, name: '旧联系人');
      await insertProduct(old, id: 'p-old', version: 1, name: '旧物料');
      expect(changesFor(old, 'contact'), isEmpty);
      await upgradeStorage.close();
      upgradeStorage = StorageManager(upRoot.path);

      final upgraded = await openInquiry(upgradeStorage, InquiryPlugin.schema);
      final contacts = changesFor(upgraded, 'contact');
      final products = changesFor(upgraded, 'product');
      expect(contacts.map((c) => c['object_id']), ['c-old']);
      expect(contacts.single['summary'], '旧联系人');
      expect(products.map((c) => c['object_id']), ['p-old']);
      expect(products.single['summary'], '旧物料');
    },
  );

  test('a new contact reaches the host object catalogue', () async {
    final host = await MuyonHost.open('${root.path}/host');
    addTearDown(host.close);
    final inquiry = await openInquiry(host.storage, InquiryPlugin.schema);
    await insertContact(inquiry, id: 'c-cat', version: 1, name: '目录联系人');
    await host.projections.sync('inquiry', inquiry.raw);
    final rows = host.workspaces.database.raw.select(
      "SELECT project_id,summary FROM object_catalog "
      "WHERE module_id='inquiry' AND object_type='contact' AND object_id='c-cat'",
    );
    expect(rows.single['project_id'], ProjectionService.globalProject);
    expect(rows.single['summary'], '目录联系人');
  });
}
