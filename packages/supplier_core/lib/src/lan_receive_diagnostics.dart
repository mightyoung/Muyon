import 'dart:async';
import 'dart:io';

/// Internal, opt-in receiver diagnostics for trusted in-process callers.
/// Import this src library explicitly; it is not exported by the LAN API.
/// Events contain no request/exception text, identity, address, path or proof.
enum LanReceiveStage {
  authorization,
  admission,
  identity,
  createTemp,
  open,
  read,
  write,
  flush,
  close,
  validateLength,
  verify,
  rename,
  persist,
  deliver,
  cleanup,
  response,
  http,
}

enum LanReceiveEventKind { entered, deadline, failure, cleaned, responded }

enum LanReceiveError { filesystem, format, timeout, socket, state, other }

class LanReceiveEvent {
  const LanReceiveEvent({
    required this.attempt,
    required this.kind,
    required this.stage,
    required this.elapsedMicroseconds,
    this.error,
    this.deadlineExpired = false,
    this.stopped,
    this.retained,
    this.cleanupSucceeded,
    this.activeUploads,
    this.reservedBytes,
    this.statusCode,
  });

  // A process-local ordinal, never a request's nonce or message ID.
  final int attempt;
  final LanReceiveEventKind kind;
  final LanReceiveStage stage;
  final int elapsedMicroseconds;
  final LanReceiveError? error;
  final bool deadlineExpired;
  final bool? stopped, retained;
  final bool? cleanupSucceeded;
  final int? activeUploads, reservedBytes, statusCode;

  @override
  String toString() =>
      'receive attempt=$attempt kind=${kind.name} stage=${stage.name} '
      'elapsedUs=$elapsedMicroseconds error=${error?.name} '
      'deadline=$deadlineExpired stopped=$stopped retained=$retained '
      'cleanup=$cleanupSucceeded active=$activeUploads reserved=$reservedBytes '
      'status=$statusCode';
}

class LanReceiveDiagnostics {
  LanReceiveDiagnostics(this.onEvent);
  final void Function(LanReceiveEvent) onEvent;
  int _nextAttempt = 0;
  static final Object _zoneKey = Object();

  static LanReceiveDiagnostics? get current =>
      Zone.current[_zoneKey] as LanReceiveDiagnostics?;

  /// Nodes started in this zone capture the observer for their lifetime.
  /// Observer exceptions are isolated from HTTP handling. Callers are trusted
  /// in-process code; an observer must not mutate receiver state or block.
  T run<T>(T Function() operation) =>
      runZoned(operation, zoneValues: {_zoneKey: this});

  LanReceiveAttempt begin() => LanReceiveAttempt(this, ++_nextAttempt);
}

class LanReceiveAttempt {
  LanReceiveAttempt(this._diagnostics, this._ordinal);
  final LanReceiveDiagnostics _diagnostics;
  final int _ordinal;
  final Stopwatch _watch = Stopwatch()..start();
  LanReceiveStage stage = LanReceiveStage.authorization;
  bool deadlineExpired = false;
  bool hasFailure = false;

  void enter(LanReceiveStage next) {
    stage = next;
    emit(LanReceiveEventKind.entered);
  }

  void failure(Object error) {
    hasFailure = true;
    emit(
      LanReceiveEventKind.failure,
      error: switch (error) {
        FileSystemException() => LanReceiveError.filesystem,
        FormatException() => LanReceiveError.format,
        TimeoutException() => LanReceiveError.timeout,
        SocketException() => LanReceiveError.socket,
        StateError() => LanReceiveError.state,
        _ => LanReceiveError.other,
      },
    );
  }

  void emit(
    LanReceiveEventKind kind, {
    LanReceiveError? error,
    bool? stopped,
    bool? retained,
    bool? cleanupSucceeded,
    int? activeUploads,
    int? reservedBytes,
    int? statusCode,
  }) {
    try {
      _diagnostics.onEvent(
        LanReceiveEvent(
          attempt: _ordinal,
          kind: kind,
          stage: stage,
          elapsedMicroseconds: _watch.elapsedMicroseconds,
          error: error,
          deadlineExpired: deadlineExpired,
          stopped: stopped,
          retained: retained,
          cleanupSucceeded: cleanupSucceeded,
          activeUploads: activeUploads,
          reservedBytes: reservedBytes,
          statusCode: statusCode,
        ),
      );
    } catch (_) {
      // No exception text is retained or forwarded.
    }
  }
}
