import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';

void main() {
  test(
    'withdrawal while real TLS push ledger is queued sends zero bytes',
    () async {
      final root = Directory.systemTemp.createTempSync('auth-transfer-');
      final db = ManagedConnection(sqlite3.openInMemory());
      for (final migration in KnowledgeService.schema.migrations) {
        migration.migrate(db.raw);
      }
      final sender = TransferService(db, '${root.path}/sender');
      final receiver = TransferService(db, '${root.path}/receiver');
      addTearDown(() async {
        await sender.close();
        await receiver.close();
        await db.close();
        root.deleteSync(recursive: true);
      });
      for (final (service, id) in [
        (sender, 'sender'),
        (receiver, 'receiver'),
      ]) {
        await service.start(
          deviceId: id,
          deviceName: id,
          discoveryPort: 0,
          httpPort: 0,
          secrets: MemoryLanSecretStore(),
        );
      }
      Future<LanPeer> pair(
        TransferService local,
        TransferService remote,
      ) async {
        final peer = await local.probe('127.0.0.1', port: remote.httpPort!);
        local.confirmPeer(
          fingerprint: peer.fingerprint,
          confirmedCode: remote.localShortCode!,
          certificatePem: peer.certificatePem,
        );
        return peer;
      }

      final peer = await pair(sender, receiver);
      await pair(receiver, sender);
      final file = File('${root.path}/source.txt')
        ..writeAsStringSync('private source');
      final package = await sender.exportFiles([file.path]);
      final entered = Completer<void>(), release = Completer<void>();
      Future<void>? held;
      var withdrawn = false;
      void guard() {
        if (withdrawn) {
          throw const ToolPlatformException(
            'revoked',
            'Host permission withdrawn',
          );
        }
        final staging = Directory('${root.path}/sender/sending');
        if (held == null &&
            staging.existsSync() &&
            staging.listSync().any((e) => e is File)) {
          held = db.exclusiveAsync((_) async {
            entered.complete();
            await release.future;
          });
        }
      }

      final send = sender.send(peer, package, checkBeforeEffect: guard);
      final rejected = expectLater(send, throwsA(isA<ToolPlatformException>()));
      await entered.future.timeout(const Duration(seconds: 10));
      withdrawn = true;
      release.complete();
      await held;
      await rejected;
      final rows = db.raw.select(
        "SELECT * FROM outbound_tool_requests WHERE tool_id='transfer.send'",
      );
      expect(rows, hasLength(1));
      expect(rows.single['bytes_sent'], 0);
      expect(rows.single['state'], 'failed');
      expect(Directory('${root.path}/receiver/inbox').listSync(), isEmpty);
    },
  );
}
