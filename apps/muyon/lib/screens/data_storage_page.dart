import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:path/path.dart' as p;

import '../platform/backup_service.dart';
import 'storage_status.dart';

/// Where backups are written and read; replaced in tests.
typedef PickDirectory = Future<String?> Function(String title);

Future<String?> pickDirectoryWithDialog(String title) =>
    FilePicker.getDirectoryPath(dialogTitle: title);

/// 数据与存储: module availability, database health, projection lag, and
/// backup / verify / restore.
class DataStoragePage extends StatefulWidget {
  const DataStoragePage({
    super.key,
    required this.readStatus,
    required this.createBackup,
    required this.restore,
    this.pickDirectory = pickDirectoryWithDialog,
    this.verify = BackupService.verify,
    this.clock = DateTime.now,
    this.dataFlow,
    this.mcpServers,
  });

  final StorageStatus Function() readStatus;

  /// Writes a verified-consistent backup into the given new directory.
  final Future<Map<String, Object?>> Function(String targetDir) createBackup;

  /// Closes the host, restores from a verified backup, and reopens. Only called
  /// after the person confirmed the dialog.
  final Future<void> Function(String backupDir) restore;
  final PickDirectory pickDirectory;
  final Future<List<String>> Function(String backupDir) verify;
  final DateTime Function() clock;

  /// Entry points owned by the shell: 数据去向 and MCP server pages. Passed as
  /// widgets so this page keeps no direct host dependency.
  final Widget? dataFlow;
  final Widget? mcpServers;

  @override
  State<DataStoragePage> createState() => _DataStoragePageState();
}

enum _Outcome { none, ok, failed }

class _DataStoragePageState extends State<DataStoragePage> {
  late StorageStatus status = widget.readStatus();
  bool busy = false;
  _Outcome outcome = _Outcome.none;
  String? headline;
  List<String> details = const [];

  void _show(_Outcome result, String title, [List<String> lines = const []]) {
    if (!mounted) return;
    setState(() {
      outcome = result;
      headline = title;
      details = lines;
    });
  }

