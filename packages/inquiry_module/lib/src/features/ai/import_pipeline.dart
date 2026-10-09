import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/supplier_core.dart';

import '../../app/app_state.dart';

part 'list_import_pipeline.dart';

/// Existing MaterialImportPage functions, chosen before any field preview.
enum InquiryImportPurpose { quotations, materials }

class SelectedInquiryInput extends SelectedInput {
  const SelectedInquiryInput({
    required super.path,
    required super.displayName,
    required this.purpose,
    this.additionalPurposes = const {},
  });
  final InquiryImportPurpose purpose;
  final Set<InquiryImportPurpose> additionalPurposes;
}

enum InquiryRecordStatus { valid, duplicate, incomplete, conflict, succeeded }

class InquiryImportRecord {
  const InquiryImportRecord(
    this.id,
    this.plan,
    this.status,
    this.receiptRef,
    this.purpose,
  );
  final String id;
  final OfferPlan plan;
  final InquiryRecordStatus status;
  final String? receiptRef;
  final InquiryImportPurpose purpose;
}

/// Plugin-owned data and effects. Host freezes files and supplies its existing
/// parser; no coordinator, agent, authorization or envelope execution lives here.
class InquiryImportPipeline {
  InquiryImportPipeline({
    required this.state,
    required this.files,
    required this.parseText,
    required this.isActive,
    required this.validateTarget,
  });
  final AppState state;
  final ModuleFiles files;
  final Future<String> Function(SelectedInput) parseText;
  final bool Function() isActive;
  final void Function(ImportIntent) validateTarget;
  static const _prefix = 'inquiry-import:';
  String get schemaDigest => _hash(
    utf8.encode(
      jsonEncode({
        for (final e in offerFields.entries) e.key: [e.value.$1, e.value.$2],
      }),
    ),
  );
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
  void _admit() {
    if (!isActive()) throw StateError('Inquiry import is not active');
  }

  Map<String, dynamic> _read(String key) {
    final rows = state.store.db.select('SELECT value FROM meta WHERE key=?', [
      '$_prefix$key',
    ]);
    if (rows.isEmpty) {
      throw StateError('Import draft or receipt is unavailable');
    }
    return Map<String, dynamic>.from(
      jsonDecode(rows.single['value'] as String) as Map,
    );
  }

  void _put(Store store, String key, Map<String, dynamic> value) =>
      store.db.execute(
        'INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        ['$_prefix$key', jsonEncode(value)],
      );
  Future<T> _write<T>(T Function(Store) action, {bool atomic = true}) async {
    late T result;
    final error = await state.writeInBackground((store) {
      _admit();
      result = atomic ? store.transaction(() => action(store)) : action(store);
    });
    if (error != null) throw StateError(error);
    return result;
  }

