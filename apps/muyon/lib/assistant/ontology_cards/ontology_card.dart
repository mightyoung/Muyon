import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'ontology_card_snapshot.dart';

/// Fixed trusted host template: no model-provided component, binding, action,
/// route or executable callback. All references remain plain, inactive text.
class OntologyCard extends StatelessWidget {
  const OntologyCard({super.key, required this.snapshot});
  final OntologyCardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${snapshot.typeLabel} · 只读预览',
          style: Theme.of(context).textTheme.titleMedium),
      Text('保存快照 · 修订 ${snapshot.object.revisionRef}'),
      if (snapshot.fallback) const Text('不支持的本体版本或类型，请在原页面编辑'),
      KeyValue(items: [
        for (final field in snapshot.fields) ...[
          ('${field.label}${field.required ? '（必填）' : ''}', field.value),
          if (field.suggestion != null)
            ('${field.label} · 建议（尚未写入）', field.suggestion!),
        ],
      ]),
      Text(snapshot.hasRegisteredUpdateTool
          ? '当前为只读预览，编辑与提交尚未接入'
          : '此类型未开放通用修改，请在原页面操作'),
      if (!snapshot.hasOriginalPage)
        const Text('此类型没有独立原页面，请从询价业务页面操作'),
      const FilledButton(onPressed: null, child: Text('提交（不可用）')),
    ],
  );
}