  Future<void> _run(Future<void> Function() job, {bool refresh = true}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await job();
    } catch (error) {
      _show(_Outcome.failed, '操作失败', ['$error']);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          if (refresh) status = widget.readStatus();
        });
      }
    }
  }

  Future<void> _create() => _run(() async {
    final parent = await widget.pickDirectory('选择保存备份的位置');
    if (parent == null) return;
    final stamp = widget.clock().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final target = p.join(parent, 'muyon-backup-$stamp');
    final manifest = await widget.createBackup(target);
    final entries = (manifest['entries'] as List?)?.length;
    _show(_Outcome.ok, '备份已创建', [
      target,
      if (entries != null) '共 $entries 个文件。建议随后用“校验备份”确认。',
    ]);
  });

  Future<void> _verify() => _run(() async {
    final dir = await widget.pickDirectory('选择要校验的备份');
    if (dir == null) return;
    final problems = await widget.verify(dir);
    if (problems.isEmpty) {
      _show(_Outcome.ok, '校验通过', [dir, '清单中的文件齐全、未被改动，数据库完整性检查通过。']);
    } else {
      _show(_Outcome.failed, '校验未通过，发现 ${problems.length} 个问题', problems);
    }
  });

  Future<void> _restore() async {
    String? verified;
    await _run(() async {
      final dir = await widget.pickDirectory('选择要恢复的备份');
      if (dir == null) return;
      final problems = await widget.verify(dir);
      if (problems.isNotEmpty) {
        _show(_Outcome.failed, '备份未通过校验，未做任何恢复', problems);
        return;
      }
      verified = dir;
    });
    final dir = verified;
    if (dir == null || !mounted) return;
    final root = status.rootPath;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从备份恢复'),
        content: SingleChildScrollView(
          child: Text(
            '恢复将关闭并重启 Muyon。\n\n'
            '当前数据会移到 $root.before-restore-*，不会被删除；'
            '之后可手动移回。\n\n备份：$dir',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('关闭并恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The host is closed and replaced by now; do not read its status again.
    await _run(() => widget.restore(dir), refresh: false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(MuyonTokens.space4),
      children: [
        if (busy) const LinearProgressIndicator(),
        Text('数据与存储', style: theme.textTheme.titleLarge),
        const SizedBox(height: MuyonTokens.space4),
        _Section(title: '数据目录', child: SelectableText(status.rootPath)),
        _Section(
          title: '模块状态',
          child: status.unavailableModules.isEmpty
              ? const _Quiet('所有已登记模块可用。')
              : Column(
                  children: [
                    for (final entry in status.unavailableModules.entries)
                      _Row(
                        label: entry.key,
                        badge: '不可用',
                        bad: true,
                        detail: entry.value,
                      ),
                  ],
                ),
        ),
        _Section(
          title: '数据库',
          child: status.catalog.isEmpty
              ? const _Quiet('尚无数据库记录。')
              : Column(
                  children: [
                    for (final row in status.catalog)
                      _Row(
                        label: row.moduleId,
                        badge: row.blocked ? '已阻止' : '就绪',
                        bad: row.blocked,
                        detail: [
                          '版本 ${row.observedVersion ?? '未知'} / 目标 ${row.targetVersion}',
                          if (row.lastError != null) row.lastError!,
                        ].join('\n'),
                      ),
                  ],
                ),
        ),
        _Section(
          title: '投影滞后',
          child: status.projectionErrors.isEmpty
              ? const _Quiet('未发现投影错误；业务数据不受投影影响。')
              : Column(
                  children: [
                    for (final entry in status.projectionErrors.entries)
                      _Row(
                        label: entry.key,
                        badge: '滞后',
                        bad: true,
                        detail: '${entry.value}\n业务数据完好，仅跨模块检索与总览可能过期。',
                      ),
                  ],
                ),
        ),
        _Section(
          title: '备份与恢复',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Quiet('备份不含 OCR 模型等可重新下载的文件。恢复会关闭并重启 Muyon，当前数据移到旁边保留。'),
              const SizedBox(height: MuyonTokens.space3),
              Wrap(
                spacing: MuyonTokens.space2,
                runSpacing: MuyonTokens.space2,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : _create,
                    icon: const Icon(Icons.save_alt_outlined),
                    label: const Text('创建备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _verify,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('校验备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _restore,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('从备份恢复'),
                  ),
                ],
              ),
              if (outcome != _Outcome.none) ...[
                const SizedBox(height: MuyonTokens.space3),
                _Result(
                  ok: outcome == _Outcome.ok,
                  title: headline!,
                  lines: details,
                  tokens: tokens,
                ),
              ],
            ],
          ),
        ),
        if (widget.dataFlow != null || widget.mcpServers != null)
          _Section(
            title: '数据去向与外部工具',
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  if (widget.dataFlow != null)
                    _entry(
                      context,
                      '数据去向',
                      '模型请求与工具调用实际发到了哪里',
                      widget.dataFlow!,
                    ),
                  if (widget.mcpServers != null)
                    _entry(
                      context,
                      'MCP 服务器',
                      '添加并连接外部工具服务器',
                      widget.mcpServers!,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _entry(
    BuildContext context,
    String title,
    String detail,
    Widget body,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(detail),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: body,
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyonTokens.space4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.rule),
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: MuyonTokens.space2),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall);
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.badge,
    required this.bad,
    required this.detail,
  });
  final String label;
  final String badge;
  final bool bad;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MuyonTokens.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MuyonTokens.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: theme.textTheme.bodyLarge),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: bad ? tokens.redBg : tokens.greenBg,
                  borderRadius: BorderRadius.circular(MuyonTokens.radius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MuyonTokens.space2,
                    vertical: MuyonTokens.space1 / 2,
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: bad ? tokens.red : tokens.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SelectableText(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.ok,
    required this.title,
    required this.lines,
    required this.tokens,
  });
  final bool ok;
  final String title;
  final List<String> lines;
  final MuyonTokens tokens;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: ok ? tokens.greenBg : tokens.redBg,
        borderRadius: BorderRadius.circular(MuyonTokens.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(MuyonTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: ok ? tokens.green : tokens.red),
            ),
            for (final line in lines)
              SelectableText(
                line,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    ),
  );
}
