import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart'
    show ImportReceipt, SelectedInput, ImportTarget;
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:flutter/material.dart';

import 'adapters/inquiry_module.dart';
import 'bootstrap.dart';
import '../platform/ui_workspace_store.dart';
import '../workspace/import_coordinator.dart';

/// A projection attached to an existing task, with a human-only submission port.
/// No agent tool mapping, planner flag or new execution kernel is installed.
class ImportReviewProjection {
  ImportReviewProjection(
    this.host,
    this.runtime,
    this.draft, {
    required this.taskId,
    this.page = 0,
  });
  final MuyonHost host;
  final InquiryModuleRuntime runtime;
  final PreparedInquiryDraft draft;
  final String taskId;
  final int page;
  static const pageSize = 5;
  int get pageCount => (draft.recordIds.length + pageSize - 1) ~/ pageSize;
  List<InquiryImportRecord> get visibleRecords =>
      draft.records.skip(page * pageSize).take(pageSize).toList();
  ImportReviewProjection forPage(int value) {
    if (value < 0 || value >= pageCount) {
      throw RangeError.index(value, draft.recordIds);
    }
    return ImportReviewProjection(
      host,
      runtime,
      draft,
      taskId: taskId,
      page: value,
    );
  }

  String get surfaceId => 'import:${draft.draftId}:page:$page';
  final _pending = <String, Future<ImportReceipt>>{};

  ValidatedUiPlan get plan {
    final ref = SnapshotRef(draft.draftId, draft.revision);
    final facts = <String, SnapshotFact>{};
    final values = <String, Object?>{};
    final nodes = <UiNode>[];
    for (final record in visibleRecords) {
      final object = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'importDraft',
        objectId: '${draft.draftId}:${record.id}',
      );
      final status =
          '${record.status.name}${record.plan.error == null ? '' : ': ${record.plan.error}'}';
      final statusKey = '${record.id}:status';
      facts[statusKey] = SnapshotFact(
        object: object,
        field: '校验状态',
        value: status,
        state: record.status == InquiryRecordStatus.conflict
            ? FactState.conflict
            : FactState.unverified,
      );
      nodes.add(
        UiNode(
          id: statusKey,
          component: 'WarnBanner',
          bindings: {'value': BindingRef.fact(statusKey)},
        ),
      );
      for (final field in draft.fieldLabels.entries) {
        final key = '${record.id}:${field.key}';
        final value = record.plan.offer[field.key];
        facts[key] = SnapshotFact(
          object: object,
          field: field.value,
          value: value,
          state: value == null ? FactState.notDisclosed : FactState.unverified,
          sourceRefs: ['source'],
        );
        values[key] = value ?? '';
        nodes.add(
          UiNode(
            id: key,
            component: 'Field',
            properties: {'label': field.value, 'inputType': 'text'},
            bindings: {
              'value': BindingRef.fact(key),
              'draft': BindingRef.uiState(key),
            },
            events: draft.canEdit(record.id, field.key)
                ? {
                    'change': ActionBinding(
                      actionRef: 'edit',
                      inputRefs: [key],
                    ),
                  }
                : const {},
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
      id: 'import-review',
      purpose: '复核所选询价导入用途',
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
          properties: {'title': '询价导入复核'},
          children: nodes.map((n) => n.id).toList(),
        ),
        ...nodes,
      ],
    );
    final validation = validateUiPlan(ui, snapshot, intent, dynamicUiCatalog);
    if (!validation.isValid) {
      throw StateError(
        'Import review projection invalid: ${validation.errors}',
      );
    }
    return validation.validatedPlan!;
  }

  Future<UiWorkspaceController> open() async {
    final store = HostUiWorkspaceStore(host.foundation, taskId: taskId);
    final scope = store.scopeKey;
    if (scope == null) throw StateError('Owning task unavailable');
    return UiWorkspaceController.open(
      store: store,
      taskId: taskId,
      scopeKey: scope,
      plan: plan,
      receiptLookup: (id) async => await runtime.receipt(id) == null
          ? UiOperationRecovery.unknown
          : UiOperationRecovery.succeeded,
    );
  }

  /// Called by the human selection/confirmation flow, never by a UIPlan or a
  /// tool result's `confirmed` property. The coordinator mints the operation id.
  Future<ImportReceipt> commitSelected(
    UiWorkspaceController controller,
    List<String> records,
  ) {
    final selected = List<String>.of(records)..sort();
    final key =
        '${controller.surface.current.snapshot.ref.revision}:${controller.surface.session.draftRevision}:${selected.join(',')}';
    return _pending.putIfAbsent(
      key,
      () => _commit(controller, records).catchError((
        Object error,
        StackTrace stack,
      ) {
        _pending.remove(key);
        Error.throwWithStackTrace(error, stack);
      }),
    );
  }

