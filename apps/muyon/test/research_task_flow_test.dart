import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/services/transfer/task_coordinator.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:supplier_core/lan.dart';

/// Cross-device research tasks between two looped-back hosts. "Executing" a
/// task means: authorise → package imported into the local research module →
/// the person does the work → result returned. Nothing runs by itself.
void main() {
  late Directory root;
  late MuyonHost a, b;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('research-task-flow-');
    a = await MuyonHost.open('${root.path}/a');
    b = await MuyonHost.open('${root.path}/b');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    for (final name in ['a', 'b']) {
      final seen = File('${root.path}/$name/transfer/inbox.seen-pushes.json');
      if (seen.existsSync()) seen.deleteSync();
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> listen(MuyonHost host) => host.services.transfer.start(
    deviceId: host.workspaces.setting('deviceId') as String,
    deviceName: 'host',
    discoveryPort: 0,
    httpPort: 0,
    secrets: MemoryLanSecretStore(),
  );

  Future<void> pair(MuyonHost x, MuyonHost y) async {
    final peer = await x.services.transfer.probe(
      '127.0.0.1',
      port: y.services.transfer.httpPort!,
    );
    x.services.transfer.confirmPeer(
      fingerprint: peer.fingerprint,
      confirmedCode: y.services.transfer.localShortCode!,
      certificatePem: peer.certificatePem,
    );
  }

  Future<void> connect() async {
    await listen(a);
    await listen(b);
    await pair(a, b);
    await pair(b, a);
  }

  Future<void> until(bool Function() ready, String label) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail(label);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// A research project with one task on [host], via the normal import path.
  Future<ResearchTask> makeTask(MuyonHost host) async {
    final source = Directory('${root.path}/src')..createSync();
    File(p.join(source.path, 'README.md')).writeAsStringSync('# 研究\n内容');
    await host.activateResearch();
    final workspace = await host.workspaces.create('发起方工作区');
    final binding = WorkspaceBinding(
      workspaceId: workspace.id,
      moduleId: 'research',
      nativeProjectId: 'P',
    );
    final prepared = await host.research!.prepareImport(
      SelectedInput(path: source.path, displayName: 'P'),
      ImportTarget.create(binding),
    );
    final coordinator = ImportCoordinator(host.workspaces);
    await coordinator.commit(
      host.research!,
      prepared,
      await coordinator.record(prepared),
    );
    final project = host.research!.store.projects().single;
    return host.research!.store.write(
      () => host.research!.store.saveTask(
        projectId: project.id,
        title: '对比实验',
        goal: '比较两种配置',
        spec: {
          'parameters': {'seed': 7},
          'command': 'manual-only',
        },
      ),
    );
  }

  String resultFile(ResearchTask task, {String? taskId, int? revision}) {
    final file = File(
      '${root.path}/result-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    file.writeAsStringSync(
      jsonEncode({
        'format': 'research-result-v1',
        'runId': 'run-${task.id}',
        'taskId': taskId ?? task.id,
        'taskRevision': revision ?? task.revision,
        'status': 'completed',
        'finishedAt': '2026-10-05T10:00:00Z',
        'metrics': {'score': 0.9},
        'logs': <String>[],
        'artifacts': <String>[],
      }),
    );
    return file.path;
  }

  test('offered precedes attachment persistence and itemsSettled waits for it', () async {
    await connect();
    final saving = Completer<void>();
    final release = Completer<void>();
    var executions = 0;
    final receiver = TaskCoordinator(
      database: b.tasks.database,
      deviceId: b.tasks.deviceId,
      send: b.services.transfer.sendTaskEnvelope,
      executor: (_) async {
        executions++;
        return null;
      },
      onOfferAttachment: (taskId, revision, attachment) async {
        saving.complete();
        await release.future;
        await b.researchTasks.saveOfferAttachment(taskId, revision, attachment);
      },
    );
    b.services.transfer.onTaskEnvelope = receiver.receive;
    const taskId = 'held-offer', revision = '1';
    final archive = Archive()..addFile(ArchiveFile('README.md', 1, [65]));
    final bytes = ZipEncoder().encode(archive);
    // Report a drain failure independently of a primary assertion failure.
    // This runs before the suite's tearDown closes either host.
    addTearDown(() => b.services.transfer.itemsSettled);
    try {
      await a.tasks.offer(
        taskId: taskId,
        inputRevision: revision,
        idempotencyKey: 'held-offer-key',
        attachment: {
          'kind': 'research-task',
          'name': 'held-offer.zip',
          'sha256': sha256.convert(bytes).toString(),
          'dataBase64': base64Encode(bytes),
        },
      );
      await saving.future.timeout(const Duration(seconds: 20));
      expect(receiver.stateOf(taskId, revision), 'offered');
      expect(b.researchTasks.isResearchTask(taskId, revision), isFalse);
      var settled = false;
      final received = b.services.transfer.itemsSettled.then((_) => settled = true);
      // Positive control: an already completed signal is observable at this
      // same checkpoint. The real queue remains gated on the unfinished save.
      var immediateSettled = false;
      final immediate = Future<void>.value().then((_) => immediateSettled = true);
      await immediate;
      expect(immediateSettled, isTrue);
      expect(settled, isFalse);
      release.complete();
      await received;
      expect(settled, isTrue);
      expect(receiver.stateOf(taskId, revision), 'offered');
      expect(b.researchTasks.isResearchTask(taskId, revision), isTrue);
      expect(b.workspaces.all(), isEmpty);
      expect(b.research, isNull);
      expect(executions, 0);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });

  test(
    'offer → authorise → import (not run) → result → one import on the origin',
    () async {
      await connect();
      final task = await makeTask(a);
      final rev = '${task.revision}';
      await a.researchTasks.offer(task);

      await until(() => b.tasks.stateOf(task.id, rev) == 'offered', 'offered');
      // Ownership is visible before the queued attachment save finishes.
      await b.services.transfer.itemsSettled;
      // Receiving, even with the package, imports nothing and runs nothing.
      expect(b.researchTasks.isResearchTask(task.id, rev), isTrue);
      expect(b.workspaces.all(), isEmpty);
      expect(b.research, isNull);

      expect(await b.tasks.accept(taskId: task.id, inputRevision: rev), isTrue);
      await until(
        () => a.tasks.stateOf(task.id, rev) == 'accepted',
        'accepted',
      );
      expect(
        b.workspaces.all(),
        isEmpty,
        reason: 'accepting is not authorising import',
      );

      await b.tasks.start(taskId: task.id, inputRevision: rev);
      expect(b.tasks.stateOf(task.id, rev), 'running');
      final imported = b.research!.store.taskRevision(task.id, task.revision);
      expect(imported, isNotNull);
      expect(imported!.title, '对比实验');
      expect(
        b.research!.store.runs(imported.projectId),
        isEmpty,
        reason: 'importing is not running',
      );
      expect(b.workspaces.all(), hasLength(1));
      expect(b.tasks.resultOf(task.id, rev), isNull);

      // A second authorisation does not import again.
      await b.tasks.start(taskId: task.id, inputRevision: rev);
      expect(b.workspaces.all(), hasLength(1));

      await b.researchTasks.submitResult(task.id, rev, resultFile(task));
      expect(b.tasks.stateOf(task.id, rev), 'succeeded');
      await until(
        () => a.researchTasks.hasReturnedResult(task.id, rev),
        'returned',
      );
      expect(a.tasks.stateOf(task.id, rev), 'succeeded');
      final projectId = a.research!.store.projects().single.id;
      expect(
        a.research!.store.runs(projectId),
        isEmpty,
        reason: 'a returned result is stored, not yet attached',
      );

      final runId = await a.researchTasks.importReturnedResult(task.id, rev);
      final runs = a.research!.store.runs(projectId);
      expect(runs.single.id, runId);
      expect(runs.single.taskId, task.id);
      expect(runs.single.accepted, isFalse, reason: 'awaits human assessment');
      expect(await a.researchTasks.importReturnedResult(task.id, rev), runId);
      expect(a.research!.store.runs(projectId), hasLength(1));
    },
  );

  test(
    'a late or duplicate result is ignored and a second submit is refused',
    () async {
      await connect();
      final task = await makeTask(a);
      final rev = '${task.revision}';
      await a.researchTasks.offer(task);
      await until(() => b.tasks.stateOf(task.id, rev) == 'offered', 'offered');
      await b.services.transfer.itemsSettled;
      await b.tasks.accept(taskId: task.id, inputRevision: rev);
      await b.tasks.start(taskId: task.id, inputRevision: rev);
      await b.researchTasks.submitResult(task.id, rev, resultFile(task));
      await until(
        () => a.researchTasks.hasReturnedResult(task.id, rev),
        'returned',
      );
      await expectLater(
        b.researchTasks.submitResult(task.id, rev, resultFile(task)),
        throwsStateError,
      );
      final envelope = {
        'muyon': 'muyon-task-v1',
        'type': 'result',
        'taskId': task.id,
        'inputRevision': rev,
        'idempotencyKey': 'x',
        'deviceId': 'peer',
        'seq': 1,
        'result': jsonEncode({
          'kind': 'research-result',
          'name': 'r.json',
          'sha256': '0',
          'dataBase64': '',
        }),
      };
      await a.tasks.receive(envelope);
      await a.tasks.receive({...envelope, 'seq': 0});
      expect(
        a.tasks.resultOf(task.id, rev),
        isNot(contains('"sha256":"0"')),
        reason: 'the first result stays',
      );
    },
  );

  test(
    'a result for another task or revision is refused before anything is sent',
    () async {
      await connect();
      final task = await makeTask(a);
      final rev = '${task.revision}';
      await a.researchTasks.offer(task);
      await until(() => b.tasks.stateOf(task.id, rev) == 'offered', 'offered');
      await b.services.transfer.itemsSettled;
      await b.tasks.accept(taskId: task.id, inputRevision: rev);
      await b.tasks.start(taskId: task.id, inputRevision: rev);
      await expectLater(
        b.researchTasks.submitResult(
          task.id,
          rev,
          resultFile(task, taskId: 'other'),
        ),
        throwsFormatException,
      );
      await expectLater(
        b.researchTasks.submitResult(
          task.id,
          rev,
          resultFile(task, revision: 9),
        ),
        throwsFormatException,
      );
      // A small archive whose result.json inflates past 1 MB is refused
      // before it is read into memory.
      final padded = utf8.encode(
        jsonEncode({
          'taskId': task.id,
          'taskRevision': task.revision,
          'logs': List.filled(40000, 'x' * 40),
        }),
      );
      final zip = File(p.join(root.path, 'bomb.zip'))
        ..writeAsBytesSync(
          ZipEncoder().encodeBytes(
            Archive()..addFile(ArchiveFile.bytes('result.json', padded)),
          ),
        );
      expect(zip.lengthSync(), lessThan(100 * 1024));
      await expectLater(
        b.researchTasks.submitResult(task.id, rev, zip.path),
        throwsFormatException,
      );
      expect(b.tasks.stateOf(task.id, rev), 'running');
      expect(a.researchTasks.hasReturnedResult(task.id, rev), isFalse);
    },
  );

  test('restart keeps running and does not import twice', () async {
    final task = await makeTask(a);
    final rev = '${task.revision}';
    // Build the offer envelope an origin would send, without a network.
    final temp = Directory('${root.path}/pkg')..createSync();
    final zip = await ResearchExchange(a.research!.store)
        .exportTask(task, temp.path);
    final bytes = File(zip).readAsBytesSync();
    final envelope = {
      'muyon': 'muyon-task-v1',
      'type': 'offer',
      'taskId': task.id,
      'inputRevision': rev,
      'idempotencyKey': 'idem-1',
      'deviceId': 'origin',
      'attachment': {
        'kind': 'research-task',
        'name': 'task.zip',
        'sha256': sha256Hex(bytes),
        'dataBase64': base64Encode(bytes),
      },
    };
    await connect(); // accepting announces to the paired device
    await b.tasks.receive(envelope);
    expect(b.workspaces.all(), isEmpty);
    await b.tasks.accept(taskId: task.id, inputRevision: rev);
    await b.tasks.start(taskId: task.id, inputRevision: rev);
    expect(b.tasks.stateOf(task.id, rev), 'running');
    expect(b.workspaces.all(), hasLength(1));

    await b.close();
    b = await MuyonHost.open('${root.path}/b');
    expect(b.tasks.stateOf(task.id, rev), 'running');
    await b.tasks.start(taskId: task.id, inputRevision: rev);
    expect(b.workspaces.all(), hasLength(1));
    await b.activateResearch();
    expect(
      b.research!.store.tasks(b.research!.store.projects().single.id),
      hasLength(1),
    );
    // The same offer again (a duplicate delivery) neither re-imports nor re-saves.
    await b.tasks.receive(envelope);
    expect(b.workspaces.all(), hasLength(1));
  });

  test('a task package that does not match the offer is rejected', () async {
    final task = await makeTask(a);
    final temp = Directory('${root.path}/pkg')..createSync();
    final zip = await ResearchExchange(a.research!.store)
        .exportTask(task, temp.path);
    final bytes = File(zip).readAsBytesSync();
    await connect();
    await b.tasks.receive({
      'muyon': 'muyon-task-v1',
      'type': 'offer',
      'taskId': 'a-different-task',
      'inputRevision': '${task.revision}',
      'idempotencyKey': 'idem-2',
      'deviceId': 'origin',
      'attachment': {
        'kind': 'research-task',
        'name': 'task.zip',
        'sha256': sha256Hex(bytes),
        'dataBase64': base64Encode(bytes),
      },
    });
    await b.tasks.accept(
      taskId: 'a-different-task',
      inputRevision: '${task.revision}',
    );
    await expectLater(
      b.tasks.start(
        taskId: 'a-different-task',
        inputRevision: '${task.revision}',
      ),
      throwsA(anything),
    );
    expect(b.workspaces.all(), isEmpty);
    expect(b.tasks.stateOf('a-different-task', '${task.revision}'), 'failed');
  });

  test('an offer with a tampered package digest carries no package', () async {
    await b.tasks.receive({
      'muyon': 'muyon-task-v1',
      'type': 'offer',
      'taskId': 't',
      'inputRevision': '1',
      'idempotencyKey': 'idem-3',
      'deviceId': 'origin',
      'attachment': {
        'kind': 'research-task',
        'name': 'task.zip',
        'sha256': '0' * 64,
        'dataBase64': base64Encode([1, 2, 3]),
      },
    });
    expect(b.researchTasks.isResearchTask('t', '1'), isFalse);
  });
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
