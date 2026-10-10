import 'dart:async';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../platform/foundation_repository.dart';
import '../app/bootstrap.dart';
import '../platform/tool_registry.dart';
import '../platform/ui_workspace_store.dart';
import '../platform/ui_navigation_anchors.dart';
import '../assistant/personal_agent.dart';
import '../assistant/ui_planning_events.dart';
import 'conversation_workspace_pane.dart';

/// An incremental route within the existing Shell. Planning/host action
/// attachment remains the caller's boundary; a disabled dynamic page still
/// exposes its stored draft and actual registry receipts, read-only.
class DynamicWorkspace extends StatefulWidget {
  const DynamicWorkspace({
    super.key,
    required this.repository,
    required this.taskId,
    required this.surfaceId,
    this.plan,
    this.host,
    this.originalAnswer = '',
    this.tools,
    this.onEvent,
    this.agent,
    this.businessActions = const {},
    this.session,
    this.embedded = false,
    this.textOnly = false,
    this.onClose,
  });
  final DynamicWorkspaceSession? session;
  final bool embedded;
  final bool textOnly;
  final Future<void> Function()? onClose;
  final FoundationRepository repository;
  final MuyonHost? host;
  final String taskId, surfaceId, originalAnswer;
  final ValidatedUiPlan? plan;
  final ToolRegistry? tools;
  final UiEventSink? onEvent;
  final PersonalAgent? agent;
  final Map<String, UiBusinessAction> businessActions;
  @override
  State<DynamicWorkspace> createState() => _DynamicWorkspaceState();
}

/// Presentation ownership only: one old dynamic controller/router per open surface.
/// The responsive host retains this session while route and pane views change.
class DynamicWorkspaceSession extends ChangeNotifier {
  DynamicWorkspaceSession(this.widget);
  final DynamicWorkspace widget;
  UiWorkspaceController? controller;
  UiPlanningEventRouter? router;
  StoredUiWorkspace? stored;
  Map<String, Object?>? unreadableDraft;
  String? error;
  bool ready = false;
  bool _disposed = false;
  Future<void>? _loading;
  // Includes registered object-page lease disposal after its pushed route pops.
  Future<void>? _pendingReferenceNavigation;
  Future<void>? get pendingReferenceNavigation => _pendingReferenceNavigation;
  set pendingReferenceNavigation(Future<void>? value) {
    _pendingReferenceNavigation = value;
    if (!_disposed) notifyListeners();
  }
  bool _canPresentReferences = true;
  bool get canPresentReferences => _canPresentReferences;
  void stopReferenceAdmission() {
    if (!_canPresentReferences) return;
    _canPresentReferences = false;
    if (!_disposed) notifyListeners();
  }
  void resumeReferenceAdmission() {
    if (_disposed || _canPresentReferences) return;
    _canPresentReferences = true;
    notifyListeners();
  }
  // Ephemeral app presentation only; never a business draft or runtime state.
  String? focusedFieldNode;
  TextSelection? focusedFieldSelection;
  void Function()? capturePresentation;

  final receipts = <String, UiOperationRecovery>{};
  Future<void> ensureLoaded() => _loading ??= load();
  Future<UiOperationRecovery> receipt(String ref) async {
    final task = widget.repository.task(widget.taskId);
    final calls = task?.payload['toolCalls'];
    final known = <String>{
      if (calls is List)
        for (final call in calls)
          if (call is Map && call['invocationId'] is String)
            call['invocationId'] as String,
      for (final event in widget.repository.taskEvents(widget.taskId))
        if (event.data['invocationId'] is String)
          event.data['invocationId'] as String,
    };
    if (!known.contains(ref)) {
      return widget.agent == null
          ? UiOperationRecovery.unknown
          : recoverUiPlanningOperation(
              widget.agent!,
              widget.taskId,
              widget.surfaceId,
              ref,
            );
    }
    final result = widget.tools?.receiptFor(ref);
    if (result == null || result.unknown) return UiOperationRecovery.unknown;
    return result.succeeded
        ? UiOperationRecovery.succeeded
        : UiOperationRecovery.failed;
  }