  /// Query only durable references owned by this surface; activation reconciles
  /// the host binding and never invokes the domain commit again.
  Future<List<ImportReceipt>> queryReceipts(
    UiWorkspaceController controller,
  ) async {
    if (controller.taskId != taskId ||
        controller.surface.current.plan.surfaceId != surfaceId ||
        !identical(
          runtime,
          host.modules.runtime<InquiryModuleRuntime>('inquiry'),
        ) ||
        !identical(draft.pipeline, runtime.imports)) {
      throw StateError('Import review changed; reopen it');
    }
    final coordinator = ImportCoordinator(host.workspaces);
    final receipts = <ImportReceipt>[];
    for (final operationId in controller.surface.operationRefs) {
      final receipt = await runtime.receipt(operationId);
      if (receipt == null) continue;
      final intent = receipt.intent;
      final binding = draft.target.binding;
      if (intent.operationId != operationId ||
          intent.moduleId != binding.moduleId ||
          intent.workspaceId != binding.workspaceId ||
          intent.targetProjectId != binding.nativeProjectId ||
          !intent.stagingToken.startsWith('${draft.draftId}:')) {
        throw StateError('Receipt is outside this import');
      }
      await coordinator.activate(receipt);
      receipts.add(receipt);
    }
    return receipts;
  }

  Future<void> syncEdits(UiWorkspaceController controller) async {
    if (controller.taskId != taskId ||
        controller.surface.current.plan.surfaceId != surfaceId ||
        controller.readOnly ||
        controller.surface.current.snapshot.ref.revision != draft.revision) {
      throw StateError('Import review changed; reopen it');
    }
    await controller.flush();
    for (final entry in controller.surface.session.userOverrides.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2 ||
          !draft.recordIds.contains(parts[0]) ||
          !draft.fieldLabels.containsKey(parts[1]) ||
          entry.value is! String) {
        throw StateError('Field is outside the reviewed import');
      }
      final text = entry.value as String;
      final value = text.isEmpty ? null : text;
      if (draft.value(parts[0], parts[1]) != value) {
        await draft.edit(parts[0], parts[1], value);
      }
    }
  }

  Future<ImportReceipt> _commit(
    UiWorkspaceController controller,
    List<String> records,
  ) async {
    if (controller.taskId != taskId ||
        controller.surface.current.plan.surfaceId != surfaceId ||
        controller.readOnly ||
        controller.surface.current.snapshot.ref.revision != draft.revision ||
        !identical(
          runtime,
          host.modules.runtime<InquiryModuleRuntime>('inquiry'),
        ) ||
        !identical(draft.pipeline, runtime.imports)) {
      throw StateError('Import review changed; reopen it');
    }
    if (records.any((id) => !visibleRecords.any((r) => r.id == id))) {
      throw StateError('Confirm only the visible group');
    }
    final binding = draft.target.binding;
    final owner = host.workspaces.ownerWorkspace(
      binding.moduleId,
      binding.nativeProjectId,
    );
    final current = host.workspaces.binding(
      binding.workspaceId,
      binding.moduleId,
    );
    if ((owner != null && owner != binding.workspaceId) ||
        (current != null &&
            current.nativeProjectId != binding.nativeProjectId)) {
      throw StateError('Import target changed; choose the workspace again');
    }
    controller.selectedRecords = List.of(records);
    await controller.flush();
    await syncEdits(controller);
    final prepared = await draft.confirm(records);
    final coordinator = ImportCoordinator(host.workspaces);
    final pending = coordinator
        .pending('inquiry')
        .where(prepared.matches)
        .toList();
    if (pending.length > 1) {
      throw StateError('Multiple pending imports require reconciliation');
    }
    final intent = pending.isEmpty
        ? await coordinator.record(prepared)
        : pending.single;
    // Durable real reference precedes the side effect; restoration only queries.
    controller.surface.lockRecoveredOperations([intent.operationId]);
    controller.step = 'submitting';
    await controller.flush();
    final result = await coordinator.commit(runtime, prepared, intent);
    controller.step = 'receipt';
    await controller.flush();
    return result;
  }
}

/// File-context entry attached to an existing task. Preparation requires an
/// explicit plugin/function selection; it never installs an agent tool port.
class InquiryImportEntry extends StatefulWidget {
  const InquiryImportEntry({
    super.key,
    required this.host,
    required this.taskId,
    required this.input,
    required this.target,
  });
  final MuyonHost host;
  final String taskId;
  final SelectedInput input;
  final ImportTarget target;
  @override
  State<InquiryImportEntry> createState() => _InquiryImportEntryState();
}

