import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_catalog.dart';
import 'package:muyon/app/adapters/inquiry_module.dart';
import 'package:muyon/platform/ui_navigation_anchors.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/aiui5_revision2_review_test.dart' show reviewPlan;
import 'support/conversation_workspace_fixture.dart';
import 'support/fake_v2_module.dart';
import 'support/ui_navigation_fixture.dart';

// Public registered plugin fixture. No model, business tool or network is used.
class _NavigationRuntime extends FakeRuntime implements ObjectPages {
  _NavigationRuntime(super.resources);
  int opened = 0, released = 0;
  Completer<void>? entered, release;
  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async {
    opened++;
    entered?.complete();
    await release?.future;
    return ObjectPageLease(
      title: '公开集合对象',
      page: Text('注册对象 ${ref.objectId}'),
      dispose: () async { released++; },
    );
  }
}

// Uses the production Inquiry adapter/schema/database and its real object
// resolver. The wrapper holds an actual lease only to control the await window.
class _SupportedModule extends InquiryBusinessModule {
  _SupportedModule(MuyonHost Function() host) : super(host);
  int activations = 0;
  _SupportedRuntime? runtime;
  @override
  final manifest = ModuleManifest(id: 'inquiry', apiVersion: 2,
    features: {ModuleFeature.importPipeline, ModuleFeature.objectPages},
    capabilities: {const CapabilityRequest(id: 'ocr', reason: 'lease barrier fixture')});
  @override
  void registerTools(ToolRegistrar registrar) {} // No fixture business dispatch.
  @override
  Future<ModuleRuntime> activate(ModuleResources resources) async {
    activations++;
    final actual = await super.activate(resources) as InquiryModuleRuntime;
    return runtime = _SupportedRuntime(resources, actual);
  }
}

class _SupportedRuntime extends FakeRuntime implements ObjectPages {
  _SupportedRuntime(super.resources, this.actual);
  final InquiryModuleRuntime actual;
  int opened = 0, released = 0;
  Completer<void>? entered, release;
  @override
  Future<ModuleSession> openSession(WorkspaceBinding binding) => actual.openSession(binding);
  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async {
    final lease = await actual.open(context, ref);
    if (lease == null) return null;
    opened++;
    entered?.complete();
    await release?.future;
    return ObjectPageLease(title: lease.title, page: lease.page, dispose: () async {
      released++;
      await lease.dispose();
    });
  }
}

Future<({NavigationFixture fixture, _SupportedModule module, ObjectRef ref})>
    _supported(WidgetTester tester) async {
  late NavigationFixture fixture;
  final module = _SupportedModule(() => fixture.host);
  fixture = await NavigationFixture.open(tester, extra: [module]);
  final unpinned = await fixture.seedObject(tester, 'inquiry');
  final runtime = (await workspaceOperation(tester,
    () => fixture.host.modules.runtimeFor('inquiry')))! as _SupportedRuntime;
  final session = await workspaceOperation(tester, () => runtime.actual.openScopeSession());
  final view = await workspaceOperation(tester, () => session.resolve(unpinned));
  await workspaceOperation(tester, session.dispose);
  expect(view, isNotNull);
  expect(view!.ref.revisionRef, isNotNull);
  expect(view.ref.contentDigest, isNotNull);
  return (fixture: fixture, module: module, ref: view.ref);
}

FakeV2Module _module() => FakeV2Module('navigation_fixture',
  features: {ModuleFeature.objectPages}, runtimeFactory: _NavigationRuntime.new);

const _object = ObjectRef(moduleId: 'navigation_fixture', objectType: 'note',
  objectId: 'public-note', revisionRef: 'v1', contentDigest: 'public-fixture-digest');

ValidatedUiPlan _plan([String component = 'Choice', ObjectRef object = _object]) {
  final source = reviewPlan(component);
  final snapshot = DataSnapshot(
    ref: source.snapshot.ref,
    facts: {
      for (final entry in source.snapshot.facts.entries)
        entry.key: SnapshotFact(object: object, field: entry.value.field,
          value: entry.value.value, state: entry.value.state),
      'unrelated': SnapshotFact(
        object: const ObjectRef(moduleId: 'unrelated-fixture', objectType: 'note', objectId: 'hidden'),
        field: 'label', value: 'NOT IN PLAN', state: FactState.verified),
    },
    initialUiState: {...source.snapshot.initialUiState, 'count': 2.0},
    editSpecs: {...source.snapshot.editSpecs, 'count': const UiNumberEdit(min: 0, max: 10)},
    collections: {
      for (final entry in source.snapshot.collections.entries)
        entry.key: UiCollection(id: entry.value.id, columns: entry.value.columns,
          rows: [for (final row in entry.value.rows)
            UiRow(itemId: row.itemId, cells: row.cells,
              object: row.object == null ? null : object)]),
      'unused': UiCollection(id: 'unused',
      columns: const [UiColumn('label', 'Unused')],
      rows: [UiRow(itemId: 'hidden', cells: {'label': const BindingRef.fact('unrelated')})])},
    actionContext: source.snapshot.actionContext,
  );
  final result = validateUiPlan(source.plan.copyWith(nodes: [
    for (final node in source.plan.nodes)
      node.id == 'root' ? node.copyWith(children: [...node.children, 'count']) : node,
    UiNode(id: 'count', component: 'NumberStepper', properties: {'label': '数量'},
      bindings: {'value': const BindingRef.uiState('count')},
      events: {'change': ActionBinding(actionRef: 'edit', inputRefs: ['count'])}),
  ]), snapshot, source.intent, source.catalog);
  expect(result.errors, isEmpty);
  return result.validatedPlan!;
}

