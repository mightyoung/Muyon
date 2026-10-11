import 'dart:async';

import 'package:flutter/material.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../app/bootstrap.dart';
import '../assistant/personal_agent.dart';
import '../assistant/ui_planning.dart';
import '../assistant/stream_ui_planning.dart';
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
  HostUiStreamProgress? checkedPreview;
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
    controller?.dispose(); controller = null; checked = null; checkedPreview = null;
  }
  void refresh() {
    final attempt = ++generation;
    final value = widget.agent.uiPresentation(widget.taskId);
    // A source notification invalidates the installed capability immediately,
    // before the asynchronous full-pin/source check can finish.
    clear();
    if (mounted) setState(() {});
    if (!widget.agent.allowsUiContent(widget.taskId)) return;
    if (value?.request != null) {
      unawaited(check(value!, attempt));
    } else {
      final progress = widget.agent.uiStreamProgress(widget.taskId);
      if (progress != null) unawaited(checkPreview(progress, attempt));
    }
  }
  bool currentRequest(UiPlanningRequest? request) => request != null &&
    widget.agent.allowsUiContent(widget.taskId) && widget.agent.isCurrentUiRequest(request);

  bool sameHostState(UiPlanningHostState? state, UiPlanningRequest request) =>
    state != null && state.snapshot.ref == request.snapshot.ref &&
    state.currentView.surfaceId == request.currentView.surfaceId &&
    state.currentView.revision == request.currentView.revision &&
    state.catalog.version == request.catalog.version;

  Future<void> checkPreview(HostUiStreamProgress progress, int attempt) async {
    try {
      final task = widget.agent.repository.task(widget.taskId);
      final state = task == null ? null : await widget.agent.uiPlanningSource?.call(task);
      if (!mounted || attempt != generation || !currentRequest(progress.request) ||
          !identical(widget.agent.uiStreamProgress(widget.taskId), progress) ||
          !sameHostState(state, progress.request)) {
        return;
      }
      setState(() { checkedPreview = progress; });
    } catch (_) {
      if (mounted && attempt == generation) setState(clear);
    }
  }
  Future<void> check(UiPlannedPresentation value, int attempt) async {
    try {
      final task = widget.agent.repository.task(widget.taskId);
      final state = task == null ? null : await widget.agent.uiPlanningSource?.call(task);
      if (!mounted || attempt != generation ||
          !currentRequest(value.request) ||
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
      if (value.validated == null) {
        setState(() { checked = value; });
        return;
      }
      final surface = UiSurfaceController(value.validated!,
        readOnlyProbe: () => !currentRequest(value.request) || !identical(widget.agent.uiPresentation(widget.taskId), value),
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
  Widget readOnlyPreview(HostUiStreamProgress progress) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final text in progress.view.text) SelectableText(text),
      // This is a projection of the compiler's last-good visible nodes. It
      // cannot create a controller, events, callbacks or a validation token.
      for (final node in progress.view.previewPlan.nodes)
        for (final key in const ['title', 'label', 'text', 'description'])
          if (node.properties[key] case final String text) Text(text),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.agent.allowsUiContent(widget.taskId)) return const SizedBox.shrink();
    final value = checked, surface = controller;
    if (value != null && currentRequest(value.request) &&
        identical(widget.agent.uiPresentation(widget.taskId), value)) {
      if (surface != null && value.validated != null) {
        return DynamicUiSurface(key: ValueKey('ui-stream-final-${widget.taskId}'),
          plan: value.validated!, controller: surface);
      }
      final request = value.request!;
      return Column(key: ValueKey('ui-stream-fallback-${widget.taskId}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('界面未完成 · 只读，动作不可用'),
          if (value.stream case final progress?) readOnlyPreview(progress),
          snapshotFallback(request.snapshot, request.intent),
        ]);
    }
    final progress = checkedPreview;
    if (progress == null || !currentRequest(progress.request) ||
        !identical(widget.agent.uiStreamProgress(widget.taskId), progress)) {
      return const SizedBox.shrink();
    }
    return Column(key: ValueKey('ui-stream-preview-${widget.taskId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(progress.view.phase == UiStreamPhase.streaming
          ? '界面接收中 · 动作尚不可用' : '界面未完成 · 只读，动作不可用'),
        readOnlyPreview(progress),
        if (progress.view.phase != UiStreamPhase.streaming)
          snapshotFallback(progress.request.snapshot, progress.request.intent),
      ]);
  }
}
