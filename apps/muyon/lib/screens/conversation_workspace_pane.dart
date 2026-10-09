import 'dart:async';

import 'package:flutter/material.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'dynamic_workspace.dart';
import 'conversation_shell_controller.dart';

typedef WorkspaceOpener = Future<void> Function(DynamicWorkspace workspace);

/// A presentation host. Moving between a phone route and a desktop pane keeps
/// the same session, store, event router and pending-operation locks.
class ConversationWorkspaceHost extends StatefulWidget {
  const ConversationWorkspaceHost({super.key, required this.builder, this.allowInteractive = true, this.controller});
  final Widget Function(BuildContext, WorkspaceOpener) builder;
  /// Injected host policy; this shell does not grant or persist authorization.
  final bool allowInteractive;
  final ConversationShellController? controller;
  @override
  State<ConversationWorkspaceHost> createState() => _ConversationWorkspaceHostState();
}

class _ConversationWorkspaceHostState extends State<ConversationWorkspaceHost> {
  DynamicWorkspaceSession? session;
  Route<void>? route;
  bool desktop = false;
  bool closing = false;
  Future<void>? opening;
  FocusNode? sourceFocus;

  @override
  void initState() {
    super.initState();
    attachLifecycle();
  }

  void attachLifecycle() {
    widget.controller?.attach(this, () {
      session?.capturePresentation?.call();
      return session?.checkpoint() ?? Future.value();
    }, () => session?.dispose());
  }

  @override
  void didUpdateWidget(ConversationWorkspaceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.release(this);
      attachLifecycle();
    }
  }

  Future<void> open(DynamicWorkspace workspace) {
    if (closing) return Future.value();
    if (session != null &&
        identical(session!.widget.repository, workspace.repository) &&
        session!.widget.taskId == workspace.taskId &&
        session!.widget.surfaceId == workspace.surfaceId) return opening ?? Future.value();
    return opening ??= _open(workspace).whenComplete(() => opening = null);
  }

  Future<void> _open(DynamicWorkspace workspace) async {
    if (session != null && !await close()) return;
    if (!mounted) return;
    sourceFocus = FocusManager.instance.primaryFocus;
    session = DynamicWorkspaceSession(workspace);
    setState(() {});
    present();
  }

  DynamicWorkspace view() {
    final w = session!.widget;
    return DynamicWorkspace(
      key: ValueKey(session),
      repository: w.repository, host: w.host, taskId: w.taskId,
      surfaceId: w.surfaceId, plan: w.plan, originalAnswer: w.originalAnswer,
      tools: w.tools, onEvent: w.onEvent, agent: w.agent,
      businessActions: w.businessActions, session: session, embedded: true,
      textOnly: w.textOnly || !widget.allowInteractive,
      onClose: () async { await close(); },
    );
  }

  void present() {
    if (!mounted || session == null) return;
    if (desktop) {
      final old = route;
      route = null;
      if (old != null) old.navigator?.removeRoute(old);
    } else if (route == null) {
      route = MaterialPageRoute<void>(builder: (_) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(close());
        },
        child: Scaffold(body: SafeArea(child: view())),
      ));
      Navigator.of(context).push(route!);
    }
  }

  Future<bool> close() async {
    final current = session;
    if (current == null) return true;
    if (closing) return false;
    closing = true;
    try {
      current.capturePresentation?.call();
      // MUTATION ONLY: omit the host close checkpoint.
      if (!mounted || !identical(session, current)) return false;
      final old = route;
      route = null;
      if (old != null) old.navigator?.removeRoute(old);
      setState(() => session = null);
      current.dispose();
      // The source may have disappeared after a plan update. In that case the
      // assistant's focus scope provides the ordinary keyboard fallback.
      if (sourceFocus?.context != null && sourceFocus!.canRequestFocus) {
        sourceFocus!.requestFocus();
      }
      return true;
    } catch (_) {
      // Controller.saveError/readOnly is rendered in the still-open view.
      if (mounted) setState(() {});
      return false;
    } finally {
      closing = false;
    }
  }

  @override
  void dispose() {
    widget.controller?.release(this);
    // Native detach cannot await; explicit close/back checkpoints above can.
    final current = session;
    if (current != null) {
      current.capturePresentation?.call();
      current.detachWithBestEffortCheckpoint();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final next = constraints.maxWidth >= 1250 && constraints.maxWidth >= 720 + 440 * scale;
    if (next != desktop) {
      session?.capturePresentation?.call();
      desktop = next;
      WidgetsBinding.instance.addPostFrameCallback((_) => present());
    }
    return PopScope(
      canPop: session == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && session != null) unawaited(close());
      },
      child: Row(children: [
        Expanded(child: widget.builder(context, open)),
        if (desktop && session != null) ...[
          const VerticalDivider(width: 1),
          SizedBox(width: 440 * scale, child: Material(child: view())),
        ],
      ]),
    );
  });
}

/// App-level embedded body; shared dynamic runtime and persistence are reused.
/// There is no nested Scaffold or route-owned controller in the desktop pane.
class ConversationWorkspaceBody extends StatefulWidget {
  const ConversationWorkspaceBody({super.key, required this.controller,
    required this.originalAnswer, this.references, this.banner, this.onClose, this.textOnly = false, this.session});
  final UiWorkspaceController controller;
  final String originalAnswer;
  final bool textOnly;
  final DynamicWorkspaceSession? session;
  final Widget? references;
  final String? banner;
  final Future<void> Function()? onClose;
  @override
  State<ConversationWorkspaceBody> createState() => _ConversationWorkspaceBodyState();
}

