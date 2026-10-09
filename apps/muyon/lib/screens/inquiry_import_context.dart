import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../app/adapters/inquiry_module.dart';
import '../app/bootstrap.dart';
import '../app/import_review_projection.dart';
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
  bool busy = false;
  List<Hit> projects = [];
  List<({PreparedInquiryDraft draft, int page})> drafts = [];
  InquiryModuleRuntime? get runtime =>
      widget.host.modules.runtime<InquiryModuleRuntime>('inquiry');
  @override
  void initState() {
    super.initState();
    workspace = widget.host.foundation.task(widget.taskId)?.scope.workspaceId;
    if (HostUiWorkspaceStore(
      widget.host.foundation,
      taskId: widget.taskId,
    ).surfaces().any((s) => s.startsWith('import:'))) {
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
    for (final surface in HostUiWorkspaceStore(
      widget.host.foundation,
      taskId: widget.taskId,
    ).surfaces()) {
      final parts = surface.split(':');
      if (parts.length != 4 || parts.first != 'import' || parts[2] != 'page') {
        continue;
      }
      final page = int.tryParse(parts.last);
      if (page == null || page < 0) continue;
      final draft = await owner.resumeImport(parts[1]);
      if (page * ImportReviewProjection.pageSize < draft.recordIds.length) {
        found.add((draft: draft, page: page));
      }
    }
    if (!mounted) return;
    setState(() {
      drafts = found;
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
        project == null ||
        widget.host.foundation.task(widget.taskId) == null) {
      throw StateError('请先选择插件、来源与目标');
    }
    if (documentId != null &&
        !await widget.host.services.knowledge.isCurrent(documentId!)) {
      throw StateError('来源文件已改变，请重新导入平台副本');
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
    final workspaces = widget.host.workspaces.all();
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
          DropdownButtonFormField<String>(
            key: ValueKey('import-project-$workspace'),
            initialValue: projects.any((p) => p.id == project) ? project : null,
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
                busy || input == null || workspace == null || project == null
                ? null
                : launch,
            child: const Text('进入用途选择'),
          ),
        ],
        if (error != null) Text(error!),
      ],
    );
  }
}
