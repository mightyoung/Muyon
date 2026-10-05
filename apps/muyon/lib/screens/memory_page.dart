import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../assistant/dream/dream_service.dart';
import '../platform/foundation_repository.dart';
import '../services/models/model_gateway.dart';
import 'dream_section.dart';

enum MemoryFilter { all, active, disabled, expired }

/// 记忆: view, edit, disable/enable, confirm and delete personal memories, and
/// organize them with Dream when the person asks for it.
class MemoryPage extends StatefulWidget {
  const MemoryPage({
    super.key,
    required this.repo,
    required this.dream,
    required this.profiles,
  });
  final FoundationRepository repo;
  final DreamService dream;

  /// Chat profiles the person may choose for a model-assisted run.
  final List<ModelProfile> Function() profiles;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  MemoryFilter filter = MemoryFilter.all;
  String? error;

  @override
  void initState() {
    super.initState();
    widget.repo.addListener(_changed);
  }

  @override
  void dispose() {
    widget.repo.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() => error = null);
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  bool _matches(PersonalMemory m) => switch (filter) {
    MemoryFilter.all => true,
    MemoryFilter.active => !m.disabled && !m.isExpired,
    MemoryFilter.disabled => m.disabled,
    MemoryFilter.expired => m.isExpired && !m.disabled,
  };

  Future<void> _edit(PersonalMemory? memory) async {
    final result = await showDialog<_MemoryDraft>(
      context: context,
      builder: (_) => _MemoryDialog(memory: memory),
    );
    if (result == null) return;
    await _guard(
      () => widget.repo
          .saveMemory(
            id: memory?.id,
            content: result.content,
            source: result.source,
            expiresAt: result.expiresAt,
            scope: memory?.scope ?? const AssistantScope.global(),
            sourceRef: memory?.sourceRef,
            // Editing keeps what the memory already is.
            verified: memory?.verified ?? true,
            disabled: memory?.disabled ?? false,
            kind: memory?.kind ?? 'fact',
            inference: memory?.inference ?? false,
            lineage: memory?.lineage ?? const [],
          )
          .then((_) {}),
    );
  }

  Future<void> _delete(PersonalMemory memory) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: Text(
          '“${_short(memory.content)}”将被永久删除，由它整理出的内容也会一并删除。'
          '已删除的内容不会被整理功能重新写入。此操作不能撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _guard(() => widget.repo.deleteMemory(memory.id));
  }

  Future<void> _confirm(PersonalMemory memory) => _guard(
    () => widget.repo
        .saveMemory(
          id: memory.id,
          content: memory.content,
          source: memory.source,
          expiresAt: memory.expiresAt,
          scope: memory.scope,
          sourceRef: memory.sourceRef,
          verified: true,
          disabled: memory.disabled,
          kind: memory.kind,
          inference: memory.inference,
          lineage: memory.lineage,
        )
        .then((_) {}),
  );