  WorkspaceBinding _binding(Map d) => WorkspaceBinding(
    workspaceId: d['workspaceId'] as String,
    moduleId: 'inquiry',
    nativeProjectId: d['projectId'] as String,
  );
  ImportTarget _target(Map d) => d['kind'] == 'create'
      ? ImportTarget.create(_binding(d))
      : ImportTarget.refresh(_binding(d));
  void _checkSource(Map d) {
    final source = File(d['path'] as String);
    if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(
          p.join(
            Directory(files.rootPath).resolveSymbolicLinksSync(),
            'staging',
          ),
          source.resolveSymbolicLinksSync(),
        ) ||
        _hash(source.readAsBytesSync()) != d['sourceDigest']) {
      throw StateError('Import source changed; review again');
    }
    if (d['schemaDigest'] != schemaDigest) {
      throw StateError('Import schema changed; review again');
    }
  }

  Future<PreparedInquiryDraft> prepare(
    SelectedInput input,
    ImportTarget target,
  ) async {
    _admit();
    if (input is! SelectedInquiryInput) {
      throw StateError('Choose an import purpose first');
    }
    if (target.binding.moduleId != 'inquiry') {
      throw StateError('Wrong import module');
    }
    final project = state.store.get('project', target.binding.nativeProjectId);
    if (project == null || project.deleted) {
      throw StateError('Choose an existing inquiry project');
    }
    final purposes = {
      input.purpose,
      ...input.additionalPurposes,
    }.map((p) => p.name).toList()..sort();
    final frozen = await files.freeze(input);
    final bytes = await File(frozen.path).readAsBytes();
    final sourceDigest = _hash(bytes);
    final text = input.displayName.toLowerCase().endsWith('.xlsx')
        ? workbookText(readXlsx(bytes))
        : await parseText(frozen);
    final book = tableFromText(text);
    var offers = book == null
        ? null
        : offersFromWorkbook(
            book,
            materials: input.purpose == InquiryImportPurpose.materials,
          );
    if (offers == null && book != null) {
      for (final purpose in input.additionalPurposes) {
        offers = offersFromWorkbook(
          book,
          materials: purpose == InquiryImportPurpose.materials,
        );
        if (offers != null) break;
      }
    }
    String? aiTaskId;
    offers ??= await state.runAiTask<List<Offer>>(
      AiTask.offerExtraction,
      {
        'source': text,
        'purpose': input.purpose.name,
        'sourceDigest': sourceDigest,
      },
      (llm) => state.store.extractOffers(llm, text),
      onCreated: (id) => aiTaskId = id,
    );
    if (offers.isEmpty) throw StateError('No importable records');
    _admit();
    final id = p.basename(p.dirname(frozen.path));
    final data = <String, dynamic>{
      'workspaceId': target.binding.workspaceId,
      'projectId': target.binding.nativeProjectId,
      'kind': target.kind.name,
      'path': frozen.path,
      'sourceName': input.displayName,
      'sourceText': text,
      'sourceDigest': sourceDigest,
      'schemaDigest': schemaDigest,
      'purpose': input.purpose.name,
      'purposes': purposes,
      'aiTaskId': aiTaskId,
      'recordPurposes': {
        for (var i = 0; i < offers.length; i++) 'r$i': input.purpose.name,
      },
      'revision': 0,
      'extracted': {for (var i = 0; i < offers.length; i++) 'r$i': offers[i]},
      'overrides': <String, dynamic>{},
      'choices': <String, dynamic>{},
      'completed': <String, dynamic>{},
      'operations': <String>[],
    };
    await _write((store) => _put(store, 'draft:$id', data));
    return resume(id);
  }

  PreparedInquiryDraft resume(String id) {
    _admit();
    final d = _read('draft:$id');
    return PreparedInquiryDraft._(
      this,
      id,
      _target(d),
      d['sourceDigest'] as String,
    );
  }

  List<String> ids(String id) =>
      _read('draft:$id')['extracted'].keys.cast<String>().toList();
  String? value(String id, String record, String field) {
    final d = _read('draft:$id');
    final overrides = d['overrides'][record] as Map?;
    return (overrides?.containsKey(field) == true
            ? overrides![field]
            : d['extracted'][record][field])
        as String?;
  }

  InquiryImportPurpose _purpose(Map d, String record) =>
      InquiryImportPurpose.values.byName(
        (d['recordPurposes'] as Map?)?[record] as String? ??
            d['purpose'] as String,
      );
  Offer _offer(Map d, String record) {
    final offer = Map<String, String?>.from({
      ...d['extracted'][record] as Map,
      ...?d['overrides'][record] as Map?,
    });
    return _purpose(d, record) == InquiryImportPurpose.materials
        ? materialOffer(offer)
        : offer;
  }

  List<InquiryImportRecord> records(String id) => _records(_read('draft:$id'));
  List<InquiryImportRecord> _records(Map d) => [
    for (final id in (d['extracted'] as Map).keys.cast<String>())
      _record(d, id),
  ];
  InquiryImportRecord _record(Map d, String id) {
    var plan = state.store.planOffer(
      _offer(d, id),
      source: d['sourceText'] as String,
    );
    final choice = d['choices'][id] as Map?;
    final staleChoice =
        choice != null &&
        ['product', 'supplier'].any((type) {
          final entityId = choice['${type}Id'] as String?;
          if (entityId == null) return false;
          final entity = state.store.get(type, entityId);
          return entity == null ||
              entity.deleted ||
              entity.version != choice['${type}Version'];
        });
    if (choice != null && !staleChoice) {
      plan = OfferPlan(
        plan.offer,
        error: plan.error,
        unverified: plan.unverified,
        supplierCandidates: plan.supplierCandidates,
        productCandidates: plan.productCandidates,
        supplierId: choice['supplierId'] as String?,
        productId: choice['productId'] as String?,
      );
    }
    final receiptRef = d['completed'][id] as String?;
    final recordedStatus = receiptRef == null
        ? null
        : (receipt(receiptRef)?.result['records'] as Map?)?[id] as Map?;
    final status = receiptRef != null
        ? (recordedStatus?['status'] == 'skipped'
              ? InquiryRecordStatus.duplicate
              : InquiryRecordStatus.succeeded)
        : staleChoice
        ? InquiryRecordStatus.conflict
        : plan.error != null
        ? InquiryRecordStatus.incomplete
        : choice == null &&
              ((plan.supplierId == null &&
                      plan.supplierCandidates.isNotEmpty) ||
                  (plan.productId == null && plan.productCandidates.isNotEmpty))
        ? InquiryRecordStatus.conflict
        : _purpose(d, id) == InquiryImportPurpose.quotations &&
              state.store.existingOfferQuotation(
                    plan,
                    projectId: d['projectId'] as String,
                  ) !=
                  null
        ? InquiryRecordStatus.duplicate
        : InquiryRecordStatus.valid;
    return InquiryImportRecord(id, plan, status, receiptRef, _purpose(d, id));
  }

  Future<void> edit(String draft, String record, String field, String? value) =>
      _write((store) {
        final d = _read('draft:$draft');
        if (!(d['extracted'] as Map).containsKey(record) ||
            !offerFields.containsKey(field) ||
            (_purpose(d, record) == InquiryImportPurpose.materials &&
                !materialFields.contains(field)) ||
            (d['completed'] as Map).containsKey(record)) {
          throw StateError('Record cannot be edited');
        }
        final overrides = d['overrides'] as Map;
        (overrides[record] ??= <String, dynamic>{})[field] = value?.trim();
        (d['choices'] as Map).remove(record);
        d['revision'] = (d['revision'] as int) + 1;
        _put(store, 'draft:$draft', d);
      });
  Future<void> choose(
    String draft,
    String record, {
    String? supplierId,
    String? productId,
  }) => _write((store) {
    final d = _read('draft:$draft');
    final plan = state.store.planOffer(
      _offer(d, record),
      source: d['sourceText'] as String,
    );
    if ((supplierId != null &&
            !plan.supplierCandidates.any((c) => c.id == supplierId)) ||
        (productId != null &&
            !plan.productCandidates.any((c) => c.id == productId)) ||
        (d['completed'] as Map).containsKey(record)) {
      throw StateError('Choice is outside the reviewed candidates');
    }
    (d['choices'] as Map)[record] = {
      'supplierId': supplierId,
      'productId': productId,
      'supplierVersion': supplierId == null
          ? null
          : store.get('supplier', supplierId)?.version,
      'productVersion': productId == null
          ? null
          : store.get('product', productId)?.version,
    };
    d['revision'] = (d['revision'] as int) + 1;
    _put(store, 'draft:$draft', d);
  });

  Map<String, Object?> _resolved(InquiryImportRecord r) => {
    'productId': r.plan.productId,
    'supplierId': r.plan.supplierId,
    'productVersion': r.plan.productId == null
        ? null
        : state.store.get('product', r.plan.productId!)?.version,
    'supplierVersion': r.plan.supplierId == null
        ? null
        : state.store.get('supplier', r.plan.supplierId!)?.version,
  };

  /// Called only from the human review port. Model/tool booleans are not read.
  Future<PreparedImport> confirm(String id, List<String> selected) =>
      _write((store) {
        final d = _read('draft:$id');
        _checkSource(d);
        final records = _records(d);
        if (selected.isEmpty ||
            selected.toSet().length != selected.length ||
            selected.any(
              (id) => !records.any(
                (r) => r.id == id && r.status == InquiryRecordStatus.valid,
              ),
            )) {
          throw StateError('Confirm only valid, unfinished records');
        }
        final frozen = <String, dynamic>{
          ...d,
          'draftId': id,
          'selected': List.of(selected)..sort(),
          'resolved': {
            for (final r in records)
              if (selected.contains(r.id)) r.id: _resolved(r),
          },
        };
        final digest = _hash(utf8.encode(jsonEncode(frozen)));
        final token = '$id:${d['revision']}:$digest';
        _put(store, 'confirmation:$token', frozen);
        return PreparedImport(
          target: _target(d),
          inputDigest: digest,
          stagingToken: token,
        );
      });
  Map<String, dynamic> _identity(ImportIntent i) => {
    'operationId': i.operationId,
    'workspaceId': i.workspaceId,
    'moduleId': i.moduleId,
    'targetProjectId': i.targetProjectId,
    'kind': i.kind.name,
    'inputDigest': i.inputDigest,
    'stagingToken': i.stagingToken,
  };
  ImportReceipt? receipt(String operationId) {
    final rows = state.store.db.select('SELECT value FROM meta WHERE key=?', [
      '${_prefix}receipt:$operationId',
    ]);
    if (rows.isEmpty) return null;
    final d = jsonDecode(rows.single['value'] as String) as Map;
    final i = d['identity'] as Map;
    return ImportReceipt(
      intent: ImportIntent(
        operationId: i['operationId'] as String,
        workspaceId: i['workspaceId'] as String,
        moduleId: i['moduleId'] as String,
        targetProjectId: i['targetProjectId'] as String,
        kind: ImportKind.values.byName(i['kind'] as String),
        inputDigest: i['inputDigest'] as String,
        stagingToken: i['stagingToken'] as String,
      ),
      result: Map<String, Object?>.from(d['result'] as Map),
      committedAt: DateTime.parse(d['committedAt'] as String),
    );
  }

  Future<ImportReceipt> commit(
    PreparedImport prepared,
    ImportIntent intent,
  ) async {
    if (!prepared.matches(intent) || intent.moduleId != 'inquiry') {
      throw StateError('Import identity mismatch');
    }
    return _write((store) {
      final prior = receipt(intent.operationId);
      if (prior != null) {
        if (!prior.intent.sameIdentity(intent)) {
          throw StateError('Operation identity conflict');
        }
        return prior;
      }
      // Host facts are read synchronously inside the admitted final write.
      // No await separates target validation and the original domain transaction.
      // Existing receipts return above, so reconciliation cannot reapply effects.
      validateTarget(intent);
      final frozen = _read('confirmation:${intent.stagingToken}');
      if (_hash(utf8.encode(jsonEncode(frozen))) != intent.inputDigest ||
          frozen['workspaceId'] != intent.workspaceId ||
          frozen['projectId'] != intent.targetProjectId ||
          frozen['kind'] != intent.kind.name) {
        throw StateError('Confirmation identity mismatch');
      }
      final draftId = frozen['draftId'] as String;
      final d = _read('draft:$draftId');
      _checkSource(d);
      if (d['revision'] != frozen['revision']) {
        throw StateError('Import confirmation is stale');
      }
      final selected = List<String>.from(frozen['selected'] as List);
      final records = _records(d);
      if (selected.any(
        (id) => !records.any(
          (r) => r.id == id && r.status == InquiryRecordStatus.valid,
        ),
      )) {
        throw StateError('Import validation changed; review again');
      }
      if (selected.any(
        (id) =>
            jsonEncode(frozen['resolved'][id]) !=
            jsonEncode(_resolved(records.singleWhere((r) => r.id == id))),
      )) {
        throw StateError('Reviewed entity changed; review again');
      }
      late ImportReceipt committed;
      state.commitAiTask(d['aiTaskId'] as String?, (store) {
        committed = store.transaction(() {
          final appliedIds = <String, String?>{};
          final batchDuplicates = <String>[];
          final summaries = <ImportSummary>[];
          for (final purpose in InquiryImportPurpose.values) {
            final group = records
                .where((r) => selected.contains(r.id) && r.purpose == purpose)
                .toList();
            if (group.isEmpty) continue;
            summaries.add(
              store.applyOffers(
                [
                  for (final r in group)
                    (
                      offer: r.plan.offer,
                      supplierId: r.plan.supplierId,
                      productId: r.plan.productId,
                    ),
                ],
                onApplied:
                    (index, productId, supplierId, quotationId, duplicate) {
                      if (duplicate) {
                        batchDuplicates.add(group[index].id);
                      }
                      appliedIds[group[index].id] =
                          purpose == InquiryImportPurpose.materials
                          ? productId
                          : quotationId ?? productId;
                    },
                projectId: purpose == InquiryImportPurpose.materials
                    ? null
                    : intent.targetProjectId,
                inquirer: '-',
                source: (
                  name: d['sourceName'] as String,
                  bytes: File(d['path'] as String).readAsBytesSync(),
                ),
              ),
            );
          }
          final succeeded = selected
              .where((id) => !batchDuplicates.contains(id))
              .toList();
          final skipped = [
            ...batchDuplicates,
            for (final r in records)
              if (r.status == InquiryRecordStatus.duplicate &&
                  r.receiptRef == null)
                r.id,
          ];
          final result = <String, Object?>{
            'succeededRecordIds': succeeded,
            'skippedRecordIds': skipped,
            'pendingRecordIds': [
              for (final r in records)
                if (!selected.contains(r.id) &&
                    !skipped.contains(r.id) &&
                    r.receiptRef == null)
                  r.id,
            ],
            'summary': {
              'suppliers': summaries.fold<int>(0, (n, s) => n + s.suppliers),
              'contacts': summaries.fold<int>(0, (n, s) => n + s.contacts),
              'products': summaries.fold<int>(0, (n, s) => n + s.products),
              'quotations': summaries.fold<int>(0, (n, s) => n + s.quotations),
              'duplicates': skipped.length,
            },
            'records': {
              for (final record in records)
                if (record.receiptRef == null)
                  record.id: {
                    'status': succeeded.contains(record.id)
                        ? 'succeeded'
                        : skipped.contains(record.id)
                        ? 'skipped'
                        : 'pending',
                    'businessObjectId':
                        selected.contains(record.id) ||
                            skipped.contains(record.id)
                        ? (appliedIds[record.id] ??
                              (record.purpose == InquiryImportPurpose.materials
                                  ? store.sameProductId(record.plan.offer)
                                  : store.existingOfferQuotation(
                                      record.plan,
                                      projectId: intent.targetProjectId,
                                    )))
                        : null,
                    'receiptId':
                        selected.contains(record.id) ||
                            skipped.contains(record.id)
                        ? intent.operationId
                        : null,
                    'error':
                        selected.contains(record.id) ||
                            skipped.contains(record.id)
                        ? null
                        : record.plan.error ??
                              (record.status == InquiryRecordStatus.conflict
                                  ? 'Choose a duplicate resolution'
                                  : 'Not selected'),
                  },
            },
          };
          final at = store.clock().toUtc();
          _put(store, 'receipt:${intent.operationId}', {
            'identity': _identity(intent),
            'result': result,
            'committedAt': at.toIso8601String(),
          });
          for (final id in [...selected, ...skipped]) {
            (d['completed'] as Map)[id] = intent.operationId;
          }
          (d['operations'] as List).add(intent.operationId);
          d['aiTaskId'] = null;
          d['kind'] = 'refresh';
          d['revision'] = (d['revision'] as int) + 1;
          _put(store, 'draft:$draftId', d);
          return ImportReceipt(intent: intent, result: result, committedAt: at);
        });
      });
      return committed;
    }, atomic: false);
  }
}

