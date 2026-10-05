import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';

import '../services/transfer/task_coordinator.dart';
import '../workspace/import_coordinator.dart';
import 'bootstrap.dart';

/// Cross-device research tasks. Muyon does not run research: "executing" a
/// task means the person authorises importing its package into the local
/// research module, does the work themselves, and returns a result package.
///
/// Stored files (under `transfer/research-tasks/`) are keyed by a hash of
/// (task id, input revision) so a crafted id can never choose a path.
class ResearchTaskBridge {
  ResearchTaskBridge(this.host);
  final MuyonHost host;

  static const maxPackageBytes = 8 * 1024 * 1024;
  static const maxResultBytes = 32 * 1024 * 1024;
  static const _taskKind = 'research-task';
  static const _resultKind = 'research-result';

  String get _dir =>
      p.join(host.storage.rootPath, 'transfer', 'research-tasks');

  static String _key(String taskId, String revision) => sha256
      .convert(utf8.encode('$taskId\u0000$revision'))
      .toString()
      .substring(0, 32);

  File _packageFile(String taskId, String revision) =>
      File(p.join(_dir, '${_key(taskId, revision)}.task.zip'));

  File? _resultFile(String taskId, String revision) {
    for (final ext in const ['zip', 'json']) {
      final file = File(p.join(_dir, '${_key(taskId, revision)}.result.$ext'));
      if (file.existsSync()) return file;
    }
    return null;
  }

  File _marker(String taskId, String revision) =>
      File(p.join(_dir, '${_key(taskId, revision)}.imported'));

  /// A research package travelled with this offer (so it is a research task).
  bool isResearchTask(String taskId, String revision) =>
      _packageFile(taskId, revision).existsSync();

  bool hasReturnedResult(String taskId, String revision) =>
      _resultFile(taskId, revision) != null;

  bool resultImported(String taskId, String revision) =>
      _marker(taskId, revision).existsSync();

  // ---- offering side ----------------------------------------------------

