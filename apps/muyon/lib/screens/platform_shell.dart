import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';

import '../app/app_shell.dart';
import '../app/bootstrap.dart';
import '../assistant/execution_store.dart';
import '../platform/foundation_repository.dart';
import '../services/models/credential_redaction.dart';
import '../services/models/model_gateway.dart';
import '../services/models/profile_repository.dart';
import '../services/models/secret_store.dart';
import 'assistant_page.dart';
import 'devices_page.dart';
import 'knowledge_preview.dart';
import 'data_storage_page.dart';
import 'data_flow_page.dart';
import 'execution_panel.dart';
import 'mcp_servers_page.dart';
import 'memory_page.dart';
import 'chat/chat_entry_page.dart';
import 'storage_status.dart';
import '../platform/backup_service.dart';

part 'platform_shell_home.dart';
part 'platform_shell_knowledge.dart';
part 'platform_shell_personal.dart';

class PlatformShell extends StatefulWidget {
  const PlatformShell({
    super.key,
    required this.host,
    required this.themeMode,
    required this.onTheme,
    required this.onRestore,
    this.pickDirectory = pickDirectoryWithDialog,
  });
  final MuyonHost host;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;

  /// Closes the host, restores a verified backup and reopens (see MuyonApp).
  final Future<void> Function(String backupDir) onRestore;
  final PickDirectory pickDirectory;
  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int section = 0;
  final query = TextEditingController();
  String? error;
  bool busy = false;
  bool assistantOpen = true;
  bool executionOpen = false;
  List<Map<String, Object?>> hits = [];
  MuyonHost get host => widget.host;
  FoundationRepository get repo => host.foundation;
  ProfileRepository get profiles => ProfileRepository(host.workspaces);
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void showSection(int value) => setState(() => section = value);

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
  // Rebuild from the repository so a pushed mobile page never shows stale state.
  Widget executionPanel() => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => ExecutionPanel(
      tasks: repo.tasks(),
      onCancel: (task) => action(() => host.personalAgent.cancel(task.id)),
      onPause: (task) => action(() => host.personalAgent.pause(task.id)),
      onResume: (task) =>
          action(() => host.personalAgent.resume(task.id).then((_) {})),
      onOpenObject: openObject,
    ),
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

  Future<void> openPrototype() async {
    PrototypeRuntime? runtime;
    await action(() async {
      await host.activatePrototype();
      runtime = host.prototype;
      if (runtime == null) {
        throw StateError('原型模块不可用：${host.prototypeError ?? '未知原因'}');
      }
    });
    final opened = runtime;
    if (opened == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrototypeHome(store: opened.store),
      ),
    );
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

  /// Phone-first hub: every destination opens as its own page with a back
  /// button. Wide layouts also keep these as top-bar shortcuts.
  Widget mine() => list([
    Text('我的', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    card(
      '个人中心',
      '任务、记忆与个人助手设置',
      () => page('个人中心', personal()),
      Icons.person_outline,
    ),
    card(
      '消息中心',
      '通知与待处理事项',
      () => page('消息中心', notifications()),
      Icons.notifications_outlined,
    ),
    card(
      '执行面板',
      '助手任务的目标、进度与产物',
      () => page('执行面板', executionPanel()),
      Icons.fact_check_outlined,
    ),
    card(
      '设备聊天',
      '本人已配对设备之间的文字',
      () => page('设备聊天', ChatEntryPage(host: host)),
      Icons.forum_outlined,
    ),
    card(
      '记忆与整理',
      '查看、停用、删除记忆；整理建议与撤回',
      () => page('记忆', memoryPage()),
      Icons.psychology_alt_outlined,
    ),
    card(
      '系统设置',
      '外观、模型与数据去向',
      () => page('系统设置', settings()),
      Icons.settings_outlined,
    ),
    card(
      '数据与存储',
      '模块状态、备份与恢复',
      () => page('数据与存储', storagePage()),
      Icons.storage_outlined,
    ),
    card(
      '接口与工具',
      '宿主注册的工具与调用',
      () => page('接口与工具', tools()),
      Icons.extension_outlined,
    ),
  ]);

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
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => LayoutBuilder(
      builder: (context, size) {
        final bodies = [home, () => assistant(), knowledge, mine];
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
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Muyon'),
            actions: [
              if (section != 1 && size.maxWidth >= 1250)
                IconButton(
                  tooltip: assistantOpen ? '收起助手' : '展开助手',
                  onPressed: () =>
                      setState(() => assistantOpen = !assistantOpen),
                  icon: Icon(
                    assistantOpen
                        ? Icons.chevron_right
                        : Icons.auto_awesome_outlined,
                  ),
                ),
              if (size.maxWidth >= 900) ...[
                IconButton(
                  tooltip: executionOpen ? '收起执行面板' : '执行面板',
                  onPressed: () =>
                      setState(() => executionOpen = !executionOpen),
                  icon: const Icon(Icons.fact_check_outlined),
                ),
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
                    if (section != 1 && size.maxWidth >= 1250 && assistantOpen)
                      SizedBox(width: 360, child: assistant()),
                    if (executionOpen)
                      SizedBox(width: 360, child: executionPanel()),
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
