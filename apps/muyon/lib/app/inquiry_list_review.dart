import 'package:flutter/material.dart';
import 'package:supplier_core/supplier_core.dart' show Hit, parseQty;
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'adapters/inquiry_module.dart';
import 'bootstrap.dart';
import '../platform/ui_workspace_store.dart';
import '../workspace/import_coordinator.dart';

/// Human-only projection of the original new-project list workflow.
class InquiryListReviewPage extends StatefulWidget {
  const InquiryListReviewPage({
    super.key,
    required this.host,
    required this.taskId,
    required this.draft,
    this.page = 0,
  });
  final MuyonHost host;
  final String taskId;
  final PreparedInquiryListDraft draft;
  final int page;
  static const pageSize = 5;
  @override
  State<InquiryListReviewPage> createState() => _InquiryListReviewPageState();
}

class _InquiryListReviewPageState extends State<InquiryListReviewPage> {
  UiWorkspaceController? controller;
  late int page = widget.page;
  bool busy = false;
  String? error;
  ImportReceipt? receipt;
  PreparedInquiryListDraft get draft => widget.draft;
  InquiryModuleRuntime get runtime =>
      widget.host.modules.runtime<InquiryModuleRuntime>('inquiry')!;
  String get surfaceId => 'list-import:${draft.draftId}:page:$page';
  List<InquiryListRecord> get records => draft.records
      .skip(page * InquiryListReviewPage.pageSize)
      .take(InquiryListReviewPage.pageSize)
      .toList();
  int get pageCount =>
      (draft.recordIds.length + InquiryListReviewPage.pageSize - 1) ~/
      InquiryListReviewPage.pageSize;
  static const projectLabels = {
    'name': '新项目名称',
    'code': '新项目编号',
    'customer': '客户',
    'markup_rate': '加价率',
  };
  static const labels = {
    'name': '清单名称',
    'requirements': '需求',
    'qty': '数量原文',
    'unit': '单位原文',
  };
  String? value(InquiryListRecord r, String f) => switch (f) {
    'name' => r.line.item.name,
    'requirements' => r.line.item.requirements,
    'qty' => r.line.item.qty,
    'unit' => r.line.item.unit,
    _ => null,
  };
  ValidatedUiPlan get plan {
    final ref = SnapshotRef('list:${draft.draftId}', draft.revision);
    final facts = <String, SnapshotFact>{};
    final values = <String, Object?>{};
    final nodes = <UiNode>[];
    for (final f
        in page == 0
            ? projectLabels.entries
            : const <MapEntry<String, String>>[]) {
      final key = 'project:${f.key}';
      final v = draft.project[f.key];
      values[key] = v ?? '';
      facts[key] = SnapshotFact(
        object: ObjectRef(
          moduleId: 'inquiry',
          objectType: 'newProjectDraft',
          objectId: draft.draftId,
        ),
        field: f.value,
        value: v,
        state: FactState.unverified,
      );
      nodes.add(
        UiNode(
          id: key,
          component: 'Field',
          properties: {'label': f.value, 'inputType': 'text'},
          bindings: {
            'value': BindingRef.fact(key),
            'draft': BindingRef.uiState(key),
          },
          events: draft.projectCreated
              ? const {}
              : {
                  'change': ActionBinding(actionRef: 'edit', inputRefs: [key]),
                },
        ),
      );
    }
    for (final r in records) {
      for (final f in labels.entries) {
        final key = '${r.id}:${f.key}';
        final v = value(r, f.key);
        facts[key] = SnapshotFact(
          object: ObjectRef(
            moduleId: 'inquiry',
            objectType: 'listDraft',
            objectId: '${draft.draftId}:${r.id}',
          ),
          field: f.value,
          value: v,
          state: FactState.unverified,
          sourceRefs: ['source'],
        );
        values[key] = v ?? '';
        nodes.add(
          UiNode(
            id: key,
            component: 'Field',
            properties: {'label': f.value, 'inputType': 'text'},
            bindings: {
              'value': BindingRef.fact(key),
              'draft': BindingRef.uiState(key),
            },
            events: r.receiptRef != null
                ? const {}
                : {
                    'change': ActionBinding(
                      actionRef: 'edit',
                      inputRefs: [key],
                    ),
                  },
          ),
        );
      }
    }
    nodes.add(
      UiNode(
        id: 'source',
        component: 'SourceList',
        bindings: {'source': const BindingRef.sourceSpan('source')},
        events: {'tap': ActionBinding(actionRef: 'source')},
      ),
    );
    final snapshot = DataSnapshot(
      ref: ref,
      facts: facts,
      initialUiState: values,
      sources: {
        'source': SourceSpanRef(
          artifact: ArtifactRef(
            moduleId: 'inquiry',
            artifactId: draft.draftId,
            contentDigest: draft.sourceDigest,
          ),
          originalText: draft.sourceText,
          start: 0,
          end: draft.sourceText.length,
        ),
      },
      sourceDigests: {draft.draftId: draft.sourceDigest},
    );
    final intent = InteractionIntent(
      id: 'new-project-list-review',
      purpose: '人工确认新建项目清单',
      snapshotRef: ref,
      requiredBindings: {const BindingRef.sourceSpan('source')},
      allowedActionRefs: {'edit', 'source'},
    );
    final ui = UIPlan(
      surfaceId: surfaceId,
      revision: draft.revision,
      catalogVersion: dynamicUiCatalog.version,
      snapshotRef: ref,
      intentRef: intent.id,
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'PageScaffold',
          properties: {'title': '新建项目清单预览'},
          children: nodes.map((n) => n.id).toList(),
        ),
        ...nodes,
      ],
    );
    final result = validateUiPlan(ui, snapshot, intent, dynamicUiCatalog);
    if (!result.isValid) throw StateError(result.errors.join('; '));
    return result.validatedPlan!;
  }

  @override
  void initState() {
    super.initState();
    run(() => refresh());
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '未确认完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final store = HostUiWorkspaceStore(
      widget.host.foundation,
      taskId: widget.taskId,
    );
    final scope = store.scopeKey;
    if (scope == null) throw StateError('Owning task unavailable');
    final next = await UiWorkspaceController.open(
      store: store,
      taskId: widget.taskId,
      scopeKey: scope,
      plan: plan,
      receiptLookup: (id) async => await runtime.receipt(id) == null
          ? UiOperationRecovery.unknown
          : UiOperationRecovery.succeeded,
    );
    if (!mounted) {
      next.dispose();
      return;
    }
    final valid = records.where((r) => r.valid).map((r) => r.id).toSet();
    next.selectedRecords.removeWhere((id) => !valid.contains(id));
    if (!next.readOnly) await next.flush();
    final old = controller;
    setState(() => controller = next);
    old?.dispose();
  }

  Future<void> sync() async {
    final c = controller!;
    if (c.readOnly ||
        c.taskId != widget.taskId ||
        c.surface.current.plan.surfaceId != surfaceId ||
        c.surface.current.snapshot.ref.revision != draft.revision ||
        !identical(draft.pipeline, runtime.imports)) {
      throw StateError('List review changed; reopen');
    }
    await c.flush();
    for (final e in c.surface.session.userOverrides.entries) {
      final parts = e.key.split(':');
      if (parts.length == 2 &&
          parts[0] == 'project' &&
          page == 0 &&
          projectLabels.containsKey(parts[1]) &&
          e.value is String) {
        if ((draft.project[parts[1]] ?? '') != e.value) {
          await draft.editProject(parts[1], e.value as String);
        }
        continue;
      }
      if (parts.length != 2 ||
          !labels.containsKey(parts[1]) ||
          !records.any((r) => r.id == parts[0]) ||
          e.value is! String) {
        throw StateError('Field outside list group');
      }
      final r = records.singleWhere((r) => r.id == parts[0]);
      final v = (e.value as String).isEmpty ? null : e.value as String;
      if (value(r, parts[1]) != v) {
        await draft.edit(r.id, parts[1], v);
      }
    }
  }

  Future<void> commit() => run(() async {
    final c = controller!;
    final selected = List<String>.of(c.selectedRecords);
    if (selected.any((id) => !records.any((r) => r.id == id))) {
      throw StateError('Confirm visible group only');
    }
    await sync();
    final prepared = await draft.confirm(selected);
    final coordinator = ImportCoordinator(widget.host.workspaces);
    final pending = coordinator
        .pending('inquiry')
        .where(prepared.matches)
        .toList();
    if (pending.length > 1) throw StateError('Multiple pending confirmations');
    final intent = pending.isEmpty
        ? await coordinator.record(prepared)
        : pending.single;
    c.surface.lockRecoveredOperations([intent.operationId]);
    c.step = 'submitting';
    await c.flush();
    final result = await coordinator.commit(runtime, prepared, intent);
    c.step = 'receipt';
    await c.flush();
    if (mounted) setState(() => receipt = result);
    await refresh();
  });
  Future<void> query() => run(() async {
    final c = controller!;
    final coordinator = ImportCoordinator(widget.host.workspaces);
    var unknown = false;
    for (final id in c.surface.operationRefs) {
      final found = await runtime.receipt(id);
      if (found == null) {
        unknown = true;
        continue;
      }
      final i = found.intent;
      final b = draft.target.binding;
      if (i.operationId != id ||
          i.workspaceId != b.workspaceId ||
          i.moduleId != 'inquiry' ||
          i.targetProjectId != b.nativeProjectId ||
          !i.stagingToken.startsWith('list:${draft.draftId}:')) {
        throw StateError('Receipt outside reviewed list');
      }
      await coordinator.activate(found);
      receipt = found;
    }
    await refresh();
    if (mounted && unknown) setState(() => error = '回执尚未确认，未重新执行导入');
  });
  Future<void> move(int next) => run(() async {
    await sync();
    page = next;
    await refresh();
  });
  Future<void> choose(InquiryListRecord record, String? id) => run(() async {
    await sync();
    await draft.choose(record.id, id);
    await refresh();
  });
  String candidateLabel(Hit product) => [
    for (final key in ['name', 'brand', 'model', 'specification', 'unit'])
      if (product.data[key] is String &&
          (product.data[key] as String).isNotEmpty)
        product.data[key] as String,
  ].join(' · ');

  String effectPreview(InquiryListRecord record) {
    final line = record.line;
    final selected = line.candidates
        .where((h) => h.id == line.productId)
        .firstOrNull;
    final quantity = parseQty(line.item.qty);
    final unit = selected?.data['unit'] ?? line.item.unit ?? '项';
    final quote = line.quote;
    final supplier = quote == null
        ? null
        : runtime.owner.runtime.state.store.get(
            'supplier',
            quote.data['supplier_id'] as String,
          );
    return [
      if (selected != null) candidateLabel(selected),
      '入库数量：${quantity.$1} $unit',
      if (quantity.$2 != null) quantity.$2!,
      if (selected != null && line.item.unit != null && line.item.unit != unit)
        '清单单位：${line.item.unit}',
      if (quote == null)
        '采用成本：0（待询价）'
      else
        '采用报价：${quote.price} ${draft.project['currency']} · ${draft.project['tax_mode']} · ${supplier?.data['name'] ?? quote.data['supplier_id']} · ${quote.data['quoted_on']}',
    ].join('；');
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      children: [
        Text(
          draft.projectCreated
              ? '本草稿已创建项目：${draft.project['name']}'
              : '将新建项目：${draft.project['name']}',
        ),
        Text('项目编号：${draft.project['code']}'),
        if (page != 0 && !draft.projectCreated) const Text('项目资料在第一组统一编辑'),
        if (error != null) Text(error!),
        if (c == null)
          const LinearProgressIndicator()
        else ...[
          Expanded(
            child: AbsorbPointer(
              absorbing: busy,
              child: UiWorkspaceView(
                key: ValueKey(identityHashCode(c)),
                controller: c,
                originalAnswer: '',
              ),
            ),
          ),
          if (receipt != null)
            Text(
              '已入库 ${(receipt!.result['succeededRecordIds'] as List).length} · 待补 ${(receipt!.result['pendingRecordIds'] as List).length}',
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final r in records) ...[
                    CheckboxListTile(
                      key: ValueKey('list-select-${r.id}'),
                      title: Text(
                        '${r.line.item.name} · ${r.receiptRef != null ? '已入库' : r.error ?? '待确认'}',
                      ),
                      subtitle: Text(effectPreview(r)),
                      value: c.selectedRecords.contains(r.id),
                      onChanged: busy || c.readOnly || !r.valid
                          ? null
                          : (v) async {
                              setState(() {
                                if (v == true) {
                                  c.selectedRecords.add(r.id);
                                } else {
                                  c.selectedRecords.remove(r.id);
                                }
                              });
                              try {
                                await c.flush();
                              } catch (e) {
                                if (mounted) setState(() => error = '$e');
                              }
                            },
                    ),
                    if (r.receiptRef == null && r.line.candidates.isNotEmpty)
                      DropdownButton<String>(
                        key: ValueKey('list-product-${r.id}'),
                        value:
                            r.line.candidates.any(
                              (h) => h.id == r.line.productId,
                            )
                            ? r.line.productId
                            : '',
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('保留名称待询价'),
                          ),
                          for (final h in r.line.candidates)
                            DropdownMenuItem(
                              value: h.id,
                              child: Text(candidateLabel(h)),
                            ),
                        ],
                        onChanged: busy || c.readOnly
                            ? null
                            : (v) => choose(r, v == '' ? null : v),
                      ),
                  ],
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              if (page > 0)
                TextButton(
                  onPressed: busy ? null : () => move(page - 1),
                  child: const Text('上一组'),
                ),
              Text('第 ${page + 1}/$pageCount 组'),
              if (page + 1 < pageCount)
                TextButton(
                  onPressed: busy ? null : () => move(page + 1),
                  child: const Text('下一组'),
                ),
              if (c.surface.operationRefs.isNotEmpty)
                TextButton(
                  onPressed: busy ? null : query,
                  child: const Text('查询提交回执'),
                ),
              TextButton(
                onPressed: busy || c.readOnly
                    ? null
                    : () => run(() async {
                        await sync();
                        await refresh();
                      }),
                child: const Text('校验编辑'),
              ),
              FilledButton(
                onPressed: busy || c.readOnly || c.selectedRecords.isEmpty
                    ? null
                    : commit,
                child: Text(draft.projectCreated ? '确认剩余清单' : '确认新建项目并导入'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