class _ConversationWorkspaceBodyState extends State<ConversationWorkspaceBody> {
  late final scroll = ScrollController(initialScrollOffset: widget.controller.scrollOffset);
  UiWorkspaceController get c => widget.controller;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    scroll.addListener(scrolled);
    widget.session?.capturePresentation = capturePresentation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(c.scrollOffset.clamp(0.0, scroll.position.maxScrollExtent).toDouble());
      }
      restorePresentation();
    });
  }
  Map<String, EditableText> inputFields() {
    final fields = <String, EditableText>{};
    final nodeIds = c.surface.current.plan.nodes.map((n) => n.id).toSet();
    void visit(Element element) {
      if (element.widget is EditableText) {
        String? nodeId;
        element.visitAncestorElements((ancestor) {
          final key = ancestor.widget.key;
          if (key is ValueKey<String>) {
            for (final id in nodeIds) {
              if (key.value == '$id-field') { nodeId = id; return false; }
            }
          }
          return ancestor != context;
        });
        if (nodeId != null) fields[nodeId!] = element.widget as EditableText;
      }
      element.visitChildElements(visit);
    }
    (context as Element).visitChildElements(visit);
    return fields;
  }

  void capturePresentation() {
    if (!mounted) return;
    if (scroll.hasClients && !c.readOnly) {
      c.scrollOffset = scroll.offset.clamp(0.0, scroll.position.maxScrollExtent).toDouble();
    }
    final session = widget.session;
    if (session == null) return;
    // Identity comes from the renderer's stable validated-node field key.
    for (final entry in inputFields().entries) {
      if (entry.value.focusNode.hasFocus) {
        session.focusedFieldNode = entry.key;
        session.focusedFieldSelection = entry.value.controller.selection;
        return;
      }
    }
    session.focusedFieldNode = null;
    session.focusedFieldSelection = null;
  }

  void restorePresentation() {
    final session = widget.session;
    if (!mounted || session == null || c.readOnly || widget.textOnly) return;
    final field = inputFields()[session.focusedFieldNode];
    final selection = session.focusedFieldSelection;
    if (field == null || selection == null || !selection.isValid) return;
    final length = field.controller.text.length;
    field.controller.selection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, length).toInt(),
      extentOffset: selection.extentOffset.clamp(0, length).toInt(),
      affinity: selection.affinity, isDirectional: selection.isDirectional,
    );
    field.focusNode.requestFocus();
  }

  void changed() { if (mounted) setState(() {}); }
  void scrolled() {
    if (!scroll.hasClients || c.readOnly) return;
    c.scrollOffset = scroll.offset.clamp(0.0, scroll.position.maxScrollExtent).toDouble();
    unawaited(c.flush().catchError((Object _) {}));
  }
  Future<void> close() async {
    if (closing) return;
    setState(() => closing = true);
    try {
      if (scroll.hasClients && !c.readOnly) c.scrollOffset = scroll.offset.clamp(0.0, scroll.position.maxScrollExtent).toDouble();
      // MUTATION ONLY: omit the view close checkpoint.
      await widget.onClose?.call();
    } catch (_) {
      changed();
    } finally {
      if (mounted) setState(() => closing = false);
    }
  }
  @override
  void dispose() {
    if (widget.session?.capturePresentation == capturePresentation) {
      widget.session?.capturePresentation = null;
    }
    c.removeListener(changed); scroll.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
      const Expanded(child: Text('当前工作区')),
      SizedBox(width: 48, height: 48, child: IconButton(
        onPressed: closing ? null : close, tooltip: '关闭工作区 / 返回', icon: const Icon(Icons.close))),
    ])),
    Expanded(child: SingleChildScrollView(controller: scroll, child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.banner != null) Text(widget.banner!),
        if (widget.references != null) widget.references!,
        Text('Current surface revision: ${c.surface.current.plan.revision}'),
        if (c.saveError != null) Text('未保存，人工输入仍保留：${c.saveError}'),
        if (c.readOnly || widget.textOnly) ...[
          Text(widget.textOnly ? '仅文字展示；原回答与固定页面仍可阅读。' : '版本已变化或保存冲突，当前草稿只读。'),
          for (final entry in {...?c.readableDraft, ...c.surface.session.userOverrides}.entries)
            SelectableText('${entry.key}: ${entry.value}'),
        ] else ...[
          DynamicUiSurface(plan: c.surface.current, controller: c.surface),
          for (final entry in c.surface.session.userOverrides.entries)
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('人工 ${entry.key}: ${entry.value} · 提取建议 ${c.surface.current.snapshot.initialUiState[entry.key]}'),
              TextButton(onPressed: () async { try { await c.adoptExtracted(entry.key); } catch (_) { changed(); } }, child: const Text('采用提取值')),
            ]),
        ],
        for (final e in c.recoveredOperations.entries) Text('回执 ${e.key}: ${e.value.name} · 未自动重放'),
        Text('继续步骤：${c.step}'),
        if (c.selectedRecords.isNotEmpty) Text('选中记录：${c.selectedRecords.join(', ')}'),
        SelectableText(widget.originalAnswer),
      ]),
    ))),
  ]);
}
