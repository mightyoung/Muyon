import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/model_request_gate.dart';
import 'package:muyon/assistant/request_view.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/services/models/token_estimate.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

Map<String, Object?> _stored(
  String id, {
  String? purpose,
  Object? capabilities,
}) => {
  'id': id,
  'endpoint': 'http://127.0.0.1:11434/v1/chat/completions',
  'location': 'local',
  'modelId': 'm-$id',
  'endpointIdentity': 'fixture',
  'credentialRef': null,
  'cloudProxy': false,
  'purpose': ?purpose,
  if (capabilities != null) 'capabilities': capabilities,
};

void main() {
  late Directory root;
  late StorageManager storage;
  late WorkspaceRepository workspaces;
  late ProfileRepository profiles;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-capabilities-');
    storage = StorageManager(root.path);
    workspaces = WorkspaceRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    profiles = ProfileRepository(workspaces);
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  group('capabilities', () {
    test('the default is compatibility, non-streaming, nothing declared', () {
      const c = ModelCapabilities();
      expect(c.toJson(), ModelCapabilities.compat.toJson());
      expect(c.nativeTools, isFalse);
      expect(c.streaming, isFalse);
      expect(c.contextTokens, isNull);
      expect(c.source, CapabilitySource.unknown);
    });

    test('toJson writes every field and round-trips', () {
      const declared = ModelCapabilities(
        nativeTools: true,
        parallelToolCalls: true,
        streaming: true,
        jsonSchema: true,
        jsonObject: true,
        reportsUsage: true,
        contextTokens: 128000,
        maxOutputTokens: 8192,
        source: CapabilitySource.userDeclared,
      );
      expect(declared.toJson().keys, [
        'nativeTools',
        'parallelToolCalls',
        'streaming',
        'jsonSchema',
        'jsonObject',
        'reportsUsage',
        'contextTokens',
        'maxOutputTokens',
        'source',
      ]);
      expect(
        ModelCapabilities.fromJson(declared.toJson()).toJson(),
        declared.toJson(),
      );
      // Damaged values never unlock anything.
      final damaged = ModelCapabilities.fromJson({
        'nativeTools': 'yes',
        'contextTokens': -5,
        'source': 'root',
      });
      expect(damaged.nativeTools, isFalse);
      expect(damaged.contextTokens, isNull);
      expect(damaged.source, CapabilitySource.unknown);
      expect(
        ModelCapabilities.fromJson('x').toJson(),
        ModelCapabilities.compat.toJson(),
      );
    });

    test('ModelProfile.toJson always carries the full capabilities', () {
      final plain = ModelProfile(
        id: 'p',
        endpoint: Uri.parse('http://127.0.0.1:1/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'x',
      );
      expect(plain.toJson()['capabilities'], ModelCapabilities.compat.toJson());
      final streaming = ModelProfile(
        id: 'p',
        endpoint: Uri.parse('http://127.0.0.1:1/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'x',
        capabilities: const ModelCapabilities(
          streaming: true,
          source: CapabilitySource.preset,
        ),
      );
      final json = streaming.toJson()['capabilities'] as Map;
      expect(json['streaming'], true);
      expect(json['source'], 'preset');
      expect(json.keys, hasLength(9));
    });

    test('a saved profile reads back with its capabilities; one without the '
        'key is compatibility', () async {
      await workspaces.setSetting('modelProfiles', [
        _stored('old'),
        _stored(
          'new',
          capabilities: const ModelCapabilities(nativeTools: true).toJson(),
        ),
      ]);
      final byId = {for (final p in profiles.all()) p.id: p};
      expect(byId['old']!.capabilities.streaming, isFalse);
      expect(byId['old']!.capabilities.nativeTools, isFalse);
      expect(byId['new']!.capabilities.nativeTools, isTrue);
    });
  });

  group('one-time migration', () {
    test('chat profiles without capabilities become streaming/migrated; '
        'embedding and declared ones are left alone', () async {
      await workspaces.setSetting('modelProfiles', [
        _stored('chat-default'),
        _stored('chat', purpose: 'chat'),
        _stored('embed', purpose: 'embedding'),
        _stored(
          'declared',
          capabilities: const ModelCapabilities(nativeTools: true).toJson(),
        ),
      ]);
      expect(await migrateModelProfileCapabilities(workspaces), 2);
      final raw = <String, Map<dynamic, dynamic>>{
        for (final p in workspaces.setting('modelProfiles') as List)
          (p as Map)['id'] as String: p,
      };
      for (final id in ['chat-default', 'chat']) {
        final c = raw[id]!['capabilities'] as Map;
        expect(c['streaming'], true);
        expect(c['source'], 'migrated');
        expect(c['nativeTools'], false);
        expect(c['parallelToolCalls'], false);
        expect(c['jsonSchema'], false);
        expect(c['contextTokens'], isNull);
      }
      expect(raw['embed']!.containsKey('capabilities'), isFalse);
      expect(
        (raw['declared']!['capabilities'] as Map)['streaming'],
        false,
        reason: 'what the person declared is theirs',
      );
      // Everything else about a profile survives.
      expect(raw['chat']!['modelId'], 'm-chat');
      expect(workspaces.setting('modelProfilesSchema'), 2);
      expect(workspaces.setting('modelProfilesMigrationNotice'), {
        'pending': true,
        'migrated': 2,
      });
      final read = {for (final p in profiles.all()) p.id: p};
      expect(read['chat']!.capabilities.streaming, isTrue);
      expect(read['embed']!.capabilities.streaming, isFalse);
    });

    test('it is idempotent', () async {
      await workspaces.setSetting('modelProfiles', [_stored('a')]);
      await migrateModelProfileCapabilities(workspaces);
      final after = jsonEncode(workspaces.setting('modelProfiles'));
      expect(await migrateModelProfileCapabilities(workspaces), 0);
      expect(jsonEncode(workspaces.setting('modelProfiles')), after);
    });

    test('a person who turned streaming off is not changed back on the '
        'next start', () async {
      await workspaces.setSetting('modelProfiles', [_stored('a')]);
      await migrateModelProfileCapabilities(workspaces);
      final saved = profiles.all().single;
      await profiles.save(
        ModelProfile(
          id: saved.id,
          endpoint: saved.endpoint,
          location: saved.location,
          modelId: saved.modelId,
          endpointIdentity: saved.endpointIdentity,
          capabilities: const ModelCapabilities(
            source: CapabilitySource.userDeclared,
          ),
        ),
      );
      await migrateModelProfileCapabilities(workspaces); // "restart"
      expect(profiles.all().single.capabilities.streaming, isFalse);
      expect(
        profiles.all().single.capabilities.source,
        CapabilitySource.userDeclared,
      );
    });

    test('a profile saved without capabilities after the marker is not '
        'migrated again: the marker, not the data, decides', () async {
      await migrateModelProfileCapabilities(workspaces);
      await workspaces.setSetting('modelProfiles', [_stored('late')]);
      expect(await migrateModelProfileCapabilities(workspaces), 0);
      expect(profiles.all().single.capabilities.streaming, isFalse);
    });

    test('with nothing saved it only sets the marker, and no notice', () async {
      expect(await migrateModelProfileCapabilities(workspaces), 0);
      expect(workspaces.setting('modelProfilesSchema'), 2);
      expect(workspaces.setting('modelProfilesMigrationNotice'), isNull);
    });

    test('reading profiles has no side effects', () async {
      await workspaces.setSetting('modelProfiles', [_stored('a')]);
      final before = jsonEncode(workspaces.setting('modelProfiles'));
      profiles.all();
      profiles.all();
      expect(jsonEncode(workspaces.setting('modelProfiles')), before);
      expect(workspaces.setting('modelProfilesSchema'), isNull);
      expect(workspaces.setting('modelProfilesMigrationNotice'), isNull);
    });
  });

  group('ledger migration', () {
    test('rows from before keep their data, gain empty new columns, and the '
        'status CHECK is unchanged', () async {
      final old = Directory.systemTemp.createTempSync('muyon-ledger-v6-');
      addTearDown(() => old.deleteSync(recursive: true));
      final v6 = ModuleSchema(
        version: 6,
        definitionDigest: 'foundation-v6',
        migrations: WorkspaceRepository.schema.migrations.take(6).toList(),
      );
      final first = StorageManager(old.path);
      final before = OutboundLedger(await first.open('muyon', v6));
      final profile = ModelProfile(
        id: 'p',
        endpoint: Uri.parse('http://127.0.0.1:1/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'x',
      );
      final id = await before.begin(
        caller: 'chat',
        profile: profile,
        payload: '{"a":1}',
        itemCount: 1,
      );
      await before.finish(id, 'succeeded', httpStatus: 200);
      await first.close();

      final second = StorageManager(old.path);
      addTearDown(second.close);
      final db = await second.open('muyon', WorkspaceRepository.schema);
      final ledger = OutboundLedger(db);
      final row = ledger.recent().single;
      expect(row['id'], id);
      expect(row['status'], 'succeeded');
      expect(row['payload_bytes'], 7);
      for (final column in [
        'request_digest',
        'prompt_tokens',
        'completion_tokens',
        'first_byte_ms',
        'bytes_received',
        'streamed',
      ]) {
        expect(row.containsKey(column), isTrue, reason: column);
        expect(row[column], isNull, reason: column);
      }
      // New rows use the new columns; no `partial` status was added.
      final next = await ledger.begin(
        caller: 'assistant',
        profile: profile,
        payload: '{}',
        itemCount: 1,
        requestDigest: 'd',
        streamed: true,
      );
      await ledger.finish(
        next,
        'failed',
        error: 'stream_truncated',
        bytesReceived: 12,
        firstByteMs: 40,
        promptTokens: 3,
      );
      final written = ledger.recent().first;
      expect(written['request_digest'], 'd');
      expect(written['streamed'], 1);
      expect(written['bytes_received'], 12);
      expect(written['first_byte_ms'], 40);
      expect(written['prompt_tokens'], 3);
      expect(
        () => db.raw.execute(
          "UPDATE outbound_requests SET status='partial' WHERE id=?",
          [next],
        ),
        throwsA(anything),
      );
    });
  });

  group('token estimate', () {
    test('ASCII counts bytes / 4, rounded up', () {
      expect(estimateTokens(''), 0);
      expect(estimateTokens('abcd'), 1);
      expect(estimateTokens('abcde'), 2);
      expect(estimateTokens('a' * 400), 100);
    });

    test('every non-ASCII character counts one token', () {
      expect(estimateTokens('你好世界'), 4);
      expect(estimateTokens('成本合计 2080 元'), 5 + 2);
      // bytes / 4 would give 3 for four Chinese characters (12 bytes).
      expect(
        estimateTokens('你好世界'),
        greaterThan(utf8.encode('你好世界').length ~/ 4),
      );
    });

    test('mixed text adds both parts', () {
      expect(estimateTokens('abcd你好'), 1 + 2);
      expect(estimateTokens('😀'), 1, reason: 'one character, one token');
    });

    test('a reported size wins over an estimate', () {
      expect(tokensOf('a' * 400, reported: 7), 7);
      expect(tokensOf('a' * 400), 100);
      expect(tokensSinceReport(reported: 1000, added: 'abcd'), 1001);
      final messages = [
        {'role': 'system', 'content': 'x' * 4000},
        {'role': 'user', 'content': 'hello'},
        {'role': 'user', 'content': 'a' * 400},
      ];
      final all = estimateMessageTokens(messages);
      final withReport = estimateMessageTokens(
        messages,
        reportedPromptTokens: 50,
        reportedMessageCount: 2,
      );
      expect(withReport, lessThan(all));
      expect(
        withReport,
        50 + estimateTokens(jsonEncode([messages.last])),
        reason:
            'the report stands for the first two messages; only the '
            'third is estimated',
      );
    });
  });

  group('request view and gate', () {
    test('with no compaction state the view is the stored list, untouched', () {
      final messages = <Object?>[
        {'role': 'user', 'content': 'x'},
      ];
      expect(buildRequestView(messages), same(messages));
      expect(buildRequestView(messages, compactionState: null), same(messages));
    });

    test('AlwaysConfirmGate always asks the person', () async {
      final decision = await const AlwaysConfirmGate().decide(
        const ModelRequestFacts(
          location: ModelLocation.remote,
          endpoint: 'https://example.com/v1/chat/completions',
          endpointIdentity: 'x',
          scopeDigest: 's',
          requestDigest: 'r',
          dataCategories: {'conversation'},
          step: 0,
        ),
      );
      expect(decision, isA<GateConfirm>());
    });
  });
}
