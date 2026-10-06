import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'models.dart';
import 'prototype_store.dart';
import 'prototype_web_page.dart';
import 'web_guard.dart';

typedef PickBuildDirectory = Future<String?> Function();

Future<String?> pickBuildDirectory() =>
    FilePicker.getDirectoryPath(dialogTitle: '选择原型构建目录（含 index.html）');

const scopeNotice =
    '这里只展示导入的单页原型构建产物，用于评审与收集反馈；'
    '不代表完整业务系统已迁入 Muyon。';

class PrototypeHome extends StatefulWidget {
  const PrototypeHome({
    super.key,
    required this.store,
    this.pickDirectory = pickBuildDirectory,
    this.webViewBuilder = defaultPrototypeWebView,
  });
  final PrototypeStore store;
  final PickBuildDirectory pickDirectory;
  final PrototypeWebViewBuilder webViewBuilder;
  @override
  State<PrototypeHome> createState() => _PrototypeHomeState();
}

class _PrototypeHomeState extends State<PrototypeHome> {
  bool busy = false;
  String? error;

  Future<void> _import() async {
    final dir = await widget.pickDirectory();
    if (dir == null || !mounted) return;
    final title = await _askTitle(context, dir);
    if (title == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.importBuild(sourceDir: dir, title: title);
    } catch (e) {
      error = '导入失败：$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.store.pages();
    final tokens = MuyonTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('原型页面')),
      body: ListView(
        padding: const EdgeInsets.all(MuyonTokens.space4),
        children: [
          if (busy) const LinearProgressIndicator(),
          Text(scopeNotice, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: MuyonTokens.space3),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: busy ? null : _import,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('导入原型构建'),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space3),
              child: SelectableText(
                error!,
                style: TextStyle(color: tokens.red),
              ),
            ),
          const SizedBox(height: MuyonTokens.space4),
          if (pages.isEmpty)
            Text(
              '还没有原型页面。导入一个已构建的前端目录开始。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          for (final page in pages)
            Card(
              child: ListTile(
                title: Text(page.title),
                subtitle: Text(
                  '${widget.store.versions(page.id).length} 个版本 · '
                  '${widget.store.feedback(page.id).length} 条反馈',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PrototypeDetail(
                        store: widget.store,
                        page: page,
                        pickDirectory: widget.pickDirectory,
                        webViewBuilder: widget.webViewBuilder,
                      ),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<String?> _askTitle(BuildContext context, String dir) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TitleDialog(
        initial: dir
            .split(RegExp(r'[\\/]'))
            .where((s) => s.isNotEmpty)
            .lastOrNull,
      ),
    );

/// Owns its controller so it is disposed only after the exit animation.
class _TitleDialog extends StatefulWidget {
  const _TitleDialog({this.initial});
  final String? initial;
  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('页面标题'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: '标题'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('导入'),
      ),
    ],
  );
}

class PrototypeDetail extends StatefulWidget {
  const PrototypeDetail({
    super.key,
    required this.store,
    required this.page,
    required this.pickDirectory,
    required this.webViewBuilder,
  });
  final PrototypeStore store;
  final PrototypePage page;
  final PickBuildDirectory pickDirectory;
  final PrototypeWebViewBuilder webViewBuilder;
  @override
  State<PrototypeDetail> createState() => _PrototypeDetailState();
}

class _PrototypeDetailState extends State<PrototypeDetail> {
  final note = TextEditingController();
  String? selected;
  String? error;
  bool busy = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _newVersion() async {
    final dir = await widget.pickDirectory();
    if (dir == null) return;
    await _run(() async {
      final v = await widget.store.importBuild(
        sourceDir: dir,
        pageId: widget.page.id,
      );
      selected = v.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final versions = widget.store.versions(widget.page.id);
    final feedback = widget.store.feedback(widget.page.id);
    final current =
        versions.where((v) => v.id == selected).firstOrNull ??
        versions.firstOrNull;
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.page.title)),
      body: ListView(
        padding: const EdgeInsets.all(MuyonTokens.space4),
        children: [
          if (busy) const LinearProgressIndicator(),
          Text('版本', style: theme.textTheme.titleSmall),
          RadioGroup<String>(
            groupValue: current?.id,
            onChanged: (id) => setState(() => selected = id),
            child: Column(
              children: [
                for (final v in versions)
                  RadioListTile<String>(
                    value: v.id,
                    title: Text(v.label),
                    subtitle: Text(
                      '${v.fileCount} 个文件 · 摘要 ${v.digest.substring(0, 12)}',
                    ),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: MuyonTokens.space2,
            runSpacing: MuyonTokens.space2,
            children: [
              FilledButton.icon(
                onPressed: current == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PrototypeWebPage(
                            store: widget.store,
                            version: current,
                            title: widget.page.title,
                            webViewBuilder: widget.webViewBuilder,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.open_in_browser_outlined),
                label: Text('打开 ${current?.label ?? ''}'.trim()),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : _newVersion,
                icon: const Icon(Icons.add),
                label: const Text('导入新版本'),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space3),
              child: SelectableText(
                error!,
                style: TextStyle(color: tokens.red),
              ),
            ),
          const SizedBox(height: MuyonTokens.space5),
          Text('反馈', style: theme.textTheme.titleSmall),
          const SizedBox(height: MuyonTokens.space2),
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: '针对 ${current?.label ?? '当前版本'} 的反馈',
            ),
          ),
          const SizedBox(height: MuyonTokens.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: busy || current == null
                  ? null
                  : () => _run(() async {
                      await widget.store.addFeedback(
                        versionId: current.id,
                        text: note.text,
                      );
                      note.clear();
                    }),
              child: const Text('提交反馈'),
            ),
          ),
          if (feedback.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space3),
              child: Text('暂无反馈。', style: theme.textTheme.bodySmall),
            ),
          for (final item in feedback)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: SelectableText(item.text),
              subtitle: Text(
                '${widget.store.version(item.versionId)?.label ?? '?'} · '
                '${item.createdAt.toLocal().toString().substring(0, 16)}',
              ),
            ),
        ],
      ),
    );
  }
}

class PrototypeWebPage extends StatefulWidget {
  const PrototypeWebPage({
    super.key,
    required this.store,
    required this.version,
    required this.title,
    required this.webViewBuilder,
  });
  final PrototypeStore store;
  final PrototypeVersion version;
  final String title;
  final PrototypeWebViewBuilder webViewBuilder;
  @override
  State<PrototypeWebPage> createState() => _PrototypeWebPageState();
}

class _PrototypeWebPageState extends State<PrototypeWebPage> {
  late final spec = widget.store.specFor(
    widget.version,
    bridgeChannels: {feedbackChannel},
  );
  late final guard = PrototypeWebGuard(spec);
  String? blocked;

  Future<void> _bridge(String channel, List<Object?> args) async {
    if (channel != feedbackChannel || !mounted) return;
    final text = args.isNotEmpty && args.first is String
        ? (args.first as String)
        : '';
    if (text.trim().isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('原型页面请求提交反馈'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存反馈'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.addFeedback(versionId: widget.version.id, text: text);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.title} · ${widget.version.label}')),
    body: Column(
      children: [
        if (blocked != null)
          MaterialBanner(
            content: Text('已拦截越界访问：$blocked'),
            actions: [
              TextButton(
                onPressed: () => setState(() => blocked = null),
                child: const Text('知道了'),
              ),
            ],
          ),
        Expanded(
          child: widget.webViewBuilder(
            PrototypeWebConfig(
              spec: spec,
              guard: guard,
              onBlocked: (url) {
                if (mounted) setState(() => blocked = url);
              },
              onBridge: _bridge,
            ),
          ),
        ),
      ],
    ),
  );
}
