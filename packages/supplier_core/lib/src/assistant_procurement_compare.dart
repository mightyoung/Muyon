part of 'assistant_procurement.dart';

extension _ProcurementCompare on AssistantProcurementTools {
  Map<String, Object?> _bindings(String? itemId) {
    if (itemId == null) return {};
    final item = _live('project_item', itemId);
    return {
      'item': _record(item),
      'project': _record(_live('project', item.data['project_id'] as String)),
      if (item.data['product_id'] case final String id)
        'product': _record(_live('product', id)),
      if (item.data['quotation_id'] case final String id)
        'quotation': _record(_live('quotation', id)),
    };
  }

  Map<String, Object?> _candidate(String id) {
    final candidate = _object(_load()['candidates'])[id];
    if (candidate is! Map) throw const FormatException('未知候选ID');
    return candidate.cast<String, Object?>();
  }

  (AssistantWebSnapshot, AssistantWebProduct) _source(
    Map<String, Object?> candidate,
  ) {
    final snapshot = AssistantWebSnapshot.fromJson(
      _object(candidate['source']),
    );
    final row = snapshot.products
        .where((p) => p.id == candidate['row_id'])
        .firstOrNull;
    if (row == null) throw const FormatException('来源行不存在');
    return (snapshot, row);
  }

  void _fresh(Map<String, Object?> candidate) {
    if (_canonical(_bindings(candidate['item_id'] as String?)) !=
        _canonical(candidate['bindings'])) {
      throw const FormatException('原预算/项目/物料/报价已变更，请重新研究');
    }
  }

  Map<String, Object?> _qualification(Map<String, Object?> candidate) {
    final (snapshot, row) = _source(candidate);
    final requirement = candidate['requirement'] as String;
    final checks = <Map<String, Object?>>[];
    for (final raw
        in requirement
            .split(RegExp(r'[\n;；。]'))
            .where((s) => s.trim().isNotEmpty)) {
      final clause = raw.trim();
      var status = 'unknown';
      String? reason;
      String? evidence;
      String? countryField;
      if (RegExp(r'^(中国制造|中国生产|制造地[:：]?中国|国产制造)$').hasMatch(clause)) {
        countryField = 'manufacture_country';
      }
      if (RegExp(r'^(中国品牌|国产品牌|品牌来源[:：]?中国)$').hasMatch(clause)) {
        countryField = 'brand_origin';
      }
      if (clause == '国产') {
        countryField = switch (domesticCriterion?.call()) {
          'manufacture' => 'manufacture_country',
          'brand' => 'brand_origin',
          _ => null,
        };
        if (countryField == null) reason = '国产认定口径未由用户明确';
      }
      if (countryField != null) {
        evidence = row.facts[countryField];
        if (evidence != null) {
          status =
              const {
                '中国',
                '中华人民共和国',
                'China',
                'CN',
                '中国大陆',
                'Mainland China',
              }.contains(evidence)
              ? 'source_supported'
              : 'contradicted';
        } else {
          reason = '来源未明确声明所需国别，品牌与制造地不可混用';
        }
      } else if (reason == null) {
        final parsed = _numericRequirement(clause);
        if (parsed != null) {
          final (property, constraint) = parsed;
          evidence =
              row.parameters[property.code] ?? row.parameters[property.label];
          final have = evidence == null ? null : _number(property, evidence);
          if (have != null) {
            final verdict = evaluateConstraint(
              property,
              have,
              constraint,
              today: _today,
            );
            status = verdict.satisfied
                ? 'source_supported'
                : verdict.outcome.name == 'worse'
                ? 'contradicted'
                : 'unknown';
            reason = verdict.note;
          } else {
            reason = '缺少明确字典参数或单位不支持';
          }
        } else {
          reason = '完整条款未被支持的严格规则解析，须人工核验';
        }
      }
      checks.add({
        'requirement': clause,
        'status': status,
        'evidence': evidence,
        'reason': reason,
      });
    }
    if (checks.isEmpty) {
      checks.add({
        'requirement': requirement,
        'status': 'unknown',
        'reason': '未绑定完整技术要求，仅供资料研究',
      });
    }
    if (snapshot.truncated) {
      checks.add({
        'requirement': '来源完整性',
        'status': 'unknown',
        'reason': '网页快照被截断',
      });
    }
    if (row.warnings.isNotEmpty) {
      checks.add({
        'requirement': '来源字段完整性',
        'status': 'unknown',
        'reason': row.warnings.join('；'),
      });
    }
    final status = checks.any((c) => c['status'] == 'contradicted')
        ? 'contradicted'
        : checks.every((c) => c['status'] == 'source_supported')
        ? 'source_supported'
        : 'unknown';
    return {
      'candidate_id': candidate['id'],
      'requirement': requirement,
      'status': status,
      'checks': checks,
      'review': 'source_supported仅为网页声明支持，须逐项人工审阅，不保证网页真实',
    };
  }

