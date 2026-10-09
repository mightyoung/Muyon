part of 'import_pipeline.dart';

class InquiryListRecord {
  const InquiryListRecord(this.id, this.line, this.receiptRef, this.error);
  final String id;
  final ProposedLine line;
  final String? receiptRef, error;
  bool get valid => receiptRef == null && error == null;
}

extension InquiryListImport on InquiryImportPipeline {
  static const listSchema = 'inquiry-list-v1';
  Future<PreparedInquiryListDraft> prepareList(
    SelectedInput input,
    ImportTarget target,
    Map<String, Object?> project,
  ) async {
    _admit();
    if (target.kind != ImportKind.create ||
        target.binding.moduleId != 'inquiry' ||
        state.store.get('project', target.binding.nativeProjectId) != null) {
      throw StateError('清单导入必须新建项目');
    }
    final metadata = <String, Object?>{
      for (final field in Project.fields) field: null,
      'status': 'active',
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
      ...project,
    };
    if ((metadata['name'] as String? ?? '').trim().isEmpty) {
      throw StateError('填写项目名称');
    }
    final frozen = await files.freeze(input);
    final bytes = File(frozen.path).readAsBytesSync();
    final text = input.displayName.toLowerCase().endsWith('.xlsx')
        ? workbookText(readXlsx(bytes))
        : await parseText(frozen);
    String? aiTask;
    final lines = await state.runAiTask<List<ProposedLine>>(
      AiTask.listProposal,
      {'source': text, 'project': metadata, 'purpose': 'newProjectList'},
      (llm) => state.store.proposeFromList(
        llm,
        text,
        currency: metadata['currency'] as String,
        taxMode: metadata['tax_mode'] as String,
      ),
      onCreated: (id) => aiTask = id,
    );
    if (lines.isEmpty) throw StateError('No importable records');
    final id = p.basename(p.dirname(frozen.path));
    await _write(
      (store) => _put(store, 'list-draft:$id', {
        'workspaceId': target.binding.workspaceId,
        'projectId': target.binding.nativeProjectId,
        'kind': 'create',
        'project': metadata,
        'createdReceipt': null,
        'path': frozen.path,
        'sourceName': input.displayName,
        'sourceText': text,
        'sourceDigest': InquiryImportPipeline._hash(bytes),
        'schemaDigest': schemaDigest,
        'listSchema': listSchema,
        'revision': 0,
        'aiTaskId': aiTask,
        'completed': <String, dynamic>{},
        'lines': {
          for (var i = 0; i < lines.length; i++)
            'r$i': {
              'name': lines[i].item.name,
              'requirements': lines[i].item.requirements,
              'qty': lines[i].item.qty,
              'unit': lines[i].item.unit,
              'keywords': lines[i].item.keywords,
              'productId': lines[i].productId,
              'confidence': lines[i].confidence,
              'reason': lines[i].reason,
              'candidates': {
                for (final h in lines[i].candidates)
                  h.id: store.get('product', h.id)?.version,
              },
            },
        },
      }),
    );
    return resumeList(id);
  }

  PreparedInquiryListDraft resumeList(String id) {
    final d = _read('list-draft:$id');
    return PreparedInquiryListDraft._(
      this,
      id,
      _target(d),
      d['sourceDigest'] as String,
    );
  }

  void _checkList(Map d) {
    _checkSource(d);
    if (d['listSchema'] != listSchema) throw StateError('List schema changed');
    if (d['createdReceipt'] != null) {
      final project = state.store.get('project', d['projectId'] as String);
      if (project == null ||
          project.deleted ||
          project.version != d['createdProjectVersion']) {
        throw StateError(
          'Created project changed; review its original receipt',
        );
      }
    }
  }

  InquiryListRecord _listRecord(Map d, String id) {
    final row = d['lines'][id] as Map;
    final candidateVersions = row['candidates'] as Map;
    final candidates = <Hit>[
      for (final candidate in candidateVersions.keys)
        if (state.store.get('product', candidate as String) case final product?
            when !product.deleted)
          Hit(product.id, product.data, 0),
    ];
    final selected = row['productId'] as String?;
    final product = selected == null
        ? null
        : state.store.get('product', selected);
    final item = RequestedItem(
      row['name'] as String,
      row['requirements'] as String?,
      row['qty'] as String?,
      row['unit'] as String?,
      List<String>.from(row['keywords'] as List),
    );
    final options = product == null
        ? <QuoteOption>[]
        : state.store.quoteOptionsFor(
            product.id,
            currency: d['project']['currency'] as String,
            taxMode: d['project']['tax_mode'] as String,
            qty: parseQty(item.qty).$1,
          );
    final error = item.name.trim().isEmpty
        ? '填写清单名称'
        : selected != null &&
              (product == null ||
                  product.deleted ||
                  candidateVersions[selected] != product.version)
        ? '所选物料已改变，请重新选择'
        : null;
    return InquiryListRecord(
      id,
      ProposedLine(
        item,
        candidates,
        productId: selected,
        confidence: row['confidence'] as String,
        reason: row['reason'] as String?,
        quote: options.isNotEmpty && options.first.valid ? options.first : null,
      ),
      d['completed'][id] as String?,
      error,
    );
  }