void _viewport(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _unmount(WidgetTester tester) async {
  final workspaces = find.byType(DynamicWorkspace, skipOffstage: false).evaluate();
  if (workspaces.isNotEmpty) {
    final navigator = Navigator.of(workspaces.first);
    final workspaceRoute = ModalRoute.of(workspaces.first);
    await workspaceOperation(tester, () async {
      // Pop ordinary object routes to complete their lease futures. A failed
      // checkpoint intentionally blocks the phone workspace's PopScope; do
      // not repeatedly request that blocked user pop during test cleanup.
      navigator.popUntil((route) => identical(route, workspaceRoute));
      if (workspaceRoute != null && !workspaceRoute.isFirst) {
        navigator.removeRoute(workspaceRoute);
      }
    });
  }
  await tester.pumpWidget(const SizedBox());
  await workspaceReady(tester);
}

Future<DynamicWorkspaceSession> _show(WidgetTester tester, MuyonHost host,
    ValidatedUiPlan plan, void Function() business) async {
  await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, open) =>
    Scaffold(body: TextButton(onPressed: () => open(DynamicWorkspace(
      repository: host.foundation, host: host, taskId: 'task', surfaceId: plan.plan.surfaceId,
      plan: plan, originalAnswer: '完整原回答', onEvent: (_) async { business(); },
    )), child: const Text('打开当前工作区'))))));
  await tester.tap(find.text('打开当前工作区'));
  await workspaceVisible(tester, find.byType(ConversationWorkspaceBody));
  return tester.widget<DynamicWorkspace>(find.byType(DynamicWorkspace)).session!;
}

