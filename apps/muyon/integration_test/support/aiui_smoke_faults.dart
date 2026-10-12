import 'dart:async';
import 'dart:io';

import 'aiui_smoke_config.dart';

enum SmokeFaultKind {
  connectionInterruption,
  stalledPlanning,
  userCancellation,
}

/// Request-scoped I/O ownership; never replaces gateway, compiler, grants or
/// renderer. Bootstrap still needs to forward clientFactory and correlation.
/// Scripted protocol fixtures are deliberately outside this real-upstream path.
final class AiuiSmokeFaults {
  String? _planningTask, _parentTask;
  SmokeFaultKind? _kind;
  HttpClient? _client;
  bool _sent = false, _received = false, _closed = false;
  Completer<void>? _pause;
  bool get receivedActualContent => _received;

  void arm({
    required String planningTask,
    required String parentTask,
    required bool uiPlanningInternal,
    required SmokeFaultKind kind,
  }) {
    if (_planningTask != null ||
        planningTask.isEmpty ||
        parentTask.isEmpty ||
        planningTask == parentTask ||
        !uiPlanningInternal) {
      throw SmokeFailure(SmokeFailureCode.faultPreconditionUnmet);
    }
    _planningTask = planningTask;
    _parentTask = parentTask;
    _kind = kind;
  }

  bool attach(String task, String parent, HttpClient client) {
    if (_closed ||
        task != _planningTask ||
        parent != _parentTask ||
        _client != null) {
      return false;
    }
    _client = client;
    return true;
  }

  void sent(String task) {
    if (!_closed && task == _planningTask) _sent = true;
  }

  void actualContent(String task, String content) {
    if (!_closed &&
        _sent &&
        task == _planningTask &&
        content.trim().isNotEmpty) {
      _received = true;
    }
  }

  void interrupt() {
    _requireReady(SmokeFaultKind.connectionInterruption);
    _closed = true;
    _client!.close(force: true);
  }

  /// Only the I/O completion is paused. The production deadline remains the
  /// sole timeout authority. A watchdog must fail the test, never call cancel.
  Future<void> holdCompletion(String task) {
    _requireReady(SmokeFaultKind.stalledPlanning);
    if (task != _planningTask) {
      throw SmokeFailure(SmokeFailureCode.faultPreconditionUnmet);
    }
    return (_pause ??= Completer<void>()).future;
  }

  void releaseLateCompletion() {
    if (_pause?.isCompleted == false) _pause!.complete();
  }

  void _requireReady(SmokeFaultKind kind) {
    if (_closed || _kind != kind || !_sent || !_received || _client == null) {
      throw SmokeFailure(SmokeFailureCode.faultPreconditionUnmet);
    }
  }

  void close() {
    if (!_closed) _client?.close(force: true);
    _closed = true;
    releaseLateCompletion();
  }
}
