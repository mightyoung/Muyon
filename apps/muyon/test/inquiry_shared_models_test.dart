import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/inquiry_plugin.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/services/models/secret_store.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

class MemoryModelSecrets extends MethodChannelSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String reference) async => values[reference];
  @override
  Future<void> write(String reference, String value) async {
    values[reference] = value;
  }

  @override
  Future<void> remove(String reference) async {
    values.remove(reference);
  }
}

void main() {
  late ManagedConnection database;
  late ProfileRepository profiles;
  late MemoryModelSecrets secrets;
  late HttpServer server;
  late ModelProfile profile;
  late OpenAiModelGateway gateway;
  setUp(() async {
    database = ManagedConnection(sqlite3.openInMemory());
    database.raw.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
    profiles = ProfileRepository(WorkspaceRepository(database));
    secrets = MemoryModelSecrets();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gateway = OpenAiModelGateway(secrets, timeout: const Duration(seconds: 3));
    profile = ModelProfile(
      id: 'active',
      endpoint: Uri.parse(
        'http://127.0.0.1:${server.port}/v1/chat/completions',
      ),
      location: ModelLocation.local,
      modelId: 'host-model',
      endpointIdentity: 'local-test',
      credentialRef: 'key',
    );
    secrets.values['key'] = 'private-value';
    await profiles.save(profile);
  });
  tearDown(() async {
    await server.close(force: true);
    await database.close();
  });
  Future<void> activate() =>
      profiles.workspaces.setSetting('activeModelProfileId', profile.id);

  test(
    'missing or deleted active profile never implicitly selects another',
    () async {
      final bridge = InquiryHostModels(
        profiles: profiles,
        gateway: gateway,
        secrets: secrets,
      );
      expect(await bridge.createClient(), isNull);
      expect(bridge.baseUrl, isEmpty);
      expect(await bridge.hasCredential(), isFalse);
      await activate();
      expect(bridge.model, 'host-model');
      await profiles.remove(profile.id);
      expect(await bridge.createClient(), isNull);
    },
  );

  test('embedding profile cannot be used for Folio chat', () async {
    await profiles.save(
      ModelProfile(
        id: 'embedding',
        endpoint: profile.endpoint,
        location: ModelLocation.local,
        modelId: 'embed',
        endpointIdentity: 'embed',
        purpose: ModelPurpose.embedding,
      ),
    );
    await profiles.workspaces.setSetting('activeModelProfileId', 'embedding');
    final bridge = InquiryHostModels(
      profiles: profiles,
      gateway: gateway,
      secrets: secrets,
    );
    expect(await bridge.createClient(), isNull);
    expect(bridge.model, isEmpty);
  });
  test('original LlmClient sends tools and JSON through gateway after exact approval', () async {
    await activate();
    final received = Completer<String>();
    server.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value('authorization'), 'Bearer private-value');
      received.complete(await utf8.decoder.bind(request).join());
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': '<think>hidden</think>answer',
                'tool_calls': [
                  {
                    'id': 'call',
                    'type': 'function',
                    'function': {'name': 'lookup', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    late InquiryModelApprovalPreview approved;
    var approvals = 0;
    final bridge = InquiryHostModels(
      profiles: profiles,
      gateway: gateway,
      secrets: secrets,
      approve: (preview) async {
        approved = preview;
        approvals++;
        return true;
      },
    );
    final client = (await bridge.createClient())!;
    final response = await client.complete(
      [
        {'role': 'user', 'content': 'supplier question'},
      ],
      tools: [
        {
          'type': 'function',
          'function': {'name': 'lookup'},
        },
      ],
      json: true,
      maxTokens: 123,
    );
    final actual = await received.future;
    expect(approved.endpoint, profile.endpoint);
    expect(approved.bodyDigest, sha256.convert(utf8.encode(actual)).toString());
    expect(approved.body['model'], 'host-model');
    expect(approved.body['tools'], isNotEmpty);
    expect(approved.body['response_format'], {'type': 'json_object'});
    expect(approved.body['max_tokens'], 123);
    expect(() => approved.body['model'] = 'tampered', throwsUnsupportedError);
    expect(actual, isNot(contains('private-value')));
    expect(response['content'], 'answer');
    expect(response['tool_calls'], isNotEmpty);
    expect(approvals, 1);
  });

  test(
    'no delegate and declined approval fail closed without network requests',
    () async {
      await activate();
      var sent = 0;
      server.listen((request) {
        sent++;
        request.response.close();
      });
      for (final approval in <InquiryModelApproval?>[
        null,
        (_) async => false,
      ]) {
        final bridge = InquiryHostModels(
          profiles: profiles,
          gateway: gateway,
          secrets: secrets,
          approve: approval,
        );
        await expectLater(
          (await bridge.createClient())!.complete([
            {'role': 'user', 'content': 'private'},
          ]),
          throwsA(isA<LlmException>()),
        );
      }
      expect(sent, 0);
    },
  );

  test(
    'profile switch during confirmation and cancellation block send',
    () async {
      await activate();
      var sent = 0;
      server.listen((request) {
        sent++;
        request.response.close();
      });
      final bridge = InquiryHostModels(
        profiles: profiles,
        gateway: gateway,
        secrets: secrets,
        approve: (_) async {
          await profiles.workspaces.setSetting('activeModelProfileId', '');
          return true;
        },
      );
      await expectLater(
        (await bridge.createClient())!.complete([
          {'role': 'user', 'content': 'private'},
        ]),
        throwsA(isA<LlmException>()),
      );
      await activate();
      final cancellation = AiCancellation()..cancel();
      await expectLater(
        (await bridge.createClient(cancellation: cancellation))!.complete([
          {'role': 'user', 'content': 'private'},
        ]),
        throwsA(isA<LlmException>()),
      );
      expect(sent, 0);
    },
  );

  test('source settings save updates shared active profile and stores key only in vault', () async {
    await activate();
    final bridge = InquiryHostModels(
      profiles: profiles,
      gateway: gateway,
      secrets: secrets,
    );
    await bridge.save(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'updated',
      apiKey: 'new-secret',
    );
    expect(profiles.all().single.modelId, 'updated');
    expect(bridge.model, 'updated');
    expect(bridge.active!.endpoint, profile.endpoint);
    expect(secrets.values['key'], 'new-secret');
    expect(
      profiles.workspaces.setting('modelProfiles').toString(),
      isNot(contains('new-secret')),
    );
    expect(await bridge.hasCredential(), isTrue);
    await bridge.save(baseUrl: bridge.baseUrl, model: bridge.model, apiKey: '');
    expect(await bridge.hasCredential(), isFalse);
  });

  test('saving without active creates and explicitly selects a shared local profile', () async {
    final bridge = InquiryHostModels(
      profiles: profiles,
      gateway: gateway,
      secrets: secrets,
    );
    await bridge.save(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'new-local',
    );
    expect(bridge.active!.id, isNot(profile.id));
    expect(bridge.active!.modelId, 'new-local');
    expect(await bridge.hasCredential(), isTrue);
    expect(profiles.all(), hasLength(2));
  });
}
