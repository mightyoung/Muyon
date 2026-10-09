import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart' show UiDispatchOutcome;

import 'support/ui_navigation_fixture.dart';
import 'support/conversation_workspace_fixture.dart';

void _registerCleanup(WidgetTester tester, NavigationFixture fixture) {
  addTearDown(() async {
    try {
      try {
        final workspaces = find.byType(DynamicWorkspace, skipOffstage: false).evaluate();
        if (workspaces.isNotEmpty) {
          final navigator = Navigator.of(workspaces.first);
          await workspaceOperation(tester, () async {
            navigator.popUntil((route) => route.isFirst);
          });
          await workspaceReady(tester);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await workspaceReady(tester);
      }
    } finally {
      await workspaceOperation(tester, fixture.host.close);
    }
  });
}

class _WorkspaceRoutes extends NavigatorObserver {
  final routes = <Route<dynamic>>{};
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);
}

void main() {
  const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');

  testWidgets('resize_moves_one_surface_without_duplicate_controller_or_dispatch', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerCleanup(tester, f);
    var events = 0;
    WorkspaceOpener? open;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (context, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    final workspace = DynamicWorkspace(repository: f.host.foundation, host: f.host,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref),
      originalAnswer: '原对话回答', onEvent: (_) async { events++; });
    await open!(workspace);
    await open!(workspace);
    await workspaceReady(tester);
    expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '37');
    await workspaceOperation(tester, c.flush);
    c.surface.lockRecoveredOperations(['pending-existing']);
    final node = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'quantity');
    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      await workspaceReady(tester);
      expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
      expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
      expect(c.surface.session.userOverrides['quantity'], width == 1280 ? '37' : '38');
      expect(c.surface.operationRefs, contains('pending-existing'));
      expect(c.surface.current.plan.nodes.firstWhere((n) => n.id == 'quantity'), same(node));
      await tester.enterText(find.byType(TextField).first, width == 1280 ? '38' : '39');
      await workspaceOperation(tester, c.flush);
      expect(tester.takeException(), isNull);
    }
    expect(c.surface.session.userOverrides['quantity'], '39');
    expect(events, 0); // Local editing never invokes the model/business port.
    final detail = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'detail');
    final event = c.surface.eventFor(detail, 'tap');
    expect(await workspaceOperation(tester, () => c.surface.dispatch(event)), UiDispatchOutcome.applied);
    expect(await workspaceOperation(tester, () => c.surface.dispatch(event)), UiDispatchOutcome.duplicate);
    expect(events, 0); // detail is old dynamic local navigation, not a host port.
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    expect(find.text('父对话'), findsOneWidget);
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!.displayValues['quantity'], '39');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('registered_business_event_is_dispatched_once_across_resize', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerCleanup(tester, f);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var portCalls = 0;
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    // Simulated registered host business port: validates old dynamic confirm
    // routing/idempotency without executing a model or a real business write.
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
      plan: f.plan(ref), onEvent: (_) async { portCalls++; }));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    final confirm = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'confirm');
    expect(c.surface.canConfirm(confirm), isTrue);
    final event = c.surface.eventFor(confirm, 'confirm');
    expect(await workspaceOperation(tester, () => c.surface.dispatch(event)), UiDispatchOutcome.routed);
    expect(portCalls, 1);
    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      await workspaceReady(tester);
      expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
      expect(await workspaceOperation(tester, () => c.surface.dispatch(event)), UiDispatchOutcome.duplicate);
      // A fresh event id still cannot replay the already locked operation.
      final repeated = c.surface.eventFor(confirm, 'confirm');
      expect(await workspaceOperation(tester, () => c.surface.dispatch(repeated)), UiDispatchOutcome.duplicate);
      expect(c.surface.canConfirm(confirm), isFalse);
      expect(portCalls, 1);
    }
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    final saved = (await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!;
    expect(saved.operationRefs, contains('public-qty'));
    expect(portCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resize_restores_measured_scroll_and_focused_field_selection', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerCleanup(tester, f);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
      plan: f.plan(ref), originalAnswer: List.filled(40, '固定完整回答，用于真实滚动验证。').join('\n')));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '12345');
    EditableText editor() => tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('quantity-field')), matching: find.byType(EditableText)));
    editor().controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    editor().focusNode.requestFocus();
    await tester.pump();
    final scroller = find.descendant(of: find.byType(ConversationWorkspaceBody), matching: find.byType(SingleChildScrollView));
    await tester.drag(scroller, const Offset(0, -30));
    await tester.pumpAndSettle();
    await workspaceOperation(tester, c.flush);
    final before = tester.widget<SingleChildScrollView>(scroller).controller!.offset;
    expect(before, greaterThan(0));
    expect(editor().focusNode.hasFocus, isTrue);
    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 500);
      await workspaceReady(tester);
      final scroll = tester.widget<SingleChildScrollView>(scroller).controller!;
      expect(scroll.offset, before.clamp(0.0, scroll.position.maxScrollExtent));
      expect(c.scrollOffset, scroll.offset);
      expect(editor().controller.text, '12345');
      expect(editor().controller.selection, const TextSelection(baseOffset: 1, extentOffset: 3));
      expect(editor().focusNode.hasFocus, isTrue);
    }
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'continued-edit');
    await workspaceOperation(tester, c.flush);
    expect(c.surface.session.userOverrides['quantity'], 'continued-edit');
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop_opening_another_surface_replaces_disposed_view_owner', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerCleanup(tester, f);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    final original = f.plan(ref);
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison', plan: original));
    await workspaceReady(tester);
    final first = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '41');
    await workspaceOperation(tester, first.flush);
    // Open B immediately after closing A, before a frame removes A's subtree.
    // The new session key must replace its late-final state owner.
    final prior = original.plan;
    final secondPlan = validateUiPlan(UIPlan(surfaceId: 'other-surface', revision: prior.revision,
      catalogVersion: prior.catalogVersion, snapshotRef: prior.snapshotRef,
      intentRef: prior.intentRef, root: prior.root, nodes: prior.nodes),
      original.snapshot, original.intent, original.catalog).validatedPlan!;
    await workspaceOperation(tester, () => open!(DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'other-surface', plan: secondPlan)));
    await workspaceReady(tester);
    final second = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    expect(second, isNot(same(first)));
    expect(second.surface.current.plan.surfaceId, 'other-surface');
    await tester.enterText(find.byType(TextField).first, '42');
    await workspaceOperation(tester, second.flush);
    expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!.displayValues['quantity'], '41');
    expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('other-surface'))!.displayValues['quantity'], '42');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('active_workspace_large_text_keeps_full_confirmation_reachable_across_route_and_pane', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerCleanup(tester, f);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scale = ValueNotifier<double>(1);
    final routes = _WorkspaceRoutes();
    addTearDown(scale.dispose);
    const tail = '公开确认正文尾部完整标记';
    final original = f.plan(ref), snapshot = original.snapshot;
    final context = snapshot.actionContext!;
    final draft = {...context.draft, '公开说明': [
      for (var i = 0; i < 18; i++) '公开段落 $i：核对数量、对象与来源，完整内容供人工阅读，不触发业务操作。',
      tail,
    ].join('\n')};
    final longSnapshot = DataSnapshot(ref: snapshot.ref, facts: snapshot.facts,
      initialUiState: snapshot.initialUiState, computations: snapshot.computations,
      sources: snapshot.sources, sourceDigests: snapshot.sourceDigests,
      actionContext: UiActionContext(draftRevision: context.draftRevision,
        draft: draft, confirmedRecordRefs: context.confirmedRecordRefs,
        operations: context.operations));
    final validated = validateUiPlan(original.plan, longSnapshot, original.intent, original.catalog);
    expect(validated.validatedPlan, isNotNull);
    final payload = '$draft';
    var businessCalls = 0;
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [routes],
      builder: (context, child) => ValueListenableBuilder<double>(valueListenable: scale,
        builder: (context, value, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(value)), child: child!)),
      home: ConversationWorkspaceHost(builder: (_, opener) {
        open = opener;
        return const Scaffold(body: Text('父对话'));
      }),
    ));
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
      plan: validated.validatedPlan!, originalAnswer: '公开原回答完整保留。',
      onEvent: (_) async { businessCalls++; }));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    final confirm = c.surface.current.plan.nodes.firstWhere((node) => node.id == 'confirm');
    for (final config in [
      (width: 1250.0, scale: 1.0, pane: true),
      (width: 1280.0, scale: 1.0, pane: true),
      (width: 1250.0, scale: 2.0, pane: false),
      (width: 1280.0, scale: 2.0, pane: false),
      (width: 1920.0, scale: 2.0, pane: true),
      (width: 390.0, scale: 2.0, pane: false),
    ]) {
      scale.value = config.scale;
      tester.view.physicalSize = Size(config.width, 900);
      await workspaceReady(tester);
      expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
      expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
      expect(find.text('父对话').hitTestable(), config.pane ? findsOneWidget : findsNothing,
        reason: '${config.width} at ${config.scale}x must use the expected presentation');
      expect(routes.routes.length, config.pane ? 1 : 2);
      expect(tester.getSize(find.byType(ConversationWorkspaceBody)).width,
        config.pane ? 440 * config.scale : config.width);
      final closeTarget = find.byTooltip('关闭工作区 / 返回');
      expect(closeTarget.hitTestable(), findsOneWidget);
      expect(tester.getSize(closeTarget).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(closeTarget).height, greaterThanOrEqualTo(48));
      expect(c.surface.canConfirm(confirm), isTrue);
      final expand = find.text('展开内容');
      if (expand.evaluate().isNotEmpty) {
        await tester.ensureVisible(expand);
        await tester.tap(expand);
        await workspaceReady(tester);
      }
      final full = find.text(payload);
      expect(full, findsOneWidget);
      expect(tester.widget<Text>(full).maxLines, isNull);
      expect(tester.widget<Text>(full).overflow, isNot(TextOverflow.ellipsis));
      await Scrollable.ensureVisible(tester.element(full), alignment: 1);
      await workspaceReady(tester);
      final paragraph = tester.renderObject<RenderParagraph>(full);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.text.toPlainText(), payload);
      expect(paragraph.textScaler.scale(16), 16 * config.scale);
      final tailBoxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: payload.indexOf(tail), extentOffset: payload.indexOf(tail) + tail.length));
      expect(tailBoxes, isNotEmpty);
      final scroll = find.descendant(of: find.byType(ConversationWorkspaceBody),
        matching: find.byType(SingleChildScrollView));
      final viewport = tester.getRect(scroll);
      for (final box in tailBoxes) {
        expect(viewport.contains(paragraph.localToGlobal(box.toRect().center)), isTrue,
          reason: 'The complete payload tail must be painted inside the scroll viewport');
      }
      for (final label in ['请求宿主确认；界面本身不授予写入权限。', '仅这一次', '拒绝']) {
        final target = find.text(label);
        await tester.ensureVisible(target);
        await workspaceReady(tester);
        expect(target.hitTestable(), findsOneWidget);
        if (label == '仅这一次' || label == '拒绝') {
          final button = find.widgetWithText(TextButton, label);
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
      }
      for (final label in ['仅这一次', '拒绝']) {
        expect(tester.widget<TextButton>(find.widgetWithText(TextButton, label)).onPressed, isNotNull);
      }
      expect(businessCalls, 0);
      expect(c.surface.operationRefs, isEmpty);
      expect(tester.takeException(), isNull, reason: 'No layout overflow at ${config.width}/${config.scale}x');
    }
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    expect(businessCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop_close_checkpoints_before_dispose', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerCleanup(tester, f);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref)));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() { if (!release.isCompleted) release.complete(); });
    Future<void>? blocked;
    await workspaceOperation(tester, () async {
      blocked = (f.host.foundation.database as ExclusiveDatabase).exclusiveAsync((db) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
    });
    // A presentation checkpoint field is not auto-flushed by a surface edit.
    c.step = 'review-before-close';
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await tester.pump();
    expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
    expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
    // The awaited save must retain a live editable controller, not merely a
    // stale widget painted after its owner was disposed.
    await tester.enterText(find.byType(TextField).first, 'still editing');
    expect(c.surface.session.userOverrides['quantity'], 'still editing');
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'still editing');
    release.complete();
    await workspaceOperation(tester, () => blocked!);
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    final saved = (await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!;
    expect(saved.step, 'review-before-close');
    expect(saved.userOverrides['quantity'], 'still editing');
    expect(saved.nodeIds, contains('quantity'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
