part of 'platform_shell.dart';

extension _HomeSections on _PlatformShellState {
  Widget taskHub() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => page('执行面板', executionPanel()),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('执行面板'),
            ),
            OutlinedButton.icon(
              onPressed: () => page('消息中心', notifications()),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('消息中心'),
            ),
            OutlinedButton.icon(
              onPressed: () => page('数据交换', DevicesPage(host: host)),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('数据交换'),
            ),
          ],
        ),
      ),
      Expanded(child: tasks()),
    ],
  );

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
                    onSelected: (value) {
                      if (value == 'import') {
                        // The task-center route keeps the outer shell action
                        // busy until it returns. Navigation stays local here.
                        page(
                          '从文件导入业务',
                          InquiryImportContextPage(host: host, taskId: task.id),
                        );
                        return;
                      }
                      action(() async {
                        if (value == 'cancel') {
                          await host.personalAgent.cancel(task.id);
                        }
                        if (value == 'pause') {
                          await host.personalAgent.pause(task.id);
                        }
                        if (value == 'resume') {
                          await host.personalAgent.resume(task.id);
                        }
                      });
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'import',
                        child: Text('从文件导入业务'),
                      ),
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

/// The icon for a declared `iconKey`; an unknown key gets a generic one.
IconData moduleIcon(String? key) => switch (key) {
  'receipt_long' => Icons.receipt_long_outlined,
  'menu_book' => Icons.menu_book_outlined,
  'web' => Icons.web_outlined,
  _ => Icons.extension_outlined,
};
