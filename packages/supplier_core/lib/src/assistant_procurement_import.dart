part of 'assistant_procurement.dart';

extension _ProcurementImport on AssistantProcurementTools {
  Future<String> _import(
    Map<String, Object?> args,
    String callId,
    AiCancellation cancellation,
  ) async {
    _check(cancellation, write: true);
    final operation = args['operation'];
    if (operation != 'catalog') {
      throw const FormatException('仅可导入资料；替换预算须重新询价并使用正式报价');
    }
    final key =
            'assistant_procurement_receipt:${jsonEncode([sessionId, callId])}',
        canonical = _canonical(args);
    String? receipt() {
      final rows = store.db.select('SELECT value FROM meta WHERE key=?', [key]);
      if (rows.isEmpty) return null;
      final r = _object(jsonDecode(rows.single['value'] as String));
      if (r['arguments'] != canonical) throw const FormatException('调用ID参数改变');
      return _canonical(r['result']);
    }

    final replay = receipt();
    if (replay != null) return replay;
    final candidate = _candidate(args['candidate_id'] as String);
    _fresh(candidate);
    final (source, row) = _source(candidate);
    final qualification = _qualification(candidate);
    final criterion = domesticCriterion?.call();
    final f = row.facts;
    if (f['name'] == null || f['unit'] == null) {
      throw const FormatException('来源缺物料名称或单位，不能创建物料；候选和来源已保留');
    }
    final product = validatePayload('product', {
      for (final key in payloadFields('product')) key: null,
      'name': f['name'],
      'unit': f['unit'],
      'brand': f['brand'],
      'model': f['model'],
      'notes': '网页研究资料，未核验；来源 ${source.url}',
    });
    final bindings = _object(candidate['bindings']);
    final before = bindings['item'] == null
        ? <String, Object?>{}
        : _object(_object(bindings['item'])['data']);
    final priceProblems = _priceProblems(row);
    if (source.truncated) priceProblems.add('来源截断');
    if (bindings['project'] == null) priceProblems.add('缺少项目，不能建立标准参考报价');
    final preview = AssistantActionPreview(
      operation: 'procurement_import',
      type: 'product',
      id: candidate['id'] as String,
      title: '逐项审核网页采购资料（不保证来源真实）',
      before: before,
      after: {
        'operation': operation,
        'product': product,
        'requirement': candidate['requirement'],
        'qualification': qualification,
        'source': source.toJson(),
        'quote_exclusions': priceProblems,
        'reference_quote': priceProblems.isEmpty,
        'cost_policy': '仅新增资料；原预算完全保持，待重新询价并在预算界面用正式报价完成替换',
      },
      affectedReferences: {},
      referencedRecords: bindings,
      version: bindings['item'] == null
          ? null
          : _object(bindings['item'])['version'] as int,
    );
    if (approve == null) throw const FormatException('没有人工审核界面');
    if (!await cancellation.wait(approve!(preview))) {
      _check(cancellation, write: true);
      return _canonical({'status': 'denied', 'candidate_id': candidate['id']});
    }
    _check(cancellation, write: true);
    var applied = false;
    final result = store.transaction(() {
      _check(cancellation, write: true);
      final prior = receipt();
      if (prior != null) return prior;
      _fresh(candidate);
      final currentPriceProblems = _priceProblems(row);
      if (source.truncated) currentPriceProblems.add('来源截断');
      if (bindings['project'] == null) {
        currentPriceProblems.add('缺少项目，不能建立标准参考报价');
      }
      if (_canonical(currentPriceProblems) != _canonical(priceProblems)) {
        throw const FormatException('报价时效或条件已变，请重新审核');
      }
      if (criterion != domesticCriterion?.call() ||
          _canonical(qualification) != _canonical(_qualification(candidate))) {
        throw const FormatException('审核期间认定条件改变');
      }
      final attachmentId = store.addAttachment(
        '采购来源-${source.digest.substring(0, 12)}.json',
        utf8.encode(
          _canonical({
            'source': source.toJson(),
            'selected_row_id': row.id,
            'requirement': candidate['requirement'],
            'qualification': qualification,
          }),
        ),
        mime: 'application/json',
      );
      final productId = store.save('product', {
        ...product,
        'source_attachment_ids': [attachmentId],
        'notes': '未核验网页资料；来源附件 $attachmentId；${source.url}',
      });
      for (final property in specProperties.where(
        (p) => p.type == ParamType.num,
      )) {
        final raw =
            row.parameters[property.code] ?? row.parameters[property.label];
        final value = raw == null ? null : _number(property, raw);
        if (value != null) {
          store.setParam(
            productId,
            property.code,
            value,
            source: 'import',
            confirmed: false,
            evidence: raw,
            attachmentId: attachmentId,
          );
        }
      }
      String? supplierId, quotationId;
      if (f['supplier'] != null) {
        supplierId = store.save('supplier', {
          for (final field in payloadFields('supplier')) field: null,
          'name': f['supplier'],
          'aliases': <String>[],
          'categories': <String>[],
          'notes': '网页声明供应方，未核验；来源附件 $attachmentId',
        });
      }
      if (priceProblems.isEmpty && supplierId != null) {
        final projectId = _object(bindings['project'])['id'];
        quotationId = store.save('quotation', {
          for (final field in payloadFields('quotation')) field: null,
          'supplier_id': supplierId,
          'product_id': productId,
          'project_id': projectId,
          'price': f['price'],
          'currency': f['currency'],
          'tax_mode': f['tax_mode'],
          'tax_rate': f['tax_rate'],
          'unit_snapshot': f['unit'],
          'min_qty': f['min_qty'],
          'quoted_on': f['quoted_on'],
          'valid_until': f['valid_until'],
          'capture_mode': 'standard',
          'price_basis': 'reference',
          'inquirer_name': '网页研究',
          'inquiry_precision': 'date',
          'inquiry_date': f['quoted_on'],
          'attachment_ids': [attachmentId],
          'notes':
              '网页参考价；运费口径 ${f['shipping']}；配置 ${f['configuration']}；未核验，不作为正式报价或成本',
        });
      }
      final result = <String, Object?>{
        'status': 'applied',
        'candidate_id': candidate['id'],
        'product_id': productId,
        'supplier_id': supplierId,
        'quotation_id': quotationId,
        'attachment_id': attachmentId,
        'item_id': candidate['item_id'],
        'price_basis': 'reference',
        'qualification': qualification['status'],
        'cost_status': 'unchanged',
        'next_step': '待重新询价，在预算界面用正式报价完成替换',
      };
      store.db.execute('INSERT INTO meta(key,value) VALUES (?,?)', [
        key,
        _canonical({'arguments': canonical, 'result': result}),
      ]);
      applied = true;
      return _canonical(result);
    });
    if (applied) {
      try {
        onChanged?.call();
      } catch (_) {}
    }
    return result;
  }
}
