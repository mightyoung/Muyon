import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';

/// Public simulation only. Host authority/SQLite/agent lifecycle are exercised
/// separately by host tests; this page never invokes a model or product tools.
class SubconversationPreview extends StatefulWidget {
  const SubconversationPreview({super.key, required this.store});
  final UiWorkspaceStore store;
  @override
  State<SubconversationPreview> createState() => _PreviewState();
}

class _PreviewState extends State<SubconversationPreview> {
  final input = TextEditingController();
  int revision = 0, version = 1;
  List<Map<String, Object?>> reads = [];
  String? error;
  bool loaded = false, saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.store.load('public-ui4c-child');
      if (!mounted) return;
      if (value != null) {
        revision = value.revision;
        input.text = value.viewValues['draft'] as String? ?? '';
        version = value.viewValues['version'] as int? ?? 1;
        reads = [
          for (final r in jsonDecode(
            value.viewValues['reads'] as String? ?? '[]',
          ) as List)
            Map<String, Object?>.from(r as Map),
        ];
      }
      setState(() => loaded = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<bool> save() async {
    if (saving) return false;
    saving = true;
    try {
      final value = StoredUiWorkspace(
        taskId: 'public-ui4c',
        surfaceId: 'public-ui4c-child',
        scopeKey: 'public-only',
        revision: revision + 1,
        schemaVersion: 1,
        catalogVersion: 'public-v1',
        snapshotRef: SnapshotRef('public-child', version),
        intentRef: 'public-child-readonly',
        planRevision: 1,
        draftRevision: 1,
        extracted: {},
        userOverrides: {},
        nodeIds: ['child'],
        viewValues: {
          'draft': input.text,
          'version': version,
          'reads': jsonEncode(reads),
        },
      );
      if (!await widget.store.save(value, expectedRevision: revision)) {
        throw StateError('Saved state changed; pending input retained');
      }
      revision++;
      return true;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      return false;
    } finally {
      saving = false;
    }
  }

  Future<void> open() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: StatefulBuilder(
            builder: (context, update) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('公开子对话 · 一层 · 只读'),
                    const Text('模拟任务运行中；关闭仅保存 UI'),
                    Text('子成果 v$version'),
                    TextField(
                      controller: input,
                      decoration: const InputDecoration(labelText: '待发输入'),
                    ),
                    TextButton(
                      onPressed: () {
                        update(() => version++);
                      },
                      child: const Text('模拟子成果更新'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        if (await save()) {
                          if (mounted) navigator.pop();
                        } else {
                          update(() {});
                        }
                      },
                      child: const Text('保存并关闭'),
                    ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('UI-4c · 公开模拟')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('仅公开夹具；没有真实模型、授权、业务写入或后台能力证明。'),
          if (error != null) Text(error!),
          if (loaded) ...[
            FilledButton(onPressed: open, child: const Text('打开子对话')),
            TextButton(
              onPressed: () async {
                setState(
                  () => reads.add({
                    'version': version,
                    'summary': '子成果 v$version',
                    'readAt': DateTime.now().toUtc().toIso8601String(),
                  }),
                );
                await save();
              },
              child: const Text('查询最新'),
            ),
            for (final read in reads)
              Text('只读历史引用：${read['summary']} · ${read['readAt']}'),
          ],
        ],
      ),
    ),
  );
}
