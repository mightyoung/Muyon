import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/model_profile_tile.dart';
import 'package:muyon/services/models/capability_probe.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/openai_compat_provider.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:sqlite3/sqlite3.dart';

/// K-2b: the model profile page. The dialog and the notice are driven with a
/// fake probe runner; the probe itself is tested against a loopback endpoint
/// in capability_probe_test.dart.
class _MemoryDb implements ManagedDatabase {
  _MemoryDb() : raw = sqlite3.openInMemory() {
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(raw);
    }
  }
  @override
  final Database raw;
  @override
  Future<T> write<T>(T Function(Database database) body) async {
    raw.execute('BEGIN');
    try {
      final result = body(raw);
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }
}

final _profile = ModelProfile(
  id: 'p1',
  endpoint: Uri.parse('http://127.0.0.1:11434/v1'),
  location: ModelLocation.local,
  modelId: 'qwen2.5:7b',
  endpointIdentity: '本机 Ollama',
  capabilities: const ModelCapabilities(
    streaming: true,
    source: CapabilitySource.preset,
  ),
);

DetectedCapabilities _found({
  ProbeVerdict nativeTools = ProbeVerdict.yes,
  ProbeVerdict usage = ProbeVerdict.yes,
}) => DetectedCapabilities(
  nativeTools: nativeTools,
  streaming: ProbeVerdict.yes,
  reportsUsage: usage,
  contextTokens: 32768,
  maxOutputTokens: 8192,
  detectedAt: DateTime.utc(2026, 10, 7),
  payloadDigest: probeContentDigest(),
);