void main() {
  for (final width in [390.0, 1280.0]) {
    for (final component in ['Choice', 'Checklist', 'CompareTable']) {
    testWidgets('typed $component object round trip and SQLite reopen width=$width', (tester) async {
      _viewport(tester, width);
      final supported = await _supported(tester);
      final module = supported.module, f = supported.fixture, ref = supported.ref;
      MuyonHost? reopened;
      addTearDown(() async {
        try { await _unmount(tester); }
        finally { if (reopened != null) { await workspaceOperation(tester, reopened.close); } }
      });
      final plan = _plan(component, ref);
      var calls = 0;
      final session = await _show(tester, f.host, plan, () { calls++; });
      final c = session.controller!;
      final navigator = Navigator.of(tester.element(find.byType(DynamicWorkspace)));
      expect(navigator.canPop(), width < 1250);
      if (component != 'CompareTable') {
        await tester.tap(find.text('B'));
      }
      await tester.tap(find.byKey(const ValueKey('stepper-plus')));
      await workspaceOperation(tester, c.flush);
      if (component != 'CompareTable') {
        expect(c.surface.session.selections['k'], ['a', 'b']);
      }
      expect(c.surface.session.userOverrides['count'], 3.0);
      expect(find.text('查看对象 · inquiry'), findsOneWidget);
      expect(find.text('查看对象 · unrelated-fixture'), findsNothing);
      final oldCallback = tester.widget<IconButton>(find.byKey(const ValueKey('stepper-plus'))).onPressed!;
      await tester.tap(find.text('查看对象 · inquiry'));
      await workspaceVisible(tester, find.text('真实询价对象'));
      final runtime = module.runtime!;
      expect(runtime.opened, 1);
      expect(runtime.released, 0);
      final store = HostUiWorkspaceStore(f.host.foundation, taskId: 'task');
      final anchor = (await workspaceOperation(tester, () => store.loadNavigationAnchor('s')))!;
      expect(anchor.objectRef, ref);
      expect(anchor.conversationId, f.conversationId);
      expect(anchor.nodeId, 'target');
      await tester.pageBack();
      await workspaceReady(tester);
      expect(runtime.released, 1);
      expect(session.controller, same(c));
      if (component != 'CompareTable') {
        expect(c.surface.session.selections['k'], ['a', 'b']);
      }
      expect(c.surface.session.userOverrides['count'], 3.0);
      await tester.tap(find.byTooltip('关闭工作区 / 返回'));
      await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
      expect(navigator.canPop(), isFalse);
      final committed = (await workspaceOperation(tester, () => store.load('s')))!;
      oldCallback(); // A callback retained from the disposed surface cannot dispatch.
      await workspaceReady(tester);
      expect(calls, 0);
      expect(runtime.released, 1);
      expect((await workspaceOperation(tester, () => store.load('s')))!.toJson(), committed.toJson());
      await _unmount(tester);
      await workspaceOperation(tester, f.host.close);
      final freshModule = _SupportedModule(() => reopened!);
      reopened = await workspaceOperation(tester, () => MuyonHost.open('${f.root.path}/data', modules: [freshModule, ...moduleCatalog()]));
      final restored = await _show(tester, reopened!, plan, () { calls++; });
      expect(restored.controller!.readOnly, isFalse);
      if (component != 'CompareTable') {
        expect(restored.controller!.surface.session.selections['k'], ['a', 'b']);
      }
      expect(restored.controller!.surface.session.userOverrides['count'], 3.0);
      expect(restored.controller!.returnAnchor, committed.returnAnchor);
      expect(restored.controller!.surface.session.draftRevision, committed.draftRevision);
      expect(calls, 0);
      expect(freshModule.activations, 0);
      await tester.tap(find.text('查看对象 · inquiry'));
      await workspaceVisible(tester, find.text('真实询价对象'));
      expect(freshModule.activations, 1);
      await tester.pageBack();
      await workspaceReady(tester);
      expect(freshModule.runtime!.released, 1);
      expect(restored.controller!.surface.session.userOverrides['count'], 3.0);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });
    }

    testWidgets('scope revoked while registered lease opens prevents late page width=$width', (tester) async {
      _viewport(tester, width);
      final supported = await _supported(tester);
      final module = supported.module, f = supported.fixture;
      addTearDown(() => _unmount(tester));
      var calls = 0;
      final session = await _show(tester, f.host, _plan('Choice', supported.ref), () { calls++; });
      await workspaceOperation(tester, () => f.host.modules.runtimeFor('inquiry'));
      final runtime = module.runtime!;
      final entered = Completer<void>(), release = Completer<void>();
      runtime.entered = entered;
      runtime.release = release;
      Future<void>? pending;
      String? savedBytes;
      addTearDown(() { if (!release.isCompleted) { release.complete(); } });
      try {
        await tester.tap(find.text('查看对象 · inquiry'));
        await workspaceOperation(tester, () => entered.future);
        pending = session.pendingReferenceNavigation;
        expect(pending, isNotNull);
        savedBytes = f.host.foundation.database.raw.select(
          'SELECT value FROM settings WHERE key=?', ['ui-workspace:["task","s"]'],
        ).single['value'] as String;
        expect(runtime.opened, 1);
        expect(runtime.released, 0);
        await workspaceOperation(tester, () => f.host.foundation.database.write((db) => db.execute(
          "UPDATE execution_records SET payload=json_set(payload,'\$.scope',json(?)) WHERE id='task'",
          [jsonEncode(AssistantScope.workspace('other-workspace').toJson())],
        )));
      } finally {
        if (!release.isCompleted) { release.complete(); }
      }
      await workspaceOperation(tester, () => pending!);
      await workspaceReady(tester);
      expect(find.text('真实询价对象'), findsNothing);
      expect(find.textContaining('无法打开引用，原草稿仍保留'), findsWidgets);
      expect(runtime.released, 1);
      expect(f.host.foundation.database.raw.select(
        'SELECT value FROM settings WHERE key=?', ['ui-workspace:["task","s"]'],
      ).single['value'], savedBytes);
      expect(calls, 0);
      await tester.tap(find.byTooltip('关闭工作区 / 返回'));
      await workspaceReady(tester);
      expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
      expect(session.controller!.readOnly, isTrue);
      expect(calls, 0);
      expect(runtime.released, 1);
      expect(tester.takeException(), isNull);
    });

    for (final change in ['revoke', 'database']) {
      testWidgets('real Inquiry late lease $change rejects navigation width=$width', (tester) async {
        _viewport(tester, width);
        final supported = await _supported(tester);
        final f = supported.fixture, runtime = supported.module.runtime!;
        addTearDown(() => _unmount(tester));
        var calls = 0;
        final plan = _plan('Choice', supported.ref);
        final session = await _show(tester, f.host, plan, () { calls++; });
        await tester.tap(find.byKey(const ValueKey('stepper-plus')));
        await workspaceOperation(tester, session.controller!.flush);
        final scope = HostUiWorkspaceStore(f.host.foundation, taskId: 'task').scopeKey;
        final snapshot = session.controller!.surface.current.snapshot;
        final entered = Completer<void>(), release = Completer<void>();
        runtime.entered = entered;
        runtime.release = release;
        addTearDown(() { if (!release.isCompleted) release.complete(); });
        Future<void>? pending;
        String? savedBytes;
        try {
          await tester.tap(find.text('查看对象 · inquiry'));
          await workspaceOperation(tester, () => entered.future);
          pending = session.pendingReferenceNavigation;
          expect(pending, isNotNull);
          expect(runtime.opened, 1);
          expect(runtime.released, 0);
          savedBytes = f.host.foundation.database.raw.select(
            'SELECT value FROM settings WHERE key=?', ['ui-workspace:["task","s"]'],
          ).single['value'] as String;
          if (change == 'revoke') {
            await workspaceOperation(tester, () => f.host.modules.revokeCapability('inquiry', 'ocr'));
            expect(f.host.modules.scopeAuthorityRevision('inquiry'), isNull);
          } else {
            final store = f.host.inquiry!.runtime.state.store;
            final before = store.get('project', supported.ref.objectId)!;
            await workspaceOperation(tester, () async {
              store.save('project', {...before.data, 'name': '已变化的询价对象'}, id: before.id);
            });
            final current = store.get('project', supported.ref.objectId)!;
            expect(current.version.toString(), isNot(supported.ref.revisionRef));
            expect(current.data['name'], '已变化的询价对象');
          }
          expect(HostUiWorkspaceStore(f.host.foundation, taskId: 'task').scopeKey, scope);
          expect(session.controller!.surface.current.snapshot, same(snapshot));
        } finally {
          if (!release.isCompleted) release.complete();
        }
        await workspaceOperation(tester, () => pending!);
        await workspaceReady(tester);
        expect(find.text('真实询价对象'), findsNothing);
        expect(find.text('已变化的询价对象'), findsNothing);
        expect(find.textContaining('无法打开引用，原草稿仍保留'), findsWidgets);
        expect(runtime.released, 1);
        expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
        expect(session.controller!.surface.session.userOverrides['count'], 3.0);
        expect(f.host.foundation.database.raw.select(
          'SELECT value FROM settings WHERE key=?', ['ui-workspace:["task","s"]'],
        ).single['value'], savedBytes);
        expect(calls, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('unsupported source proof keeps workspace without plugin read width=$width', (tester) async {
      _viewport(tester, width);
      final module = _module();
      final f = await NavigationFixture.open(tester, extra: [module]);
      addTearDown(() => _unmount(tester));
      var calls = 0;
      final session = await _show(tester, f.host, _plan(), () { calls++; });
      await tester.tap(find.byKey(const ValueKey('stepper-plus')));
      await workspaceOperation(tester, session.controller!.flush);
      await tester.tap(find.text('查看对象 · navigation_fixture'));
      await workspaceVisible(tester, find.textContaining('无法打开引用，原草稿仍保留'));
      expect(module.activations, 1); // Prepare succeeded; source proof is unsupported.
      expect((module.runtime! as _NavigationRuntime).opened, 0);
      expect(find.text('注册对象 public-note'), findsNothing);
      expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
      expect(session.controller!.surface.session.userOverrides['count'], 3.0);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typed workspace CAS loss prevents object navigation and close width=$width', (tester) async {
      _viewport(tester, width);
      final module = _module();
      final f = await NavigationFixture.open(tester, extra: [module]);
      addTearDown(() => _unmount(tester));
      var calls = 0;
      final plan = _plan();
      final session = await _show(tester, f.host, plan, () { calls++; });
      final c = session.controller!;
      await tester.tap(find.byKey(const ValueKey('stepper-plus')));
      await workspaceOperation(tester, c.flush);
      final store = HostUiWorkspaceStore(f.host.foundation, taskId: 'task');
      final competing = await workspaceOperation(tester, () => UiWorkspaceController.open(
        store: store, taskId: 'task', scopeKey: store.scopeKey!, plan: plan));
      addTearDown(competing.dispose);
      competing.surface.session.edit('count', 7.0);
      await workspaceOperation(tester, competing.flush);
      final winner = (await workspaceOperation(tester, () => store.load('s')))!.toJson();
      await tester.tap(find.text('查看对象 · navigation_fixture'));
      await workspaceVisible(tester, find.textContaining('无法打开引用，原草稿仍保留'));
      expect(module.activations, 0);
      expect(find.text('注册对象 public-note'), findsNothing);
      expect(c.readOnly, isTrue);
      expect(c.surface.session.userOverrides['count'], 3.0);
      await tester.tap(find.byTooltip('关闭工作区 / 返回'));
      await workspaceReady(tester);
      expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
      expect(c.surface.session.userOverrides['count'], 3.0);
      expect((await workspaceOperation(tester, () => store.load('s')))!.toJson(), winner);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
