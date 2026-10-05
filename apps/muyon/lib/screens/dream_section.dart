import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../assistant/dream/dream_service.dart';
import '../platform/foundation_repository.dart';
import '../services/models/model_gateway.dart';

/// 整理: Dream runs only when the person starts it; every result is a
/// proposal they accept or reject, and the latest run can be rolled back.
class DreamSection extends StatefulWidget {
  const DreamSection({
    super.key,
    required this.dream,
    required this.repo,
    required this.profiles,
  });
  final DreamService dream;
  final FoundationRepository repo;
  final List<ModelProfile> Function() profiles;

  @override
  State<DreamSection> createState() => _DreamSectionState();
}

class _DreamSectionState extends State<DreamSection> {
  String? profileId;
  bool busy = false;
  String? error, notice;

  Future<void> _job(Future<void> Function() body) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await body();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  ModelProfile? get _profile {
    for (final p in widget.profiles()) {
      if (p.id == profileId) return p;
    }
    return null;
  }

  Future<void> _run() async {
    final profile = _profile;
    if (profile != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('用模型辅助整理？'),
          content: Text(
            '将把本次新增或变化的记忆内容（含来源）发送到 ${profile.endpointIdentity}'
            '（${profile.modelId}，${_where(profile.location)}）。'
            '发送记录可在出站记录中查看。模型只能提出整理建议，不会替你接受任何一条。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('发送并整理'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _job(() async {
      final before = widget.dream.runs().length;
      final run = await widget.dream.run(profile: profile);
      final created = widget.dream.runs().length > before;
      notice = !created
          ? '自上次整理后没有新的变化，未产生新的建议。'
          : run.status == 'done'
          ? '整理完成，请在下面查看建议。'
          : '整理未完成：${run.status}';
    });
  }

  static String _where(ModelLocation l) => switch (l) {
    ModelLocation.local => '本机',
    ModelLocation.ownDevice => '本人设备',
    ModelLocation.remote => '远程服务',
  };

