import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';

import '../app/app_shell.dart';
import '../app/bootstrap.dart';
import '../assistant/execution_store.dart';
import '../platform/foundation_repository.dart';
import '../services/models/model_gateway.dart';
import '../services/models/profile_repository.dart';
import '../services/models/secret_store.dart';
import 'assistant_page.dart';
import 'devices_page.dart';
import 'knowledge_preview.dart';

class PlatformShell extends StatefulWidget {
  const PlatformShell({
    super.key,
    required this.host,
    required this.themeMode,
    required this.onTheme,
  });
  final MuyonHost host;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int section = 0;
  final query = TextEditingController();
  String? error;
  bool busy = false;
  List<Map<String, Object?>> hits = [];
  MuyonHost get host => widget.host;
  FoundationRepository get repo => host.foundation;
  ProfileRepository get profiles => ProfileRepository(host.workspaces);
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  AssistantPage assistant({AssistantScope? scope, String? conversationId}) =>
      AssistantPage(
        repo: repo,
        agent: host.personalAgent,
        profiles: profiles,
        scope: scope,
        conversationId: conversationId,
        onOpenReference: openObject,
      );
  Future<void> openModule(String module) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspacePage(
          host: host,
          themeMode: widget.themeMode,
          onTheme: widget.onTheme,
          initialModule: module,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> openObject(ObjectRef ref) async {
    await action(() async {
      final resolved = await host.tools.resolveScope(
        AssistantScope.selectedObjects([ref]),
      );
      final current = resolved.objects.single;
      if (!mounted) return;
      if (current.moduleId == 'knowledge' && current.objectType == 'document') {
        final document = host.services.knowledge.require(current.objectId);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(document.title),
                actions: [
                  IconButton(
                    tooltip: '针对当前资料使用助手',
                    icon: const Icon(Icons.chat_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('资料专题对话')),
                          body: assistant(
                            scope: AssistantScope.selectedObjects([current]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, size) => size.maxWidth >= 1100
                    ? Row(
                        children: [
                          Expanded(child: KnowledgePreview(document: document)),
                          SizedBox(
                            width: 360,
                            child: assistant(
                              scope: AssistantScope.selectedObjects([current]),
                            ),
                          ),
                        ],
                      )
                    : KnowledgePreview(document: document),
              ),
            ),
          ),
        );
        return;
      }
      if (current.moduleId == 'research' && current.objectType == 'document') {
        final document = host.research!.store
            .documents(current.nativeProjectId!)
            .firstWhere((d) => d.id == current.objectId);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(document.relativePath),
                actions: [
                  IconButton(
                    tooltip: '针对当前论文使用助手',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('论文专题对话')),
                          body: assistant(
                            scope: AssistantScope.selectedObjects([current]),
                          ),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chat_outlined),
                  ),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, size) => size.maxWidth >= 1100
                    ? Row(
                        children: [
                          Expanded(
                            child: ReaderPage(
                              store: host.research!.store.scoped(
                                current.nativeProjectId!,
                              ),
                              document: document,
                            ),
                          ),
                          SizedBox(
                            width: 360,
                            child: assistant(
                              scope: AssistantScope.selectedObjects([current]),
                            ),
                          ),
                        ],
                      )
                    : ReaderPage(
                        store: host.research!.store.scoped(
                          current.nativeProjectId!,
                        ),
                        document: document,
                      ),
              ),
            ),
          ),
        );
        return;
      }
      final data = current.moduleId == 'inquiry'
          ? host.inquiry!.runtime.state.store
                .get(current.objectType, current.objectId)
                ?.data
          : current.toJson();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('${data?['name'] ?? current.objectType}'),
              actions: [
                IconButton(
                  tooltip: '对象专题对话',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('专题对话')),
                        body: assistant(
                          scope: AssistantScope.selectedObjects([current]),
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.chat_outlined),
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, size) {
                final object = ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(data),
                    ),
                    if (current.moduleId == 'inquiry')
                      FilledButton.icon(
                        onPressed: () => openRecord(
                          context,
                          host.inquiry!.runtime.state,
                          current.objectType,
                          current.objectId,
                        ),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('在业务页面查看与编辑'),
                      ),
                  ],
                );
                return size.maxWidth >= 1100
                    ? Row(
                        children: [
                          Expanded(child: object),
                          SizedBox(
                            width: 360,
                            child: assistant(
                              scope: AssistantScope.selectedObjects([current]),
                            ),
                          ),
                        ],
                      )
                    : object;
              },
            ),
          ),
        ),
      );
    });
  }

  Future<void> page(String title, Widget body) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: body,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget list(Iterable<Widget> children) =>
      ListView(padding: const EdgeInsets.all(16), children: children.toList());
  Widget card(String title, String detail, VoidCallback tap, IconData icon) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(detail),
          onTap: tap,
          trailing: const Icon(Icons.chevron_right),
        ),
      );
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
      () => setState(() => section = 1),
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
  Future<void> editMemory([PersonalMemory? memory]) async {
    final content = TextEditingController(text: memory?.content);
    final source = TextEditingController(text: memory?.source ?? '本人手动确认');
    final expiry = TextEditingController(
      text: memory?.expiresAt?.toIso8601String().split('T').first,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有来源的个人记忆'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: content,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '偏好、背景、决定或已验证经验'),
              ),
              TextField(
                controller: source,
                decoration: const InputDecoration(
                  labelText: '来源（原文、对象、记录或本人确认）',
                ),
              ),
              TextField(
                controller: expiry,
                decoration: const InputDecoration(
                  labelText: '过期日期 YYYY-MM-DD（可留空）',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await action(
        () => repo
            .saveMemory(
              id: memory?.id,
              content: content.text,
              source: source.text,
              scope: memory?.scope ?? const AssistantScope.global(),
              sourceRef: memory?.sourceRef,
              verified: memory?.verified ?? true,
              expiresAt: expiry.text.trim().isEmpty
                  ? null
                  : DateTime.parse(expiry.text.trim()),
            )
            .then((_) {}),
      );
    }
    content.dispose();
    source.dispose();
    expiry.dispose();
  }

  Widget personal() => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => list([
      ListTile(
        title: const Text('个人资料'),
        subtitle: Text(
          '${host.workspaces.setting('personalName') ?? '本人'}\n设备 ID：${host.workspaces.setting('deviceId')}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => action(() async {
            final name = TextEditingController(
              text: host.workspaces.setting('personalName') as String? ?? '',
            );
            final result = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('个人名称'),
                content: TextField(controller: name),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, name.text.trim()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            );
            name.dispose();
            if (result != null) {
              await host.workspaces.setSetting('personalName', result);
            }
            repo.refresh();
          }),
        ),
      ),
      const Text('记忆保留来源与过期状态；模型建议不会自动扩大操作权限。'),
      FilledButton.icon(
        onPressed: () => editMemory(),
        icon: const Icon(Icons.add),
        label: const Text('添加记忆'),
      ),
      for (final memory in repo.memories(includeExpired: true))
        ListTile(
          title: Text(memory.content),
          subtitle: Text(
            '${memory.source}\n${memory.isExpired ? '已过期' : '有效'} ${memory.expiresAt ?? ''}',
          ),
          isThreeLine: true,
          onTap: () => editMemory(memory),
          trailing: IconButton(
            tooltip: '删除记忆',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => action(() => repo.deleteMemory(memory.id)),
          ),
        ),
      const Divider(),
      const Text('记忆整理'),
      const Text('后台按来源记录生成只读整理候选，保留全部来源，等待本人处理；不自动扩大操作权限。'),
      OutlinedButton.icon(
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('查看整理建议与来源摘要'),
        onPressed: () {
          final review = host.memoryReview.current;
          page(
            '记忆整理预览',
            list([
              Text(
                '重复候选 ${review.duplicates.length} 组 · 内容变化候选 ${review.conflicts.length} 组 · 过期 ${review.expired.length} 条',
              ),
              const Text('内容变化仅提示复核，不代表已确认矛盾；摘要逐条保留来源，不生成新事实。'),
              for (final group in review.duplicates) ...[
                const Text('相同内容，来源需要逐一保留或人工合并'),
                for (final memory in group)
                  ListTile(
                    title: Text(memory.content),
                    subtitle: Text(memory.source),
                    onTap: () => editMemory(memory),
                  ),
              ],
              for (final group in review.conflicts) ...[
                const Text('同一属性出现不同内容，请检查决定是否发生变化'),
                for (final memory in group)
                  ListTile(
                    title: Text(memory.content),
                    subtitle: Text(memory.source),
                    onTap: () => editMemory(memory),
                  ),
              ],
              const Divider(),
              const Text('有效记忆与来源摘要'),
              SelectableText(review.summary.join('\n\n')),
            ]),
          );
        },
      ),
      const Text('Dream、语义矛盾识别和自动经验提炼仍属于后续增强。'),
    ]),
  );
  Future<void> addProfile() async {
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final model = TextEditingController();
    final secret = TextEditingController();
    var location = ModelLocation.local;
    var purpose = ModelPurpose.chat;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('添加自选模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ModelPurpose>(
                  initialValue: purpose,
                  decoration: const InputDecoration(labelText: '模型用途'),
                  items: ModelPurpose.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v == ModelPurpose.chat ? '对话与工具' : '向量化'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => purpose = value!),
                ),
                DropdownButtonFormField<ModelLocation>(
                  initialValue: location,
                  items: ModelLocation.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(switch (v) {
                            ModelLocation.local => '本机',
                            ModelLocation.ownDevice => '本人其他设备',
                            ModelLocation.remote => '自选远程',
                          }),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => location = value!),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                TextField(
                  controller: endpoint,
                  decoration: const InputDecoration(
                    labelText: '完整端点 URL',
                    hintText: 'http://127.0.0.1:11434/v1/chat/completions',
                  ),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: '模型名称'),
                ),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key（仅存入系统凭据）',
                  ),
                ),
                const Text('非本机端点需要凭据；远程使用 HTTPS。不会自动切换到其他模型。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await action(() async {
        final id = const Uuid().v4();
        final ref = secret.text.isEmpty ? null : 'model-$id';
        final profile = ModelProfile(
          id: id,
          endpoint: Uri.parse(endpoint.text.trim()),
          location: location,
          modelId: model.text.trim(),
          endpointIdentity: name.text.trim(),
          credentialRef: ref,
          purpose: purpose,
        );
        if (ref != null) {
          await const MethodChannelSecretStore().write(ref, secret.text);
        }
        await profiles.save(profile);
        if (purpose == ModelPurpose.chat) {
          await host.workspaces.setSetting('activeModelProfileId', id);
        }
        repo.refresh();
      });
    }
    name.dispose();
    endpoint.dispose();
    model.dispose();
    secret.dispose();
  }

  Widget settings() => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => list([
      DropdownButtonFormField<ThemeMode>(
        initialValue: widget.themeMode,
        decoration: const InputDecoration(labelText: '外观'),
        items: ThemeMode.values
            .map(
              (mode) => DropdownMenuItem(value: mode, child: Text(mode.name)),
            )
            .toList(),
        onChanged: (value) => widget.onTheme(value!),
      ),
      SwitchListTile(
        title: const Text('减少动态效果'),
        value: host.workspaces.setting('reduceMotion') == true,
        onChanged: (value) => action(() async {
          await host.workspaces.setSetting('reduceMotion', value);
          repo.refresh();
        }),
      ),
      ListTile(
        title: const Text('私有存储'),
        subtitle: SelectableText(host.storage.rootPath),
      ),
      const Text('模型与数据去向'),
      DropdownButtonFormField<String>(
        initialValue:
            profiles.all().any(
              (p) =>
                  p.purpose == ModelPurpose.chat &&
                  p.id == host.workspaces.setting('activeModelProfileId'),
            )
            ? host.workspaces.setting('activeModelProfileId') as String
            : '',
        decoration: const InputDecoration(labelText: '主对话模型（Folio 共用）'),
        items: [
          const DropdownMenuItem(value: '', child: Text('未指定 · 离线工具可用')),
          for (final profile in profiles.all().where(
            (p) => p.purpose == ModelPurpose.chat,
          ))
            DropdownMenuItem(
              value: profile.id,
              child: Text(profile.endpointIdentity),
            ),
        ],
        onChanged: (value) => action(() async {
          await host.workspaces.setSetting('activeModelProfileId', value!);
          repo.refresh();
        }),
      ),
      FilledButton.icon(
        onPressed: addProfile,
        icon: const Icon(Icons.add),
        label: const Text('添加模型'),
      ),
      for (final profile in profiles.all())
        ListTile(
          title: Text(profile.endpointIdentity),
          subtitle: Text(
            '${profile.location.name} · ${profile.modelId}\n${profile.endpoint}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: '删除模型配置',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => action(() async {
              await profiles.remove(profile.id);
              if (profile.credentialRef != null) {
                await const MethodChannelSecretStore().remove(
                  profile.credentialRef!,
                );
              }
              repo.refresh();
            }),
          ),
        ),
      const Divider(),
      const Text('权限与能力'),
      const Text('只读业务查询可在明确范围内执行；写入和外传逐次确认。未注册能力不会自动替换为云服务。'),
      for (final tool in host.tools.list())
        ListTile(
          title: Text(tool.descriptor.toolId),
          subtitle: Text(
            '${tool.accessLevel.name} · ${tool.available ? '可调用' : tool.unavailableReason ?? '不可用'}',
          ),
        ),
    ]),
  );
  Future<void> importFile() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty || files.first.path == null) return;
    await action(
      () => host.trackOperation(() async {
        final document = await host.services.knowledge.importFile(
          files.first.path!,
        );
        await host.services.knowledge.index(document.id);
      }),
    );
  }

  Widget knowledge() => list([
    const Text('数据与知识', style: TextStyle(fontSize: 24)),
    const Text('原文件与来源对象保留；全文检索无需模型。扫描图片的 OCR 状态单独显示。'),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : importFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('导入文件'),
        ),
        OutlinedButton.icon(
          onPressed: () => action(() async {
            final scope = await host.tools.resolveScope(
              const AssistantScope.global(),
            );
            if (mounted) {
              await page(
                '业务对象目录',
                list([
                  for (final ref in scope.objects)
                    ListTile(
                      title: Text('${ref.moduleId} · ${ref.objectType}'),
                      subtitle: Text(ref.objectId),
                      onTap: () => openObject(ref),
                      trailing: const Icon(Icons.open_in_new),
                    ),
                ]),
              );
            }
          }),
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('查找业务对象'),
        ),
      ],
    ),
    TextField(
      controller: query,
      decoration: InputDecoration(
        labelText: '离线全文检索',
        suffixIcon: IconButton(
          onPressed: () => action(() async {
            final result = await host.services.knowledge.search(query.text);
            hits = [
              for (final hit in result)
                {
                  'title': hit.title,
                  'text': hit.text,
                  'page': hit.pageIndex + 1,
                  'ref': hit.sourceRef,
                },
            ];
          }),
          icon: const Icon(Icons.search),
        ),
      ),
      onSubmitted: (_) => action(() async {
        final result = await host.services.knowledge.search(query.text);
        hits = [
          for (final hit in result)
            {
              'title': hit.title,
              'text': hit.text,
              'page': hit.pageIndex + 1,
              'ref': hit.sourceRef,
            },
        ];
      }),
    ),
    for (final hit in hits)
      Card(
        child: ListTile(
          title: Text('${hit['title']} · 第${hit['page']}页'),
          subtitle: Text(
            '${hit['text']}',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openObject(hit['ref'] as ObjectRef),
        ),
      ),
    const Divider(),
    for (final document in host.services.knowledge.documents())
      ListTile(
        title: Text(document.title),
        subtitle: Text('${document.status}\n${document.summary}'),
        isThreeLine: true,
        onTap: () => openObject(document.source),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => action(
            () => host.trackOperation(() async {
              if (value == 'index') {
                await host.services.knowledge.index(document.id);
              }
              if (value == 'delete') {
                await host.services.knowledge.delete(document.id);
              }
            }),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'index', child: Text('重建索引')),
            PopupMenuItem(value: 'delete', child: Text('删除平台副本')),
          ],
        ),
      ),
  ]);
  Future<void> runTool(RegisteredToolInfo info) async {
    final parameters = TextEditingController(text: '{}');
    final destination = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(info.descriptor.toolId),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ')
                    .convert(info.descriptor.parameterSchema),
              ),
              TextField(
                controller: parameters,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '参数 JSON'),
              ),
              if (info.accessLevel == ToolAccessLevel.external)
                TextField(
                  controller: destination,
                  decoration: const InputDecoration(labelText: '明确发送目的地'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('校验并调用'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await action(() async {
        var request = ToolCallRequest(
          invocationId: const Uuid().v4(),
          toolId: info.descriptor.toolId,
          scope: const AssistantScope.global(),
          parameters: Map<String, Object?>.from(
            jsonDecode(parameters.text) as Map,
          ),
          destination: destination.text.isEmpty
              ? null
              : destination.text.trim(),
        );
        final prepared = await host.tools.prepare(request);
        if (info.accessLevel != ToolAccessLevel.read) {
          if (!mounted) return;
          final approve = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认本次操作'),
              content: SingleChildScrollView(
                child: SelectableText(
                  '${info.accessLevel.name}\n目的地：${request.destination ?? '本地'}\n参数：${jsonEncode(request.parameters)}\n范围对象：${prepared.resolvedScope.objects.length}\n输入摘要：${prepared.parameterDigest}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('仅确认这一次'),
                ),
              ],
            ),
          );
          if (approve != true) return;
          request = request.withApproval(await host.tools.approve(prepared));
        }
        final result = await host.trackOperation(
          () => host.tools.invoke(request),
        );
        if (mounted) {
          await page(
            '调用结果',
            list([
              SelectableText(result.summary),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(result.data),
              ),
              for (final ref in result.objectRefs)
                ListTile(
                  title: Text('${ref.moduleId} · ${ref.objectType}'),
                  subtitle: Text(ref.objectId),
                  onTap: () => openObject(ref),
                ),
            ]),
          );
        }
      });
    }
    parameters.dispose();
    destination.dispose();
  }

  Widget tools() => list([
    const Text('接口与工具', style: TextStyle(fontSize: 24)),
    const Text('页面与助手调用同一注册表；参数与权限由宿主校验。'),
    for (final info in host.tools.list())
      Card(
        child: ListTile(
          title: Text(info.descriptor.toolId),
          subtitle: Text(
            '${info.providerId} · ${info.accessLevel.name}\n${info.available ? '可用' : info.unavailableReason ?? '不可用'}',
          ),
          isThreeLine: true,
          onTap: info.available ? () => runTool(info) : null,
          trailing: const Icon(Icons.play_arrow_outlined),
        ),
      ),
  ]);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => LayoutBuilder(
      builder: (context, size) {
        final bodies = [home, () => assistant(), knowledge, tools];
        final body = Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: bodies[section]()),
          ],
        );
        const destinations = [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: '工作台',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: '助手',
          ),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '资料'),
          NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            label: '工具',
          ),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Muyon'),
            actions: [
              IconButton(
                tooltip: '消息中心',
                onPressed: () => page('消息中心', notifications()),
                icon: const Icon(Icons.notifications_outlined),
              ),
              IconButton(
                tooltip: '个人中心',
                onPressed: () => page('个人中心', personal()),
                icon: const Icon(Icons.person_outline),
              ),
              IconButton(
                tooltip: '系统设置',
                onPressed: () => page('系统设置', settings()),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: size.maxWidth >= 900
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: section,
                      onDestinationSelected: (value) =>
                          setState(() => section = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations
                          .map(
                            (d) => NavigationRailDestination(
                              icon: d.icon,
                              label: Text(d.label),
                            ),
                          )
                          .toList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                    if (section != 1 && size.maxWidth >= 1250)
                      SizedBox(width: 360, child: assistant()),
                  ],
                )
              : body,
          bottomNavigationBar: size.maxWidth < 900
              ? NavigationBar(
                  selectedIndex: section,
                  onDestinationSelected: (value) =>
                      setState(() => section = value),
                  destinations: destinations,
                )
              : null,
        );
      },
    ),
  );
}
