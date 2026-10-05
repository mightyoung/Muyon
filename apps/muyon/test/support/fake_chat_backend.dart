import 'package:flutter/foundation.dart';
import 'package:muyon/screens/chat/chat_models.dart';

/// In-memory stand-in for the transfer service's chat API.
class FakeChatBackend extends ChangeNotifier implements ChatBackend {
  final Map<String, ChatThread> _threads = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final List<String> sentBodies = [];
  final List<String> retried = [];
  Object? sendError;
  var _n = 0;

  void addThread(
    String peer, {
    String name = '我的笔记本',
    bool online = true,
    bool paired = true,
  }) {
    _threads[peer] = ChatThread(
      peerFingerprint: peer,
      peerName: name,
      online: online,
      paired: paired,
    );
    _messages.putIfAbsent(peer, () => []);
    notifyListeners();
  }

  void setPeer(String peer, {bool? online, bool? paired}) {
    final t = _threads[peer]!;
    _threads[peer] = ChatThread(
      peerFingerprint: peer,
      peerName: t.peerName,
      online: online ?? t.online,
      paired: paired ?? t.paired,
    );
    notifyListeners();
  }

  void add(
    String peer, {
    required ChatDirection direction,
    required String body,
    SendState? state,
    DateTime? readAt,
    Acceptance acceptance = Acceptance.none,
    String? error,
  }) {
    _messages[peer]!.add(
      ChatMessage(
        id: 'm${++_n}',
        peerFingerprint: peer,
        direction: direction,
        body: body,
        createdAt: DateTime.utc(2026, 10, 5, 9, _n),
        sendState: state,
        readAt: readAt,
        acceptance: acceptance,
        error: error,
      ),
    );
    notifyListeners();
  }

  @override
  List<ChatThread> threads() => [for (final t in _threads.values) _withLast(t)];

  ChatThread _withLast(ChatThread t) {
    final list = _messages[t.peerFingerprint]!;
    return ChatThread(
      peerFingerprint: t.peerFingerprint,
      peerName: t.peerName,
      online: t.online,
      paired: t.paired,
      last: list.isEmpty ? null : list.last,
      unread: list.where((m) => m.unread).length,
    );
  }

  @override
  ChatThread? thread(String peer) =>
      _threads[peer] == null ? null : _withLast(_threads[peer]!);

  @override
  List<ChatMessage> messages(String peer) =>
      List.unmodifiable(_messages[peer] ?? const []);

  @override
  Future<void> sendText(String peer, String body) async {
    final t = _threads[peer]!;
    if (!t.paired) throw StateError('未配对或已撤销');
    if (!t.online) throw StateError('对方不在线，没有中继');
    if (sendError != null) throw sendError!;
    sentBodies.add(body);
    add(
      peer,
      direction: ChatDirection.outgoing,
      body: body,
      state: SendState.sent,
    );
  }

  void _replace(String id, ChatMessage Function(ChatMessage) change) {
    for (final list in _messages.values) {
      final i = list.indexWhere((m) => m.id == id);
      if (i >= 0) {
        list[i] = change(list[i]);
        notifyListeners();
        return;
      }
    }
    throw StateError('消息不存在');
  }

  ChatMessage _copy(
    ChatMessage m, {
    DateTime? readAt,
    Acceptance? acceptance,
    SendState? state,
  }) => ChatMessage(
    id: m.id,
    peerFingerprint: m.peerFingerprint,
    direction: m.direction,
    body: m.body,
    createdAt: m.createdAt,
    sendState: state ?? m.sendState,
    acceptance: acceptance ?? m.acceptance,
    readAt: readAt ?? m.readAt,
    error: m.error,
  );

  @override
  Future<void> markRead(String peer) async {
    final now = DateTime.utc(2026, 10, 5, 10);
    final list = _messages[peer]!;
    for (var i = 0; i < list.length; i++) {
      if (list[i].unread) list[i] = _copy(list[i], readAt: now);
    }
    notifyListeners();
  }

  @override
  Future<void> accept(String id) async =>
      _replace(id, (m) => _copy(m, acceptance: Acceptance.accepted));
  @override
  Future<void> reject(String id) async =>
      _replace(id, (m) => _copy(m, acceptance: Acceptance.rejected));
  @override
  Future<void> retry(String id) async {
    retried.add(id);
    _replace(id, (m) => _copy(m, state: SendState.queued));
  }

  @override
  Future<void> delete(String id) async {
    for (final list in _messages.values) {
      list.removeWhere((m) => m.id == id);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteThread(String peer) async {
    _messages.remove(peer);
    _threads.remove(peer);
    notifyListeners();
  }
}
