import 'package:muyon_module_api/muyon_module_api.dart';

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
  const InquiryReadonlySnapshot._(this.scene, this.record);
  final InquiryReadonlyScene scene;
  final OntologyCardSnapshot record;
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
            ref.contentDigest == null || ref.contentDigest!.isEmpty)) {
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
    return InquiryReadonlySnapshot._(scene, card);
  }
}
