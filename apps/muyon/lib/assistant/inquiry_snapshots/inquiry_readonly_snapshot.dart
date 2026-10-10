import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../../app/bootstrap.dart';
import '../ontology_cards/inquiry_ontology_card_adapter.dart';
import '../ontology_cards/ontology_card_snapshot.dart';

enum InquiryReadonlyScene {
  inquiry('询价单'),
  quote('报价'),
  budgetLine('预算行');

  const InquiryReadonlyScene(this.label);
  final String label;
}

/// A single pinned saved record, never an atomic aggregate or a write payload.
final class InquiryReadonlySnapshot {
  const InquiryReadonlySnapshot._(this.scene, this.record, this.sourceLabel);
  final InquiryReadonlyScene scene;
  final OntologyCardSnapshot record;
  final String sourceLabel;
}

/// Host-only entry for the initial read-only inquiry scene templates.
/// Reuses the established owner for scope, revision/digest and masking rules.
final class InquiryReadonlySnapshots {
  static const maxSelectionObjects = 5;

  static Future<InquiryReadonlySnapshot> read({
    required MuyonHost host,
    required AssistantScope scope,
    required ObjectRef object,
    Map<String, Object?> suggestions = const {},
  }) async {
    if (scope.kind != AssistantScopeKind.selectedObjects ||
        scope.objects.length > maxSelectionObjects ||
        !scope.objects.contains(object) ||
        scope.objects.any((ref) => ref.moduleId != 'inquiry' ||
            ref.revisionRef == null || ref.revisionRef!.isEmpty ||
            ref.contentDigest == null || ref.contentDigest!.isEmpty ||
            [ref.moduleId, ref.objectType, ref.objectId, ref.nativeProjectId,
              ref.revisionRef, ref.contentDigest].any((value) => value != null &&
                utf8.encode(value).length > UiCollectionLimits.idBytes))) {
      throw StateError('Inquiry scene requires bounded pinned selected objects');
    }
    final scene = switch (object.objectType) {
      'inquiry' => InquiryReadonlyScene.inquiry,
      'quotation' => InquiryReadonlyScene.quote,
      'project_item' => InquiryReadonlyScene.budgetLine,
      _ => throw StateError('Unsupported read-only inquiry scene'),
    };
    final owner = host.inquiry;
    final lifecycle = host.modules.scopeAuthorityRevision('inquiry');
    final authority = host.workspaces.scopeAuthorityRevision;
    final card = await InquiryOntologyCardAdapter.read(
      host: host, scope: scope, object: object, suggestions: suggestions,
    );
    if (!identical(host.inquiry, owner) ||
        host.modules.scopeAuthorityRevision('inquiry') != lifecycle ||
        host.workspaces.scopeAuthorityRevision != authority) {
      throw StateError('Inquiry scene owner or scope changed during read');
    }
    final trusted = card.object;
    final sourceLabel = '来源对象 ${trusted.moduleId}/${trusted.objectType}/${trusted.objectId} · 修订 ${trusted.revisionRef}';
    final rows = <(String, String)>[
      for (final field in card.fields) ...[
        ('${field.label}${field.required ? '（必填）' : ''}', field.value),
        if (field.suggestion != null)
          ('${field.label} · 建议（尚未写入）', field.suggestion!),
      ],
    ];
    // Bound visible copy plus KeyValue's combined accessibility equivalent.
    // Count every optional fixed message conservatively, even when not shown.
    final displayText = [
      sourceLabel, '${scene.label} · 已保存事实',
      '来源：询价插件的已保存记录；建议尚未写入',
      '${card.typeLabel} · 只读预览',
      '保存快照 · 修订 ${trusted.revisionRef}',
      '不支持的本体版本或类型，请在原页面编辑',
      '当前为只读预览，编辑与提交尚未接入',
      '此类型未开放通用修改，请在原页面操作',
      '此类型没有独立原页面，请从询价业务页面操作',
      '提交（不可用）',
      for (final row in rows) ...[row.$1, row.$2],
      rows.map((row) => '${row.$1}：${row.$2}').join('；'),
    ];
    if (utf8.encode(sourceLabel).length > UiCollectionLimits.labelBytes ||
        displayText.fold<int>(0, (size, text) => size + utf8.encode(text).length) >
            UiStreamLimits.v1.textBytes) {
      throw StateError('Inquiry scene source or text exceeds display budget');
    }
    return InquiryReadonlySnapshot._(scene, card, sourceLabel);
  }
}
