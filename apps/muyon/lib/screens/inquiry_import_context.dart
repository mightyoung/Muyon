import 'package:file_picker/file_picker.dart';
import 'package:inquiry_module/inquiry_module.dart' show suggestProjectCode;
import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../app/adapters/inquiry_module.dart';
import '../app/bootstrap.dart';
import '../app/import_review_projection.dart';
import '../app/inquiry_list_review.dart';
import '../platform/ui_workspace_store.dart';
import '../workspace/import_coordinator.dart';

/// Human file-context entry in an existing task. It does not create/run an
/// agent task, register a model tool or enable global UI planning.
class InquiryImportContextPage extends StatefulWidget {
  const InquiryImportContextPage({
    super.key,
    required this.host,
    required this.taskId,
    this.pickInput,
  });
  final MuyonHost host;
  final String taskId;
  final Future<SelectedInput?> Function()? pickInput;
  @override
  State<InquiryImportContextPage> createState() =>
      _InquiryImportContextPageState();
}

class _InquiryImportContextPageState extends State<InquiryImportContextPage> {
  String? plugin, workspace, project, documentId, error;
  SelectedInput? input;
  String function = 'offers';
  final listName = TextEditingController(), listCode = TextEditingController();
  List<({PreparedInquiryListDraft draft, int page})> listDrafts = [];
  @override
  void dispose() {
    listName.dispose();
    listCode.dispose();
    super.dispose();
  }

  bool busy = false;
  List<Hit> projects = [];
  List<({PreparedInquiryDraft draft, int page})> drafts = [];
  InquiryModuleRuntime? get runtime =>
      widget.host.modules.runtime<InquiryModuleRuntime>('inquiry');
  @override
  void initState() {
    super.initState();
    workspace = widget.host.foundation.task(widget.taskId)?.scope.workspaceId;
    if (HostUiWorkspaceStore(widget.host.foundation, taskId: widget.taskId)
        .surfaces()
        .any((s) => s.startsWith('import:') || s.startsWith('list-import:'))) {
      selectPlugin('inquiry');
    }
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final owner = runtime;
    if (owner == null) throw StateError('询价插件不可用');
    final found = <({PreparedInquiryDraft draft, int page})>[];
    final foundLists = <({PreparedInquiryListDraft draft, int page})>[];
    for (final surface in HostUiWorkspaceStore(
      widget.host.foundation,
      taskId: widget.taskId,
    ).surfaces()) {
      final parts = surface.split(':');
      if (parts.length != 4 ||
          !['import', 'list-import'].contains(parts.first) ||
          parts[2] != 'page') {
        continue;
      }
      final page = int.tryParse(parts.last);
      if (page == null || page < 0) continue;
      if (parts.first == 'list-import') {
        final draft = await owner.resumeListImport(parts[1]);
        if (page * InquiryListReviewPage.pageSize < draft.recordIds.length) {
          foundLists.add((draft: draft, page: page));
        }
        continue;
      }
      final draft = await owner.resumeImport(parts[1]);
      if (page * ImportReviewProjection.pageSize < draft.recordIds.length) {
        found.add((draft: draft, page: page));
      }
    }
    if (!mounted) return;
    setState(() {
      drafts = found;
      listDrafts = foundLists;
      projects = owner.imports.state.store.searchByName(
        'project',
        '',
        limit: 500,
      );
    });
  }

