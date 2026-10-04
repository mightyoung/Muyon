import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/lan.dart';

import '../app/bootstrap.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.host});
  final MuSpaceHost host;
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
  MuSpaceHost get host => widget.host;
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
            '目的地：${peer.address}:${peer.port}\n设备 ID：${peer.id}\n文字/链接：${text.text}\n附件：${files.map(p.basename).join('、')}\n局域网明文传输，接收方须核验接纳。',
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
      final package = await host.services.transfer.exportFiles(
        attachments,
        message: message.isEmpty ? null : message,
      );
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
  Future<void> accept(String path) => run('核验接收数据包', () async {
    final receipt = await host.services.transfer.importPackage(path);
    host.services.transfer.pendingReceivedPaths.remove(path);
    return '完整性核验完成；接收记录 ${receipt.id}，${receipt.paths.length} 个文件。未自动导入业务。';
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('本人设备与在线通信', style: TextStyle(fontSize: 22)),
      const Text(
        '仅在本人可信局域网启用。当前连接为明文，设备名称不是身份认证；收到的文件进入待核验区。跨网络可以使用数据包和自选传递渠道。',
      ),
      SwitchListTile(
        title: const Text('启用当前设备在线发现与接收'),
        subtitle: Text(
          '${host.workspaces.setting('personalName') ?? 'Miyono'} · ${host.workspaces.setting('deviceId')}',
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
                        'Miyono',
                  );
                } else {
                  await host.services.transfer.close();
                }
                return value ? '等待在线设备；未发送私人资料。' : '通信已关闭。';
              }),
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
            '${peer.address}:${peer.port}\n最后可达：${peer.seen.toLocal()}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: '发送给此设备',
            icon: const Icon(Icons.send_outlined),
            onPressed: busy ? null : () => send(peer),
          ),
        ),
      const Divider(),
      const Text('待核验接收'),
      for (final path in List<String>.of(
        host.services.transfer.pendingReceivedPaths,
      ))
        ListTile(
          title: Text(p.basename(path)),
          subtitle: const Text('尚未校验，未接纳到业务数据。'),
          trailing: TextButton(
            onPressed: busy ? null : () => accept(path),
            child: const Text('接收并核验'),
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