  (SpecProperty, SpecConstraint)? _numericRequirement(String clause) {
    for (final property in specProperties.where(
      (p) => p.type == ParamType.num,
    )) {
      for (final label in [property.code, property.label]) {
        if (!clause.startsWith(label)) continue;
        final match = RegExp(r'^\s*(>=|<=|≥|≤|=|不低于|不少于|不高于|不超过|等于)\s*(.+)$')
            .firstMatch(clause.substring(label.length));
        if (match == null) continue;
        final number = _number(property, match[2]!);
        if (number == null) continue;
        final op = const {
          '>=': 'ge',
          '≥': 'ge',
          '不低于': 'ge',
          '不少于': 'ge',
          '<=': 'le',
          '≤': 'le',
          '不高于': 'le',
          '不超过': 'le',
          '=': 'eq',
          '等于': 'eq',
        }[match[1]]!;
        return (property, SpecConstraint(property.code, op, number));
      }
    }
    return null;
  }

  Map<String, Object?>? _number(SpecProperty property, String text) {
    final m = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)\s*([^\s]*)\s*$')
        .firstMatch(text);
    if (m == null) return null;
    final unit = m[2]!;
    if (property.kind != null && unit.isEmpty) return null;
    if (property.kind == null &&
        unit.isNotEmpty &&
        unit != property.unitLabel) {
      return null;
    }
    try {
      return normalizeParamValue(property, {
        'v': m[1],
        if (property.kind != null) 'u': unit,
      });
    } on FormatException {
      return null;
    }
  }

  List<String> _priceProblems(AssistantWebProduct row) {
    final facts = row.facts, missing = <String>[];
    for (final field in [
      'brand',
      'model',
      'configuration',
      'supplier',
      'price',
      'currency',
      'unit',
      'tax_mode',
      'tax_rate',
      'shipping',
      'min_qty',
      'quoted_on',
      'valid_until',
    ]) {
      if (facts[field] == null) missing.add('缺少$field');
    }
    if (row.warnings.isNotEmpty) missing.addAll(row.warnings);
    try {
      ExactDecimal.parse(facts['price'] ?? '', positive: true);
      ExactDecimal.parse(facts['min_qty'] ?? '', positive: true);
    } on FormatException {
      missing.add('价格或最小数量不是明确正十进制值');
    }
    if (!const {'included', 'excluded'}.contains(facts['tax_mode'])) {
      missing.add('税口径未知');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(facts['currency'] ?? '')) {
      missing.add('币种无效');
    }
    try {
      final rate = ExactDecimal.parse(
        facts['tax_rate'] ?? '',
        maxIntegerDigits: 3,
        maxFractionDigits: 4,
      );
      if (rate.compareTo(ExactDecimal.parse('100')) > 0) missing.add('税率超出范围');
    } on FormatException {
      missing.add('税率不是明确十进制值');
    }
    if (!const {
      'included',
      'excluded',
      'free',
      '含运费',
      '不含运费',
      '包邮',
      '免运费',
    }.contains(facts['shipping'])) {
      missing.add('运费口径未知');
    }
    for (final field in ['quoted_on', 'valid_until']) {
      try {
        requireDate(facts[field], field);
      } on FormatException {
        missing.add('$field日期无效');
      }
    }
    final today = _today;
    if ((facts['quoted_on'] ?? '9999').compareTo(today) > 0) {
      missing.add('报价日期晚于今天');
    }
    if ((facts['valid_until'] ?? '0000').compareTo(today) < 0) {
      missing.add('报价过期或有效期未知');
    }
    if (facts['quoted_on'] != null &&
        facts['valid_until'] != null &&
        facts['valid_until']!.compareTo(facts['quoted_on']!) < 0) {
      missing.add('日期顺序矛盾');
    }
    return missing;
  }

  Map<String, Object?> _compare(List<String> ids, String? itemId) {
    final rows = [for (final id in ids) _candidate(id)];
    for (final c in rows) {
      _fresh(c);
    }
    final target = _bindings(itemId);
    final product = target['product'] == null
        ? null
        : _object(_object(target['product'])['data']);
    final item = target['item'] == null
        ? null
        : _object(_object(target['item'])['data']);
    final included = <Map<String, Object?>>[],
        excluded = <Map<String, Object?>>[];
    Map<String, String>? basis;
    final sellers = <String>{}, domains = <String>{};
    final prices = <BigInt>[];
    for (final c in rows) {
      final (source, row) = _source(c);
      final f = row.facts;
      final problems = _priceProblems(row);
      if (source.truncated) problems.add('来源截断');
      if (product != null &&
          (f['brand'] != product['brand'] || f['model'] != product['model'])) {
        problems.add('与项目品牌或完整型号不同');
      }
      if (item != null) {
        if (f['unit'] != item['unit']) problems.add('与项目单位不同');
        try {
          if (micros(f['min_qty']!) > micros(item['qty'] as String)) {
            problems.add('项目数量未达到最小起订量');
          }
        } catch (_) {
          problems.add('数量条件未知');
        }
      }
      final b = {
        for (final key in [
          'brand',
          'model',
          'configuration',
          'currency',
          'unit',
          'tax_mode',
          'tax_rate',
          'shipping',
          'min_qty',
          'quoted_on',
          'valid_until',
        ])
          key: f[key] ?? '',
      };
      if (basis != null && _canonical(b) != _canonical(basis)) {
        problems.add('样本品牌/完整型号/配置/币种/单位/税运/数量/日期口径不同');
      }
      // Conservative grouping also rejects subdomains as independent sellers.
      final labels = Uri.parse(source.url).host.toLowerCase().split('.');
      final host = labels
          .skip(labels.length > 2 ? labels.length - 2 : 0)
          .join('.');
      final seller = (f['supplier'] ?? '').trim().toLowerCase();
      if (sellers.contains(seller) || domains.contains(host)) {
        problems.add('卖方或域名重复，不能作为独立样本');
      }
      if (problems.isNotEmpty) {
        excluded.add({'candidate_id': c['id'], 'reasons': problems});
        continue;
      }
      basis ??= b;
      sellers.add(seller);
      domains.add(host);
      prices.add(micros(f['price']!));
      included.add({
        'candidate_id': c['id'],
        'source': source.url,
        'seller': f['supplier'],
        'price': f['price'],
      });
    }
    prices.sort();
    return {
      'kind': 'comparison',
      'as_of': _today,
      'status': prices.length >= 2
          ? 'reference_range'
          : 'insufficient_evidence',
      'included': included,
      'excluded': excluded,
      'basis': basis,
      if (prices.length >= 2) 'min': fromMicros(prices.first),
      if (prices.length >= 2) 'max': fromMicros(prices.last),
      'project_difference': _projectDifference(target, basis, prices),
      'notice': '仅网页参考样本区间，不是公允价或合理性结论；不支持的字段必须人工核验',
    };
  }

  Map<String, Object?> _projectDifference(
    Map<String, Object?> bindings,
    Map<String, String>? basis,
    List<BigInt> prices,
  ) {
    final reasons = <String>[];
    if (bindings['item'] == null) {
      return {
        'status': 'not_comparable',
        'reasons': ['未指定预算行'],
      };
    }
    if (basis == null || prices.length < 2) {
      return {
        'status': 'not_comparable',
        'reasons': ['缺少两个完整同口径独立样本'],
      };
    }
    final item = _object(_object(bindings['item'])['data']);
    final product = bindings['product'] == null
        ? null
        : _object(_object(bindings['product'])['data']);
    final quote = bindings['quotation'] == null
        ? null
        : _object(_object(bindings['quotation'])['data']);
    final project = _object(_object(bindings['project'])['data']);
    if (product == null) reasons.add('预算没有明确物料');
    if (quote == null) {
      return {
        'status': 'not_comparable',
        'reasons': [...reasons, '预算未选择正式报价'],
      };
    }
    if (quote['price_basis'] != null || quote['capture_mode'] != 'standard') {
      reasons.add('选中报价不是正式标准报价');
    }
    if (quote['product_id'] != item['product_id']) reasons.add('选中报价与预算物料不同');
    if (quote['project_id'] != _object(bindings['project'])['id']) {
      reasons.add('选中报价不属于当前项目');
    }
    for (final field in ['brand', 'model']) {
      if (product?[field] == null || product?[field] != basis[field]) {
        reasons.add('本机$field与来源不一致或缺失');
      }
    }
    final configs = <String>{};
    final attrs = product?['attributes'];
    if (attrs is Map) {
      for (final key in ['configuration', '配置']) {
        if (attrs[key] case final String value when value.isNotEmpty) {
          configs.add(value);
        }
      }
    }
    // A source document can supply configuration only when its selected row is
    // bound to this exact product and all of this quotation's core terms.
    for (final id in quote['attachment_ids'] as List? ?? const []) {
      final attachment = store.attachment(id as String);
      if (attachment?.bytes == null || attachment!.size > 512 * 1024) continue;
      try {
        final evidence = _object(jsonDecode(utf8.decode(attachment.bytes!)));
        final source = AssistantWebSnapshot.fromJson(
          _object(evidence['source']),
        );
        if (source.truncated) continue;
        final row = source.products
            .where((p) => p.id == evidence['selected_row_id'])
            .firstOrNull;
        if (row == null || row.warnings.isNotEmpty) continue;
        final f = row.facts;
        if (f['brand'] != product?['brand'] ||
            f['model'] != product?['model']) {
          continue;
        }
        if (f['unit'] != quote['unit_snapshot']) continue;
        if (['price', 'tax_rate', 'min_qty'].any(
          (key) =>
              f[key] == null ||
              quote[key] == null ||
              micros(f[key]!) != micros(quote[key] as String),
        )) {
          continue;
        }
        if ([
          'currency',
          'tax_mode',
          'quoted_on',
          'valid_until',
        ].any((key) => f[key] != quote[key])) {
          continue;
        }
        if (f['configuration'] case final String configuration) {
          configs.add(configuration);
        }
      } catch (_) {
        /* Ordinary non-source attachments provide no typed facts. */
      }
    }
    if (configs.length != 1 || configs.single != basis['configuration']) {
      reasons.add('本机配置缺失、冲突或与来源不同');
    }
    for (final field in ['currency', 'tax_mode', 'quoted_on', 'valid_until']) {
      if (quote[field] == null || quote[field] != basis[field]) {
        reasons.add('正式报价$field与来源不同或缺失');
      }
    }
    for (final field in ['currency', 'tax_mode']) {
      if (project[field] != basis[field]) reasons.add('项目$field与来源不同，不自动换算');
    }
    if (item['unit'] != basis['unit'] ||
        quote['unit_snapshot'] != basis['unit']) {
      reasons.add('预算/正式报价单位与来源不同，不自动换算');
    }
    for (final field in ['tax_rate', 'min_qty']) {
      try {
        if (micros(quote[field] as String) != micros(basis[field]!)) {
          reasons.add('正式报价$field与来源不同');
        }
      } catch (_) {
        reasons.add('正式报价$field缺失或无效');
      }
    }
    final scope = quote['includes'];
    final shipping = basis['shipping'];
    final included = const {
      'included',
      'free',
      '含运费',
      '包邮',
      '免运费',
    }.contains(shipping);
    final excluded = const {'excluded', '不含运费'}.contains(shipping);
    if (scope is! List) {
      reasons.add('正式报价运费范围未知');
    } else {
      if ((!included && !excluded) || scope.contains('freight') != included) {
        reasons.add('正式报价运费范围与来源不同');
      }
      if (scope.any((value) => value != 'freight')) {
        reasons.add('正式报价包含安装/调试/培训等额外范围，不能视为同口径单价');
      }
    }
    if (quote['extra_cost'] != null &&
        micros(quote['extra_cost'] as String) != BigInt.zero) {
      reasons.add('正式报价存在额外费用，需另行核对');
    }
    if (quote['price_tiers'] != null) reasons.add('正式报价有阶梯价格，当前工具不推定适用档位');
    if (micros(item['qty'] as String) < micros(quote['min_qty'] as String)) {
      reasons.add('预算数量低于正式报价最小数量');
    }
    final cost = micros(item['unit_cost'] as String),
        quoted = micros(quote['price'] as String);
    if (cost != quoted) reasons.add('预算成本快照与当前正式报价单价不同');
    if (reasons.isNotEmpty) {
      return {'status': 'not_comparable', 'reasons': reasons};
    }
    return {
      'status': 'comparable_unit_price',
      'scope': '仅比较同口径单价，不代表总采购成本或市场公允价',
      'project_unit_cost': fromMicros(cost),
      'currency': basis['currency'],
      'unit': basis['unit'],
      'difference_from_min': fromMicros(cost - prices.first),
      'difference_from_max': fromMicros(cost - prices.last),
      'position': cost < prices.first
          ? 'below_reference_range'
          : cost > prices.last
          ? 'above_reference_range'
          : 'within_reference_range',
    };
  }
}
