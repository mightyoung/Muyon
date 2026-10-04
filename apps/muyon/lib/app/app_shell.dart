import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:uuid/uuid.dart';

import '../platform/file_gateway.dart';
import '../workspace/import_coordinator.dart';
import 'bootstrap.dart';
import 'research_tools_page.dart';
import '../screens/platform_shell.dart';

class MuyonApp extends StatefulWidget {
  const MuyonApp({super.key, required this.host});
  final MuyonHost host;
  @override
  State<MuyonApp> createState() => _MuyonAppState();
}

class _MuyonAppState extends State<MuyonApp> {
  ThemeMode mode = ThemeMode.system;
  final navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener lifecycle;
  @override
  void initState() {
    super.initState();
    widget.host.approveInquiryModelRequest = (preview) async {
      final context = navigator.currentContext;
      if (!mounted || context == null) return false;
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认 Folio 本次模型请求'),
              content: SingleChildScrollView(
                child: SelectableText(
                  '模型：${preview.profile.modelId}\n位置：${preview.profile.location.name}\n端点：${preview.endpoint}\n摘要：${preview.bodyDigest}\n发送内容：\n${preview.body}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('仅发送这一次'),
                ),
              ],
            ),
          ) ??
          false;
    };
    lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.host.close();
        return AppExitResponse.exit;
      },
      onDetach: () {
        widget.host.close();
      },
    );
    mode = ThemeMode.values.byName(
      widget.host.workspaces.setting('theme') as String? ?? 'system',
    );
  }

  @override
  void dispose() {
    lifecycle.dispose();
    widget.host.approveInquiryModelRequest = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.host.foundation,
    builder: (context, _) => MaterialApp(
      title: 'Muyon',
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              MediaQuery.of(context).disableAnimations ||
              widget.host.workspaces.setting('reduceMotion') == true,
        ),
        child: child!,
      ),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff356859)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff356859),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: mode,
      home: PlatformShell(
        host: widget.host,
        themeMode: mode,
        onTheme: (value) async {
          await widget.host.workspaces.setSetting('theme', value.name);
          if (mounted) setState(() => mode = value);
        },
      ),
    ),
  );
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.host,
    required this.themeMode,
    required this.onTheme,
    this.initialModule = 'inquiry',
  });
  final MuyonHost host;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  final String initialModule;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late String activeModule;
  String? workspaceId;
  ResearchSession? session;
  bool busy = false;
  String? error;
  MuyonHost get host => widget.host;
  @override
  void initState() {
    super.initState();
    activeModule = widget.initialModule;
    final saved = host.workspaces.setting('selectedWorkspace') as String?;
    if (host.workspaces.all().any((w) => w.id == saved)) workspaceId = saved;
    _open();
  }

  Future<void> _open() async {
    if (activeModule == 'inquiry') {
      await host.activateInquiry();
      if (mounted) setState(() {});
      return;
    }
    final selected = workspaceId;
    await host.activateResearch();
    if (!mounted || selected != workspaceId) return;
    final binding = selected == null
        ? null
        : host.workspaces.binding(selected, 'research');
    ResearchSession? next;
    try {
      if (binding != null && host.research != null) {
        next = await host.research!.openSession(binding);
      }
    } catch (e) {
      error = '工作区绑定需要修复：$e';
    }
    if (!mounted || selected != workspaceId) {
      await next?.dispose();
      return;
    }
    await session?.dispose();
    setState(() => session = next);
  }

  Future<void> _select(String id) async {
    if (busy) return;
    final old = session;
    setState(() {
      workspaceId = id;
      session = null;
      error = null;
    });
    await old?.dispose();
    await host.workspaces.setSetting('selectedWorkspace', id);
    await _open();
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建工作区'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '工作区名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    final workspace = await host.workspaces.create(title);
    if (mounted) await _select(workspace.id);
  }

  Future<void> _import(bool folder) async {
    final selected = workspaceId;
    if (selected == null || busy || host.research == null) return;
    final runtime = host.research!;
    final gateway = runtime.resources.files as FileGateway;
    final path = await gateway.pickResearch(folder: folder);
    if (path == null || !mounted || selected != workspaceId) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final existing = host.workspaces.binding(selected, 'research');
      final binding =
          existing ??
          WorkspaceBinding(
            workspaceId: selected,
            moduleId: 'research',
            nativeProjectId: const Uuid().v4(),
          );
      final target = existing == null
          ? ImportTarget.create(binding)
          : ImportTarget.refresh(binding);
      final prepared = await runtime.prepareImport(
        SelectedInput(path: path, displayName: p.basename(path)),
        target,
      );
      final coordinator = ImportCoordinator(host.workspaces);
      final intent = await coordinator.record(prepared);
      await coordinator.commit(runtime, prepared, intent);
      if (mounted && workspaceId == selected) await _open();
    } catch (e) {
      if (mounted) setState(() => error = '导入未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _retry() async {
    if (workspaceId == null || host.research == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final coordinator = ImportCoordinator(host.workspaces);
      for (final intent
          in coordinator
              .pending('research')
              .where((i) => i.workspaceId == workspaceId)) {
        final binding = WorkspaceBinding(
          workspaceId: intent.workspaceId,
          moduleId: intent.moduleId,
          nativeProjectId: intent.targetProjectId,
        );
        final prepared = PreparedImport(
          target: intent.kind == ImportKind.create
              ? ImportTarget.create(binding)
              : ImportTarget.refresh(binding),
          inputDigest: intent.inputDigest,
          stagingToken: intent.stagingToken,
        );
        await coordinator.commit(host.research!, prepared, intent);
      }
      await _open();
    } catch (e) {
      if (mounted) setState(() => error = '恢复失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _task(String path) async {
    final selected = workspaceId;
    final runtime = host.research;
    if (selected == null || runtime == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await _taskCore(path, selected, runtime);
    } catch (e) {
      if (mounted) setState(() => error = '任务导入未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _taskCore(
    String path,
    String selected,
    ResearchRuntime runtime,
  ) async {
    final task = await runtime.prepareTask(
      SelectedInput(path: path, displayName: p.basename(path)),
    );
    final coordinator = ImportCoordinator(host.workspaces);
    // Recover committed imports before deciding whether a source is unowned.
    await coordinator.recover('research', runtime);
    final owner = host.workspaces.ownerWorkspace('research', task.projectId);
    final current = host.workspaces.binding(selected, 'research');
    var targetWorkspace = selected;
    if (owner != null && owner != selected) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('任务属于其他工作区'),
          content: const Text('切换到已绑定该研究项目的工作区后导入？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('切换并导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      targetWorkspace = owner;
    } else if (owner == null &&
        current != null &&
        current.nativeProjectId != task.projectId) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('为来件任务创建工作区'),
          content: Text('当前工作区已绑定其他项目。新建「接收任务 · ${task.title}」并导入？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('新建并导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      targetWorkspace = (await host.workspaces.create('接收任务 · ${task.title}'))
          .id;
    }
    final binding = WorkspaceBinding(
      workspaceId: targetWorkspace,
      moduleId: 'research',
      nativeProjectId: task.projectId,
    );
    final existing = host.workspaces.binding(targetWorkspace, 'research');
    final target = existing == null
        ? ImportTarget.create(binding)
        : ImportTarget.refresh(binding);
    final prepared = await runtime.prepareTaskImport(task, target);
    final intent = await coordinator.record(prepared);
    await coordinator.commit(runtime, prepared, intent);
    if (mounted) {
      final old = session;
      setState(() {
        workspaceId = targetWorkspace;
        session = null;
      });
      await old?.dispose();
      await host.workspaces.setSetting('selectedWorkspace', targetWorkspace);
      await _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaces = host.workspaces.all();
    final selected = workspaces.where((w) => w.id == workspaceId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          activeModule == 'inquiry'
              ? 'Muyon · Folio'
              : selected == null
              ? 'Muyon · 科研'
              : 'Muyon · ${selected.title}',
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '业务插件',
            icon: const Icon(Icons.apps),
            onSelected: (id) {
              setState(() {
                activeModule = id;
                error = null;
              });
              _open();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'inquiry', child: Text('Folio · 询价与成本')),
              PopupMenuItem(value: 'research', child: Text('科研工作台')),
            ],
          ),
          if (activeModule == 'research' && session != null)
            IconButton(
              tooltip: '检索与资料问答',
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => ResearchToolsPage(
                          host: host,
                          binding: session!.binding,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.manage_search),
            ),
          if (activeModule == 'research')
            IconButton(
              tooltip: '工作区',
              onPressed: busy
                  ? null
                  : () => showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final workspace in workspaces)
                              ListTile(
                                title: Text(workspace.title),
                                selected: workspace.id == workspaceId,
                                onTap: () {
                                  Navigator.pop(context);
                                  _select(workspace.id);
                                },
                              ),
                            ListTile(
                              leading: const Icon(Icons.add),
                              title: const Text('新建工作区'),
                              onTap: () {
                                Navigator.pop(context);
                                _create();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
              icon: const Icon(Icons.workspaces_outline),
            ),
          PopupMenuButton<String>(
            tooltip: '设置与导入',
            onSelected: (value) {
              switch (value) {
                case 'folder':
                  _import(true);
                case 'zip':
                  _import(false);
                case 'retry':
                  _retry();
                case 'task':
                  final gateway =
                      host.research?.resources.files as FileGateway?;
                  gateway?.pickResearch().then((path) {
                    if (path != null && mounted) _task(path);
                  });
                default:
                  widget.onTheme(ThemeMode.values.byName(value));
              }
            },
            itemBuilder: (context) => [
              if (activeModule == 'research') ...[
                const PopupMenuItem(value: 'folder', child: Text('导入研究目录')),
                const PopupMenuItem(value: 'zip', child: Text('导入研究 ZIP')),
                const PopupMenuItem(value: 'retry', child: Text('恢复未完成导入')),
                const PopupMenuItem(value: 'task', child: Text('接收任务包')),
              ],
              for (final entry in [
                ('system', '跟随系统'),
                ('light', '浅色'),
                ('dark', '深色'),
              ])
                PopupMenuItem(value: entry.$1, child: Text(entry.$2)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null ||
              (activeModule == 'research'
                      ? host.researchError
                      : host.inquiryError) !=
                  null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                error ??
                    (activeModule == 'research'
                        ? '科研模块不可用：${host.researchError}'
                        : 'Folio 模块不可用：${host.inquiryError}'),
              ),
            ),
          Expanded(
            child: activeModule == 'inquiry'
                ? host.inquiry == null
                      ? Center(
                          child: host.inquiryError == null
                              ? const CircularProgressIndicator()
                              : FilledButton(
                                  onPressed: _open,
                                  child: const Text('重试打开 Folio'),
                                ),
                        )
                      : InquiryHome(state: host.inquiry!.runtime.state)
                : session == null
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selected == null ? '创建工作区，开始研究' : '导入研究或创建项目',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: busy ? null : _create,
                            child: const Text('新建工作区'),
                          ),
                          if (selected != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: busy ? null : () => _import(false),
                              child: const Text('导入研究 ZIP'),
                            ),
                            OutlinedButton(
                              onPressed: busy ? null : () => _import(true),
                              child: const Text('导入研究目录'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ResearchHome(
                    key: ValueKey(workspaceId),
                    store: session!.store,
                    projectId: session!.binding.nativeProjectId,
                    importTaskThroughHost: _task,
                    hosted: true,
                  ),
          ),
        ],
      ),
    );
  }
}