  static String _short(String text) =>
      text.length <= 40 ? text : '${text.substring(0, 40)}…';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MuyonTokens.of(context);
    final all = widget.repo.memories(
      includeExpired: true,
      includeDisabled: true,
    );
    final shown = [
      for (final m in all)
        if (_matches(m)) m,
    ];
    return ListView(
      padding: const EdgeInsets.all(MuyonTokens.space4),
      children: [
        Text('记忆', style: theme.textTheme.titleLarge),
        const SizedBox(height: MuyonTokens.space2),
        Text(
          '记忆都有来源。停用的记忆助手不会使用；模型整理出的内容先是“待确认”，'
          '确认前助手不会当作事实使用。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: MuyonTokens.space3),
        Wrap(
          spacing: MuyonTokens.space2,
          runSpacing: MuyonTokens.space2,
          children: [
            FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('添加记忆'),
            ),
            for (final (value, label) in const [
              (MemoryFilter.all, '全部'),
              (MemoryFilter.active, '有效'),
              (MemoryFilter.disabled, '已停用'),
              (MemoryFilter.expired, '已过期'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: filter == value,
                onSelected: (_) => setState(() => filter = value),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: MuyonTokens.space3),
            child: SelectableText(error!, style: TextStyle(color: tokens.red)),
          ),
        const SizedBox(height: MuyonTokens.space3),
        if (shown.isEmpty)
          Text(
            all.isEmpty ? '还没有记忆。' : '没有符合筛选条件的记忆。',
            style: theme.textTheme.bodyMedium,
          ),
        for (final memory in shown)
          _MemoryCard(
            memory: memory,
            onEdit: () => _edit(memory),
            onDelete: () => _delete(memory),
            onConfirm: () => _confirm(memory),
            onToggle: (disabled) => _guard(
              () => widget.repo.setMemoryDisabled(memory.id, disabled),
            ),
          ),
        const Divider(height: MuyonTokens.space6 * 2),
        DreamSection(
          dream: widget.dream,
          repo: widget.repo,
          profiles: widget.profiles,
        ),
      ],
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    required this.onEdit,
    required this.onDelete,
    required this.onConfirm,
    required this.onToggle,
  });
  final PersonalMemory memory;
  final VoidCallback onEdit, onDelete, onConfirm;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MuyonTokens.of(context);
    final tags = <(String, Color)>[
      if (memory.disabled) ('已停用', tokens.ink3),
      if (memory.isExpired) ('已过期', tokens.amber),
      if (!memory.verified) ('待确认', tokens.amber),
      if (memory.kind == 'summary' || memory.inference) ('整理生成', tokens.accent),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: MuyonTokens.space2),
      child: Padding(
        padding: const EdgeInsets.all(MuyonTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              memory.content,
              style: memory.disabled
                  ? theme.textTheme.bodyLarge?.copyWith(color: tokens.ink3)
                  : theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: MuyonTokens.space1),
            Text(
              '来源：${memory.source}'
              '${memory.expiresAt == null ? '' : ' · 过期 ${memory.expiresAt!.toLocal().toString().split(' ').first}'}',
              style: theme.textTheme.bodySmall,
            ),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space1),
                child: Wrap(
                  spacing: MuyonTokens.space2,
                  children: [
                    for (final (text, color) in tags)
                      Text(
                        text,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            Wrap(
              spacing: MuyonTokens.space1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(onPressed: onEdit, child: const Text('编辑')),
                if (!memory.verified)
                  TextButton(onPressed: onConfirm, child: const Text('确认')),
                TextButton(
                  onPressed: () => onToggle(!memory.disabled),
                  child: Text(memory.disabled ? '启用' : '停用'),
                ),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: tokens.red),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryDraft {
  const _MemoryDraft(this.content, this.source, this.expiresAt);
  final String content, source;
  final DateTime? expiresAt;
}

class _MemoryDialog extends StatefulWidget {
  const _MemoryDialog({this.memory});
  final PersonalMemory? memory;
  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  late final content = TextEditingController(text: widget.memory?.content);
  late final source = TextEditingController(
    text: widget.memory?.source ?? '本人手动确认',
  );
  late final expiry = TextEditingController(
    text: widget.memory?.expiresAt?.toLocal().toString().split(' ').first,
  );
  String? problem;

  @override
  void dispose() {
    content.dispose();
    source.dispose();
    expiry.dispose();
    super.dispose();
  }

  void _save() {
    final text = content.text.trim();
    final from = source.text.trim();
    DateTime? when;
    if (expiry.text.trim().isNotEmpty) {
      when = DateTime.tryParse(expiry.text.trim());
      if (when == null) {
        setState(() => problem = '过期日期格式应为 YYYY-MM-DD');
        return;
      }
    }
    if (text.isEmpty || from.isEmpty) {
      setState(() => problem = '内容和来源都不能为空');
      return;
    }
    Navigator.pop(context, _MemoryDraft(text, from, when));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.memory == null ? '添加记忆' : '编辑记忆'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: content,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '内容'),
          ),
          const SizedBox(height: MuyonTokens.space2),
          TextField(
            controller: source,
            decoration: const InputDecoration(labelText: '来源（原文、对象、记录或本人确认）'),
          ),
          const SizedBox(height: MuyonTokens.space2),
          TextField(
            controller: expiry,
            decoration: const InputDecoration(
              labelText: '过期日期 YYYY-MM-DD（可留空）',
            ),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space2),
              child: Text(
                problem!,
                style: TextStyle(color: MuyonTokens.of(context).red),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
