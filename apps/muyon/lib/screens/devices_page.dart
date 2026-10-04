import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/lan.dart';

import '../app/bootstrap.dart';
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
