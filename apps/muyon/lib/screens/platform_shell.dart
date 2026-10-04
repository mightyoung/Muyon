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
import 'data_storage_page.dart';
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
                    if (section != 1 && size.maxWidth >= 1250 && assistantOpen)
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
