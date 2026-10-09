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
  });
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

class _DynamicWorkspaceState extends State<DynamicWorkspace> {
  UiWorkspaceController? controller;
  UiPlanningEventRouter? router;
  StoredUiWorkspace? stored;
  String? error;
  bool ready = false;
  bool navigating = false;
  final receipts = <String, UiOperationRecovery>{};
  @override
  void initState() {
    super.initState();
    load();
  }

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
        stored = await store.load(widget.surfaceId);
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
        if (!mounted) {
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
    if (mounted) setState(() => ready = true);
  }

  Future<void> openReference({
    ObjectRef? object,
    String? source,
    required String nodeId,
  }) async {
    final host = widget.host, c = controller;
    if (host == null || c == null || navigating) return;
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
            onPressed: navigating || c.readOnly
                ? null
                : () => openReference(object: entry.key, nodeId: entry.value),
            child: Text('查看对象 · ${entry.key.moduleId}'),
          ),
        for (final entry in sources.entries)
          TextButton(
            onPressed: navigating || c.readOnly
                ? null
                : () => openReference(source: entry.key, nodeId: entry.value),
            child: Text('查看原文 · ${entry.key}'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    router?.dispose();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return UiWorkspaceView(
        controller: controller!,
        originalAnswer: widget.originalAnswer,
        references: referenceLinks(),
        banner: error,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('已保存草稿')),
      body: !ready
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
                    SelectableText(widget.originalAnswer),
                  ],
                ),
              ),
            ),
    );
  }
}
