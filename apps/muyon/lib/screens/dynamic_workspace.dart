import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../platform/foundation_repository.dart';
import '../platform/tool_registry.dart';
import '../platform/ui_workspace_store.dart';

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
    this.originalAnswer = '',
    this.tools,
    this.onEvent,
  });
  final FoundationRepository repository;
  final String taskId, surfaceId, originalAnswer;
  final ValidatedUiPlan? plan;
  final ToolRegistry? tools;
  final UiEventSink? onEvent;
  @override
  State<DynamicWorkspace> createState() => _DynamicWorkspaceState();
}

class _DynamicWorkspaceState extends State<DynamicWorkspace> {
  UiWorkspaceController? controller;
  StoredUiWorkspace? stored;
  String? error;
  bool ready = false;
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
    if (!known.contains(ref)) return UiOperationRecovery.unknown;
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
          onEvent: widget.onEvent,
          receiptLookup: receipt,
        );
        if (!mounted) {
          c.dispose();
          return;
        }
        controller = c;
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => ready = true);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return UiWorkspaceView(
        controller: controller!,
        originalAnswer: widget.originalAnswer,
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
