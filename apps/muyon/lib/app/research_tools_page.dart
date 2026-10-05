import 'dart:async';

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';

import '../services/transfer/transfer_service.dart';
import '../workspace/import_coordinator.dart';

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
  final MuyonHost host;
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

enum ResearchImportCommitState { committed, notCommitted, unknown }

/// The receipt determines business truth independently of transfer bookkeeping.
class ResearchImportFailure implements Exception {
  const ResearchImportFailure({
    required this.itemId,
    required this.commitState,
    required this.error,
    this.receiptError,
  });
  final String itemId;
  final ResearchImportCommitState commitState;
  final Object error;
  final Object? receiptError;

  String get title => switch (commitState) {
    ResearchImportCommitState.committed => '研究数据已提交，后续状态待恢复',
    ResearchImportCommitState.notCommitted => '研究包未导入',
    ResearchImportCommitState.unknown => '研究导入结果未知',
  };

  String get description {
    final truth = switch (commitState) {
      ResearchImportCommitState.committed => '已确认持久导入回执；研究数据已提交，绑定或传输状态尚未完成。',
      ResearchImportCommitState.notCommitted => '未找到该接纳记录的导入回执；本次研究导入未提交。',
      ResearchImportCommitState.unknown => '无法确认持久回执，不能判断研究数据是否已提交。',
    };
    return '接纳记录 $itemId：$truth 错误：$error。'
        '${receiptError == null ? '' : ' 回执检查：$receiptError。'}'
        '不会自动重放研究导入。';
  }

  @override
  String toString() => '$title：$description';
}

/// Human acceptance imports data into an isolated workspace, never executes it.
/// Transfer callbacks are void; track completion and report failures durably.
class AcceptedResearchImports {
  AcceptedResearchImports(this.host);
  final MuyonHost host;
  Future<void> _settled = Future.value();
  Future<void> get settled => _settled;
  final Set<String> _admitted = {};

  static String _operation(String id) => 'transfer-research:$id';
  static String _token(TransferItem item) =>
      '${_operation(item.id)}:${item.attachmentSha256}';

  void accept(TransferItem item) {
    if (!_admitted.add(item.id)) return;
    final operation = host.trackOperation(() async {
      try {
        await _import(item);
      } catch (error, stack) {
        await _reportFailure(item, error, stack, runtime: host.research);
      }
    });
    // Admission can fail while closing; there is no new work after shutdown.
    _settled = Future.wait<void>([_settled, operation]).then<void>((_) {});
    unawaited(_settled.catchError((Object _) {}));
  }

  bool _matchesReceipt(TransferItem item, ImportReceipt receipt) =>
      receipt.intent.operationId == _operation(item.id) &&
      receipt.intent.moduleId == 'research' &&
      receipt.intent.inputDigest == item.attachmentSha256 &&
      receipt.intent.stagingToken == _token(item);