  Future<void> selectPlugin(String value) => act(() async {
    if (value != 'inquiry') throw StateError('所选插件尚无此导入入口');
    await widget.host.activateInquiry();
    if (!mounted) return;
    setState(() => plugin = value);
    await refresh();
    listCode.text = suggestProjectCode(runtime!.owner.runtime.state);
    final binding = workspace == null
        ? null
        : widget.host.workspaces.binding(workspace!, 'inquiry');
    if (mounted) setState(() => project = binding?.nativeProjectId);
  });
  Future<void> pick() => act(() async {
    SelectedInput? selected;
    if (widget.pickInput != null) {
      selected = await widget.pickInput!();
    } else {
      final files = await FilePicker.pickFiles();
      if (files.isNotEmpty && files.first.path != null) {
        selected = SelectedInput(
          path: files.first.path!,
          displayName: files.first.name,
        );
      }
    }
    if (selected != null && mounted) {
      setState(() {
        input = selected;
        documentId = null;
      });
    }
  });
  Future<void> launch() => act(() async {
    if (plugin != 'inquiry' ||
        input == null ||
        workspace == null ||
        (function == 'offers' && project == null) ||
        (function == 'list' && listName.text.trim().isEmpty) ||
        widget.host.foundation.task(widget.taskId) == null) {
      throw StateError('请先选择插件、来源与目标');
    }
    if (documentId != null &&
        !await widget.host.services.knowledge.isCurrent(documentId!)) {
      throw StateError('来源文件已改变，请重新导入平台副本');
    }
    if (function == 'list') {
      if (widget.host.workspaces.binding(workspace!, 'inquiry') != null) {
        throw StateError('新建清单请选择未绑定询价的工作区');
      }
      final target = ImportTarget.create(
        WorkspaceBinding(
          workspaceId: workspace!,
          moduleId: 'inquiry',
          nativeProjectId: newUuid(),
        ),
      );
      final draft = await runtime!.prepareListImport(input!, target, {
        'name': listName.text.trim(),
        'code': listCode.text.trim(),
      });
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('新建项目清单预览')),
            body: InquiryListReviewPage(
              host: widget.host,
              taskId: widget.taskId,
              draft: draft,
            ),
          ),
        ),
      );
      await refresh();
      return;
    }
    final binding = widget.host.workspaces.binding(workspace!, 'inquiry');
    if (binding != null && binding.nativeProjectId != project) {
      throw StateError('工作区目标已改变');
    }
    final ownerWorkspace = widget.host.workspaces.ownerWorkspace(
      'inquiry',
      project!,
    );
    if (ownerWorkspace != null && ownerWorkspace != workspace) {
      throw StateError('项目已属于其他工作区，请重新选择目标');
    }
    final targetBinding = WorkspaceBinding(
      workspaceId: workspace!,
      moduleId: 'inquiry',
      nativeProjectId: project!,
    );
    final target = binding == null
        ? ImportTarget.create(targetBinding)
        : ImportTarget.refresh(targetBinding);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('选择导入用途')),
          body: InquiryImportEntry(
            host: widget.host,
            taskId: widget.taskId,
            input: input!,
            target: target,
          ),
        ),
      ),
    );
    await refresh();
  });
  Future<void> resume(PreparedInquiryDraft draft, int page) => act(() async {
    final owner = runtime;
    if (owner == null) throw StateError('询价插件不可用');
    final coordinator = ImportCoordinator(widget.host.workspaces);
    for (final intent
        in coordinator
            .pending('inquiry')
            .where((i) => i.stagingToken.startsWith('${draft.draftId}:'))) {
      final receipt = await owner.receipt(intent.operationId);
      if (receipt != null) {
        if (!receipt.intent.sameIdentity(intent)) throw StateError('回执身份不匹配');
        await coordinator.activate(receipt);
      }
    }
    final projection = ImportReviewProjection(
      widget.host,
      owner,
      draft,
      taskId: widget.taskId,
      page: page,
    );
    final controller = await projection.open();
    if (!mounted) {
      controller.dispose();
      return;
    }
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('继续导入草稿')),
            body: ImportReviewView(
              projection: projection,
              controller: controller,
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
    await refresh();
  });
  @override
  Widget build(BuildContext context) {
    final task = widget.host.foundation.task(widget.taskId);
    if (task == null) return const Center(child: Text('原任务不可用'));
    final workspaces = widget.host.workspaces
        .all()
        .where(
          (w) =>
              function != 'list' ||
              widget.host.workspaces.binding(w.id, 'inquiry') == null,
        )
        .toList();
    final binding = workspace == null
        ? null
        : widget.host.workspaces.binding(workspace!, 'inquiry');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(task.prompt),
        DropdownButtonFormField<String>(
          key: const ValueKey('import-plugin'),
          initialValue: plugin,
          decoration: const InputDecoration(labelText: '目标插件'),
          items: const [DropdownMenuItem(value: 'inquiry', child: Text('询价'))],
          onChanged: busy ? null : (v) => selectPlugin(v!),
        ),
        if (plugin == 'inquiry') ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('import-function'),
            initialValue: function,
            decoration: const InputDecoration(labelText: '导入功能'),
            items: const [
              DropdownMenuItem(value: 'offers', child: Text('报价或材料')),
              DropdownMenuItem(value: 'list', child: Text('新建项目清单')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    function = v!;
                    if (function == 'list' &&
                        workspace != null &&
                        widget.host.workspaces.binding(workspace!, 'inquiry') !=
                            null) {
                      workspace = null;
                    }
                  }),
          ),
          for (final saved in listDrafts)
            ListTile(
              title: const Text('继续项目清单草稿'),
              subtitle: Text(
                '${saved.draft.project['name']} · 第${saved.page + 1}组',
              ),
              onTap: busy
                  ? null
                  : () => act(() async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('继续项目清单草稿')),
                            body: InquiryListReviewPage(
                              host: widget.host,
                              taskId: widget.taskId,
                              draft: saved.draft,
                              page: saved.page,
                            ),
                          ),
                        ),
                      );
                      await refresh();
                    }),
            ),
          for (final saved in drafts)
            ListTile(
              title: const Text('继续导入草稿'),
              subtitle: Text('${saved.draft.sourceName} · 第${saved.page + 1}组'),
              onTap: busy ? null : () => resume(saved.draft, saved.page),
            ),
          DropdownButtonFormField<String>(
            key: ValueKey('workspace-$workspace'),
            initialValue: workspaces.any((w) => w.id == workspace)
                ? workspace
                : null,
            decoration: const InputDecoration(labelText: '目标工作区'),
            items: [
              for (final w in workspaces)
                DropdownMenuItem(value: w.id, child: Text(w.title)),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    workspace = v;
                    project = widget.host.workspaces
                        .binding(v!, 'inquiry')
                        ?.nativeProjectId;
                  }),
          ),
          if (function == 'list') ...[
            TextField(
              key: const ValueKey('list-project-name'),
              controller: listName,
              decoration: const InputDecoration(labelText: '新项目名称'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: listCode,
              decoration: const InputDecoration(labelText: '新项目编号'),
            ),
          ],
          if (function == 'offers')
            DropdownButtonFormField<String>(
              key: ValueKey('import-project-$workspace'),
              initialValue: projects.any((p) => p.id == project)
                  ? project
                  : null,
              decoration: const InputDecoration(labelText: '目标项目'),
              items: [
                for (final p in projects)
                  if ((binding == null || p.id == binding.nativeProjectId) &&
                      (widget.host.workspaces.ownerWorkspace('inquiry', p.id) ==
                              null ||
                          widget.host.workspaces.ownerWorkspace(
                                'inquiry',
                                p.id,
                              ) ==
                              workspace))
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.data['name'] as String),
                    ),
              ],
              onChanged: busy ? null : (v) => setState(() => project = v),
            ),
          DropdownButtonFormField<String>(
            initialValue: documentId,
            decoration: const InputDecoration(labelText: '已有来源文件'),
            items: [
              for (final d in widget.host.services.knowledge.documents())
                DropdownMenuItem(value: d.id, child: Text(d.title)),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    final d = widget.host.services.knowledge.require(v!);
                    documentId = v;
                    input = SelectedInput(path: d.path, displayName: d.title);
                  }),
          ),
          TextButton(
            onPressed: busy ? null : pick,
            child: const Text('选择本地文件'),
          ),
          if (input != null) Text('来源：${input!.displayName}'),
          FilledButton(
            onPressed:
                busy ||
                    input == null ||
                    workspace == null ||
                    (function == 'offers'
                        ? project == null
                        : listName.text.trim().isEmpty)
                ? null
                : launch,
            child: Text(function == 'list' ? '准备新项目清单' : '进入用途选择'),
          ),
        ],
        if (error != null) Text(error!),
      ],
    );
  }
}
