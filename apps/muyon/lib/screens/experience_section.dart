import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../platform/foundation_repository.dart';

String scopeLabel(AssistantScope scope) => switch (scope.kind) {
  AssistantScopeKind.global => '全局',
  AssistantScopeKind.workspace => '仅某个工作区',
  AssistantScopeKind.selectedObjects => '仅所选对象',
};

/// 经验: candidates proposed by Dream (or saved directly) stay out of the
/// assistant's context until the person verifies them; retiring is one-way.
class ExperienceSection extends StatefulWidget {
  const ExperienceSection({super.key, required this.repo});
  final FoundationRepository repo;
  @override
  State<ExperienceSection> createState() => _ExperienceSectionState();
}

class _ExperienceSectionState extends State<ExperienceSection> {
  String? error;

  Future<void> _guard(Future<void> Function() job) async {
    setState(() => error = null);
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _retire(ExperienceEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退役这条经验？'),
        content: const Text('退役后助手不再使用它，同样的内容也不会被整理功能重新写入。此操作不能撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退役'),
          ),
        ],
      ),
    );
    if (ok == true) await _guard(() => widget.repo.retireExperience(e.id));
  }

  String _memory(String id) {
    for (final m in widget.repo.memories(
      includeExpired: true,
      includeDisabled: true,
    )) {
      if (m.id == id) return m.content;
    }
    return '（这条记忆已被删除）';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repo,
    builder: (context, _) {
      final theme = Theme.of(context);
      final tokens = MuyonTokens.of(context);
      final all = widget.repo.experiences(
        includeUnverified: true,
        includeRetired: true,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('经验', style: theme.textTheme.titleLarge),
          const SizedBox(height: MuyonTokens.space2),
          Text(
            '经验只是整理出的候选。你确认之后助手才会使用；一次成功的任务不会自动把它变成通用规则。',
            style: theme.textTheme.bodySmall,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space2),
              child: SelectableText(
                error!,
                style: TextStyle(color: tokens.red),
              ),
            ),
          const SizedBox(height: MuyonTokens.space3),
          if (all.isEmpty) Text('还没有经验。', style: theme.textTheme.bodyMedium),
          for (final e in all)
            Card(
              margin: const EdgeInsets.only(bottom: MuyonTokens.space2),
              child: Padding(
                padding: const EdgeInsets.all(MuyonTokens.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      e.content,
                      style: e.status == 'retired'
                          ? theme.textTheme.bodyLarge?.copyWith(
                              color: tokens.ink3,
                            )
                          : theme.textTheme.bodyLarge,
                    ),
                    Text(
                      '${switch (e.status) {
                        'candidate' => '候选（助手暂不使用）',
                        'verified' => '已核实',
                        'retired' => '已退役',
                        final other => other,
                      }} · ${scopeLabel(e.scope)} · 来源：${e.source}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (e.evidence.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          '依据 ${e.evidence.length} 条记忆',
                          style: theme.textTheme.bodySmall,
                        ),
                        children: [
                          for (final item in e.evidence)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                '· ${_memory('${item['id']}')}',
                              ),
                            ),
                        ],
                      ),
                    Wrap(
                      spacing: MuyonTokens.space1,
                      children: [
                        if (e.status == 'candidate')
                          TextButton(
                            onPressed: () => _guard(
                              () => widget.repo.verifyExperience(e.id),
                            ),
                            child: const Text('确认'),
                          ),
                        if (e.status != 'retired')
                          TextButton(
                            onPressed: () => _retire(e),
                            style: TextButton.styleFrom(
                              foregroundColor: tokens.red,
                            ),
                            child: const Text('退役'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
