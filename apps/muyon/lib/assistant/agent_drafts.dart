/// The draft of a reply that is still being streamed (ADR-0005 §5.3, Q4):
/// what the screen shows while the model writes. It lives in memory only. It
/// is never written to the task payload, the conversation, the ledger, a
/// notification or a log; the task events keep its length and digest and
/// nothing else. The text of the draft is what the person may read: for a
/// compatibility-mode reply that is the `answer` value alone, never the
/// protocol JSON, a tool id, parameters or native tool-call markup.
library;

import 'dart:async';

import 'protocol_stream_view.dart';

enum DraftStage {
  /// The model is still writing; not confirmed complete.
  generating,

  /// A tool call is being prepared; only that fact is shown (any text that
  /// came before it stays).
  preparingTool,

  /// The stream ended without a usable reply (cancelled, cut, timed out,
  /// truncated). Whatever was shown stays on screen, marked as not saved.
  interrupted,

  /// The reply ended but broke the protocol and was dropped. Nothing of it
  /// is shown.
  discarded,

  /// The reply became the task's message or step; a listener drops its copy.
  committed,
}

final class AgentDraft {
  const AgentDraft(this.taskId, this.stage, {this.text = ''});
  final String taskId;
  final DraftStage stage;

  /// The text the person may see. Empty while nothing displayable has
  /// arrived (compatibility mode: `type` not known yet).
  final String text;
}

/// Drafts of the tasks that are streaming now. Read-only for the screen: a
/// listener can look, it cannot feed or settle a draft.
class AgentDrafts {
  final _controller = StreamController<AgentDraft>.broadcast();
  final _open = <String, AgentDraft>{};

  /// Every change of every draft, in order. Not replayed to late listeners;
  /// [of] gives the current one.
  Stream<AgentDraft> get stream => _controller.stream;

  /// The draft in flight for [taskId], if any. Once it is settled (the reply
  /// became a message, or the stream ended without one) it is gone from here;
  /// the last event on [stream] is what remains.
  AgentDraft? of(String taskId) => _open[taskId];

  void _publish(AgentDraft draft) {
    if (!_controller.isClosed) _controller.add(draft);
  }

  void begin(String taskId) {
    final draft = AgentDraft(taskId, DraftStage.generating);
    _open[taskId] = draft;
    _publish(draft);
  }

  void show(String taskId, DraftStage stage, String text) {
    if (!_open.containsKey(taskId)) return;
    final draft = AgentDraft(taskId, stage, text: text);
    _open[taskId] = draft;
    _publish(draft);
  }

  /// The reply became the task's message or tool step: the draft is
  /// superseded and nothing of it remains.
  void commit(String taskId) {
    if (_open.remove(taskId) != null) {
      _publish(AgentDraft(taskId, DraftStage.committed));
    }
  }

  /// The stream ended without a usable reply: keep what was shown, marked.
  void interrupt(String taskId) {
    final last = _open.remove(taskId);
    if (last == null) return;
    _publish(AgentDraft(taskId, DraftStage.interrupted, text: last.text));
  }

  /// The reply broke the protocol and is dropped; the person is told, with
  /// nothing quoted.
  void discard(String taskId) {
    if (_open.remove(taskId) == null) return;
    _publish(AgentDraft(taskId, DraftStage.discarded));
  }

  Future<void> close() => _controller.close();
}

/// Feeds the draft of one response. Compatibility mode goes through
/// [ProtocolStreamView]; native mode shows the text deltas as they come.
class DraftFeed {
  DraftFeed(this.drafts, this.taskId, {required this.native}) {
    drafts.begin(taskId);
  }
  final AgentDrafts drafts;
  final String taskId;
  final bool native;
  final _view = ProtocolStreamView();
  final _native = StringBuffer();
  var _tool = false;
  var _shownLength = 0;

  /// Length (UTF-16 units) of what the person was shown, for the task event.
  int get length => _shownLength;
  String _shown = '';
  String get shown => _shown;

  void text(String chunk) {
    if (native) {
      _native.write(chunk);
      _shown = _native.toString();
      _push();
      return;
    }
    _view.feed(chunk);
    switch (_view.phase) {
      case ProtocolPhase.answering:
        _shown = _view.text;
        _push();
      case ProtocolPhase.preparingTool:
        _tool = true;
        _shown = '';
        _push();
      case ProtocolPhase.thinking || ProtocolPhase.plain:
        break;
    }
  }

  /// A native tool-call fragment arrived: only the fact is shown.
  void toolCall() {
    if (_tool) return;
    _tool = true;
    _push();
  }

  void _push() {
    _shownLength = _shown.length;
    drafts.show(
      taskId,
      _tool ? DraftStage.preparingTool : DraftStage.generating,
      _shown,
    );
  }
}