  Map<String, dynamic> _listResolved(InquiryListRecord r) => {
    'productId': r.line.productId,
    'productVersion': r.line.productId == null
        ? null
        : state.store.get('product', r.line.productId!)?.version,
    'quoteId': r.line.quote?.id,
    'quoteVersion': r.line.quote == null
        ? null
        : state.store.get('quotation', r.line.quote!.id)?.version,
    'quotePrice': r.line.quote?.price,
  };
  Future<PreparedImport> confirmList(
    String id,
    List<String> selected,
  ) => _write((store) {
    final d = _read('list-draft:$id');
    _checkList(d);
    if ((d['project']['name'] as String? ?? '').trim().isEmpty ||
        selected.isEmpty ||
        selected.toSet().length != selected.length ||
        selected.any(
          (r) =>
              !(d['lines'] as Map).containsKey(r) || !_listRecord(d, r).valid,
        )) {
      throw StateError(
        'Confirm only valid unfinished new-project list records',
      );
    }
    validatePayload('project', Map<String, Object?>.from(d['project'] as Map));
    final frozen = <String, dynamic>{
      ...d,
      'draftId': id,
      'selected': List<String>.of(selected)..sort(),
      'resolved': {
        for (final r in selected) r: _listResolved(_listRecord(d, r)),
      },
    };
    final digest = InquiryImportPipeline._hash(utf8.encode(jsonEncode(frozen)));
    final token = 'list:$id:${d['revision']}:$digest';
    _put(store, 'confirmation:$token', frozen);
    return PreparedImport(
      target: _target(d),
      inputDigest: digest,
      stagingToken: token,
    );
  });
  Future<ImportReceipt> commitList(
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
      validateTarget(intent);
      final f = _read('confirmation:${intent.stagingToken}');
      if (InquiryImportPipeline._hash(utf8.encode(jsonEncode(f))) !=
              intent.inputDigest ||
          f['workspaceId'] != intent.workspaceId ||
          f['projectId'] != intent.targetProjectId ||
          f['kind'] != intent.kind.name) {
        throw StateError('Confirmation identity mismatch');
      }
      final d = _read('list-draft:${f['draftId']}');
      _checkList(d);
      if (d['revision'] != f['revision']) {
        throw StateError('List confirmation stale');
      }
      final selected = List<String>.from(f['selected'] as List);
      final records = [for (final r in selected) _listRecord(d, r)];
      if (records.any(
        (r) =>
            !r.valid ||
            jsonEncode(_listResolved(r)) != jsonEncode(f['resolved'][r.id]),
      )) {
        throw StateError('Reviewed list changed');
      }
      late ImportReceipt committed;
      state.commitAiTask(d['aiTaskId'] as String?, (store) {
        committed = store.transaction(() {
          final ids = <String, String>{};
          void observe(int index, String itemId) =>
              ids[selected[index]] = itemId;
          final lines = [for (final r in records) r.line];
          if (d['createdReceipt'] == null) {
            if (intent.kind != ImportKind.create ||
                store.get('project', intent.targetProjectId) != null) {
              throw StateError('List must create new project');
            }
            store.createProjectFromProposal(
              Map<String, Object?>.from(d['project'] as Map),
              lines,
              newProjectId: intent.targetProjectId,
              onCreated: observe,
            );
          } else {
            final created = receipt(d['createdReceipt'] as String);
            if (intent.kind != ImportKind.refresh ||
                created == null ||
                created.intent.targetProjectId != intent.targetProjectId ||
                created.result['draftId'] != f['draftId']) {
              throw StateError('Created project receipt unavailable');
            }
            store.continueCreatedProjectProposal(
              intent.targetProjectId,
              lines,
              onCreated: observe,
            );
          }
          for (final id in selected) {
            (d['completed'] as Map)[id] = intent.operationId;
          }
          final result = <String, Object?>{
            'draftId': f['draftId'],
            'projectId': intent.targetProjectId,
            'newProject': d['createdReceipt'] == null,
            'succeededRecordIds': selected,
            'skippedRecordIds': <String>[],
            'pendingRecordIds': [
              for (final id in (d['lines'] as Map).keys)
                if (!(d['completed'] as Map).containsKey(id)) id,
            ],
            'records': {
              for (final id in List<String>.from((d['lines'] as Map).keys))
                id: selected.contains(id)
                    ? {
                        'status': 'succeeded',
                        'businessObjectId': ids[id],
                        'receiptId': intent.operationId,
                        'error': null,
                      }
                    : (d['completed'] as Map).containsKey(id)
                    ? Map<String, Object?>.from(
                        (receipt(d['completed'][id] as String)!
                                    .result['records']
                                as Map)[id]
                            as Map,
                      )
                    : {
                        'status': 'pending',
                        'businessObjectId': null,
                        'receiptId': null,
                        'error': _listRecord(d, id).error,
                      },
            },
          };
          final at = store.clock().toUtc();
          _put(store, 'receipt:${intent.operationId}', {
            'identity': _identity(intent),
            'result': result,
            'committedAt': at.toIso8601String(),
          });
          d['createdReceipt'] ??= intent.operationId;
          d['createdProjectVersion'] = store
              .get('project', intent.targetProjectId)!
              .version;
          d['kind'] = 'refresh';
          d['revision'] = (d['revision'] as int) + 1;
          d['aiTaskId'] = null;
          _put(store, 'list-draft:${f['draftId']}', d);
          return ImportReceipt(intent: intent, result: result, committedAt: at);
        });
      });
      return committed;
    }, atomic: false);
  }
}

