import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../platform/foundation_repository.dart';

/// 执行面板: durable assistant-task records with goal, stage, device, wait
/// reason, error, result and object references. Actions appear only when the
/// current state actually supports them; the shell supplies the real
/// PersonalAgent operations and object navigation.
class ExecutionPanel extends StatelessWidget {
  const ExecutionPanel({
    super.key,
    required this.tasks,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
    required this.onOpenObject,
  });

  final List<PersonalTask> tasks;
  final Future<void> Function(PersonalTask task) onCancel;
  final Future<void> Function(PersonalTask task) onPause;
  final Future<void> Function(PersonalTask task) onResume;
  final void Function(ObjectRef ref) onOpenObject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(MuyonTokens.space4),
      children: [
        Text('执行面板', style: theme.textTheme.titleLarge),
        const SizedBox(height: MuyonTokens.space2),
        Text(
          '助手任务的目标、阶段、设备、等待原因、错误与结果会保留在这里，关闭聊天后仍可查看。'
          '暂停、取消、恢复只在任务当前状态支持时出现。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: MuyonTokens.space3),
        if (tasks.isEmpty)
          Text('暂无执行记录。', style: theme.textTheme.bodySmall)
        else
          for (final task in tasks)
            _TaskCard(
              task: task,
              onCancel: onCancel,
              onPause: onPause,
              onResume: onResume,
              onOpenObject: onOpenObject,
            ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
    required this.onOpenObject,
  });
  final PersonalTask task;
  final Future<void> Function(PersonalTask task) onCancel;
  final Future<void> Function(PersonalTask task) onPause;
  final Future<void> Function(PersonalTask task) onResume;
  final void Function(ObjectRef ref) onOpenObject;

  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    final platformOwned = task.payload['owner'] == 'platform';
    final cancelling = task.stage == 'cancelling';
    final canCancel = !task.terminal && !platformOwned && !cancelling;
    final canPause =
        task.state == PersonalTaskState.waitingConfirmation && !platformOwned;
    final canResume =
        !platformOwned &&
        const [
          PersonalTaskState.paused,
          PersonalTaskState.interrupted,
          PersonalTaskState.failed,
        ].contains(task.state);
    final interrupted = task.state == PersonalTaskState.interrupted;
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyonTokens.space3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.rule),
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space3),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: MuyonTokens.space2,
                  runSpacing: MuyonTokens.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      _stateIcon(task.state),
                      size: 18,
                      color: _stateColor(tokens, task.state),
                    ),
                    Text(
                      _stateLabel(task.state),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: _stateColor(tokens, task.state),
                      ),
                    ),
                    Text(task.prompt, style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: MuyonTokens.space1),
                SelectableText(
                  [
                    '阶段 ${task.stage}',
                    '设备 ${task.executionDeviceId}',
                    if (task.waitingFor != null) '等待 ${task.waitingFor}',
                    if (task.error != null) '错误 ${task.error}',
                    if (task.summary != null) '结果 ${task.summary}',
                  ].join('\n'),
                  style: theme.textTheme.bodySmall,
                ),
                if (interrupted) ...[
                  const SizedBox(height: MuyonTokens.space1),
                  Text(
                    '结果未知，重试前请先核实。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.red,
                    ),
                  ),
                ],
                if (task.objectRefs.isNotEmpty) ...[
                  const SizedBox(height: MuyonTokens.space1),
                  for (final ref in task.objectRefs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link, size: 18),
                      title: Text('${ref.moduleId} · ${ref.objectType}'),
                      subtitle: Text(ref.objectId),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => onOpenObject(ref),
                    ),
                ],
                if (platformOwned)
                  Text(
                    '平台任务：在设备页面查看，不支持逐项暂停或恢复。',
                    style: theme.textTheme.bodySmall,
                  )
                else if (canCancel || canPause || canResume || cancelling) ...[
                  const SizedBox(height: MuyonTokens.space2),
                  Wrap(
                    spacing: MuyonTokens.space2,
                    runSpacing: MuyonTokens.space2,
                    children: [
                      if (cancelling && !task.terminal) const Text('取消中…'),
                      if (canCancel)
                        OutlinedButton.icon(
                          onPressed: () => onCancel(task),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('取消'),
                        ),
                      if (canPause)
                        OutlinedButton.icon(
                          onPressed: () => onPause(task),
                          icon: const Icon(Icons.pause_outlined),
                          label: const Text('暂停'),
                        ),
                      if (canResume)
                        FilledButton.tonalIcon(
                          onPressed: () => onResume(task),
                          icon: const Icon(Icons.replay_outlined),
                          label: const Text('恢复（再次确认）'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _stateLabel(PersonalTaskState state) => switch (state) {
  PersonalTaskState.queued => '排队中',
  PersonalTaskState.waitingConfirmation => '等待你确认',
  PersonalTaskState.running => '执行中',
  PersonalTaskState.succeeded => '已完成',
  PersonalTaskState.failed => '失败',
  PersonalTaskState.cancelled => '已取消',
  PersonalTaskState.paused => '已暂停',
  PersonalTaskState.interrupted => '已中断（结果未知）',
};

IconData _stateIcon(PersonalTaskState state) => switch (state) {
  PersonalTaskState.queued => Icons.schedule_outlined,
  PersonalTaskState.waitingConfirmation => Icons.help_outline,
  PersonalTaskState.running => Icons.play_circle_outline,
  PersonalTaskState.succeeded => Icons.check_circle_outline,
  PersonalTaskState.failed => Icons.error_outline,
  PersonalTaskState.cancelled => Icons.cancel_outlined,
  PersonalTaskState.paused => Icons.pause_circle_outline,
  PersonalTaskState.interrupted => Icons.help_outline,
};

Color _stateColor(MuyonTokens tokens, PersonalTaskState state) =>
    switch (state) {
      PersonalTaskState.succeeded => tokens.green,
      PersonalTaskState.failed => tokens.red,
      PersonalTaskState.interrupted => tokens.amber,
      PersonalTaskState.waitingConfirmation => tokens.amber,
      _ => tokens.ink3,
    };
