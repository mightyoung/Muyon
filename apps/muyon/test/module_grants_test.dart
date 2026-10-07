import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/module_grants.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('migration 10', () {
    test('the host schema ends with module-grants at version 10', () {
      final schema = WorkspaceRepository.schema;
      expect(schema.version, 10);
      expect(schema.migrations.last.id, 'module-grants');
      expect(schema.migrations.last.version, 10);
      expect(schema.definitionDigest, 'foundation-v10');
    });

    test('an existing v8 database upgrades and keeps its data', () async {
      final dir = Directory.systemTemp.createTempSync('grants-mig-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final v8 = ModuleSchema(
        version: 8,
        definitionDigest: 'foundation-v8',
        migrations: WorkspaceRepository.schema.migrations.take(8).toList(),
      );
      final old = StorageManager(dir.path);
      final before = await old.open('muyon', v8);
      await before.write(
        (db) => db.execute("INSERT INTO settings VALUES('keep','\"me\"')"),
      );
      expect(
        before.raw.select(
          "SELECT name FROM sqlite_master WHERE name='module_grants'",
        ),
        isEmpty,
      );
      await old.close();

      final next = StorageManager(dir.path);
      addTearDown(next.close);
      final after = await next.open('muyon', WorkspaceRepository.schema);
      expect(
        after.raw
            .select("SELECT value FROM settings WHERE key='keep'")
            .single['value'],
        '"me"',
      );
      final columns = after.raw
          .select('PRAGMA table_info(module_grants)')
          .map((r) => r['name'])
          .toList();
      expect(columns, [
        'module_id',
        'capability',
        'requested',
        'reason',
        'decision',
        'policy',
        'decided_at',
      ]);
      expect(after.raw.select('SELECT * FROM module_grants'), isEmpty);
    });

    test(
      'the table refuses values outside its vocabulary and repeated keys',
      () {
        final db = sqlite3.openInMemory();
        addTearDown(db.close);
        ModuleGrants.migrate(db);
        void insert(String requested, String decision, [String cap = 'ocr']) =>
            db.execute(
              "INSERT INTO module_grants VALUES('m',?,?, 'r',?, 'auto','now')",
              [cap, requested, decision],
            );
        insert('required', 'granted');
        expect(
          () => insert('required', 'granted'),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => insert('maybe', 'granted', 'a'),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => insert('optional', 'perhaps', 'b'),
          throwsA(isA<SqliteException>()),
        );
        insert('optional', 'denied', 'c');
      },
    );
  });

  group('policy', () {
    ModuleManifest manifest(
      List<CapabilityRequest> requests, {
      Set<ModuleFeature> features = const {},
    }) => ModuleManifest(
      id: 'm',
      apiVersion: 2,
      capabilities: requests.toSet(),
      features: features,
    );

    test(
      'only ocr is automatic; transfer needs exchange; the rest are withheld',
      () {
        final decisions = {
          for (final d in GrantPolicy.decide(
            manifest([
              for (final id in hostCapabilityIds)
                CapabilityRequest(id: id, reason: 'because'),
            ]),
          ))
            d.capability: d,
        };
        expect(decisions['ocr']!.granted, isTrue);
        for (final id in ['knowledge', 'models', 'tools', 'transfer']) {
          expect(decisions[id]!.granted, isFalse, reason: id);
        }
        final exchange = GrantPolicy.decide(
          manifest(
            [const CapabilityRequest(id: 'transfer', reason: 'r')],
            features: {ModuleFeature.exchange},
          ),
        );
        expect(exchange.single.granted, isTrue);
      },
    );

    test('revoked stays denied whatever the policy says', () {
      final decision = GrantPolicy.decide(
        manifest([const CapabilityRequest(id: 'ocr', reason: 'r')]),
        revoked: {'ocr'},
      ).single;
      expect(decision.granted, isFalse);
      expect(decision.policy, 'revoked');
    });

    test('a capability the host does not know is denied', () {
      final decision = GrantPolicy.decide(
        manifest([const CapabilityRequest(id: 'telepathy', reason: 'r')]),
      ).single;
      expect(decision.granted, isFalse);
      expect(decision.policy, 'unknown-capability');
    });
  });

  test('recording replaces the module\'s rows and keeps others', () async {
    final db = ManagedConnection(sqlite3.openInMemory());
    addTearDown(db.close);
    ModuleGrants.migrate(db.raw);
    final grants = ModuleGrants(db);
    GrantDecision d(String module, String cap, bool granted) => GrantDecision(
      moduleId: module,
      capability: cap,
      required: false,
      reason: 'r',
      granted: granted,
      policy: 'auto',
    );
    await grants.record('a', [d('a', 'ocr', true), d('a', 'tools', false)]);
    await grants.record('b', [d('b', 'ocr', true)]);
    await grants.record('a', [d('a', 'ocr', false)]);
    expect(grants.forModule('a').map((x) => (x.capability, x.granted)), [
      ('ocr', false),
    ]);
    expect(grants.forModule('b'), hasLength(1));
    await grants.revoke('b', 'ocr');
    expect(grants.revoked('b'), {'ocr'});
    await expectLater(grants.revoke('b', 'nothing'), throwsStateError);
  });
}