class PreparedInquiryListDraft extends PreparedImport {
  PreparedInquiryListDraft._(
    this.pipeline,
    this.draftId,
    ImportTarget target,
    String digest,
  ) : super(target: target, inputDigest: digest, stagingToken: 'list:$draftId');
  final InquiryImportPipeline pipeline;
  final String draftId;
  Map<String, dynamic> get _data => pipeline._read('list-draft:$draftId');
  bool get projectCreated => _data['createdReceipt'] != null;
  int get revision => _data['revision'] as int;
  String get sourceName => _data['sourceName'] as String;
  String get sourceText => _data['sourceText'] as String;
  String get sourceDigest => _data['sourceDigest'] as String;
  Map<String, Object?> get project =>
      Map<String, Object?>.from(_data['project'] as Map);
  List<String> get recordIds => List<String>.from((_data['lines'] as Map).keys);
  List<InquiryListRecord> get records => [
    for (final id in recordIds) pipeline._listRecord(_data, id),
  ];
  Future<PreparedImport> confirm(List<String> selected) =>
      pipeline.confirmList(draftId, selected);
  Future<void> editProject(String field, String? value) =>
      pipeline._write((store) {
        final d = _data;
        if (projectCreated ||
            !['name', 'code', 'customer', 'markup_rate'].contains(field)) {
          throw StateError('Created project metadata is fixed');
        }
        d['project'][field] = value?.trim() ?? '';
        d['revision'] = (d['revision'] as int) + 1;
        pipeline._put(store, 'list-draft:$draftId', d);
      });
  Future<void> edit(String id, String field, String? value) =>
      pipeline._write((store) {
        final d = _data;
        if (!(d['lines'] as Map).containsKey(id) ||
            (d['completed'] as Map).containsKey(id) ||
            !['name', 'requirements', 'qty', 'unit'].contains(field)) {
          throw StateError('List field unavailable');
        }
        d['lines'][id][field] = field == 'name' ? value ?? '' : value;
        d['revision'] = (d['revision'] as int) + 1;
        pipeline._put(store, 'list-draft:$draftId', d);
      });
  Future<void> choose(String id, String? productId) => pipeline._write((store) {
    final d = _data;
    final row = d['lines'][id] as Map;
    if ((d['completed'] as Map).containsKey(id) ||
        (productId != null &&
            !(row['candidates'] as Map).containsKey(productId))) {
      throw StateError('Choose only original candidates');
    }
    if (productId != null) {
      final h = store.get('product', productId);
      if (h == null || h.deleted) throw StateError('Candidate unavailable');
      row['candidates'][productId] = h.version;
    }
    row['productId'] = productId;
    d['revision'] = (d['revision'] as int) + 1;
    pipeline._put(store, 'list-draft:$draftId', d);
  });
}
