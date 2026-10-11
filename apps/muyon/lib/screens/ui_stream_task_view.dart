import 'dart:async';

import 'package:flutter/material.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../app/bootstrap.dart';
import '../assistant/personal_agent.dart';
import '../assistant/ui_planning.dart';
import '../assistant/ui_planning_events.dart';

/// Inline production renderer. Preview owns no controller, event sink or final
/// capability; only the ended, whole-validated current host plan gets adapters.
class UiStreamTaskView extends StatefulWidget {
  const UiStreamTaskView({super.key, required this.agent, required this.taskId, this.host});
  final PersonalAgent agent;
  final String taskId;
  final MuyonHost? host;
  @override
  State<UiStreamTaskView> createState() => _UiStreamTaskViewState();
}

class _UiStreamTaskViewState extends State<UiStreamTaskView> {
  UiPlannedPresentation? checked;
  UiSurfaceController? controller;
  UiPlanningEventRouter? router;
  int generation = 0;
  StreamSubscription<Object?>? moduleSubscription;
  VoidCallback? removeInquiryListener;
  @override
  void initState() {
    super.initState();
    widget.agent.repository.addListener(refresh);
    attachHost();
    refresh();
  }
  void attachHost() {
    watchInquiry();
    moduleSubscription = widget.host?.modules.changes.listen((change) {
      if (change.moduleId == 'inquiry') { watchInquiry(); refresh(); }
    });
  }
  void watchInquiry() {
    removeInquiryListener?.call();
    final state = widget.host?.inquiry?.runtime.state;
    state?.addListener(refresh);
    removeInquiryListener = () => state?.removeListener(refresh);
  }
  void detachHost() {
    removeInquiryListener?.call();
    removeInquiryListener = null;
    unawaited(moduleSubscription?.cancel());
    moduleSubscription = null;
  }
  void clear() {
    router?.dispose(); router = null;
    controller?.dispose(); controller = null; checked = null;
  }
  void refresh() {
    final attempt = ++generation;
    final value = widget.agent.uiPresentation(widget.taskId);
    // A source notification invalidates the installed capability immediately,
    // before the asynchronous full-pin/source check can finish.
    clear();
    if (mounted) setState(() {});
    if (value?.validated == null || value?.stream == null) return;
    unawaited(check(value!, attempt));
  }
  Future<void> check(UiPlannedPresentation value, int attempt) async {
    try {
      final task = widget.agent.repository.task(widget.taskId);
      final state = task == null ? null : await widget.agent.uiPlanningSource?.call(task);
      if (!mounted || attempt != generation ||
          !identical(widget.agent.uiPresentation(widget.taskId), value) || state == null ||
          state.snapshot.ref != value.request?.snapshot.ref ||
          state.currentView.surfaceId != value.request?.currentView.surfaceId ||
          state.currentView.revision != value.request?.currentView.revision ||
          state.catalog.version != value.request?.catalog.version) {
        if (mounted && attempt == generation) setState(clear);
        return;
      }
      if (identical(checked, value)) return;
      clear();
      final surface = UiSurfaceController(value.validated!,
        readOnlyProbe: () => !identical(widget.agent.uiPresentation(widget.taskId), value),
        externalContentProbe: () => widget.agent.repository.authorizationFacts
          .readTask(widget.taskId).requiresConfirmation,
        onEvent: (event) async { await router?.dispatch(event); });
      router = UiPlanningEventRouter(agent: widget.agent, taskId: widget.taskId, surface: surface);
      setState(() { checked = value; controller = surface; });
    } catch (_) {
      if (mounted && attempt == generation) setState(clear);
    }
  }
  @override
  void didUpdateWidget(UiStreamTaskView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.agent, widget.agent)) {
      oldWidget.agent.repository.removeListener(refresh);
      widget.agent.repository.addListener(refresh);
    }
    if (!identical(oldWidget.host, widget.host)) { detachHost(); attachHost(); }
    if (!identical(oldWidget.agent, widget.agent) || oldWidget.taskId != widget.taskId ||
        !identical(oldWidget.host, widget.host)) {
      clear(); refresh();
    }
  }
  @override
  void dispose() {
    ++generation;
    widget.agent.repository.removeListener(refresh);
    detachHost();
    clear(); super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final value = checked, surface = controller;
    if (value != null && surface != null &&
        identical(widget.agent.uiPresentation(widget.taskId), value)) {
      return DynamicUiSurface(key: ValueKey('ui-stream-final-${widget.taskId}'),
        plan: value.validated!, controller: surface);
    }
    final progress = widget.agent.uiStreamProgress(widget.taskId);
    if (progress == null) return const SizedBox.shrink();
    // A status preview deliberately cannot acquire a renderer capability or
    // accidentally dispatch a action from a last-good partial node.
    return Text('界面接收中 · ${progress.view.statuses.length} 个节点（动作尚不可用）',
      key: ValueKey('ui-stream-preview-${widget.taskId}'));
  }
}