class _InquiryImportEntryState extends State<InquiryImportEntry> {
  final purposes = <InquiryImportPurpose>{};
  bool busy = false;
  String? error;
  ImportReviewProjection? projection;
  UiWorkspaceController? controller;
  Future<void> prepare() async {
    if (busy || purposes.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final runtime = widget.host.modules.runtime<InquiryModuleRuntime>(
        'inquiry',
      );
      if (runtime == null) throw StateError('询价插件不可用');
      final draft = await runtime.prepareImport(
        SelectedInquiryInput(
          path: widget.input.path,
          displayName: widget.input.displayName,
          purpose: purposes.first,
          additionalPurposes: purposes.skip(1).toSet(),
        ),
        widget.target,
      ) as PreparedInquiryDraft;
      final next = ImportReviewProjection(
        widget.host,
        runtime,
        draft,
        taskId: widget.taskId,
      );
      final opened = await next.open();
      if (!mounted) {
        opened.dispose();
        return;
      }
      setState(() {
        projection = next;
        controller = opened;
      });
    } catch (e) {
      if (mounted) setState(() => error = '无法准备预览：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (projection != null) {
      return ImportReviewView(projection: projection!, controller: controller!);
    }
    return Scaffold(
      body: Column(
        children: [
          const Text('插件：询价'),
          Text('来源：${widget.input.displayName}'),
          for (final purpose in InquiryImportPurpose.values)
            CheckboxListTile(
              title: Text(
                purpose == InquiryImportPurpose.quotations ? '询价报价' : '材料库导入',
              ),
              value: purposes.contains(purpose),
              onChanged: busy
                  ? null
                  : (selected) => setState(() {
                      if (selected == true) {
                        purposes.add(purpose);
                      } else {
                        purposes.remove(purpose);
                      }
                    }),
            ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy || purposes.isEmpty ? null : prepare,
            child: const Text('准备预览'),
          ),
        ],
      ),
    );
  }
}

/// Human review entry point; callers attach it to the existing owning task.
class ImportReviewView extends StatefulWidget {
  const ImportReviewView({
    super.key,
    required this.projection,
    required this.controller,
    this.originalAnswer = '',
  });
  final ImportReviewProjection projection;
  final UiWorkspaceController controller;
  final String originalAnswer;
  @override
  State<ImportReviewView> createState() => _ImportReviewViewState();
}

class _ImportReviewViewState extends State<ImportReviewView> {
  late UiWorkspaceController controller = widget.controller;
  late ImportReviewProjection projection = widget.projection;
  bool ownsController = false, busy = false;
  String? error;
  ImportReceipt? receipt;
  String status(InquiryRecordStatus value) => switch (value) {
    InquiryRecordStatus.valid => '有效待确认',
    InquiryRecordStatus.duplicate => '确定重复，跳过',
    InquiryRecordStatus.incomplete => '待补',
    InquiryRecordStatus.conflict => '重复关系待选择',
    InquiryRecordStatus.succeeded => '已入库',
  };
  Future<void> refresh({bool sync = true}) async {
    if (sync) await projection.syncEdits(controller);
    final next = await projection.open();
    if (!mounted) {
      next.dispose();
      return;
    }
    final old = controller;
    final owned = ownsController;
    setState(() {
      controller = next;
      ownsController = true;
    });
    final valid = projection.draft.records
        .where((r) => r.status == InquiryRecordStatus.valid)
        .map((r) => r.id)
        .toSet();
    controller.selectedRecords.removeWhere((id) => !valid.contains(id));
    await controller.flush();
    if (owned) old.dispose();
  }