  Future<void> load() async {
    try {
      final store = HostUiWorkspaceStore(
        widget.repository,
        taskId: widget.taskId,
      );
      final scope = store.scopeKey;
      if (scope == null) throw StateError('Task not available');
      if (widget.plan == null) {
        try {
          stored = await store.load(widget.surfaceId);
        } on UiWorkspaceUnreadable catch (failure) {
          unreadableDraft = UiWorkspaceController.readUnreadableDraft(
            failure, taskId: widget.taskId, surfaceId: widget.surfaceId,
            scopeKey: scope,
          );
          error = failure.reason;
        }
        for (final ref in stored?.operationRefs ?? <String>[]) {
          receipts[ref] = await receipt(ref);
        }
      } else {
        if (widget.plan!.plan.surfaceId != widget.surfaceId) {
          throw StateError('Surface identity changed');
        }
        final c = await UiWorkspaceController.open(
          store: store,
          taskId: widget.taskId,
          scopeKey: scope,
          plan: widget.plan!,
          onEvent:
              widget.onEvent ??
              (widget.agent == null
                  ? null
                  : (event) async {
                      if (widget.agent!.uiPlanningEnabled != true) {
                        throw StateError('planning_disabled');
                      }
                      await router?.dispatch(event);
                    }),
          receiptLookup: receipt,
        );
        if (_disposed) {
          c.dispose();
          return;
        }
        controller = c;
        if (widget.agent != null) {
          router = UiPlanningEventRouter(
            agent: widget.agent!,
            taskId: widget.taskId,
            surface: c.surface,
            businessActions: widget.businessActions,
          );
        }
      }
    } catch (e) {
      error = '$e';
    }
    ready = true;
  }


  Future<void> checkpoint() {
    // With an open controller, capture before returning to a non-awaitable
    // detach caller. Readable load failures can be dismissed without writes.
    final c = controller;
    if (c != null) return c.flush();
    return ensureLoaded().then<void>((_) async { await controller?.flush(); });
  }

  void detachWithBestEffortCheckpoint() {
    if (_disposed) return;
    // flush captures synchronously before any listener/controller is detached.
    final pending = controller?.flush();
    dispose();
    if (pending != null) unawaited(pending.catchError((Object _) {}));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopReferenceAdmission();
    capturePresentation = null;
    router?.dispose();
    controller?.dispose();
    super.dispose();
  }
}

