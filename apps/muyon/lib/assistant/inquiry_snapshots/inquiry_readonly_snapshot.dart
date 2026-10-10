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
    final displayText = [sourceLabel, scene.label, card.typeLabel,
      for (final field in card.fields) ...[
        field.label, field.value, if (field.suggestion != null) field.suggestion!,
      ],
    ];
    if (utf8.encode(sourceLabel).length > UiCollectionLimits.labelBytes ||
        displayText.fold<int>(0, (size, text) => size + utf8.encode(text).length) >
            UiStreamLimits.v1.textBytes) {
      throw StateError('Inquiry scene source or text exceeds display budget');
    }
    return InquiryReadonlySnapshot._(scene, card, sourceLabel);
  }
}