  Future<void> _reportFailure(
    TransferItem item,
    Object error,
    StackTrace stack, {
    required ResearchRuntime? runtime,
  }) async {
    var state = ResearchImportCommitState.unknown;
    Object? receiptError;
    try {
      if (runtime == null) {
        throw StateError('Research receipt store unavailable');
      }
      final receipt = await runtime.receipt(_operation(item.id));
      if (receipt == null) {
        state = ResearchImportCommitState.notCommitted;
      } else if (_matchesReceipt(item, receipt)) {
        state = ResearchImportCommitState.committed;
      } else {
        throw StateError('Receipt identity differs from accepted attachment');
      }
    } catch (inspectionError) {
      receiptError = inspectionError;
    }
    final outcome = ResearchImportFailure(
      itemId: item.id,
      commitState: state,
      error: error,
      receiptError: receiptError,
    );
    try {
      await host.foundation.notify(
        title: outcome.title,
        body: outcome.description,
      );
    } catch (notificationError) {
      // The standard production Flutter error handler/log remains observable
      // even when the notification database cannot persist the outcome.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: outcome,
          stack: stack,
          library: 'muyon.research.import',
          context: ErrorDescription('研究导入通知持久化失败：$notificationError'),
        ),
      );
    }
  }

  bool _stillAccepted(TransferItem expected) {
    final item = host.services.transfer
        .items()
        .where((row) => row.id == expected.id)
        .firstOrNull;
    return item != null &&
        item.acceptance == 'accepted' &&
        !item.imported &&
        item.delivered &&
        item.attachmentState == 'durable' &&
        item.path != null &&
        item.attachmentSha256 != null &&
        item.attachmentLength != null &&
        item.attachmentLength! > 0 &&
        item.path == expected.path &&
        item.attachmentSha256 == expected.attachmentSha256 &&
        item.attachmentLength == expected.attachmentLength &&
        item.peerFingerprint == expected.peerFingerprint;
  }

  void _requireAccepted(TransferItem expected) {
    if (!_stillAccepted(expected)) {
      throw StateError('接纳已撤销、附件状态改变或导入已完成');
    }
  }

  Future<void> _import(TransferItem item) async {
    _requireAccepted(item);
    // Start activation within the admitted host operation so close can drain it.
    await host.activateResearch();
    _requireAccepted(item);
    final runtime = host.research;
    if (runtime == null) {
      throw StateError(host.researchError ?? 'Research unavailable');
    }
    final path = item.path!;
    const limit = TransferService.maxBytes * 2;
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        item.attachmentLength! > limit ||
        await File(path).length() != item.attachmentLength) {
      throw const FormatException('研究附件缺失、大小改变或不是普通文件');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(0, limit + 1)) {
      buffer.add(chunk);
      if (buffer.length > limit) throw const FormatException('研究附件过大');
    }
    final bytes = buffer.takeBytes();
    if (bytes.length != item.attachmentLength ||
        sha256.convert(bytes).toString() != item.attachmentSha256) {
      throw const FormatException('研究附件与人工接纳的摘要不一致');
    }
    _requireAccepted(item);
    // Other accepted attachments belong to their own business handlers.
    if (!TransferService.isResearchPackage(bytes)) return;
    final exchange = ResearchPackageExchange(
      CardStore(runtime.resources.database),
    );
    final projectId = const Uuid().v4();
    ImportTarget target(String workspaceId) => ImportTarget.create(
      WorkspaceBinding(
        workspaceId: workspaceId,
        moduleId: 'research',
        nativeProjectId: projectId,
      ),
    );
    // Validate the complete frozen bytes before creating any host workspace.
    exchange.prepareBytes(
      bytes,
      target(_operation(item.id)),
      stagingToken: _token(item),
    );
    _requireAccepted(item);
    final workspace = await host.workspaces.create('接纳的研究包 · ${item.id}');
    _requireAccepted(item);
    final prepared = exchange.prepareBytes(
      bytes,
      target(workspace.id),
      stagingToken: _token(item),
      checkBeforeCommit: () => _requireAccepted(item),
    );
    final coordinator = ImportCoordinator(host.workspaces);
    final intent = await coordinator.record(
      prepared,
      operationId: _operation(item.id),
    );
    _requireAccepted(item);
    await coordinator.commit(runtime, prepared, intent);
    _requireAccepted(item);
    await host.services.transfer.markImported(item.id);
  }

  /// Restore only completed business imports. Never commit pending input here.
  Future<void> reconcileCommitted(ResearchRuntime runtime) async {
    for (final item in host.services.transfer.items()) {
      if (item.acceptance != 'accepted' || item.imported) continue;
      try {
        final receipt = await runtime.receipt(_operation(item.id));
        if (receipt == null) continue;
        if (!_matchesReceipt(item, receipt)) {
          throw StateError('Receipt identity differs from accepted attachment');
        }
        final rows = host.workspaces.database.raw.select(
          'SELECT status FROM import_intents WHERE operation_id=?',
          [_operation(item.id)],
        );
        if (rows.isEmpty || rows.single['status'] != 'complete') continue;
        // Revalidate the durable host identity and binding before the transfer flag.
        if (!_stillAccepted(item)) continue;
        await ImportCoordinator(host.workspaces).activate(receipt);
        if (!_stillAccepted(item)) continue;
        await host.services.transfer.markImported(item.id);
      } catch (error, stack) {
        // A transfer bookkeeping failure must not disable the research module
        // or block independent receipts. Never replay the domain commit here.
        await _reportFailure(item, error, stack, runtime: runtime);
      }
    }
  }
}
