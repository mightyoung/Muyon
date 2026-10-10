import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/aiui5_revision2_review_test.dart' show reviewPlan;
import 'support/conversation_workspace_fixture.dart';
import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;

class _RecoveryBarrierStore implements UiWorkspaceStore {
  _RecoveryBarrierStore(this.delegate, {this.fail = false});
  final UiWorkspaceStore delegate;
  final bool fail;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<StoredUiWorkspace?> load(String surfaceId) => delegate.load(surfaceId);
  @override
  Future<bool> save(StoredUiWorkspace value, {required int expectedRevision}) async {
    entered.complete();
    await release.future;
    if (fail) throw StateError('injected storage failure');
    return delegate.save(value, expectedRevision: expectedRevision);
  }
}

void main() {
  late Directory directory;
  late StorageManager storage;
  late FoundationRepository repository;
  late HostUiWorkspaceStore store;
  const key = 'ui-workspace:["task","s"]';
  Future<void> open() async {
    storage = StorageManager(directory.path);
    repository = FoundationRepository(await storage.open('muyon', WorkspaceRepository.schema));
    store = HostUiWorkspaceStore(repository, taskId: 'task');
  }
  String bytes() => repository.database.raw.select('SELECT value FROM settings WHERE key=?', [key]).single['value'] as String;
  Future<void> writeRaw(String value) => repository.database.write((db) => db.execute('UPDATE settings SET value=? WHERE key=?', [value, key]));
  Future<void> seed() async {
    final c = await UiWorkspaceController.open(store: store, taskId: 'task', scopeKey: store.scopeKey!, plan: reviewPlan('NumberStepper'));
    c.surface.session.edit('k', 9.0);
    await c.flush();
    c.dispose();
  }
  Future<DynamicWorkspaceSession> mount(WidgetTester tester, ValidatedUiPlan? plan, {bool embedded = false, void Function()? business, void Function()? close}) async {
    final page = DynamicWorkspace(repository: repository, taskId: 'task', surfaceId: 's', plan: plan, originalAnswer: '原回答', onEvent: (_) async { business?.call(); });
    final session = DynamicWorkspaceSession(page);
    addTearDown(session.dispose);
    await workspaceOperation(tester, session.ensureLoaded);
    await tester.pumpWidget(MaterialApp(home: DynamicWorkspace(repository: repository, taskId: 'task', surfaceId: 's', session: session, embedded: embedded, onClose: close == null ? null : () async { close(); })));
    await workspaceReady(tester);
    return session;
  }
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('aiui-draft-recovery-');
    await open();
    await repository.database.write((db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', ['task', 'paused', jsonEncode({'kind': 'personal', 'executionId': 'task', 'scope': AssistantScope.workspace('w1').toJson()})]));
  });
  tearDown(() async { await storage.close(); directory.deleteSync(recursive: true); });

  testWidgets('real page rejects out-of-range restore, discards explicitly, survives SQLite reopen', (tester) async {
    await workspaceOperation(tester, seed);
    await workspaceOperation(tester, storage.close);
    await workspaceOperation(tester, open);
    final before = bytes();
    var calls = 0;
    final session = await mount(tester, reviewPlan('NumberStepper', revision: 2, max: 5), business: () { calls++; });
    final c = session.controller!;
    expect(c.readOnly, isTrue);
    expect(c.surface.session.userOverrides, isEmpty);
    await tester.tap(find.text('恢复 k'));
    await workspaceReady(tester);
    expect(bytes(), before);
    expect(c.readOnly, isTrue);
    expect(c.quarantinedDraft['k'], 9.0);
    await tester.tap(find.text('丢弃 k（采用当前提取值）'));
    await workspaceReady(tester);
    expect(c.readOnly, isFalse);
    expect(c.surface.session.resolve(const BindingRef.uiState('k')), 2.0);
    expect(c.quarantinedDraft, isEmpty);
    expect((await workspaceOperation(tester, () => store.load('s')))!.revision, 2);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await workspaceOperation(tester, storage.close);
    await workspaceOperation(tester, open);
    final reopened = await mount(tester, reviewPlan('NumberStepper', revision: 2, max: 5));
    expect(reopened.controller!.readOnly, isFalse);
    expect(reopened.controller!.quarantinedDraft, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded page explicitly restores now-valid retained value with no business call', (tester) async {
    await workspaceOperation(tester, seed);
    final raw = jsonDecode(bytes()) as Map<String, dynamic>;
    raw['userOverrides'] = <String, Object?>{};
    raw['readableDraft'] = {'k': 9.0};
    await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
    final before = bytes();
    var calls = 0;
    final session = await mount(tester, reviewPlan('NumberStepper'), embedded: true, business: () { calls++; });
    expect(session.controller!.readOnly, isTrue);
    expect(bytes(), before);
    await tester.tap(find.text('恢复 k'));
    await workspaceReady(tester);
    expect(session.controller!.readOnly, isFalse);
    expect(session.controller!.surface.session.userOverrides['k'], 9.0);
    expect(session.controller!.quarantinedDraft, isEmpty);
    expect((await workspaceOperation(tester, () => store.load('s')))!.userOverrides['k'], 9.0);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale page recovery CAS preserves winning checkpoint and isolated live draft', (tester) async {
    await workspaceOperation(tester, seed);
    final session = await mount(tester, reviewPlan('NumberStepper', revision: 2, max: 5));
    final saved = (await workspaceOperation(tester, () => store.load('s')))!;
    expect(await workspaceOperation(tester, () => store.save(saved.copyWith(revision: 2, userOverrides: {'k': 4.0}), expectedRevision: 1)), isTrue);
    final winner = bytes();
    await tester.tap(find.text('丢弃 k（采用当前提取值）'));
    await workspaceReady(tester);
    expect(bytes(), winner);
    expect(session.controller!.readOnly, isTrue);
    expect(session.controller!.quarantinedDraft['k'], 9.0);
    expect(session.controller!.surface.session.userOverrides, isEmpty);
  });

  testWidgets('scope revocation prevents explicit draft discard', (tester) async {
    await workspaceOperation(tester, seed);
    final session = await mount(tester, reviewPlan('NumberStepper', revision: 2, max: 5));
    final before = bytes();
    await workspaceOperation(tester, () => repository.database.write((db) => db.execute('DELETE FROM execution_records WHERE id=?', ['task'])));
    await tester.tap(find.text('丢弃 k（采用当前提取值）'));
    await workspaceReady(tester);
    expect(bytes(), before);
    expect(session.controller!.readOnly, isTrue);
    expect(session.controller!.quarantinedDraft['k'], 9.0);
  });

  testWidgets('incompatible node identity cannot be recovered through buttons', (tester) async {
    await workspaceOperation(tester, seed);
    final raw = jsonDecode(bytes()) as Map<String, dynamic>;
    raw['nodeIds'] = ['removed'];
    await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
    final before = bytes();
    final session = await mount(tester, reviewPlan('NumberStepper'));
    expect(session.controller!.readOnly, isTrue);
    expect(session.controller!.canResolveDraft, isFalse);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '恢复 k')).onPressed, isNull);
    await expectLater(workspaceOperation(tester, () => session.controller!.resolveDraft('k', discard: true)), throwsStateError);
    expect(bytes(), before);
    expect(session.controller!.surface.session.userOverrides, isEmpty);
  });

  testWidgets('damaged foreign scope does not disclose readable fields', (tester) async {
    await workspaceOperation(tester, seed);
    final raw = jsonDecode(bytes()) as Map<String, dynamic>;
    raw['schemaVersion'] = 99;
    raw['scopeKey'] = 'foreign';
    await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
    final before = bytes();
    final session = await mount(tester, null);
    expect(session.unreadableDraft, isNull);
    expect(find.text('k: 9.0'), findsNothing);
    expect(bytes(), before);
  });

  testWidgets('schema1 two isolated fields remain readable and byte-identical without migration', (tester) async {
    final plan = actionPlan();
    final legacy = await workspaceOperation(tester, () => UiWorkspaceController.open(store: store, taskId: 'task', scopeKey: store.scopeKey!, plan: plan));
    await workspaceOperation(tester, legacy.flush);
    legacy.dispose();
    final legacyKey = 'ui-workspace:${jsonEncode(['task', 'comparison'])}';
    String legacyBytes() => repository.database.raw.select('SELECT value FROM settings WHERE key=?', [legacyKey]).single['value'] as String;
    final raw = jsonDecode(legacyBytes()) as Map<String, dynamic>;
    raw['userOverrides'] = {'quantity': 9.0, 'sort': 8.0};
    final before = jsonEncode(raw);
    await workspaceOperation(tester, () => repository.database.write((db) => db.execute('UPDATE settings SET value=? WHERE key=?', [before, legacyKey])));
    await workspaceOperation(tester, storage.close);
    await workspaceOperation(tester, open);
    final page = DynamicWorkspace(repository: repository, taskId: 'task', surfaceId: 'comparison', plan: plan);
    final session = DynamicWorkspaceSession(page);
    addTearDown(session.dispose);
    await workspaceOperation(tester, session.ensureLoaded);
    await tester.pumpWidget(MaterialApp(home: DynamicWorkspace(repository: repository, taskId: 'task', surfaceId: 'comparison', session: session)));
    await workspaceReady(tester);
    expect(session.controller!.schemaVersion, 1);
    expect(session.controller!.quarantinedDraft, {'quantity': 9.0, 'sort': 8.0});
    expect(session.controller!.canResolveDraft, isFalse);
    await expectLater(workspaceOperation(tester, () => session.controller!.resolveDraft('quantity', discard: true)), throwsStateError);
    expect(legacyBytes(), before);
    expect(find.text('隔离 quantity: 9.0'), findsOneWidget);
    expect(find.text('隔离 sort: 8.0'), findsOneWidget);
  });

  testWidgets('schema2 handles isolated fields individually without dropping remaining durable data', (tester) async {
    await workspaceOperation(tester, seed);
    final raw = jsonDecode(bytes()) as Map<String, dynamic>;
    raw['userOverrides'] = <String, Object?>{};
    raw['readableDraft'] = {'k': 9.0, 'removed': 'kept'};
    await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
    final session = await mount(tester, reviewPlan('NumberStepper'));
    await tester.tap(find.text('丢弃 removed（采用当前提取值）'));
    await workspaceReady(tester);
    expect(session.controller!.readOnly, isTrue);
    expect((await workspaceOperation(tester, () => store.load('s')))!.readableDraft, {'k': 9.0});
    await tester.tap(find.text('恢复 k'));
    await workspaceReady(tester);
    expect(session.controller!.readOnly, isFalse);
    expect((await workspaceOperation(tester, () => store.load('s')))!.userOverrides['k'], 9.0);
  });

  for (final storageFails in [true, false]) {
    testWidgets('recovery await boundary does not install rejected state storageFailure=$storageFails', (tester) async {
      await workspaceOperation(tester, seed);
      final raw = jsonDecode(bytes()) as Map<String, dynamic>;
      raw['userOverrides'] = <String, Object?>{};
      raw['readableDraft'] = {'k': 9.0};
      await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
      final before = bytes();
      final barrier = _RecoveryBarrierStore(store, fail: storageFails);
      var calls = 0;
      final c = await workspaceOperation(tester, () => UiWorkspaceController.open(store: barrier, taskId: 'task', scopeKey: store.scopeKey!, plan: reviewPlan('NumberStepper'), onEvent: (_) async { calls++; }));
      addTearDown(c.dispose);
      Object? failure;
      var finished = false;
      c.resolveDraft('k', discard: false).then<void>((_) { finished = true; }, onError: (Object error) { failure = error; finished = true; });
      await workspaceOperation(tester, () => barrier.entered.future);
      if (!storageFails) c.surface.session.updateSourceDigest('changed-during-save', 'new-digest');
      barrier.release.complete();
      for (var turn = 0; turn < 2000 && !finished; turn++) {
        await tester.runAsync(() => Future<void>(() {}));
        await tester.pump();
      }
      expect(finished, isTrue);
      expect(failure, isA<StateError>());
      expect(c.readOnly, isTrue);
      expect(c.surface.session.userOverrides, isEmpty);
      expect(c.quarantinedDraft['k'], 9.0);
      expect(calls, 0);
      if (storageFails) {
        expect(bytes(), before);
      } else {
        expect(c.canResolveDraft, isFalse);
        // The revision/scope CAS completed; the changed session is never
        // installed. Reopen is required to validate the durable projection.
        expect((await workspaceOperation(tester, () => store.load('s')))!.userOverrides['k'], 9.0);
      }
    });
  }

  testWidgets('oversized damaged checkpoint exposes no salvage and performs no writes', (tester) async {
    await workspaceOperation(tester, seed);
    final raw = jsonDecode(bytes()) as Map<String, dynamic>;
    raw['readableDraft'] = {'k': 'x' * UiWorkspaceLimits.bytes};
    await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
    final before = bytes();
    final session = await mount(tester, reviewPlan('NumberStepper'));
    expect(session.controller!.readOnly, isTrue);
    expect(session.controller!.readableDraft, isNull);
    expect(session.controller!.canResolveDraft, isFalse);
    await workspaceOperation(tester, session.checkpoint);
    expect(bytes(), before);
  });

  for (final hasPlan in [true, false]) {
    testWidgets('actual damaged-codec page readable without activation or byte rewrite plan=$hasPlan', (tester) async {
      await workspaceOperation(tester, seed);
      final raw = jsonDecode(bytes()) as Map<String, dynamic>;
      raw['schemaVersion'] = 99;
      await workspaceOperation(tester, () => writeRaw(jsonEncode(raw)));
      final damaged = bytes();
      var calls = 0, closes = 0;
      final session = await mount(tester, hasPlan ? reviewPlan('NumberStepper') : null, embedded: hasPlan, business: () { calls++; }, close: () { closes++; });
      expect(find.text('k: 9.0'), findsOneWidget);
      expect(bytes(), damaged);
      if (hasPlan) {
        expect(session.controller!.readOnly, isTrue);
        expect(session.controller!.canResolveDraft, isFalse);
        await workspaceOperation(tester, session.checkpoint);
        await tester.tap(find.byTooltip('关闭工作区 / 返回'));
        await workspaceReady(tester);
        expect(closes, 1);
        expect(session.controller!.surface.session.userOverrides, isEmpty);
        final node = session.controller!.surface.current.plan.nodes.firstWhere((n) => n.id == 'target');
        expect(await workspaceOperation(tester, () => session.controller!.surface.dispatch(session.controller!.surface.eventFor(node, 'change', 3.0))), UiDispatchOutcome.stale);
      } else {
        expect(session.controller, isNull);
        expect(session.unreadableDraft!['k'], 9.0);
      }
      expect(calls, 0);
      expect(bytes(), damaged);
      expect(tester.takeException(), isNull);
    });
  }
}
