import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:research_module/research_module.dart';

import '../assistant/execution_store.dart';
import '../assistant/qa_service.dart';
import '../services/models/model_gateway.dart';
import '../services/models/profile_repository.dart';
import '../services/models/secret_store.dart';
import '../services/search/search_service.dart';
import '../services/knowledge/research_search_adapter.dart';
import 'bootstrap.dart';

class ResearchToolsPage extends StatefulWidget {
  const ResearchToolsPage({
    super.key,
    required this.host,
    required this.binding,
  });
  final MuSpaceHost host;
  final WorkspaceBinding binding;
  @override
  State<ResearchToolsPage> createState() => _ResearchToolsPageState();
}

class _ResearchToolsPageState extends State<ResearchToolsPage> {
  final question = TextEditingController();
  final selected = <String>{};
  SearchService? search;
  QaService? qa;
  SearchResult? result;
  QaAnswer? answer;
  QaRequest? request;
  bool busy = false;
  String? error;
  String? profileId;
  late final profiles = ProfileRepository(widget.host.workspaces);
  WorkspaceBinding get binding => widget.binding;
  ExecutionStore get executions =>
      ExecutionStore(widget.host.workspaces.database);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final pending = request;
    if (pending != null) qa?.cancel(pending.executionId);
    question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final service = ResearchSearchAdapter(
        widget.host.services.knowledge,
        widget.host.workspaces,
        widget.host.research!.store,
      );
      final assistant = QaService(
        gateway: widget.host.services.gateway,
        executions: executions,
        evidenceProvider: (context, question) async {
          final hits = await service.search(
            binding,
            question,
            selectedDocumentIds: context.selectedObjectRefs
                .map((r) => r.objectId)
                .toSet(),
          );
          if (hits.partial || hits.unavailable.isNotEmpty) {
            throw StateError('请先完成所选资料的索引');
          }
          return [
            for (var i = 0; i < hits.hits.length; i++)
              QaEvidence(
                id: 'source-$i',
                documentId: hits.hits[i].document.id,
                contentDigest: hits.hits[i].contentDigest,
                pageIndex: hits.hits[i].pageIndex,
                text: hits.hits[i].text,
              ),
          ];
        },
        evidenceValidator: (context, evidence) async {
          final current = widget.host.workspaces.binding(
            context.workspaceId,
            context.moduleId,
          );
          if (current?.nativeProjectId != context.nativeProjectId) return false;
          final documents = {
            for (final doc in service.documents(binding)) doc.id: doc,
          };
          for (final ref in context.selectedObjectRefs) {
            final doc = documents[ref.objectId];
            if (doc == null || !await File(doc.absolutePath).exists()) {
              return false;
            }
            if ((await sha256.bind(File(doc.absolutePath).openRead()).first)
                    .toString() !=
                ref.contentDigest) {
              return false;
            }
          }
          for (final e in evidence) {
            if (!context.selectedObjectRefs.any(
              (r) =>
                  r.objectId == e.documentId &&
                  r.contentDigest == e.contentDigest,
            )) {
              return false;
            }
          }
          return true;
        },
      );
      if (mounted) {
        setState(() {
          search = service;
          qa = assistant;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _action(Future<void> Function() body) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().contains('insufficient_evidence')
              ? '所选资料证据不足。'
              : '操作未完成：$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _index() => _action(() async {
    for (final doc
        in search!.documents(binding).where((d) => selected.contains(d.id))) {
      await search!.index(binding, doc);
    }
  });
  Future<void> _search() => _action(() async {
    final hits = await search!.search(
      binding,
      question.text,
      selectedDocumentIds: Set.of(selected),
    );
    if (mounted) {
      setState(() {
        result = hits;
        answer = null;
      });
    }
  });
  Future<void> _ask() => _action(() async {
    final profile = profiles.all().where((p) => p.id == profileId).firstOrNull;
    if (profile == null) throw StateError('请明确选择模型端点');
    final documents = search!
        .documents(binding)
        .where((d) => selected.contains(d.id));
    final refs = <ObjectRef>[];
    for (final doc in documents) {
      refs.add(
        ObjectRef(
          moduleId: 'research',
          objectType: 'document',
          objectId: doc.id,
          nativeProjectId: binding.nativeProjectId,
          contentDigest:
              (await sha256.bind(File(doc.absolutePath).openRead()).first)
                  .toString(),
        ),
      );
    }
    final contextRef = ContextRef(
      workspaceId: binding.workspaceId,
      moduleId: 'research',
      nativeProjectId: binding.nativeProjectId,
      selectedObjectRefs: refs,
    );
    final prepared = await qa!.prepare(
      context: contextRef,
      profile: profile,
      question: question.text,
    );
    if (!mounted) return;
    request = prepared;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('授权本次资料问答'),
        content: SingleChildScrollView(
          child: Text(
            '目标：${profile.endpoint}\n位置：${profile.location.name}\n模型：${profile.modelId}\n${profile.cloudProxy ? '提供者声明可能代理到云端' : '未声明云代理；位置仅代表第一跳'}\n\n发送问题和 ${prepared.evidence.length} 个所选原文片段：\n${question.text}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('授权并发送'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      request = null;
      return;
    }
    final response = await qa!.run(prepared, prepared.approve());
    if (mounted) {
      setState(() {
        answer = response;
        result = null;
      });
    }
    request = null;
  });
  Future<void> _open(SearchHit hit) async {
    final current = search!
        .documents(binding)
        .where((d) => d.id == hit.document.id)
        .firstOrNull;
    if (current == null ||
        (await sha256.bind(File(current.absolutePath).openRead()).first)
                .toString() !=
            hit.contentDigest) {
      throw StateError('来源缺失或已换版');
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => ReaderPage(
          store: widget.host.research!.store.scoped(binding.nativeProjectId),
          document: current,
          initialPageIndex: hit.pageIndex,
          initialQuote: hit.text.length > 500
              ? hit.text.substring(0, 500)
              : hit.text,
        ),
      ),
    );
  }

  Future<void> _profile() async {
    final endpoint = TextEditingController(
      text: 'http://127.0.0.1:11434/v1/chat/completions',
    );
    final model = TextEditingController();
    final token = TextEditingController();
    var location = ModelLocation.local;
    var cloudProxy = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('配置模型端点'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ModelLocation>(
                  initialValue: location,
                  items: [
                    for (final value in ModelLocation.values)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                  onChanged: (value) => setDialog(() => location = value!),
                ),
                TextField(
                  controller: endpoint,
                  decoration: const InputDecoration(
                    labelText: 'chat/completions 完整 URL',
                  ),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: '模型名'),
                ),
                TextField(
                  controller: token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: '密钥（仅写入系统密钥库）'),
                ),
                CheckboxListTile(
                  value: cloudProxy,
                  onChanged: (value) => setDialog(() => cloudProxy = value!),
                  title: const Text('提供者可能代理到云端'),
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
      ),
    );
    try {
      if (save != true) return;
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final reference = token.text.isEmpty ? null : 'model-$id';
      final profile = ModelProfile(
        id: id,
        endpoint: Uri.parse(endpoint.text.trim()),
        location: location,
        modelId: model.text.trim(),
        endpointIdentity: endpoint.text.trim(),
        credentialRef: reference,
        cloudProxy: cloudProxy,
      );
      if (reference != null) {
        await const MethodChannelSecretStore().write(reference, token.text);
      }
      await profiles.save(profile);
      if (mounted) setState(() => profileId = id);
    } catch (e) {
      if (mounted) setState(() => error = '模型设置未保存：$e');
    } finally {
      endpoint.dispose();
      model.dispose();
      token.clear();
      token.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = search?.documents(binding) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('原文检索与资料问答'),
        actions: [
          IconButton(
            tooltip: '模型设置',
            onPressed: busy ? null : _profile,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('仅在明确选择的当前工作区资料中检索；模型关闭时仍可离线使用。'),
            for (final doc in documents)
              CheckboxListTile(
                value: selected.contains(doc.id),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        value! ? selected.add(doc.id) : selected.remove(doc.id);
                        result = null;
                        answer = null;
                      }),
                title: Text(doc.title),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy || selected.isEmpty ? null : _index,
                  child: const Text('索引所选原文'),
                ),
                OutlinedButton(
                  onPressed: busy || selected.isEmpty ? null : _search,
                  child: const Text('离线检索'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: question,
              enabled: !busy,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '问题或原文关键词',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: profileId,
              decoration: const InputDecoration(labelText: '明确选择模型端点'),
              items: [
                for (final profile in profiles.all())
                  DropdownMenuItem(
                    value: profile.id,
                    child: Text(
                      '${profile.modelId} · ${profile.location.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => profileId = value),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy || selected.isEmpty || profileId == null
                      ? null
                      : _ask,
                  child: const Text('基于所选资料问答'),
                ),
                if (busy && request != null)
                  TextButton(
                    onPressed: () => qa?.cancel(request!.executionId),
                    child: const Text('取消问答'),
                  ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) SelectableText(error!),
            if (result != null) ...[
              if (result!.partial) const Text('未完整查找：达到页数上限。'),
              if (result!.unavailable.isNotEmpty)
                Text('未就绪资料：${result!.unavailable.values.join('、')}'),
              if (result!.hits.isEmpty &&
                  !result!.partial &&
                  result!.unavailable.isEmpty)
                const Text('所选已索引资料中无结果。'),
              for (final hit in result!.hits)
                Card(
                  child: ListTile(
                    title: Text(
                      '${hit.document.title} · ${hit.pageIndex + 1} 页',
                    ),
                    subtitle: Text(
                      hit.text,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _open(hit),
                  ),
                ),
            ],
            if (answer != null) ...[
              SelectableText(answer!.text),
              const Text('引用定位已经核对；论断是否受支持仍需人工评估。'),
              for (final citation in answer!.citations)
                TextButton(
                  onPressed: () {
                    final doc = documents
                        .where((d) => d.id == citation.documentId)
                        .firstOrNull;
                    if (doc != null) {
                      _open(
                        SearchHit(
                          document: doc,
                          contentDigest: citation.contentDigest,
                          pageIndex: citation.pageIndex,
                          text: citation.text,
                        ),
                      );
                    }
                  },
                  child: Text(
                    '${citation.documentId} · ${citation.pageIndex + 1} 页',
                  ),
                ),
            ],
            const Divider(),
            const Text('执行记录'),
            for (final execution in executions.all().where(
              (r) => r.contextSnapshot.workspaceId == binding.workspaceId,
            ))
              ListTile(
                title: Text('${execution.toolId} · ${execution.state.name}'),
                subtitle: Text(
                  '${execution.executionDeviceId} · ${execution.stage}',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('执行产物'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        executions.answer(execution.executionId) ??
                            execution.error ??
                            execution.state.name,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