class _DynamicWorkspaceState extends State<DynamicWorkspace>
    with WidgetsBindingObserver {
  late final session = widget.session ?? DynamicWorkspaceSession(widget);
  UiWorkspaceController? get controller => session.controller;
  StoredUiWorkspace? get stored => session.stored;
  Map<String, UiOperationRecovery> get receipts => session.receipts;
  String? error;
  bool ready = false;
  bool navigating = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    await session.ensureLoaded();
    if (mounted) setState(() { ready = true; error = session.error; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(session.checkpoint().catchError((Object e) {
        if (mounted) setState(() => error = '未保存：$e');
      }));
    }
  }
  Future<void> openReference({
    ObjectRef? object,
    String? source,
    required String nodeId,
  }) {
    if (widget.host == null || controller == null || !session.canPresentReferences) return Future.value();
    // Ownership survives view replacement: a new route/pane State cannot
    // replace the in-flight future and orphan its eventual object-page lease.
    final existing = session.pendingReferenceNavigation;
    if (existing != null) return existing;
    final pending = _openReference(object: object, source: source, nodeId: nodeId);
    session.pendingReferenceNavigation = pending;
    return pending.whenComplete(() {
      if (identical(session.pendingReferenceNavigation, pending)) {
        session.pendingReferenceNavigation = null;
      }
    });
  }

  Future<void> _openReference({
    ObjectRef? object,
    String? source,
    required String nodeId,
  }) async {
    final host = widget.host, c = controller;
    if (host == null || c == null || !session.canPresentReferences) return;
    setState(() => navigating = true);
    try {
      if (!identical(host.foundation, widget.repository)) {
        throw StateError('Workspace owner changed');
      }
      final task = widget.repository.task(widget.taskId);
      if (task == null) throw StateError('Task unavailable');
      final artifact = source == null
          ? null
          : c.surface.current.snapshot.sources[source]?.artifact;
      final ref =
          object ??
          ObjectRef(
            moduleId: artifact!.moduleId,
            objectType: 'document',
            objectId: artifact.artifactId,
            contentDigest: artifact.contentDigest,
          );
      final anchor = NavigationAnchor(
        conversationId: task.conversationId,
        taskId: task.id,
        surfaceId: widget.surfaceId,
        nodeId: nodeId,
        scrollOffset: c.scrollOffset,
        objectRef: ref,
        sourceDigest: artifact?.contentDigest ?? ref.contentDigest,
        artifactRef: artifact,
      );
      final navigation = UiReferenceNavigation(
        context: context,
        host: host,
        controller: c,
        canPresent: () => session.canPresentReferences,
      );
      if (artifact == null) {
        await navigation.openReference(ref, anchor);
      } else {
        await navigation.openArtifact(artifact, anchor);
      }
    } catch (e) {
      if (mounted) setState(() => error = '无法打开引用，原草稿仍保留：$e');
    } finally {
      if (mounted) setState(() => navigating = false);
    }
  }

  Widget? referenceLinks() {
    final c = controller;
    if (widget.host == null || c == null) return null;
    final current = c.surface.current;
    final objects = <ObjectRef, String>{};
    final sources = <String, String>{};
    for (final node in current.plan.nodes) {
      for (final binding in node.bindings.values) {
        if (binding.kind == BindingKind.fact) {
          final fact = current.snapshot.facts[binding.id];
          if (fact != null) objects.putIfAbsent(fact.object, () => node.id);
        } else if (binding.kind == BindingKind.sourceSpan &&
            current.snapshot.sources.containsKey(binding.id)) {
          sources.putIfAbsent(binding.id, () => node.id);
        }
      }
    }
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in objects.entries)
          TextButton(
            onPressed: navigating || session.pendingReferenceNavigation != null || !session.canPresentReferences || c.readOnly
                ? null
                : () => openReference(object: entry.key, nodeId: entry.value),
            child: Text('查看对象 · ${entry.key.moduleId}'),
          ),
        for (final entry in sources.entries)
          TextButton(
            onPressed: navigating || session.pendingReferenceNavigation != null || !session.canPresentReferences || c.readOnly
                ? null
                : () => openReference(source: entry.key, nodeId: entry.value),
            child: Text('查看原文 · ${entry.key}'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(sessionChanged);
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      if (widget.embedded) {
        return ConversationWorkspaceBody(
          controller: controller!,
          originalAnswer: widget.originalAnswer,
          references: referenceLinks(),
          banner: error,
          onClose: widget.onClose,
          textOnly: widget.textOnly,
          session: session,
        );
      }
      return UiWorkspaceView(
        controller: controller!,
        originalAnswer: widget.originalAnswer,
        references: referenceLinks(),
        banner: error,
      );
    }
    final body = !ready
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (error != null)
                      Text('读取失败，保存内容未删除：$error')
                    else if (stored == null)
                      const Text('当前任务范围内没有保存的草稿。')
                    else ...[
                      const Text('动态页未接入当前计划，旧草稿仍可阅读；没有执行或重放操作。'),
                      for (final e in stored!.displayValues.entries)
                        SelectableText('${e.key}: ${e.value}'),
                      Text('继续步骤：${stored!.step}'),
                      Text('选中记录：${stored!.selectedRecords.join(', ')}'),
                      for (final e in receipts.entries)
                        Text('回执 ${e.key}: ${e.value.name}'),
                    ],
                    for (final e in (session.unreadableDraft ?? {}).entries)
                      SelectableText('${e.key}: ${e.value}'),
                    SelectableText(widget.originalAnswer),
                  ],
                ),
              ),
            );
    if (widget.embedded) {
      return Column(children: [
        Row(children: [const Expanded(child: Text('已保存草稿')),
          IconButton(onPressed: widget.onClose, tooltip: '关闭工作区', icon: const Icon(Icons.close))]),
        Expanded(child: body),
      ]);
    }
    return Scaffold(appBar: AppBar(title: const Text('已保存草稿')), body: body);
  }
}
