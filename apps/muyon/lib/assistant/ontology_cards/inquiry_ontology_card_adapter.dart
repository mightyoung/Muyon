import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:supplier_core/supplier_core.dart' as domain;

import '../../app/bootstrap.dart';
import '../../platform/scope_resolver.dart';
import 'ontology_card_snapshot.dart';

/// Read-only entry point for a future page owner. Does not activate a module,
/// enumerate a global scope, open a page lease, or invoke any business tool.
final class InquiryOntologyCardAdapter {
  static Future<OntologyCardSnapshot> read({
    required MuyonHost host,
    required AssistantScope scope,
    required ObjectRef object,
    Map<String, Object?> suggestions = const {},
  }) async {
    final owner = host.inquiry;
    final lifecycle = host.modules.scopeAuthorityRevision('inquiry');
    final authority = host.workspaces.scopeAuthorityRevision;
    final declaration = host.modules.registry.require('inquiry');
    if (owner == null || lifecycle == null || authority == null ||
        declaration is! BusinessModuleV2 ||
        object.moduleId != 'inquiry' ||
        !domain.entityTypes.contains(object.objectType) ||
        object.revisionRef == null || object.contentDigest == null) {
      throw StateError('Inquiry card requires an active pinned object');
    }
    final source = host.scopeResolver.sources.singleWhere(
      (source) => source.moduleId == 'inquiry',
    );
    final resolved = await ScopeResolver(
      sources: [_ActiveInquirySource(source)],
      workspaces: host.workspaces,
      knowledgeSources: () async => const [],
    ).resolve(scope);
    if (!resolved.contains(object) ||
        host.modules.scopeAuthorityRevision('inquiry') != lifecycle ||
        host.workspaces.scopeAuthorityRevision != authority) {
      throw StateError('Inquiry card scope changed');
    }
    // Table interpolation is restricted to supplier_core's existing enum.
    // No await between this read, identity validation and projection.
    final rows = owner.runtime.state.store.db.select(
      'SELECT data,version,deleted FROM ${object.objectType} WHERE id=?',
      [object.objectId],
    );
    if (rows.isEmpty || rows.single['deleted'] != 0) {
      throw StateError('Inquiry card object is absent');
    }
    final row = rows.single;
    final raw = row['data'] as String;
    final data = Map<String, Object?>.from(jsonDecode(raw) as Map);
    final project = object.objectType == 'project'
        ? object.objectId
        : data['project_id'];
    if (object.revisionRef != '${row['version']}' ||
        object.contentDigest != sha256.convert(utf8.encode(raw)).toString() ||
        object.nativeProjectId != project) {
      throw StateError('Inquiry card object changed');
    }
    final type = declaration.ontology.type(object.objectType);
    final update = host.tools.inspect('inquiry.update_record');
    final properties = update?.descriptor.parameterSchema['properties'];
    final typeSchema = properties is Map ? properties['type'] : null;
    final allowedTypes = typeSchema is Map ? typeSchema['enum'] : null;
    return OntologyCardSnapshot.fromHostSnapshot(
      ontology: declaration.ontology,
      moduleApiVersion: declaration.manifest.apiVersion,
      object: object,
      scope: resolved,
      hasRegisteredUpdateTool: update?.available == true &&
          update?.providerId == 'inquiry' &&
          update?.descriptor.effect == ToolEffect.write &&
          allowedTypes is List && allowedTypes.contains(object.objectType),
      snapshot: DataSnapshot(
        ref: SnapshotRef(jsonEncode(object.toJson()), row['version'] as int),
        facts: {
          for (final field in type?.fields ?? <OntologyFieldSpec>[])
            field.name: SnapshotFact(
              object: object,
              field: field.name,
              value: data[field.name],
              state: FactState.verified,
            ),
        },
      ),
      suggestions: suggestions,
    );
  }
}

/// Reuses the established host scope membership/version checks without
/// ScopeSource.prepare activation. The caller fenced the active inquiry owner.
final class _ActiveInquirySource implements ScopeSource {
  const _ActiveInquirySource(this.source);
  final ScopeSource source;
  @override
  String get moduleId => source.moduleId;
  @override
  bool get resolvesDirectly => source.resolvesDirectly;
  @override
  Future<void> prepare() async {}
  @override
  Future<List<ObjectRef>> enumerate() => source.enumerate();
  @override
  Future<ObjectRef?> resolve(ObjectRef requested) => source.resolve(requested);
}
