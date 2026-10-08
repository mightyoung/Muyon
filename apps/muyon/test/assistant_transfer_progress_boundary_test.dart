import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/platform/grants/host_tool_authorization.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';

void main() {
  for (final revoke in [false, true]) {
    test(
      'positive progress callback ${revoke ? 'withdraws authority' : 'expires approval'} before chunk delivery',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'auth-transfer-intent-',
        );
        final storage = StorageManager('${root.path}/host');
        final owner = await storage.open('muyon', WorkspaceRepository.schema);
        final module = ManagedConnection(sqlite3.openInMemory());
        for (final migration in KnowledgeService.schema.migrations) {
          migration.migrate(module.raw);
        }
        final sender = TransferService(
          module,
          '${root.path}/sender',
          outboundDatabase: owner,
        );
        final receiver = TransferService(
          module,
          '${root.path}/receiver',
          outboundDatabase: owner,
        );
        var currentClock = DateTime.now();
        final registry = ToolRegistry(
          database: owner,
          clock: () => currentClock,
          resolveScope: (scope) async =>
              ResolvedAssistantScope(requested: scope, objects: const []),
        );
        addTearDown(() async {
          await registry.close();
          await sender.close();
          await receiver.close();
          await module.close();
          await storage.close();
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
        final source = File('${root.path}/source.txt')
          ..writeAsStringSync('中文 private source');
        final memberHash = sha256.convert(source.readAsBytesSync()).toString();
        final package = await sender.exportFiles([source.path]);
        final actualBytes = File(package).readAsBytesSync();
        final bodyHash = sha256.convert(actualBytes).toString();
        final endpoint = Uri(
          scheme: 'https',
          host: peer.address,
          port: peer.port,
          path: '/push',
        );
        final request = ToolCallRequest(
          invocationId: 'real-tls-call',
          toolId: 'transfer.send',
          scope: AssistantScope.global(),
          destination: endpoint.toString(),
          parameters: {
            'path': package,
            'sourceDigest': bodyHash,
            'peerId': peer.id,
            'clean': true,
            'grantId': 'fake',
            'endpointIdentity': 'model-fake',
          },
        );
        registry.register(
          providerId: 'host.transfer.fixture',
          descriptor: ToolDescriptor(
            toolId: 'transfer.send',
            moduleId: 'knowledge',
            effect: ToolEffect.network,
            parameterSchema: const {
              'type': 'object',
              'additionalProperties': true,
            },
          ),
          effectIntent: (request, _) => sender.prepareSendIntent(
            request,
            allowedMembers: {'source.txt': memberHash},
          ),
          handler: (context) async {
            await sender.send(
              peer,
              package,
              expectedDigest: bodyHash,
              allowedMembers: {'source.txt': memberHash},
              authorization: registry.authorizationLink(context.request),
              onProgress: (sent, total) {
                if (sent > 0) {
                  if (revoke) {
                    registry.setAvailability('transfer.send', available: false);
                  } else {
                    currentClock = currentClock.add(const Duration(hours: 1));
                  }
                }
              },
            );
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'sent',
            );
          },
        );
        final prepared = await registry.prepare(request);
        expect(prepared.effectIntent, isNotNull);
        expect(prepared.effectIntent!.content, actualBytes);
        expect(prepared.effectIntent!.endpoint, endpoint);
        expect(
          prepared.effectIntent!.endpointIdentity,
          contains(peer.fingerprint),
        );
        expect(
          prepared.effectIntent!.endpointIdentity,
          isNot(contains('model-fake')),
        );
        expect(prepared.effectIntent!.destinationDigest, isNot(bodyHash));
        final auth = HostToolAuthorization(
          registry: registry,
          reviewer: const NoopReviewer(),
        );
        final reviewed = await auth.review(prepared);
        // Approval must re-read the actual managed package, never the model claim.
        File(package).writeAsBytesSync([...actualBytes, 32]);
        await expectLater(auth.confirm(reviewed), throwsA(anything));
        expect(owner.raw.select('SELECT * FROM tool_approvals'), isEmpty);
        expect(
          owner.raw.select(
            "SELECT * FROM outbound_tool_requests WHERE tool_id='transfer.send'",
          ),
          isEmpty,
        );
        File(package).writeAsBytesSync(actualBytes);
        final approval = await auth.confirm(reviewed);
        expect(approval, isNotNull);
        final result = await registry.invoke(request.withApproval(approval!));
        expect(result.status, isNot(ToolCallStatus.succeeded));
        final rows = owner.raw.select(
          "SELECT * FROM outbound_tool_requests WHERE tool_id='transfer.send'",
        );
        expect(rows, hasLength(1));
        expect(rows.single['state'], 'failed');
        expect(rows.single['review_decision_id'], reviewed.reviewDecisionId);
        expect(rows.single['bytes_sent'], 0);
        await receiver.itemsSettled;
        expect(Directory('${root.path}/receiver/inbox').listSync(), isEmpty);
      },
    );
  }
}
