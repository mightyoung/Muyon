part of 'platform_shell.dart';

extension _HomeSections on _PlatformShellState {
  Widget home() => list([
    Text('Muyon', style: Theme.of(context).textTheme.headlineMedium),
    const Text('打开应用自己做，也可以交给个人助手。已有资料和业务查询可离线使用。'),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          label: const Text('本人设备'),
          onPressed: () => page('设备与通信', DevicesPage(host: host)),
        ),
        ActionChip(
          label: Text('任务 ${repo.tasks().where((t) => !t.terminal).length}'),
          onPressed: () => action(() async {
            await host.activateInquiry();
            if (mounted) await page('任务中心', tasks());
          }),
        ),
        ActionChip(
          label: Text('消息 ${repo.notifications(unreadOnly: true).length}'),
          onPressed: () => page('消息中心', notifications()),
        ),
        ActionChip(
          label: const Text('个人与记忆'),
          onPressed: () => page('个人中心', personal()),
        ),
        ActionChip(
          label: const Text('系统设置'),
          onPressed: () => page('系统设置', settings()),
        ),
      ],
    ),
    card(
      '个人助手',
      '主对话、专题对话和已注册工具',
      () => showSection(1),
      Icons.auto_awesome_outlined,
    ),
    card(
      'Folio · 询价台账',
      '完整供应商、询价报价和成本业务',
      () => openModule('inquiry'),
      Icons.receipt_long_outlined,
    ),
    card(
      '科研工作台',
      '原文阅读、批注、研究过程和成果',
      () => openModule('research'),
      Icons.menu_book_outlined,
    ),
    card(
      '原型页面',
      '导入单页原型，评审版本并记录反馈（不是完整业务系统）',
      openPrototype,
      Icons.web_outlined,
    ),
    if (host.workspaces.all().isNotEmpty) ...[
      const Divider(),
      Text('项目与工作区', style: Theme.of(context).textTheme.titleMedium),
      for (final workspace in host.workspaces.all())
        ListTile(
          title: Text(workspace.title),
          leading: const Icon(Icons.folder_outlined),
          onTap: () => action(() async {
            await host.workspaces.setSetting('selectedWorkspace', workspace.id);
            await openModule('research');
          }),
          trailing: IconButton(
            tooltip: '工作区专题对话',
            icon: const Icon(Icons.chat_outlined),
            onPressed: () => page(
              '工作区助手',
              assistant(scope: AssistantScope.workspace(workspace.id)),
            ),
          ),
        ),
    ],
    const Divider(),
    Text('近期工作', style: Theme.of(context).textTheme.titleMedium),
    for (final conversation in repo.conversations().take(5))
      ListTile(
        title: Text(conversation.title),
        subtitle: Text(conversation.scope.kind.name),
        onTap: () => page('继续对话', assistant(conversationId: conversation.id)),
      ),
  ]);
  Widget tasks() => ListenableBuilder(
    listenable: Listenable.merge([
      repo,
      if (host.inquiry != null) host.inquiry!.runtime.state,
    ]),
    builder: (context, _) => list([
      const Text('暂停在安全边界停止；恢复创建新尝试并重新确认。不会自动重放写入或网络操作。'),
      for (final task in repo.tasks())
        Card(
          child: ListTile(
            title: Text(task.prompt),
            subtitle: Text(
              '${task.state.name} · ${task.stage}\n设备：${task.deviceId}\n${task.waitReason ?? task.summary ?? task.error ?? ''}',
            ),
            isThreeLine: true,
            onTap: () =>
                page('任务对话', assistant(conversationId: task.conversationId)),
            trailing: task.payload['owner'] == 'platform'
                ? const Tooltip(
                    message: '返回设备页面查看；当前传输不支持逐项暂停或恢复',
                    child: Icon(Icons.devices),
                  )
                : PopupMenuButton<String>(
                    onSelected: (value) => action(() async {
                      if (value == 'cancel') {
                        await host.personalAgent.cancel(task.id);
                      }
                      if (value == 'pause') {
                        await host.personalAgent.pause(task.id);
                      }
                      if (value == 'resume') {
                        await host.personalAgent.resume(task.id);
                      }
                    }),
                    itemBuilder: (_) => [
                      if (!task.terminal)
                        const PopupMenuItem(value: 'cancel', child: Text('取消')),
                      if (!task.terminal)
                        const PopupMenuItem(value: 'pause', child: Text('暂停')),
                      if ([
                        PersonalTaskState.paused,
                        PersonalTaskState.interrupted,
                        PersonalTaskState.failed,
                      ].contains(task.state))
                        const PopupMenuItem(
                          value: 'resume',
                          child: Text('重新尝试（再次确认）'),
                        ),
                    ],
                  ),
          ),
        ),
      for (final task in ExecutionStore(host.workspaces.database).all())
        ListTile(
          title: Text('科研 · ${task.toolId}'),
          subtitle: Text(
            '${task.state.name} · ${task.executionDeviceId}\n${task.error ?? task.stage}',
          ),
        ),
      for (final job in host.inquiry?.runtime.state.aiTasks ?? [])
        ListTile(
          title: Text('Folio · ${job.task.name}'),
          subtitle: Text(
            '${job.status} · 本机\n${job.message ?? '已保存 ${job.stepCount} 个步骤'}',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openModule('inquiry'),
        ),
      for (final call in host.tools.history())
        ListTile(
          title: Text(call.summary),
          subtitle: Text('工具调用 · ${call.status.name}'),
        ),
      if (repo.tasks().isEmpty &&
          ExecutionStore(host.workspaces.database).all().isEmpty &&
          host.tools.history().isEmpty)
        const ListTile(title: Text('暂无任务'), subtitle: Text('执行记录在关闭聊天后仍保留。')),
    ]),
  );
  Widget notifications() => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => list([
      if (repo.notifications().isEmpty) const ListTile(title: Text('暂无消息')),
      for (final item in repo.notifications())
        ListTile(
          leading: Icon(
            item.read
                ? Icons.notifications_none
                : Icons.notifications_active_outlined,
          ),
          title: Text(item.title),
          subtitle: Text(item.body),
          onTap: () => action(() async {
            await repo.markNotificationRead(item.id);
            final task = item.taskId == null ? null : repo.task(item.taskId!);
            if (task != null) {
              await page(
                '相关任务',
                assistant(conversationId: task.conversationId),
              );
            } else if (item.title == '收到设备数据包') {
              await page('待核验设备收件', DevicesPage(host: host));
            }
          }),
        ),
    ]),
  );
}
