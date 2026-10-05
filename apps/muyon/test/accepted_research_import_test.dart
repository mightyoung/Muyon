import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/services/transfer/task_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:supplier_core/lan.dart';

void main() {
  late Directory temp;
  late MuyonHost source, receiver;
  late LanNode sender;
  late LanPeer peer;
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('accepted-research-');
    source = await MuyonHost.open('${temp.path}/source');
    receiver = await MuyonHost.open('${temp.path}/receiver');
    await source.activateResearch();
    await source.research!.resources.database.write((db) {
      db.execute("INSERT INTO projects(id,title) VALUES('source','Source')");
    });
    await CardStore(source.research!.resources.database).save(
      projectId: 'source',
      cardId: 'card',
      expectedHead: null,
      bodyMarkdown: 'Accepted evidence',
    );
    await receiver.services.transfer.start(
      deviceId: 'receiver',
      deviceName: 'receiver',
      discoveryPort: 0,
      httpPort: 0,
      secrets: MemoryLanSecretStore(),
    );
    sender = await LanNode.start(
      id: 'sender',
      name: 'sender',
      inbox: Directory('${temp.path}/sender'),
      onPush: (_) {},
      discoveryPort: 0,
      httpPort: 0,
      secrets: MemoryLanSecretStore(),
    );
    peer = await sender.probe(
      '127.0.0.1',
      port: receiver.services.transfer.httpPort!,
    );
    sender.confirmPeer(
      fingerprint: peer.fingerprint,
      confirmedCode: receiver.services.transfer.localShortCode!,
      certificatePem: peer.certificatePem,
    );
    final reverse = await receiver.services.transfer.probe(
      '127.0.0.1',
      port: sender.httpPort,
    );
    receiver.services.transfer.confirmPeer(
      fingerprint: reverse.fingerprint,
      confirmedCode: sender.identity.shortCode,
      certificatePem: reverse.certificatePem,
    );
  });
  tearDown(() async {
    await sender.stop();
    await receiver.close();
    await source.close();
    temp.deleteSync(recursive: true);
  });
  Future<void> receive(List<int> bytes) async {
    final file = File('${temp.path}/package.zip')..writeAsBytesSync(bytes);
    await sender.push(peer, file.path);
    await receiver.services.transfer.itemsSettled;
  }

  Future<List<int>> package() =>
      ResearchPackageExchange(CardStore(source.research!.resources.database))
          .exportBytes('source', ['card']);
  Future<void> restart() async {
    await receiver.close();
    receiver = await MuyonHost.open('${temp.path}/receiver');
    await receiver.activateResearch();
  }

  test(
    'only human acceptance commits canonical ZIP once through host binding',
    () async {
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      expect(item.acceptance, 'pending');
      expect(item.imported, isFalse);
      expect(item.grantsExecution, isFalse);
      expect(receiver.research, isNull);
      expect(receiver.workspaces.all(), isEmpty);
      await receiver.services.transfer.markRead(item.id);
      expect(receiver.workspaces.all(), isEmpty);
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.services.transfer.acceptItem(item.id);
      await restart();
      expect(receiver.services.transfer.items().single.imported, isTrue);
      final workspace = receiver.workspaces.all().single;
      final binding = receiver.workspaces.binding(workspace.id, 'research')!;
      expect(binding.nativeProjectId, isNot('source'));
      final db = receiver.research!.store.db;
      expect(db.select('SELECT * FROM rk_cards'), hasLength(1));
      expect(db.select('SELECT * FROM rk_import_receipts'), hasLength(1));
      expect(db.select('SELECT * FROM tasks'), isEmpty);
      expect(db.select('SELECT * FROM runs'), isEmpty);
      expect(
        receiver.workspaces.database.raw
            .select('SELECT status FROM import_intents')
            .single['status'],
        'complete',
      );
      await receiver.services.transfer.acceptItem(item.id);
      expect(receiver.workspaces.all(), hasLength(1));
    },
  );
  test(
    'real task offer parsing receive and transfer acceptance never execute',
    () async {
      await receive(
        utf8.encode(
          jsonEncode({
            'muyon': TaskCoordinator.marker,
            'type': 'offer',
            'taskId': 'task-1',
            'inputRevision': 'revision-1',
            'idempotencyKey': 'key-1',
            'deviceId': 'sender',
          }),
        ),
      );
      final envelope = TaskCoordinator.decodeFile(
        receiver.services.transfer.items().single.path!,
      );
      expect(envelope, isNotNull);
      var executions = 0;
      final tasks = TaskCoordinator(
        database: receiver.workspaces.database,
        deviceId: 'receiver',
        send: (_) async {},
        executor: (_) async {
          executions++;
          throw StateError('Receiving a task must not execute it');
        },
      );
      await tasks.receive(envelope!);
      expect(tasks.stateOf('task-1', 'revision-1'), 'offered');
      expect(executions, 0);
      await receiver.services.transfer.acceptItem(
        receiver.services.transfer.items().single.id,
      );
      await receiver.acceptedResearchImports.settled;
      expect(executions, 0);
      expect(tasks.stateOf('task-1', 'revision-1'), 'offered');
      expect(
        receiver.foundation.notifications().any((n) => n.title == '研究包未导入'),
        isFalse,
      );
      await restart();
      final item = receiver.services.transfer.items().single;
      expect(item.acceptance, 'accepted');
      expect(item.imported, isFalse);
      expect(item.grantsExecution, isFalse);
      expect(receiver.workspaces.all(), isEmpty);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        isEmpty,
      );
      expect(
        receiver.research!.store.db.select('SELECT * FROM tasks'),
        isEmpty,
      );
    },
  );
  test(
    'changed accepted bytes fail without workspace or receipt and notify',
    () async {
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      final file = File(item.path!);
      final bytes = file.readAsBytesSync();
      bytes[bytes.length - 1] ^= 1;
      file.writeAsBytesSync(bytes);
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.acceptedResearchImports.settled;
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.workspaces.all(), isEmpty);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        isEmpty,
      );
      expect(
        receiver.foundation.notifications().any(
          (n) => n.title == '研究包未导入' && n.body.contains('摘要'),
        ),
        isTrue,
      );
      await restart();
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.workspaces.all(), isEmpty);
    },
  );

  test(
    'symlink attachment is rejected before parsing or workspace effects',
    () async {
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      File(item.path!).deleteSync();
      Link(item.path!).createSync('${temp.path}/package.zip');
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.acceptedResearchImports.settled;
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.workspaces.all(), isEmpty);
      expect(
        receiver.foundation.notifications().any((n) => n.title == '研究包未导入'),
        isTrue,
      );
    },
  );

  test(
    'commit failure stays pending and restart never retries business commit',
    () async {
      await receiver.activateResearch();
      await receiver.research!.resources.database.write(
        (db) => db.execute(
          "CREATE TRIGGER deny_import BEFORE INSERT ON rk_cards BEGIN SELECT RAISE(ABORT, 'injected commit failure'); END;",
        ),
      );
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.acceptedResearchImports.settled;
      expect(receiver.services.transfer.items().single.imported, isFalse);
      final workspace = receiver.workspaces.all().single;
      expect(receiver.workspaces.binding(workspace.id, 'research'), isNull);
      expect(
        receiver.research!.store.db.select('SELECT * FROM projects'),
        isEmpty,
      );
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        isEmpty,
      );
      expect(
        receiver.workspaces.database.raw
            .select('SELECT status FROM import_intents')
            .single['status'],
        'pending',
      );
      expect(
        receiver.foundation.notifications().any(
          (n) => n.body.contains('injected commit failure'),
        ),
        isTrue,
      );
      await receiver.research!.resources.database.write(
        (db) => db.execute('DROP TRIGGER deny_import'),
      );
      await restart();
      await receiver.services.transfer.acceptItem(item.id);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        isEmpty,
      );
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.workspaces.binding(workspace.id, 'research'), isNull);
    },
  );

  test(
    'recovery activates canonical receipt and only then restores imported flag',
    () async {
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.acceptedResearchImports.settled;
      final workspace = receiver.workspaces.all().single;
      final original = receiver.workspaces.binding(workspace.id, 'research')!;
      // Crash boundary: domain committed, host activation and transfer flag not saved.
      await receiver.workspaces.database.write((db) {
        db.execute('DELETE FROM workspace_module_bindings');
        db.execute("UPDATE import_intents SET status='pending'");
      });
      await receiver.services.transfer.database.write(
        (db) => db.execute('UPDATE transfer_items SET imported=0'),
      );
      await restart();
      expect(receiver.researchError, isNull);
      expect(
        receiver.workspaces.binding(workspace.id, 'research')!.nativeProjectId,
        original.nativeProjectId,
      );
      expect(receiver.services.transfer.items().single.imported, isTrue);
      final receipt = await receiver.research!.receipt(
        'transfer-research:${item.id}',
      );
      expect(receipt!.intent.workspaceId, workspace.id);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        hasLength(1),
      );
    },
  );

  test(
    'canonical origin cannot be silently imported into another local scope',
    () async {
      await receive(await package());
      await receiver.services.transfer.acceptItem(
        receiver.services.transfer.items().single.id,
      );
      await receiver.acceptedResearchImports.settled;
      final original = receiver.workspaces.all().single;
      final binding = receiver.workspaces.binding(original.id, 'research')!;
      // New ZIP package id, same canonical objects; never overwrite existing scope.
      await receive(await package());
      final second = receiver.services.transfer.items().last;
      await receiver.services.transfer.acceptItem(second.id);
      await receiver.acceptedResearchImports.settled;
      expect(receiver.services.transfer.items().last.imported, isFalse);
      expect(
        receiver.workspaces.binding(original.id, 'research')!.nativeProjectId,
        binding.nativeProjectId,
      );
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        hasLength(1),
      );
      expect(
        receiver.research!.store.db.select('SELECT * FROM projects'),
        hasLength(1),
      );
      expect(
        receiver.foundation.notifications().any(
          (n) => n.body.contains('another local project'),
        ),
        isTrue,
      );
    },
  );

  test(
    'close drains admitted acceptance and rejects any later callback',
    () async {
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      await receiver.close();
      receiver.acceptedResearchImports.accept(item);
      await expectLater(
        receiver.acceptedResearchImports.settled,
        throwsStateError,
      );
    },
  );

  test(
    'wrapped canonical ZIP remains unimported rather than counting extraction',
    () async {
      final zip = File('${temp.path}/study.zip')
        ..writeAsBytesSync(await package());
      final wrapped = await source.services.transfer.exportFiles([zip.path]);
      await receive(File(wrapped).readAsBytesSync());
      await receiver.services.transfer.acceptItem(
        receiver.services.transfer.items().single.id,
      );
      await receiver.acceptedResearchImports.settled;
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.services.transfer.receipts(), isEmpty);
      expect(receiver.workspaces.all(), isEmpty);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        isEmpty,
      );
      expect(
        receiver.foundation.notifications().any((n) => n.title == '研究包未导入'),
        isFalse,
      );
    },
  );

  test(
    'recovery binding conflict cannot falsely mark the transfer imported',
    () async {
      await receive(await package());
      final item = receiver.services.transfer.items().single;
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.acceptedResearchImports.settled;
      final original = receiver.workspaces.all().single;
      final project = receiver.workspaces
          .binding(original.id, 'research')!
          .nativeProjectId;
      await receiver.workspaces.database.write((db) {
        db.execute('DELETE FROM workspace_module_bindings');
        db.execute("UPDATE import_intents SET status='pending'");
      });
      final other = await receiver.workspaces.create('Other owner');
      await receiver.workspaces.bind(
        WorkspaceBinding(
          workspaceId: other.id,
          moduleId: 'research',
          nativeProjectId: project,
        ),
      );
      await receiver.services.transfer.database.write(
        (db) => db.execute('UPDATE transfer_items SET imported=0'),
      );
      await restart();
      expect(receiver.researchError, isNull);
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.workspaces.binding(original.id, 'research'), isNull);
      expect(
        receiver.workspaces.database.raw
            .select('SELECT status FROM import_intents')
            .single['status'],
        'conflict',
      );
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        hasLength(1),
      );
      expect(
        receiver.foundation.notifications().any((n) => n.title == '导入未能完成绑定'),
        isTrue,
      );
    },
  );
  for (final status in ['rejected', 'cancelled']) {
    test('stale accepted callback cannot import durable $status item', () async {
      await receive(await package());
      receiver.services.transfer.onAccepted = null;
      final id = receiver.services.transfer.items().single.id;
      await receiver.services.transfer.acceptItem(id);
      final stale = receiver.services.transfer.items().single;
      // No public revocation API exists yet: fault-inject the persisted state.
      await receiver.services.transfer.database.write(
        (db) => db.execute(
          'UPDATE transfer_items SET acceptance=? WHERE item_id=?',
          [status, id],
        ),
      );
      receiver.acceptedResearchImports.accept(stale);
      await receiver.acceptedResearchImports.settled;
      expect(receiver.workspaces.all(), isEmpty);
      expect(receiver.services.transfer.items().single.imported, isFalse);
      if (receiver.research != null) {
        expect(
          receiver.research!.store.db.select(
            'SELECT * FROM rk_import_receipts',
          ),
          isEmpty,
        );
      }
    });
  }

  test(
    'revoked durable acceptance during async import prevents commit',
    () async {
      await receive(await package());
      final id = receiver.services.transfer.items().single.id;
      await receiver.services.transfer.acceptItem(id);
      await receiver.services.transfer.database.write(
        (db) => db.execute(
          "UPDATE transfer_items SET acceptance='cancelled' WHERE item_id=?",
          [id],
        ),
      );
      await receiver.acceptedResearchImports.settled;
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        isEmpty,
      );
      expect(receiver.services.transfer.items().single.imported, isFalse);
    },
  );

  test(
    'high level transfer send supports canonical ZIP before accepted import',
    () async {
      final transfer = source.services.transfer;
      await transfer.start(
        deviceId: 'source-transfer',
        deviceName: 'source',
        discoveryPort: 0,
        httpPort: 0,
        secrets: MemoryLanSecretStore(),
      );
      final remote = await transfer.probe(
        '127.0.0.1',
        port: receiver.services.transfer.httpPort!,
      );
      transfer.confirmPeer(
        fingerprint: remote.fingerprint,
        confirmedCode: receiver.services.transfer.localShortCode!,
        certificatePem: remote.certificatePem,
      );
      final reverse = await receiver.services.transfer.probe(
        '127.0.0.1',
        port: transfer.httpPort!,
      );
      receiver.services.transfer.confirmPeer(
        fingerprint: reverse.fingerprint,
        confirmedCode: transfer.localShortCode!,
        certificatePem: reverse.certificatePem,
      );
      final zip = File('${temp.path}/canonical.zip')
        ..writeAsBytesSync(await package());
      await transfer.send(remote, zip.path);
      await receiver.services.transfer.itemsSettled;
      final item = receiver.services.transfer.items().single;
      expect(item.imported, isFalse);
      await receiver.services.transfer.acceptItem(item.id);
      await receiver.acceptedResearchImports.settled;
      expect(receiver.services.transfer.items().single.imported, isTrue);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        hasLength(1),
      );
    },
  );

  test('cancellation during receipt reconciliation does not fail research activation', () async {
    await receive(await package());
    final item = receiver.services.transfer.items().single;
    await receiver.services.transfer.acceptItem(item.id);
    await receiver.acceptedResearchImports.settled;
    await receiver.services.transfer.database.write(
      (db) => db.execute('UPDATE transfer_items SET imported=0'),
    );
    final reconcile = receiver.acceptedResearchImports.reconcileCommitted(
      receiver.research!,
    );
    await receiver.services.transfer.database.write(
      (db) => db.execute("UPDATE transfer_items SET acceptance='cancelled'"),
    );
    await reconcile;
    expect(receiver.services.transfer.items().single.imported, isFalse);
    expect(
      receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
      hasLength(1),
    );
  });
  Future<void> failMarker({
    String? itemId,
  }) => receiver.services.transfer.database.write((db) {
    db.execute(
      "CREATE TRIGGER deny_marker BEFORE UPDATE OF imported ON transfer_items "
      "WHEN NEW.imported=1 ${itemId == null ? '' : "AND OLD.item_id='$itemId'"} "
      "BEGIN SELECT RAISE(ABORT, 'injected marker failure'); END;",
    );
  });

  void expectCommittedFailure({int count = 1}) {
    expect(
      receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
      hasLength(count),
    );
    expect(
      receiver.research!.store.db.select('SELECT * FROM rk_cards'),
      hasLength(count),
    );
    final notices = receiver.foundation.notifications();
    expect(notices.any((n) => n.title.contains('已提交')), isTrue);
    expect(notices.any((n) => n.title == '研究包未导入'), isFalse);
  }

  test(
    'binding failure after domain commit reports committed data truthfully',
    () async {
      await receiver.workspaces.database.write(
        (db) => db.execute(
          "CREATE TRIGGER deny_binding BEFORE INSERT ON workspace_module_bindings "
          "BEGIN SELECT RAISE(ABORT, 'injected binding failure'); END;",
        ),
      );
      await receive(await package());
      final id = receiver.services.transfer.items().single.id;
      await receiver.services.transfer.acceptItem(id);
      await receiver.acceptedResearchImports.settled;
      expectCommittedFailure();
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(
        receiver.workspaces.database.raw
            .select('SELECT status FROM import_intents')
            .single['status'],
        'pending',
      );
      await receiver.workspaces.database.write(
        (db) => db.execute('DROP TRIGGER deny_binding'),
      );
      await restart();
      expect(receiver.services.transfer.items().single.imported, isTrue);
      expect(
        receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
        hasLength(1),
      );
    },
  );

  test(
    'marker failure after domain and binding commit does not claim no import',
    () async {
      await failMarker();
      await receive(await package());
      await receiver.services.transfer.acceptItem(
        receiver.services.transfer.items().single.id,
      );
      await receiver.acceptedResearchImports.settled;
      expectCommittedFailure();
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(
        receiver.workspaces.database.raw
            .select('SELECT status FROM import_intents')
            .single['status'],
        'complete',
      );
    },
  );

  test(
    'cancellation after domain commit preserves data and reports committed',
    () async {
      await receiver.activateResearch();
      final db = receiver.research!.resources.database as ManagedConnection;
      final previous = db.onCommit;
      var cancelled = false;
      db.onCommit = () {
        previous?.call();
        if (!cancelled &&
            db.raw.select('SELECT * FROM rk_import_receipts').isNotEmpty) {
          cancelled = true;
          receiver.services.transfer.database.raw.execute(
            "UPDATE transfer_items SET acceptance='cancelled'",
          );
        }
      };
      await receive(await package());
      await receiver.services.transfer.acceptItem(
        receiver.services.transfer.items().single.id,
      );
      await receiver.acceptedResearchImports.settled;
      db.onCommit = previous;
      expect(cancelled, isTrue);
      expectCommittedFailure();
      expect(receiver.services.transfer.items().single.acceptance, 'cancelled');
      expect(receiver.services.transfer.items().single.imported, isFalse);
    },
  );

  test('notification persistence failure reports original committed outcome through Flutter errors', () async {
    await failMarker();
    await receiver.workspaces.database.write(
      (db) => db.execute(
        "CREATE TRIGGER deny_notice BEFORE INSERT ON notifications "
        "WHEN NEW.title<>'收到设备数据包' BEGIN SELECT RAISE(ABORT, 'injected notification failure'); END;",
      ),
    );
    final previous = FlutterError.onError;
    final reported = <FlutterErrorDetails>[];
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    await receive(await package());
    await receiver.services.transfer.acceptItem(
      receiver.services.transfer.items().single.id,
    );
    await expectLater(receiver.acceptedResearchImports.settled, completes);
    expect(
      receiver.research!.store.db.select('SELECT * FROM rk_import_receipts'),
      hasLength(1),
    );
    expect(reported, hasLength(1));
    expect(reported.single.exception.toString(), contains('已提交'));
    expect(
      reported.single.exception.toString(),
      contains('injected marker failure'),
    );
    expect(
      reported.single.context.toString(),
      contains('injected notification failure'),
    );
  });

  test('unreadable receipt reports unknown rather than absence or automatic replay', () async {
    await receiver.activateResearch();
    await failMarker();
    final db = receiver.research!.resources.database as ManagedConnection;
    final previous = db.onCommit;
    var hidden = false;
    db.onCommit = () {
      previous?.call();
      if (!hidden &&
          db.raw.select('SELECT * FROM rk_import_receipts').isNotEmpty) {
        hidden = true;
        db.raw.execute(
          'ALTER TABLE rk_import_receipts RENAME TO hidden_receipts',
        );
      }
    };
    await receive(await package());
    await receiver.services.transfer.acceptItem(
      receiver.services.transfer.items().single.id,
    );
    await receiver.acceptedResearchImports.settled;
    db.onCommit = previous;
    expect(db.raw.select('SELECT * FROM hidden_receipts'), hasLength(1));
    expect(
      receiver.foundation.notifications().any(
        (n) => n.title.contains('结果未知') && n.body.contains('不会自动'),
      ),
      isTrue,
    );
    expect(
      receiver.foundation.notifications().any((n) => n.title == '研究包未导入'),
      isFalse,
    );
    db.raw.execute('ALTER TABLE hidden_receipts RENAME TO rk_import_receipts');
  });

  test('restart isolates completed marker failure and continues later committed items', () async {
    await receive(await package());
    final firstId = receiver.services.transfer.items().single.id;
    await receiver.services.transfer.acceptItem(firstId);
    await receiver.acceptedResearchImports.settled;
    await source.research!.resources.database.write(
      (db) =>
          db.execute("INSERT INTO projects(id,title) VALUES('other','Other')"),
    );
    await CardStore(source.research!.resources.database).save(
      projectId: 'other',
      cardId: 'other-card',
      expectedHead: null,
      bodyMarkdown: 'Other evidence',
    );
    await receive(
      await ResearchPackageExchange(
        CardStore(source.research!.resources.database),
      ).exportBytes('other', ['other-card']),
    );
    await receiver.services.transfer.acceptItem(
      receiver.services.transfer.items().last.id,
    );
    await receiver.acceptedResearchImports.settled;
    await receiver.services.transfer.database.write(
      (db) => db.execute('UPDATE transfer_items SET imported=0'),
    );
    await receiver.close();
    receiver = await MuyonHost.open('${temp.path}/receiver');
    await failMarker(itemId: firstId);
    await receiver.activateResearch();
    expect(receiver.research, isNotNull);
    expect(receiver.researchError, isNull);
    expectCommittedFailure(count: 2);
    final items = receiver.services.transfer.items();
    expect(items.first.imported, isFalse);
    expect(items.last.imported, isTrue);
    expect(
      receiver.workspaces.database.raw
          .select(
            "SELECT status FROM module_registry WHERE module_id='research'",
          )
          .single['status'],
      'ready',
    );
  });

  test(
    'cancellation queued before reconciliation marker remains isolated',
    () async {
      await receive(await package());
      await receiver.services.transfer.acceptItem(
        receiver.services.transfer.items().single.id,
      );
      await receiver.acceptedResearchImports.settled;
      await receiver.services.transfer.database.write(
        (db) => db.execute('UPDATE transfer_items SET imported=0'),
      );
      final db = receiver.workspaces.database as ManagedConnection;
      final previous = db.onCommit;
      Future<void>? cancellation;
      db.onCommit = () {
        previous?.call();
        cancellation ??= receiver.services.transfer.database.write(
          (transfer) => transfer.execute(
            "UPDATE transfer_items SET acceptance='cancelled'",
          ),
        );
      };
      await receiver.acceptedResearchImports.reconcileCommitted(
        receiver.research!,
      );
      await cancellation;
      db.onCommit = previous;
      expect(receiver.research, isNotNull);
      expect(receiver.services.transfer.items().single.imported, isFalse);
      expect(receiver.services.transfer.items().single.acceptance, 'cancelled');
      expectCommittedFailure();
    },
  );
}
