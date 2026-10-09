import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:supplier_core/supplier_core.dart';

import 'support/ui_navigation_fixture.dart';
import 'support/conversation_workspace_fixture.dart';
import 'support/fake_v2_module.dart';

import 'package:muyon/platform/ui_navigation_anchors.dart';

class _LeaseRuntime extends FakeRuntime implements ObjectPages {
  _LeaseRuntime(super.resources);
  int released = 0;
  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async =>
      ObjectPageLease(
        title: '真实插件租用页',
        page: const Text('PLUGIN LEASE CONTENT'),
        dispose: () async => released++,
      );
}

void main() {
  testWidgets('desktop_unavailable_plugin_return_keeps_parent_workspace', (tester) async {
    final f = await NavigationFixture.open(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');
    await open!(DynamicWorkspace(repository: f.host.foundation, host: f.host,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref), originalAnswer: '原对话回答'));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '24');
    await tester.tap(find.text('查看对象 · removed-plugin'));
    await workspaceReady(tester);
    await workspaceVisible(tester, find.textContaining('对象或插件当前不可用'));
    expect(find.textContaining('对象或插件当前不可用'), findsOneWidget);
    await tester.pageBack();
    await workspaceReady(tester);
    expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '24');
    expect(find.text('原对话回答'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await workspaceReady(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale_anchor_does_not_open_another_object', (tester) async {
    final f = await NavigationFixture.open(tester);
    final ref = await f.seedObject(tester, 'research');
    await f.show(tester, f.plan(ref));
    final c = tester.widget<UiWorkspaceView>(find.byType(UiWorkspaceView)).controller;
    final navigation = UiReferenceNavigation(context: tester.element(find.byType(UiWorkspaceView)), host: f.host, controller: c);
    final anchor = NavigationAnchor(conversationId: f.conversationId, taskId: 'task', surfaceId: 'comparison', nodeId: 'detail', scrollOffset: 0, objectRef: ref);
    for (final bad in [
      ObjectRef(moduleId: ref.moduleId, objectType: ref.objectType, objectId: 'other', nativeProjectId: ref.nativeProjectId),
      ObjectRef(moduleId: ref.moduleId, objectType: ref.objectType, objectId: ref.objectId, nativeProjectId: ref.nativeProjectId, revisionRef: 'changed'),
      ObjectRef(moduleId: ref.moduleId, objectType: ref.objectType, objectId: ref.objectId, nativeProjectId: ref.nativeProjectId, contentDigest: 'changed'),
    ]) {
      await expectLater(navigation.openReference(bad, anchor), throwsStateError);
    }
    expect(find.text('原对话回答'), findsOneWidget);
    expect(find.text('真实研究对象'), findsNothing);
    expect(c.returnAnchor, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'actual_global_inquiry_supplier_opens_without_fabricated_workspace_binding',
    (tester) async {
      final f = await NavigationFixture.open(tester);
      final id = (await tester.runAsync(() async {
        await f.host.activateInquiry();
        return f.host.inquiry!.runtime.state.store.save('supplier', {
          for (final field in Supplier.fields) field: null,
          'name': '真实全局供应商',
          'aliases': <String>[],
          'categories': <String>[],
        });
      }))!;
      final ref = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'supplier',
        objectId: id,
      );
      await f.show(tester, f.plan(ref));
      await tester.tap(find.text('查看对象 · inquiry'));
      await NavigationFixture.frames(tester);
      expect(find.text('真实全局供应商'), findsWidgets);
      expect(find.textContaining('对象或插件当前不可用'), findsNothing);
      expect(f.host.workspaces.ownerWorkspace('inquiry', id), isNull);
      await tester.pageBack();
      await NavigationFixture.frames(tester);
      expect(find.text('原对话回答'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inquiry_object_body_rechecks_binding_and_stale_reference', (
    tester,
  ) async {
    final f = await NavigationFixture.open(tester);
    final ref = await f.seedObject(tester, 'inquiry');
    await f.show(tester, f.plan(ref));
    final runtime = (await tester.runAsync(
      () => f.host.modules.runtimeFor('inquiry'),
    ))!;
    final workspace = f.host.workspaces.ownerWorkspace(
      'inquiry',
      ref.nativeProjectId!,
    )!;
    final binding = f.host.workspaces.binding(workspace, 'inquiry')!;
    final session = (await tester.runAsync(
      () => runtime.openSession(binding),
    ))!;
    final context = tester.element(find.byType(UiWorkspaceView));
    for (final bad in [
      ObjectRef(
        moduleId: 'inquiry',
        objectType: ref.objectType,
        objectId: ref.objectId,
        nativeProjectId: 'outside-binding',
      ),
      ObjectRef(
        moduleId: 'inquiry',
        objectType: ref.objectType,
        objectId: ref.objectId,
        nativeProjectId: ref.nativeProjectId,
        revisionRef: 'stale',
      ),
    ]) {
      expect(session.objectPage(context, bad), isNull);
    }
    await tester.runAsync(session.dispose);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy_return_anchor_keeps_draft_without_invented_navigation', (
    tester,
  ) async {
    final f = await NavigationFixture.open(tester);
    const ref = ObjectRef(
      moduleId: 'removed-plugin',
      objectType: 'item',
      objectId: 'saved',
    );
    await f.show(tester, f.plan(ref));
    final c = tester
        .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
        .controller;
    c.returnAnchor = 'legacy-message-anchor';
    await tester.runAsync(c.flush);
    final store = HostUiWorkspaceStore(f.host.foundation, taskId: 'task');
    expect(await store.loadNavigationAnchor('comparison'), isNull);
    expect(
      (await store.load('comparison'))!.returnAnchor,
      'legacy-message-anchor',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'object_page_lease_released_once_and_anchor_restores_from_store',
    (tester) async {
      final module = FakeV2Module(
        'lease',
        features: {ModuleFeature.objectPages},
        runtimeFactory: _LeaseRuntime.new,
      );
      final f = await NavigationFixture.open(tester, extra: [module]);
      const ref = ObjectRef(
        moduleId: 'lease',
        objectType: 'note',
        objectId: 'actual-note',
      );
      await f.show(tester, f.plan(ref));
      await tester.tap(find.text('查看对象 · lease'));
      await NavigationFixture.frames(tester);
      expect(find.text('PLUGIN LEASE CONTENT'), findsOneWidget);
      final runtime = module.runtime! as _LeaseRuntime;
      expect(runtime.released, 0);
      final store = HostUiWorkspaceStore(f.host.foundation, taskId: 'task');
      final anchor = (await store.loadNavigationAnchor('comparison'))!;
      expect(anchor.objectRef, ref);
      expect(anchor.conversationId, f.conversationId);
      await tester.pageBack();
      await NavigationFixture.frames(tester);
      expect(runtime.released, 1);
      await tester.pumpWidget(const SizedBox());
      expect(runtime.released, 1);
      expect(
        (await store.loadNavigationAnchor('comparison'))!.toJson(),
        anchor.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final module in ['research', 'inquiry']) {
    testWidgets('open_actual_object_and_restore_workspace $module', (
      tester,
    ) async {
      final f = await NavigationFixture.open(tester);
      final ref = await f.seedObject(tester, module);
      final plan = f.plan(ref);
      await f.show(tester, plan);
      await tester.enterText(find.byType(TextField).first, '12');
      final c = tester
          .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
          .controller;
      c.scrollOffset = 18;
      await tester.runAsync(c.flush);
      expect(find.text('查看对象 · $module'), findsOneWidget);
      await tester.ensureVisible(find.text('查看对象 · $module'));
      await tester.tap(find.text('查看对象 · $module'));
      await NavigationFixture.frames(tester);
      expect(
        find.text(module == 'research' ? '真实研究对象' : '真实询价对象'),
        findsWidgets,
      );
      final saved = (await HostUiWorkspaceStore(
        f.host.foundation,
        taskId: 'task',
      ).load(plan.plan.surfaceId))!;
      final anchor = jsonDecode(saved.returnAnchor!) as Map;
      expect(anchor['conversationId'], f.conversationId);
      expect(anchor['objectRef'], ref.toJson());
      expect(saved.displayValues['quantity'], '12');
      await tester.pageBack();
      await NavigationFixture.frames(tester);
      expect(find.text('原对话回答'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '12',
      );
      expect(c.scrollOffset, saved.scrollOffset);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unavailable_plugin_keeps_return_route', (tester) async {
    final f = await NavigationFixture.open(tester);
    const ref = ObjectRef(
      moduleId: 'removed-plugin',
      objectType: 'item',
      objectId: 'saved',
    );
    await f.show(tester, f.plan(ref));
    expect(find.text('查看对象 · removed-plugin'), findsOneWidget);
    await tester.ensureVisible(find.text('查看对象 · removed-plugin'));
    await tester.tap(find.text('查看对象 · removed-plugin'));
    await NavigationFixture.frames(tester);
    expect(find.textContaining('对象或插件当前不可用'), findsOneWidget);
    await tester.pageBack();
    await NavigationFixture.frames(tester);
    expect(find.text('原对话回答'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
