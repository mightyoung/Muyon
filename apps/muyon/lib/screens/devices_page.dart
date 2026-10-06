import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:supplier_core/lan.dart';

import '../app/bootstrap.dart';
import '../services/transfer/task_coordinator.dart';
import '../services/transfer/transfer_service.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.host});
  final MuyonHost host;
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final text = TextEditingController();
  final files = <String>[];
  Timer? refresh;
  bool busy = false;
  final peerViews = <String, String>{};
  int sentBytes = 0, totalBytes = 0;
  String? status, error;
  MuyonHost get host => widget.host;
  @override
  void initState() {
    super.initState();
    refresh = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    refresh?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> run(String label, Future<String> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      sentBytes = totalBytes = 0;
      error = null;
      status = label;
    });
    try {
      final result = await host.runPlatformOperation(label, operation);
      if (mounted) setState(() => status = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickAttachments() async {
    final selected = await FilePicker.pickFiles();
    if (mounted) {
      setState(
        () => files.addAll(
          selected.where((f) => f.path != null).map((f) => f.path!),
        ),
      );
    }
  }

  Future<void> send(LanPeer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发送给 ${peer.name}'),
        content: SingleChildScrollView(
          child: Text(
            '目的地：${peer.address}:${peer.port}\n'
            '核对指纹：${peer.fingerprint}\n'
            '文字/链接：${text.text}\n'
            '附件：${files.map(p.basename).join('、')}\n'
            '仅发给已配对设备。送达和附件收妥不等于业务导入或人工接纳。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发送这一次'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final message = text.text;
    final attachments = List<String>.of(files);
    await run('发送文字与附件', () async {
      final package = await _packageForSend(attachments, message);
      await host.services.transfer.send(
        peer,
        package,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() {
              sentBytes = sent;
              totalBytes = total;
              status = sent == total ? '字节已发出，等待接收设备确认…' : '正在发送文字与附件…';
            });
          }
        },
      );
      if (mounted) {
        text.clear();
        files.clear();
      }
      return '接收设备已收到待核验文件；业务导入仍由接收方确认。';
    });
  }

  Future<void> exportPackage() => run('导出设备数据包', () async {
    final package = await host.services.transfer.exportFiles(
      List<String>.of(files),
      message: text.text.isEmpty ? null : text.text,
    );
    final bytes = await File(package).readAsBytes();
    final target = await FilePicker.saveFile(
      dialogTitle: '选择传递渠道或保存位置',
      fileName: p.basename(package),
      bytes: bytes,
    );
    if (target == null) return '已取消保存，私有出站包保留。';
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(target).writeAsBytes(bytes, flush: true);
    }
    return '已保存数据包：$target。可通过自选渠道交给另一设备。';
  });
  Future<String> _packageForSend(
    List<String> attachments,
    String message,
  ) async {
    if (message.isEmpty && attachments.length == 1) {
      final bytes = await File(attachments.single).readAsBytes();
      if (TransferService.isResearchPackage(bytes)) return attachments.single;
    }
    return host.services.transfer.exportFiles(
      attachments,
      message: message.isEmpty ? null : message,
    );
  }

  Future<void> accept(String path) => run('核验接收数据包', () async {
    final tracked = host.services.transfer.items().where(
      (item) => item.path == path,
    );
    if (tracked.isNotEmpty) return _decideTracked(tracked.first);
    final receipt = await host.services.transfer.importPackage(path);
    host.services.transfer.pendingReceivedPaths.remove(path);
    return '完整性核验完成；接收记录 ${receipt.id}，${receipt.paths.length} 个文件。未自动导入业务。';
  });

  Future<String> _decideTracked(TransferItem item) async {
    final path = item.path;
    if (item.acceptance != 'accepted') {
      await host.services.transfer.acceptItem(item.id);
      return '已人工接纳。送达和收妥不会导入业务，也不会授予执行权限。';
    }
    if (path != null &&
        TransferService.isResearchPackage(await File(path).readAsBytes())) {
      return '科研包已接纳。导入只交给科研回调，此页不执行包内内容。';
    }
    if (!item.imported && path != null) {
      final receipt = await host.services.transfer.importPackage(path);
      host.services.transfer.pendingReceivedPaths.remove(path);
      return '已导入业务；接收记录 ${receipt.id}。';
    }
    return '该文件已经导入。';
  }

  Future<void> acceptTask(TaskRecord task) =>
      run('接受任务 ${task.taskId}', () async {
        final claimed = await host.tasks.accept(
          taskId: task.taskId,
          inputRevision: task.inputRevision,
        );
        return claimed ? '已在本机接受。接收本身没有执行。' : '没有成为执行者。任务仍由当前所有者负责。';
      });

  bool _research(TaskRecord task) =>
      host.researchTasks.isResearchTask(task.taskId, task.inputRevision);

  Future<void> startTask(TaskRecord task) async {
    final research = _research(task);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(research ? '导入本机科研' : '在本机执行'),
        content: Text(
          research
              ? '只有这一次确认才授权把这个研究任务说明导入本机科研模块。收到提议、接受所有权都不会导入，'
                    '导入后也不会运行任何东西：由你在科研页自己完成，再导出结果并回传。'
              : '只有这一次确认才授权本机执行。收到提议、接受所有权都不会执行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(research ? '授权导入' : '授权执行'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await run(
      research ? '导入研究任务 ${task.taskId}' : '执行任务 ${task.taskId}',
      () async {
        await host.tasks.start(
          taskId: task.taskId,
          inputRevision: task.inputRevision,
        );
        return research
            ? '已导入本机科研，任务进入“执行中”，但没有运行任何东西。完成后请导出结果并在这里提交。'
            : '本机执行已结束。对方是否看到结果取决于对方是否在线。';
      },
    );
  }

  /// The person exported a result from the research page; send it back.
  Future<void> submitTaskResult(TaskRecord task) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择科研页导出的结果（.zip 或 .json）',
      allowedExtensions: const ['zip', 'json'],
      type: FileType.custom,
    );
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;
    await run('提交结果 ${task.taskId}', () async {
      await host.researchTasks.submitResult(
        task.taskId,
        task.inputRevision,
        path,
      );
      return '结果已提交并发给发起设备。对方是否收到取决于对方是否在线；本机已记为完成。';
    });
  }

  Future<void> importTaskResult(TaskRecord task) =>
      run('导入结果 ${task.taskId}', () async {
        final runId = await host.researchTasks.importReturnedResult(
          task.taskId,
          task.inputRevision,
        );
        return '结果已接到原任务上（运行 $runId），等待你在科研页人工评估；没有被当作已验证的结论。';
      });

  Future<void> offerResearchTask() async {
    await host.activateResearch();
    final store = host.research?.store;
    if (store == null) {
      setState(() => error = host.researchError ?? '科研模块不可用');
      return;
    }
    final tasks = [
      for (final project in store.projects()) ...store.tasks(project.id),
    ];
    if (!mounted) return;
    final chosen = await showDialog<ResearchTask>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('提议哪个研究任务？'),
        children: [
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('科研模块里还没有任务。先在科研页创建任务。'),
            ),
          for (final task in tasks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, task),
              child: Text('${task.title} · 版本 ${task.revision}'),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提议给已配对设备'),
        content: Text(
          '将把「${chosen.title}」版本 ${chosen.revision} 的任务说明包发给所有在线的已配对设备。'
          '说明包只含目标和参数，不含代码或数据，对方不会自动导入或运行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('提议'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run('提议研究任务', () async {
      await host.researchTasks.offer(chosen);
      return '已提议。对方接受并授权导入之前，什么都不会发生。';
    });
  }

  String _taskLocalLabel(TaskRecord task) {
    if (_research(task) && task.state == 'running') {
      return '已导入本机科研，等待你完成并回传结果（没有在运行）';
    }
    if (task.state == 'succeeded' && task.ownerDeviceId != null) {
      final self = task.ownerDeviceId == host.workspaces.setting('deviceId');
      if (self && _research(task)) return '结果已提交给发起设备';
      if (!self &&
          host.researchTasks.hasReturnedResult(
            task.taskId,
            task.inputRevision,
          )) {
        return host.researchTasks.resultImported(
              task.taskId,
              task.inputRevision,
            )
            ? '收到结果，已接到原任务'
            : '收到对方回传的结果，尚未导入科研';
      }
    }
    return localTaskLabel(task.state, task.ownerDeviceId);
  }

  Future<void> queryTask(TaskRecord task) => run('查询 ${task.taskId}', () async {
    final view = await host.tasks.queryPeer(
      taskId: task.taskId,
      inputRevision: task.inputRevision,
    );
    peerViews['${task.taskId}\u0000${task.inputRevision}'] = view;
    return '对方：${peerTaskLabel(view)}。本机记录没有被改成失败或完成。';
  });

  String _stateLine(TransferItem item) {
    final delivered = item.delivered ? '已送达' : '未送达';
    final durable = item.attachmentState == 'durable'
        ? '附件已收妥 ${item.attachmentLength ?? 0} 字节'
        : '附件未收妥';
    final imported = item.imported ? '已导入' : '未导入';
    final read = item.readAt == null ? '未读' : '已读';
    final accepted = item.acceptance == 'accepted' ? '已接纳' : '待接纳';
    return '$delivered · $durable · $imported · $read · $accepted · 不授予执行';
  }

  Future<void> pair(LanPeer peer) async {
    final code = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('核对 ${peer.name}'),
        content: TextField(
          controller: code,
          decoration: const InputDecoration(labelText: '对方屏幕上的核对码或二维码内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, code.text),
            child: const Text('确认配对'),
          ),
        ],
      ),
    );
    code.dispose();
    if (confirmed == null || confirmed.trim().isEmpty) return;
    await run('配对 ${peer.name}', () async {
      final live = await host.services.transfer.probe(
        peer.address,
        port: peer.port,
      );
      host.services.transfer.confirmPeer(
        fingerprint: live.fingerprint,
        confirmedCode: confirmed,
        certificatePem: live.certificatePem,
      );
      return '已配对 ${live.name}。设备名和同一网络都不代表信任。';
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('本人设备与在线通信', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        '仅在双方当面核对指纹后通信。发现和设备名不是信任。收到的文件进入待核验区，不会自动导入，也不授予执行权限。对方不在线时没有中继。',
      ),
      SwitchListTile(
        title: const Text('启用当前设备在线发现与接收'),
        subtitle: Text(
          '${host.workspaces.setting('personalName') ?? 'Muyon'} · ${host.workspaces.setting('deviceId')}',
        ),
        value: host.services.transfer.listening,
        onChanged: busy
            ? null
            : (value) => run(value ? '开启设备通信' : '关闭设备通信', () async {
                if (value) {
                  await host.services.transfer.start(
                    deviceId: host.workspaces.setting('deviceId') as String,
                    deviceName:
                        host.workspaces.setting('personalName') as String? ??
                        'Muyon',
                  );
                } else {
                  await host.services.transfer.close();
                }
                return value ? '等待在线设备；尚未配对，未发送私人资料。' : '通信已关闭。';
              }),
      ),
      if (host.services.transfer.localShortCode case final String code)
        ListTile(
          title: const Text('本机核对码'),
          subtitle: SelectableText(
            '$code\n${host.services.transfer.localQrPayload}',
          ),
        ),
      if (busy)
        LinearProgressIndicator(
          value: totalBytes > 0 ? sentBytes / totalBytes : null,
        ),
      if (totalBytes > 0) Text('$sentBytes / $totalBytes 字节；接收完成另以对方回执为准'),
      if (status != null) SelectableText(status!),
      if (error != null)
        SelectableText(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const Divider(),
      TextField(
        controller: text,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(labelText: '一对一文字或链接'),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : pickAttachments,
            icon: const Icon(Icons.attach_file),
            label: const Text('选择附件'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : exportPackage,
            icon: const Icon(Icons.save_alt),
            label: const Text('导出数据包'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final chosen = await FilePicker.pickFiles();
                    if (chosen.firstOrNull?.path case final String path) {
                      await accept(path);
                    }
                  },
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('导入收到的数据包'),
          ),
        ],
      ),
      for (final path in files)
        ListTile(
          title: Text(p.basename(path)),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: busy ? null : () => setState(() => files.remove(path)),
          ),
        ),
      const Divider(),
      const Text('可达设备'),
      if (host.services.transfer.peers.isEmpty)
        const ListTile(
          title: Text('尚未发现在线设备'),
          subtitle: Text('双方需开启通信并处于可互通网络；不提供离线消息服务器。'),
        ),
      for (final peer in host.services.transfer.peers)
        ListTile(
          leading: const Icon(Icons.devices),
          title: Text(peer.name),
          subtitle: Text(
            host.services.transfer.isPaired(peer)
                ? '${peer.address}:${peer.port}\n已配对 · 最后可达：${peer.seen.toLocal()}'
                : '${peer.address}:${peer.port}\n未配对。宣告指纹不能当作身份。',
          ),
          isThreeLine: true,
          trailing: Wrap(
            children: [
              if (!host.services.transfer.isPaired(peer))
                IconButton(
                  tooltip: '核对并配对',
                  icon: const Icon(Icons.verified_user_outlined),
                  onPressed: busy ? null : () => pair(peer),
                )
              else ...[
                IconButton(
                  tooltip: '撤销配对',
                  icon: const Icon(Icons.link_off),
                  onPressed: busy
                      ? null
                      : () => run('撤销 ${peer.name}', () async {
                          host.services.transfer.revoke(peer.fingerprint);
                          return '已撤销 ${peer.name}。之后的连接会被拒绝。';
                        }),
                ),
                IconButton(
                  tooltip: '发送给此设备',
                  icon: const Icon(Icons.send_outlined),
                  onPressed: busy ? null : () => send(peer),
                ),
              ],
            ],
          ),
        ),
      const Divider(),
      const Text('跨设备任务'),
      const Text('收到提议不会执行。所有权、执行和对方是否可达是分开的状态。'),
      OutlinedButton.icon(
        onPressed: busy ? null : offerResearchTask,
        icon: const Icon(Icons.science_outlined),
        label: const Text('提议研究任务'),
      ),
      if (host.tasks.list().isEmpty) const ListTile(title: Text('还没有跨设备任务')),
      for (final task in host.tasks.list())
        ListTile(
          title: Text('${task.taskId} · ${task.inputRevision}'),
          subtitle: Text(
            '本机：${_taskLocalLabel(task)}\n'
            '对方：${peerTaskLabel(peerViews['${task.taskId}\u0000${task.inputRevision}'])}',
          ),
          isThreeLine: true,
          trailing: Wrap(
            children: [
              TextButton(
                onPressed: busy ? null : () => queryTask(task),
                child: const Text('查询对方'),
              ),
              if (task.state == 'offered' || task.state == 'accepted')
                TextButton(
                  onPressed: busy ? null : () => acceptTask(task),
                  child: const Text('接受'),
                ),
              if (task.state == 'accepted' &&
                  task.ownerDeviceId == host.workspaces.setting('deviceId'))
                TextButton(
                  onPressed: busy ? null : () => startTask(task),
                  child: Text(_research(task) ? '授权导入科研' : '授权执行'),
                ),
              if (task.state == 'running' &&
                  _research(task) &&
                  task.ownerDeviceId == host.workspaces.setting('deviceId'))
                TextButton(
                  onPressed: busy ? null : () => submitTaskResult(task),
                  child: const Text('提交结果'),
                ),
              if (task.state == 'succeeded' &&
                  host.researchTasks.hasReturnedResult(
                    task.taskId,
                    task.inputRevision,
                  ) &&
                  !host.researchTasks.resultImported(
                    task.taskId,
                    task.inputRevision,
                  ))
                TextButton(
                  onPressed: busy ? null : () => importTaskResult(task),
                  child: const Text('导入结果到科研'),
                ),
            ],
          ),
        ),
      const Divider(),
      const Text('收到的文件'),
      if (host.services.transfer.items().isEmpty)
        const ListTile(title: Text('还没有已核验的接收记录')),
      for (final item in host.services.transfer.items())
        ListTile(
          title: Text(p.basename(item.path ?? item.id)),
          subtitle: Text(_stateLine(item)),
          isThreeLine: true,
          trailing: Wrap(
            children: [
              if (item.readAt == null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run('标为已读', () async {
                          await host.services.transfer.markRead(item.id);
                          return '已读。导入和接纳状态没有改变。';
                        }),
                  child: const Text('标为已读'),
                ),
              if (item.acceptance != 'accepted')
                TextButton(
                  onPressed: busy || item.path == null
                      ? null
                      : () => accept(item.path!),
                  child: const Text('接纳'),
                )
              else if (!item.imported && item.path != null)
                TextButton(
                  onPressed: busy ? null : () => accept(item.path!),
                  child: const Text('导入'),
                ),
            ],
          ),
        ),
      for (final path
          in List<String>.of(host.services.transfer.pendingReceivedPaths).where(
            (path) => !host.services.transfer.items().any(
              (item) => item.path == path,
            ),
          ))
        ListTile(
          title: Text(p.basename(path)),
          subtitle: const Text('未完成核验，不会记为附件已收妥，也不会导入。'),
          trailing: TextButton(
            onPressed: busy ? null : () => accept(path),
            child: const Text('核验这份文件'),
          ),
        ),
      const Divider(),
      const Text('收到的文字与附件'),
      for (final receipt in host.services.transfer.receipts())
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${receipt.receivedAt.toLocal()} · ${receipt.id}'),
              ),
              for (final path in receipt.paths)
                path.endsWith('/message.txt')
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: FutureBuilder<String>(
                          future: File(path).readAsString(),
                          builder: (_, snapshot) =>
                              SelectableText(snapshot.data ?? '读取消息…'),
                        ),
                      )
                    : ListTile(
                        title: Text(p.basename(path)),
                        subtitle: SelectableText(path),
                      ),
            ],
          ),
        ),
    ],
  );
}