void main() {
  _wiringTests();
  late List<bool> runs;
  late List<DetectedCapabilities> stored;
  late List<ModelCapabilities> adopted;

  /// Runs the dialog's probe like the real one does: ask for the person's
  /// confirmation first, send (here: nothing) only after "yes".
  ProbeRunner runner(DetectedCapabilities result, {bool rejected = false}) =>
      (profile, {required extended, required confirm}) async {
        runs.add(extended);
        final yes = await confirm(
          ProbeConfirmation(
            index: 1,
            total: extended ? 2 : 1,
            extended: extended,
            profile: profile,
            payload: const OpenAiCompatProvider().encode(
              probeRequest(profile, extended: extended),
            ),
            digest: probeContentDigest(extended: extended),
          ),
        );
        return yes
            ? ProbeOutcome(detected: result, rejected: rejected)
            : const ProbeOutcome(stoppedBy: 'declined');
      };

  Future<void> open(WidgetTester tester, ProbeRunner run) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConnectionTestDialog(
                context,
                profile: _profile,
                run: run,
                onDetected: (d) async => stored.add(d),
                onAdopt: (c) async => adopted.add(c),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    runs = [];
    stored = [];
    adopted = [];
  });

  group('test-connection dialog', () {
    testWidgets('nothing runs until "开始测试"; the card names what is sent', (
      tester,
    ) async {
      await open(tester, runner(_found()));
      expect(runs, isEmpty, reason: 'opening the dialog sends nothing');
      expect(find.byKey(const ValueKey('probe-start')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('probe-start')));
      await tester.pumpAndSettle();
      expect(runs, [false]);
      expect(find.text('将向该端点发送凭据与固定探测内容'), findsOneWidget);
      expect(find.textContaining('probe_echo'), findsWidgets);
      expect(find.textContaining(probeContentDigest()), findsOneWidget);
      expect(find.textContaining('http://127.0.0.1:11434/v1'), findsWidgets);
      // Nothing is stored or adopted while the card is open.
      expect(stored, isEmpty);
      expect(adopted, isEmpty);
    });

    testWidgets('the result is shown beside the current settings and does not '
        'take effect until "采用"', (tester) async {
      await open(tester, runner(_found()));
      await tester.tap(find.byKey(const ValueKey('probe-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('probe-confirm')));
      await tester.pumpAndSettle();
      // Stored next to the capabilities, but nothing adopted yet.
      expect(stored, hasLength(1));
      expect(adopted, isEmpty);
      final table = find.byKey(const ValueKey('probe-result'));
      expect(table, findsOneWidget);
      expect(
        find.descendant(of: table, matching: find.text('原生工具调用')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('是')),
        findsWidgets,
      );
      expect(
        find.descendant(of: table, matching: find.text('32768')),
        findsOne,
      );
      expect(
        find.descendant(of: table, matching: find.text('未设置')),
        findsWidgets,
      );
      expect(find.textContaining('尚未生效'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('probe-adopt')));
      await tester.pumpAndSettle();
      expect(adopted, hasLength(1));
      expect(adopted.single.nativeTools, isTrue);
      expect(adopted.single.contextTokens, 32768);
      expect(adopted.single.source, CapabilitySource.detected);
      expect(find.textContaining('已采用'), findsOneWidget);
      expect(find.byKey(const ValueKey('probe-adopt')), findsNothing);
    });

    testWidgets('declining the card sends and stores nothing', (tester) async {
      await open(tester, runner(_found()));
      await tester.tap(find.byKey(const ValueKey('probe-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('probe-decline')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('probe-stopped')), findsOneWidget);
      expect(stored, isEmpty);
      expect(adopted, isEmpty);
      expect(find.byKey(const ValueKey('probe-adopt')), findsNothing);
    });

    testWidgets('the optional second request is asked for with the checkbox', (
      tester,
    ) async {
      await open(tester, runner(_found()));
      await tester.tap(find.byKey(const ValueKey('probe-extended')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('probe-start')));
      await tester.pumpAndSettle();
      expect(runs, [true]);
      expect(find.textContaining('第 1/2 次请求'), findsOneWidget);
    });

    testWidgets(
      'undetermined and unconfirmed are labelled and change nothing',
      (tester) async {
        await open(
          tester,
          runner(
            _found(
              nativeTools: ProbeVerdict.unconfirmed,
              usage: ProbeVerdict.undetermined,
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('probe-start')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('probe-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('未确认（按“否”处理）'), findsOneWidget);
        expect(find.text('未能判定（不改变设置）'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('probe-adopt')));
        await tester.pumpAndSettle();
        // The undetermined usage keeps the current (off) value; tools stay off.
        expect(adopted.single.nativeTools, isFalse);
        expect(adopted.single.reportsUsage, isFalse);
      },
    );

    testWidgets('a 400/422 is reported as such, asking for a manual check', (
      tester,
    ) async {
      await open(
        tester,
        runner(
          _found(
            nativeTools: ProbeVerdict.undetermined,
            usage: ProbeVerdict.undetermined,
          ),
          rejected: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('probe-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('probe-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('端点以 400/422 拒绝（可能是工具、流式或其他参数），请手动确认'), findsOneWidget);
      expect(find.text('否'), findsNothing);
    });

    testWidgets('a failed run says so without quoting anything', (
      tester,
    ) async {
      await open(tester, (p, {required extended, required confirm}) async {
        throw StateError('Bearer sk-secret-0123456789');
      });
      await tester.tap(find.byKey(const ValueKey('probe-start')));
      await tester.pumpAndSettle();
      expect(find.textContaining('测试没有完成'), findsOneWidget);
      expect(find.textContaining('sk-secret'), findsNothing);
    });
  });

  group('profile tile', () {
    testWidgets('streaming switch, test button and what is in effect', (
      tester,
    ) async {
      bool? streaming;
      var tested = 0;
      final withResult = _profile.copyWith(detectedCapabilities: _found());
      await tester.pumpWidget(
        MaterialApp(
          theme: muyonTheme(Brightness.light),
          home: Scaffold(
            body: ModelProfileTile(
              profile: withResult,
              onStreaming: (v) => streaming = v,
              onTest: () => tested++,
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('本机 Ollama'), findsOneWidget);
      expect(find.textContaining('兼容模式（预设）'), findsOneWidget);
      expect(find.textContaining('有未采用的检测结果'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('streaming-p1')));
      expect(streaming, isFalse);
      await tester.tap(find.byKey(const ValueKey('test-p1')));
      expect(tested, 1);
    });

    testWidgets('an embedding model has neither switch nor test button', (
      tester,
    ) async {
      final embedding = ModelProfile(
        id: 'e1',
        endpoint: Uri.parse('http://127.0.0.1:11434/v1'),
        location: ModelLocation.local,
        modelId: 'bge',
        endpointIdentity: 'embed',
        purpose: ModelPurpose.embedding,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelProfileTile(
              profile: embedding,
              onStreaming: (_) {},
              onTest: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('streaming-e1')), findsNothing);
      expect(find.byKey(const ValueKey('test-e1')), findsNothing);
    });
  });

  group('migration notice', () {
    Future<void> showNotice(WidgetTester tester, WorkspaceRepository w) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfileMigrationNotice(
                read: () => pendingModelProfilesNotice(w),
                clear: () => clearModelProfilesNotice(w),
              ),
            ),
          ),
        );

    testWidgets('appears once after the migration and never again', (
      tester,
    ) async {
      final w = WorkspaceRepository(_MemoryDb());
      await w.setSetting('modelProfiles', [
        {
          'id': 'old',
          'endpoint': 'http://127.0.0.1:11434/v1/chat/completions',
          'location': 'local',
          'modelId': 'm',
          'endpointIdentity': 'x',
        },
      ]);
      expect(await migrateModelProfileCapabilities(w), 1);
      expect(pendingModelProfilesNotice(w), 1);

      await showNotice(tester, w);
      expect(find.text('已为已有模型启用流式显示，可在每个模型上关闭'), findsOneWidget);
      // Cleared as soon as it was shown, so it cannot return...
      expect(pendingModelProfilesNotice(w), isNull);
      // ...and stays while this page is open, until dismissed.
      await tester.pump();
      expect(find.text('已为已有模型启用流式显示，可在每个模型上关闭'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pump();
      expect(find.text('已为已有模型启用流式显示，可在每个模型上关闭'), findsNothing);

      // Opening the page again: nothing.
      await tester.pumpWidget(const SizedBox());
      await showNotice(tester, w);
      expect(find.text('已为已有模型启用流式显示，可在每个模型上关闭'), findsNothing);
      // And a second migration run does not bring it back.
      expect(await migrateModelProfileCapabilities(w), 0);
      expect(pendingModelProfilesNotice(w), isNull);
    });

    testWidgets('no migration, no notice', (tester) async {
      final w = WorkspaceRepository(_MemoryDb());
      await showNotice(tester, w);
      expect(
        find.byKey(const ValueKey('profile-migration-notice')),
        findsNothing,
      );
    });
  });

  test('turning streaming off survives a restart', () async {
    final w = WorkspaceRepository(_MemoryDb());
    await w.setSetting('modelProfiles', [
      {
        'id': 'old',
        'endpoint': 'http://127.0.0.1:11434/v1/chat/completions',
        'location': 'local',
        'modelId': 'm',
        'endpointIdentity': 'x',
      },
    ]);
    await migrateModelProfileCapabilities(w);
    final repo = ProfileRepository(w);
    expect(repo.all().single.capabilities.streaming, isTrue);
    // What the switch on the settings page does.
    final current = repo.all().single;
    await repo.save(
      current.copyWith(
        capabilities: current.capabilities.copyWith(
          streaming: false,
          source: CapabilitySource.userDeclared,
        ),
      ),
    );
    // "Restart": the migration runs again at start-up.
    expect(await migrateModelProfileCapabilities(w), 0);
    final after = ProfileRepository(w).all().single;
    expect(after.capabilities.streaming, isFalse);
    expect(after.capabilities.source, CapabilitySource.userDeclared);
  });
}

/// The wiring the settings page uses (`testProfileConnection`) against a real
/// profile store: a probe stores only `detectedCapabilities`; `capabilities`
/// change only when the person clicks 采用.
void _wiringTests() {
  testWidgets('detection never writes capabilities; 采用 does', (tester) async {
    final w = WorkspaceRepository(_MemoryDb());
    final profiles = ProfileRepository(w);
    await profiles.save(_profile);
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => testProfileConnection(
                context,
                profile: _profile,
                profiles: profiles,
                run: (p, {required extended, required confirm}) async {
                  await confirm(
                    ProbeConfirmation(
                      index: 1,
                      total: 1,
                      extended: false,
                      profile: p,
                      payload: const {},
                      digest: probeContentDigest(),
                    ),
                  );
                  return ProbeOutcome(detected: _found());
                },
                onChanged: () => changes++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('probe-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('probe-confirm')));
    await tester.pumpAndSettle();

    var saved = profiles.all().single;
    expect(changes, 1);
    expect(saved.detectedCapabilities!.nativeTools, ProbeVerdict.yes);
    expect(
      saved.capabilities.toJson(),
      _profile.capabilities.toJson(),
      reason: 'a probe changes no setting',
    );

    await tester.tap(find.byKey(const ValueKey('probe-adopt')));
    await tester.pumpAndSettle();
    saved = profiles.all().single;
    expect(changes, 2);
    expect(saved.capabilities.nativeTools, isTrue);
    expect(saved.capabilities.contextTokens, 32768);
    expect(saved.capabilities.source, CapabilitySource.detected);
    expect(saved.detectedCapabilities, isNotNull);
  });

  testWidgets('declining the card stores nothing at all', (tester) async {
    final w = WorkspaceRepository(_MemoryDb());
    final profiles = ProfileRepository(w);
    await profiles.save(_profile);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => testProfileConnection(
                context,
                profile: _profile,
                profiles: profiles,
                run: (p, {required extended, required confirm}) async {
                  await confirm(
                    ProbeConfirmation(
                      index: 1,
                      total: 1,
                      extended: false,
                      profile: p,
                      payload: const {},
                      digest: probeContentDigest(),
                    ),
                  );
                  return const ProbeOutcome(stoppedBy: 'declined');
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('probe-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('probe-decline')));
    await tester.pumpAndSettle();
    final saved = profiles.all().single;
    expect(saved.detectedCapabilities, isNull);
    expect(saved.capabilities.toJson(), _profile.capabilities.toJson());
  });
}
