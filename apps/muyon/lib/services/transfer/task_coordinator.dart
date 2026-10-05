import 'dart:convert';
import 'dart:io';

import 'package:muyon_module_api/muyon_module_api.dart';

/// Ownership of one task revision across paired devices.
/// Receiving a message never runs [executor]; the local device must accept.
class TaskCoordinator {
  TaskCoordinator({
    required this.database,
    required this.deviceId,
    required this.send,
    required this.executor,
    bool Function()? peerReachable,
  }) : peerReachable = peerReachable ?? (() => true);
  final ManagedDatabase database;
  final String deviceId;
  final Future<void> Function(Map<String, Object?> envelope) send;
  final Future<String> Function(TaskOffer offer) executor;
  final bool Function() peerReachable;
  static const marker = 'muyon-task-v1';

  static Map<String, Object?>? decodeFile(String path) {
    try {
      final decoded = jsonDecode(File(path).readAsStringSync());
      if (decoded is! Map || decoded['muyon'] != marker) return null;
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> offer({
    required String taskId,
    required String inputRevision,
    required String idempotencyKey,
  }) async {
    if (!await _insertOffer(taskId, inputRevision, idempotencyKey)) return;
    await send(
      _message(
        'offer',
        taskId: taskId,
        inputRevision: inputRevision,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  Future<void> receive(Map<String, Object?> envelope) async {
    if (envelope['muyon'] != marker) {
      throw const FormatException('not a task message');
    }
    final taskId = envelope['taskId'] as String;
    final inputRevision = envelope['inputRevision'] as String;
    switch (envelope['type']) {
      case 'offer':
        await _insertOffer(
          taskId,
          inputRevision,
          envelope['idempotencyKey'] as String,
        );
      case 'accept':
        await _noteAccept(
          envelope['deviceId'] as String,
          taskId,
          inputRevision,
        );
      case 'result':
        await applyResult(
          taskId: taskId,
          inputRevision: inputRevision,
          seq: envelope['seq'] as int,
          result: envelope['result'] as String,
        );
      case 'status':
        return;
      default:
        throw const FormatException('unknown task message');
    }
  }

  /// Lower device id wins while the task is not yet running.
  Future<bool> accept({
    required String taskId,
    required String inputRevision,
  }) async {
    final claimed = await database.write((db) {
      final row = _row(db, taskId, inputRevision);
      if (row == null) return null;
      final state = row['state'] as String;
      if (_terminal(state) || state == 'running') {
        return row['owner_device_id'] == deviceId
            ? row['idempotency_key'] as String
            : null;
      }
      final owner = row['owner_device_id'] as String?;
      if (owner != null && deviceId.compareTo(owner) >= 0) return null;
      db.execute(
        "UPDATE transfer_tasks SET state='accepted', owner_device_id=?, updated_at=? WHERE task_id=? AND input_revision=?",
        [deviceId, _now(), taskId, inputRevision],
      );
      return row['idempotency_key'] as String;
    });
    if (claimed == null) return false;
    await send(
      _message(
        'accept',
        taskId: taskId,
        inputRevision: inputRevision,
        idempotencyKey: claimed,
      ),
    );
    return true;
  }

  /// Runs [executor] once, only for the owner of an accepted task.
  Future<void> start({
    required String taskId,
    required String inputRevision,
  }) async {
    final offer = await database.write((db) {
      final row = _row(db, taskId, inputRevision);
      if (row == null ||
          row['owner_device_id'] != deviceId ||
          row['state'] != 'accepted') {
        return null;
      }
      db.execute(
        "UPDATE transfer_tasks SET state='running', updated_at=? WHERE task_id=? AND input_revision=?",
        [_now(), taskId, inputRevision],
      );
      return TaskOffer(
        taskId: taskId,
        inputRevision: inputRevision,
        idempotencyKey: row['idempotency_key'] as String,
      );
    });
    if (offer == null) return;
    try {
      final result = await executor(offer);
      await applyResult(
        taskId: taskId,
        inputRevision: inputRevision,
        seq: 1,
        result: result,
      );
    } catch (error) {
      await database.write((db) {
        db.execute(
          "UPDATE transfer_tasks SET state='failed', result_json=?, updated_at=? WHERE task_id=? AND input_revision=? AND state='running' AND owner_device_id=?",
          ['$error', _now(), taskId, inputRevision, deviceId],
        );
      });
      rethrow;
    }
  }

  Future<void> applyResult({
    required String taskId,
    required String inputRevision,
    required int seq,
    required String result,
  }) => database.write((db) {
    final row = _row(db, taskId, inputRevision);
    if (row == null) return;
    final state = row['state'] as String;
    if (state == 'failed' || state == 'cancelled') return;
    if (seq <= (row['result_seq'] as int)) return;
    db.execute(
      "UPDATE transfer_tasks SET state='succeeded', result_seq=?, result_json=?, updated_at=? WHERE task_id=? AND input_revision=?",
      [seq, result, _now(), taskId, inputRevision],
    );
  });

  /// Unreachable peers are unknown. This does not write failed or done.
  Future<String> queryPeer({
    required String taskId,
    required String inputRevision,
  }) async {
    if (!peerReachable()) return 'unknown';
    final row = _local(taskId, inputRevision);
    try {
      await send(
        _message(
          'status',
          taskId: taskId,
          inputRevision: inputRevision,
          idempotencyKey: row?['idempotency_key'] as String? ?? '',
        ),
      );
    } catch (_) {
      return 'unknown';
    }
    return _local(taskId, inputRevision)?['state'] as String? ?? 'unknown';
  }

  Map<String, Object?>? _local(String taskId, String inputRevision) {
    final rows = database.raw.select(
      'SELECT * FROM transfer_tasks WHERE task_id=? AND input_revision=?',
      [taskId, inputRevision],
    );
    return rows.isEmpty ? null : rows.single;
  }

  List<TaskRecord> list() => [
    for (final row in database.raw.select(
      'SELECT * FROM transfer_tasks ORDER BY updated_at DESC, task_id',
    ))
      TaskRecord(
        taskId: row['task_id'] as String,
        inputRevision: row['input_revision'] as String,
        state: row['state'] as String,
        ownerDeviceId: row['owner_device_id'] as String?,
      ),
  ];

  String? stateOf(String taskId, String inputRevision) =>
      _local(taskId, inputRevision)?['state'] as String?;

  String? ownerOf(String taskId, String inputRevision) =>
      _local(taskId, inputRevision)?['owner_device_id'] as String?;

  String? resultOf(String taskId, String inputRevision) =>
      _local(taskId, inputRevision)?['result_json'] as String?;

  int countOf(String taskId, String inputRevision) => database.raw.select(
    'SELECT task_id FROM transfer_tasks WHERE task_id=? AND input_revision=?',
    [taskId, inputRevision],
  ).length;

  Future<bool> _insertOffer(
    String taskId,
    String inputRevision,
    String idempotencyKey,
  ) => database.write((db) {
    final existing = db.select(
      'SELECT task_id FROM transfer_tasks WHERE idempotency_key=?',
      [idempotencyKey],
    );
    if (existing.isNotEmpty) return false;
    db.execute(
      'INSERT INTO transfer_tasks(task_id,input_revision,idempotency_key,state,result_seq,updated_at) VALUES(?,?,?,?,0,?)',
      [taskId, inputRevision, idempotencyKey, 'offered', _now()],
    );
    return true;
  });

  Future<void> _noteAccept(String peer, String taskId, String inputRevision) =>
      database.write((db) {
        final row = _row(db, taskId, inputRevision);
        if (row == null) return;
        final state = row['state'] as String;
        if (_terminal(state) || state == 'running') return;
        final owner = row['owner_device_id'] as String?;
        if (owner != null && peer.compareTo(owner) >= 0) return;
        db.execute(
          "UPDATE transfer_tasks SET state='accepted', owner_device_id=?, updated_at=? WHERE task_id=? AND input_revision=?",
          [peer, _now(), taskId, inputRevision],
        );
      });

  Map<String, Object?>? _row(dynamic db, String taskId, String inputRevision) {
    final rows = db.select(
      'SELECT * FROM transfer_tasks WHERE task_id=? AND input_revision=?',
      [taskId, inputRevision],
    );
    return rows.isEmpty ? null : rows.single;
  }

  bool _terminal(String state) =>
      state == 'succeeded' || state == 'failed' || state == 'cancelled';

  Map<String, Object?> _message(
    String type, {
    required String taskId,
    required String inputRevision,
    required String idempotencyKey,
    int? seq,
    String? result,
  }) => {
    'muyon': marker,
    'type': type,
    'taskId': taskId,
    'inputRevision': inputRevision,
    'idempotencyKey': idempotencyKey,
    'deviceId': deviceId,
    'seq': ?seq,
    'result': ?result,
  };

  String _now() => DateTime.now().toUtc().toIso8601String();
}

class TaskRecord {
  const TaskRecord({
    required this.taskId,
    required this.inputRevision,
    required this.state,
    required this.ownerDeviceId,
  });
  final String taskId, inputRevision, state;
  final String? ownerDeviceId;
}

/// Local record. This is not the peer's answer.
String localTaskLabel(String? state, String? owner) => switch (state) {
  'offered' => '已提议',
  'accepted' => '已由 ${owner ?? '未知设备'} 接受',
  'running' => '执行中',
  'succeeded' => '完成',
  'failed' => '失败',
  'cancelled' => '已取消',
  _ => '未知',
};

/// Peer query. `unknown` stays unreachable and is never failed or done.
String peerTaskLabel(String? peerView) => switch (peerView) {
  null => '尚未查询',
  'unknown' => '不可达',
  'offered' => '已提议',
  'accepted' => '已接受',
  'running' => '执行中',
  'succeeded' => '完成',
  'failed' => '失败',
  'cancelled' => '已取消',
  _ => peerView,
};

class TaskOffer {
  const TaskOffer({
    required this.taskId,
    required this.inputRevision,
    required this.idempotencyKey,
  });
  final String taskId, inputRevision, idempotencyKey;
}