  /// Offers a research task revision to the paired devices. The package is a
  /// specification only; nothing runs on the other side.
  Future<void> offer(ResearchTask task) async {
    await host.activateResearch();
    final runtime = host.research;
    if (runtime == null) {
      throw StateError(host.researchError ?? 'Research unavailable');
    }
    if (runtime.store.taskRevision(task.id, task.revision) == null) {
      throw StateError('Unknown task revision');
    }
    final temp = await Directory.systemTemp.createTemp('muyon-task-offer-');
    try {
      final zip = await ResearchExchange(runtime.store)
          .exportTask(task, temp.path);
      final bytes = await File(zip).readAsBytes();
      if (bytes.length > maxPackageBytes) {
        throw const FormatException('任务包过大');
      }
      await host.tasks.offer(
        taskId: task.id,
        inputRevision: '${task.revision}',
        idempotencyKey: const Uuid().v4(),
        attachment: {
          'kind': _taskKind,
          'name': 'task-${task.revision}.zip',
          'sha256': sha256.convert(bytes).toString(),
          'dataBase64': base64Encode(bytes),
        },
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  /// Result returned by the other device. Stored only; importing into the
  /// research module is a separate, explicit step ([importReturnedResult]).
  Future<void> saveReturnedResult(
    String taskId,
    String revision,
    String result,
  ) async {
    final bytes = _decode(result, _resultKind, maxResultBytes);
    if (bytes == null) return; // not a research result; coordinator keeps it
    final name = (jsonDecode(result) as Map)['name'] as String;
    final ext = name.toLowerCase().endsWith('.zip') ? 'zip' : 'json';
    if (_resultMismatch(bytes.$1, ext, taskId, revision) != null) return;
    await _write(
      File(p.join(_dir, '${_key(taskId, revision)}.result.$ext')),
      bytes.$1,
    );
  }

  /// Attaches the returned result to the original task, once. The result must
  /// name exactly this task and revision. It becomes a run awaiting human
  /// assessment; nothing is accepted as evidence.
  Future<String> importReturnedResult(String taskId, String revision) async {
    final marker = _marker(taskId, revision);
    if (marker.existsSync()) return marker.readAsStringSync();
    final file = _resultFile(taskId, revision);
    if (file == null) throw StateError('还没有收到这个任务的结果');
    final reason = _resultMismatch(
      await file.readAsBytes(),
      p.extension(file.path).substring(1),
      taskId,
      revision,
    );
    if (reason != null) throw FormatException(reason);
    await host.activateResearch();
    final runtime = host.research;
    if (runtime == null) {
      throw StateError(host.researchError ?? 'Research unavailable');
    }
    final run = await ResearchExchange(runtime.store).importResult(file.path);
    await _write(marker, utf8.encode(run.id));
    return run.id;
  }

  // ---- receiving side ---------------------------------------------------

  /// Stores the package that came with an offer. Nothing is imported or run.
  Future<void> saveOfferAttachment(
    String taskId,
    String revision,
    Map<String, Object?> attachment,
  ) async {
    final bytes = _decode(attachment, _taskKind, maxPackageBytes);
    if (bytes == null) return;
    await _write(_packageFile(taskId, revision), bytes.$1);
  }

  /// The coordinator's executor for research tasks: import the package into
  /// the local research module and report "started" (null). It never runs
  /// anything and never marks the task done.
  Future<String?> start(TaskOffer offer) async {
    final package = _packageFile(offer.taskId, offer.inputRevision);
    if (!package.existsSync()) {
      throw StateError('没有随任务到达的研究任务包：${offer.taskId}');
    }
    await _importTask(package.path, offer);
    return null;
  }

  Future<void> _importTask(String zipPath, TaskOffer offer) async {
    await host.activateResearch();
    final runtime = host.research;
    if (runtime == null) {
      throw StateError(host.researchError ?? 'Research unavailable');
    }
    final task = await runtime.prepareTask(
      SelectedInput(path: zipPath, displayName: p.basename(zipPath)),
    );
    if (task.taskId != offer.taskId ||
        '${task.revision}' != offer.inputRevision) {
      await task.snapshot.delete(recursive: true);
      throw const FormatException('任务包与提议的任务和版本不一致');
    }
    // Restart or retry: the revision is already in the research module.
    if (runtime.store.taskRevision(task.taskId, task.revision) != null) {
      await task.snapshot.delete(recursive: true);
      return;
    }
    final coordinator = ImportCoordinator(host.workspaces);
    await coordinator.recover('research', runtime);
    final owner = host.workspaces.ownerWorkspace('research', task.projectId);
    final workspace =
        owner ?? (await host.workspaces.create('接收任务 · ${task.title}')).id;
    final binding = WorkspaceBinding(
      workspaceId: workspace,
      moduleId: 'research',
      nativeProjectId: task.projectId,
    );
    final existing = host.workspaces.binding(workspace, 'research');
    final prepared = await runtime.prepareTaskImport(
      task,
      existing == null
          ? ImportTarget.create(binding)
          : ImportTarget.refresh(binding),
    );
    final intent = await coordinator.record(prepared);
    await coordinator.commit(runtime, prepared, intent);
  }

  /// The person finished the work and exported a result file from the research
  /// module. Sends it to the offering device and marks the task done here.
  Future<void> submitResult(String taskId, String revision, String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('结果必须是一个普通文件');
    }
    final name = p.basename(path);
    final lower = name.toLowerCase();
    if (!lower.endsWith('.zip') && !lower.endsWith('.json')) {
      throw const FormatException('结果应是科研模块导出的 .zip 或 .json');
    }
    if (await File(path).length() > maxResultBytes) {
      throw const FormatException('结果文件过大');
    }
    final bytes = await File(path).readAsBytes();
    final reason = _resultMismatch(
      bytes,
      lower.endsWith('.zip') ? 'zip' : 'json',
      taskId,
      revision,
    );
    if (reason != null) throw FormatException(reason);
    final sent = await host.tasks.complete(
      taskId: taskId,
      inputRevision: revision,
      result: jsonEncode({
        'kind': _resultKind,
        'name': name,
        'sha256': sha256.convert(bytes).toString(),
        'dataBase64': base64Encode(bytes),
      }),
    );
    if (!sent) {
      throw StateError('只有本机正在处理的任务才能提交结果；可能已提交过');
    }
  }

  // ---- shared ------------------------------------------------------------

  /// Decodes an envelope `{kind, sha256, dataBase64, name}` (or its JSON text)
  /// and checks kind, size and digest. Null when it is not that kind.
  (List<int>,)? _decode(Object? raw, String kind, int limit) {
    try {
      final map = raw is String ? jsonDecode(raw) : raw;
      if (map is! Map || map['kind'] != kind) return null;
      final data = map['dataBase64'];
      if (data is! String || data.length > limit * 4 ~/ 3 + 8) return null;
      final bytes = base64Decode(data);
      if (bytes.length > limit ||
          sha256.convert(bytes).toString() != map['sha256']) {
        return null;
      }
      return (bytes,);
    } on FormatException {
      return null;
    }
  }

  /// Why this result does not belong to (task, revision); null when it does.
  String? _resultMismatch(
    List<int> bytes,
    String ext,
    String taskId,
    String revision,
  ) {
    try {
      List<int>? json = bytes;
      if (ext == 'zip') {
        final archive = ZipDecoder().decodeBytes(bytes);
        final files = archive.files
            .where((f) => f.isFile && p.basename(f.name) == 'result.json')
            .toList();
        if (files.length != 1) return '结果压缩包必须恰好包含一个 result.json';
        json = files.single.content as List<int>;
      }
      final data = jsonDecode(utf8.decode(json));
      if (data is! Map ||
          data['taskId'] != taskId ||
          '${data['taskRevision']}' != revision) {
        return '这份结果不属于该任务和版本';
      }
      return null;
    } on Object {
      return '结果文件无法读取';
    }
  }

  Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${const Uuid().v4()}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }
}