class PreparedInquiryDraft extends PreparedImport {
  PreparedInquiryDraft._(
    this.pipeline,
    this.draftId,
    ImportTarget target,
    String digest,
  ) : super(target: target, inputDigest: digest, stagingToken: draftId);
  final InquiryImportPipeline pipeline;
  final String draftId;
  List<String> get recordIds => pipeline.ids(draftId);
  int get revision => pipeline._read('draft:$draftId')['revision'] as int;
  String get sourceName =>
      pipeline._read('draft:$draftId')['sourceName'] as String;
  String get sourceText =>
      pipeline._read('draft:$draftId')['sourceText'] as String;
  String get sourceDigest =>
      pipeline._read('draft:$draftId')['sourceDigest'] as String;
  Map<String, String> get fieldLabels => {
    for (final field in offerFields.entries) field.key: field.value.$1,
  };
  List<InquiryImportRecord> get records => pipeline.records(draftId);
  Set<InquiryImportPurpose> get purposes =>
      (pipeline._read('draft:$draftId')['purposes'] as List)
          .cast<String>()
          .map(InquiryImportPurpose.values.byName)
          .toSet();
  bool canEdit(String record, String field) {
    final d = pipeline._read('draft:$draftId');
    return !(d['completed'] as Map).containsKey(record) &&
        offerFields.containsKey(field) &&
        (pipeline._purpose(d, record) != InquiryImportPurpose.materials ||
            materialFields.contains(field));
  }

  String? value(String record, String field) =>
      pipeline.value(draftId, record, field);
  Future<void> edit(String record, String field, String? value) =>
      pipeline.edit(draftId, record, field, value);
  Future<void> choose(String record, {String? supplierId, String? productId}) =>
      pipeline.choose(
        draftId,
        record,
        supplierId: supplierId,
        productId: productId,
      );
  Future<PreparedImport> confirm(List<String> selected) =>
      pipeline.confirm(draftId, selected);
  Future<void> assignPurpose(String record, InquiryImportPurpose purpose) =>
      pipeline._write((store) {
        final d = pipeline._read('draft:$draftId');
        if (!(d['purposes'] as List).contains(purpose.name) ||
            !(d['extracted'] as Map).containsKey(record) ||
            (d['completed'] as Map).containsKey(record)) {
          throw StateError('Purpose was not selected or record is complete');
        }
        (d['recordPurposes'] as Map)[record] = purpose.name;
        (d['choices'] as Map).remove(record);
        d['revision'] = (d['revision'] as int) + 1;
        pipeline._put(store, 'draft:$draftId', d);
      });
}