  Future<void> act(bool commit) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (commit) {
        final result = await projection.commitSelected(
          controller,
          List.of(controller.selectedRecords),
        );
        if (mounted) setState(() => receipt = result);
        await refresh(sync: false);
      } else {
        await refresh();
      }
    } catch (e) {
      if (mounted) setState(() => error = '未确认完成：$e。先核对回执再续办。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> queryReceipt() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final results = await projection.queryReceipts(controller);
      if (mounted) {
        setState(() {
          receipt = results.isEmpty ? null : results.last;
          error = results.length < controller.surface.operationRefs.length
              ? '回执尚未确认，请稍后再查；未重新执行导入。'
              : null;
        });
      }
      await refresh(sync: false);
    } catch (e) {
      if (mounted) setState(() => error = '回执未确认：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> move(int page) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await projection.syncEdits(controller);
      projection = projection.forPage(page);
      await refresh(sync: false);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose(InquiryImportRecord record) async {
    String product = record.plan.productId ?? '__new__';
    String supplier = record.plan.supplierId ?? '__new__';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('选择重复关系'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                key: ValueKey('product-choice-${record.id}'),
                value: product,
                items: [
                  const DropdownMenuItem(
                    value: '__new__',
                    child: Text('创建新产品'),
                  ),
                  for (final c in record.plan.productCandidates)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        [
                              c.data['name'],
                              c.data['brand'],
                              c.data['model'],
                              c.data['specification'],
                            ]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                      ),
                    ),
                ],
                onChanged: (value) => update(() => product = value!),
              ),
              DropdownButton<String>(
                value: supplier,
                items: [
                  const DropdownMenuItem(
                    value: '__new__',
                    child: Text('创建新供应商'),
                  ),
                  for (final c in record.plan.supplierCandidates)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        [
                              c.data['name'],
                              c.data['brand'],
                              c.data['model'],
                              c.data['specification'],
                            ]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                      ),
                    ),
                ],
                onChanged: (value) => update(() => supplier = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认关系'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => busy = true);
    try {
      await projection.syncEdits(controller);
      await projection.draft.choose(
        record.id,
        productId: product == '__new__' ? null : product,
        supplierId: supplier == '__new__' ? null : supplier,
      );
      await refresh(sync: false);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> assign(
    InquiryImportRecord record,
    InquiryImportPurpose purpose,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await projection.syncEdits(controller);
      await projection.draft.assignPurpose(record.id, purpose);
      await refresh(sync: false);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = projection.visibleRecords;
    final validSelection =
        controller.selectedRecords.isNotEmpty &&
        controller.selectedRecords.every(
          (id) => records.any(
            (r) => r.id == id && r.status == InquiryRecordStatus.valid,
          ),
        );
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: UiWorkspaceView(
              key: ValueKey(identityHashCode(controller)),
              controller: controller,
              originalAnswer: widget.originalAnswer,
            ),
          ),
          if (error != null) Text(error!),
          if (receipt != null)
            Text(
              '已入库 ${(receipt!.result['succeededRecordIds'] as List).length} · 跳过 ${(receipt!.result['skippedRecordIds'] as List).length} · 待补 ${(receipt!.result['pendingRecordIds'] as List).length}',
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final record in records) ...[
                    if (record.status == InquiryRecordStatus.conflict)
                      TextButton(
                        onPressed: busy || controller.readOnly
                            ? null
                            : () => choose(record),
                        child: const Text('选择重复关系'),
                      ),
                    if (projection.draft.purposes.length > 1 &&
                        record.receiptRef == null)
                      DropdownButton<InquiryImportPurpose>(
                        value: record.purpose,
                        items: [
                          for (final p in projection.draft.purposes)
                            DropdownMenuItem(
                              value: p,
                              child: Text(
                                p == InquiryImportPurpose.quotations
                                    ? '询价报价'
                                    : '材料库导入',
                              ),
                            ),
                        ],
                        onChanged: busy || controller.readOnly
                            ? null
                            : (p) => assign(record, p!),
                      ),
                    CheckboxListTile(
                      key: ValueKey('select-${record.id}'),
                      title: Text(
                        '${record.plan.offer['name'] ?? record.id} · ${status(record.status)}',
                      ),
                      value: controller.selectedRecords.contains(record.id),
                      onChanged:
                          busy ||
                              record.status != InquiryRecordStatus.valid ||
                              controller.readOnly
                          ? null
                          : (checked) async {
                              setState(() {
                                if (checked == true) {
                                  controller.selectedRecords.add(record.id);
                                } else {
                                  controller.selectedRecords.remove(record.id);
                                }
                              });
                              try {
                                await controller.flush();
                              } catch (e) {
                                if (mounted) setState(() => error = '$e');
                              }
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              if (projection.page > 0)
                TextButton(
                  onPressed: busy ? null : () => move(projection.page - 1),
                  child: const Text('上一组'),
                ),
              Text('第 ${projection.page + 1}/${projection.pageCount} 组'),
              if (projection.page + 1 < projection.pageCount)
                TextButton(
                  onPressed: busy ? null : () => move(projection.page + 1),
                  child: const Text('下一组'),
                ),
              if (controller.surface.operationRefs.isNotEmpty)
                TextButton(
                  onPressed: busy ? null : queryReceipt,
                  child: const Text('查询提交回执'),
                ),
              TextButton(
                onPressed: busy || controller.readOnly
                    ? null
                    : () => act(false),
                child: const Text('校验编辑'),
              ),
              FilledButton(
                onPressed: busy || controller.readOnly || !validSelection
                    ? null
                    : () => act(true),
                child: const Text('确认导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
