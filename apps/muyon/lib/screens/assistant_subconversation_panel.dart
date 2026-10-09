import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../app/bootstrap.dart';

import '../assistant/personal_agent.dart';
import '../platform/assistant_subconversations.dart';
import '../services/models/profile_repository.dart';
import 'assistant_page.dart';

/// A view over the shared host agent. Closing saves UI; only the existing task
/// controls can pause/cancel an execution. No new executor or approval channel.
class AssistantSubconversationPanel extends StatefulWidget {
  const AssistantSubconversationPanel({
    super.key,
    required this.service,
    required this.ref,
    required this.agent,
    required this.profiles,
    this.host,
    this.onOpenReference,
  });
  final AssistantSubconversations service;
  final SubconversationRef ref;
  final PersonalAgent agent;
  final ProfileRepository profiles;
  final MuyonHost? host;
  final void Function(ObjectRef)? onOpenReference;
  @override
  State<AssistantSubconversationPanel> createState() => _PanelState();
}

class _PanelState extends State<AssistantSubconversationPanel> {
  late SubconversationWorkspace _saved, _latest;
  Future<void> _pending = Future.value();
  String? _error;
  bool _closing = false, _allowPop = false, _loadFailure = false;
  @override
  void initState() {
    super.initState();
    try {
      _saved = _latest = widget.service.loadWorkspace(widget.ref);
    } catch (e) {
      _saved = _latest = const SubconversationWorkspace();
      _loadFailure = true;
      _error = '现场读取失败：$e；原始记录已保留，只读查看';
      return;
    }
    _enqueue(
      SubconversationWorkspace(
        draftText: _latest.draftText,
        scrollOffset: _latest.scrollOffset,
        selectedProfileId: _latest.selectedProfileId,
      ),
    );
  }

  void _changed(SubconversationWorkspace value) {
    _latest = value;
    _enqueue(value);
  }

  Future<void> _enqueue(SubconversationWorkspace value) {
    _pending = _pending.then((_) async {
      if (_error != null) return;
      try {
        final next = SubconversationWorkspace(
          draftText: value.draftText,
          scrollOffset: value.scrollOffset,
          selectedProfileId: value.selectedProfileId,
          openState: value.openState,
          revision: _saved.revision + 1,
        );
        if (!await widget.service.saveWorkspace(
          widget.ref,
          next,
          expectedRevision: _saved.revision,
        )) {
          throw StateError('现场已由另一窗口更新；当前输入仍在窗口中，请复制后重新打开');
        }
        _saved = next;
      } catch (e) {
        if (mounted) setState(() => _error = '保存失败：$e');
      }
    });
    return _pending;
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    if (!_loadFailure) {
      await _enqueue(
        SubconversationWorkspace(
          draftText: _latest.draftText,
          scrollOffset: _latest.scrollOffset,
          selectedProfileId: _latest.selectedProfileId,
          openState: false,
        ),
      );
    }
    if (!mounted) return;
    if (_error != null && !_loadFailure) {
      setState(() => _closing = false);
      return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Column(
      children: [
        Material(
          child: Row(
            children: [
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('子对话 · 只读工具 · 不继承父任务授权'),
                ),
              ),
              IconButton(
                onPressed: _closing ? null : _close,
                tooltip: '保存并关闭子对话',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (_error != null)
          Material(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_error!),
            ),
          ),
        if (_loadFailure)
          Expanded(
            child: ListView(
              children: [
                for (final message in widget.service.repository.messages(
                  widget.ref.childConversationId,
                ))
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(message.content),
                  ),
              ],
            ),
          )
        else
          Expanded(
            child: AssistantPage(
              repo: widget.service.repository,
              agent: widget.agent,
              profiles: widget.profiles,
              host: widget.host,
              onOpenReference: widget.onOpenReference,
              conversationId: widget.ref.childConversationId,
              initialWorkspace: _saved,
              onWorkspaceChanged: _changed,
            ),
          ),
      ],
    ),
  );
}