  Future<void> _revert(DreamRun run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤回最近一次整理？'),
        content: const Text(
          '记忆和经验会恢复到这次整理开始前的状态，这次的建议全部标记为已撤回。'
          '整理之后你自己做的修改也会被还原。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _job(() async {
      await widget.dream.revert(run.id);
      notice = '已撤回。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MuyonTokens.of(context);
    final profiles = widget.profiles();
    final runs = widget.dream.runs();
    final done = runs.where((r) => r.status == 'done').toList();
    final latestDone = done.isEmpty ? null : done.last;
    final proposals = [
      for (final p in widget.dream.proposals())
        if (p.status == 'proposed' ||
            (latestDone != null && p.runId == latestDone.id))
          p,
    ];
    final profile = _profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('整理', style: theme.textTheme.titleLarge),
        const SizedBox(height: MuyonTokens.space2),
        Text(
          '整理只在你点击时运行，只生成建议：合并重复、汇总、提炼经验、列出冲突来源。'
          '不选模型时只用本机规则，不联网。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: MuyonTokens.space3),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: profile?.id ?? '',
          decoration: const InputDecoration(labelText: '整理方式'),
          items: [
            const DropdownMenuItem(value: '', child: Text('仅本机规则（不联网）')),
            for (final p in profiles)
              DropdownMenuItem(
                value: p.id,
                child: Text(
                  '${p.endpointIdentity} · ${_where(p.location)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy
              ? null
              : (value) => setState(
                  () => profileId = (value == null || value.isEmpty)
                      ? null
                      : value,
                ),
        ),
        if (profile != null && profile.location != ModelLocation.local)
          Padding(
            padding: const EdgeInsets.only(top: MuyonTokens.space2),
            child: Text(
              '会把记忆内容发送到${_where(profile.location)}，运行前会再次确认。',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.amber),
            ),
          ),
        const SizedBox(height: MuyonTokens.space3),
        Wrap(
          spacing: MuyonTokens.space2,
          runSpacing: MuyonTokens.space2,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _run,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('整理记忆'),
            ),
            if (latestDone != null)
              OutlinedButton.icon(
                onPressed: busy ? null : () => _revert(latestDone),
                icon: const Icon(Icons.undo),
                label: const Text('撤回最近一次整理'),
              ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: MuyonTokens.space3),
            child: LinearProgressIndicator(),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: MuyonTokens.space3),
            child: Text(notice!, style: theme.textTheme.bodyMedium),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: MuyonTokens.space3),
            child: SelectableText(error!, style: TextStyle(color: tokens.red)),
          ),
        if (latestDone != null) _RunSummary(run: latestDone),
        const SizedBox(height: MuyonTokens.space3),
        if (proposals.isEmpty)
          Text('没有待处理的建议。', style: theme.textTheme.bodyMedium),
        for (final proposal in proposals)
          _ProposalCard(
            proposal: proposal,
            repo: widget.repo,
            busy: busy,
            onAccept: () => _job(() async {
              await widget.dream.accept(proposal.id);
              notice = '已接受。';
            }),
          ),
      ],
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});
  final DreamRun run;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: MuyonTokens.space3),
    child: Text(
      '最近一次：${run.modelProfileId == null ? '本机规则' : '模型辅助'}'
      '${run.outboundIds.isEmpty ? '' : ' · 发送 ${run.outboundIds.length} 次请求'}'
      '${run.tokenCost == null ? '' : ' · 约 ${run.tokenCost} 词元（估算）'}'
      '${run.elapsedMs == null ? '' : ' · ${run.elapsedMs} 毫秒'}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.repo,
    required this.busy,
    required this.onAccept,
  });
  final DreamProposal proposal;
  final FoundationRepository repo;
  final bool busy;
  final VoidCallback onAccept;

  String _content(String id) {
    for (final m in repo.memories(
      includeExpired: true,
      includeDisabled: true,
    )) {
      if (m.id == id) return m.content;
    }
    return '（这条记忆已被删除）';
  }

  (String, String) get _label => switch (proposal.kind) {
    'duplicate' => ('重复', '保留一条，停用其余重复项（不删除）'),
    'summary' => ('汇总', '新增一条“待确认”的汇总记忆，保留来源'),
    'experience' => ('经验', '新增一条待验证的经验'),
    'conflict' => ('冲突', '只列出各方来源，需要你自己判断，不能自动消解'),
    _ => (proposal.kind, ''),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MuyonTokens.of(context);
    final (title, effect) = _label;
    final pending = proposal.status == 'proposed';
    final payload = proposal.payload;
    final text = payload['content'] ?? payload['summary'];
    final keep = payload['keepId'] as String?;
    final disable =
        (payload['disableIds'] as List?)?.cast<String>() ?? const [];
    final statusText = switch (proposal.status) {
      'accepted' => '已接受',
      'reverted' => '已撤回',
      'proposed' => '待处理',
      final other => other,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: MuyonTokens.space2),
      child: Padding(
        padding: const EdgeInsets.all(MuyonTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: MuyonTokens.space2,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  statusText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: pending ? tokens.amber : tokens.ink3,
                  ),
                ),
              ],
            ),
            Text(effect, style: theme.textTheme.bodySmall),
            const SizedBox(height: MuyonTokens.space2),
            if (text is String) SelectableText('建议内容：$text'),
            if (keep != null) SelectableText('保留：${_content(keep)}'),
            for (final id in disable) SelectableText('停用：${_content(id)}'),
            if (proposal.kind == 'conflict' && payload['sources'] is List)
              for (final raw in payload['sources'] as List)
                if (raw is Map)
                  SelectableText('· ${raw['content']}（来源：${raw['source']}）'),
            if (proposal.kind != 'conflict' || payload['sources'] is! List)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '依据 ${proposal.evidence.length} 条记忆',
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  for (final item in proposal.evidence)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText('· ${_content('${item['id']}')}'),
                    ),
                ],
              ),
            if (pending && proposal.kind != 'conflict')
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space2),
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: const Text('接受'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
