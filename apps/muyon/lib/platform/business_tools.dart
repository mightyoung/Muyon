import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../app/bootstrap.dart';

String objectIdentity(ObjectRef ref) => jsonEncode([
  ref.moduleId,
  ref.objectType,
  ref.nativeProjectId,
  ref.objectId,
]);

Map<String, Object?> _businessSchema(Map input) {
  final schema = Map<String, Object?>.from(input);
  // The source query tool accepts a scalar or scalar list for comparison values.
  // Make that existing contract explicit for the host's strict validator.
  if (!schema.containsKey('type')) {
    schema['type'] = ['string', 'number', 'boolean', 'null', 'array'];
    schema['items'] = {
      'type': ['string', 'number', 'boolean', 'null'],
    };
    schema['maxItems'] = 100;
  }
  if (schema['properties'] case final Map properties) {
    schema['properties'] = {
      for (final entry in properties.entries)
        (entry.key as String): _businessSchema(entry.value as Map),
    };
    schema['additionalProperties'] = false;
  }
  if (schema['items'] case final Map items) {
    schema['items'] = _businessSchema(items);
  }
  return schema;
}

/// Domain objects remain in their module. The host only resolves identities
/// and versions; global scope does not copy their content into model prompts.
Future<ResolvedAssistantScope> resolveAssistantScope(
  MuyonHost host,
  AssistantScope scope,
) async {
  await host.activateInquiry();
  await host.activateResearch();
  final objects = <String, ObjectRef>{};
  void add(ObjectRef ref) => objects[objectIdentity(ref)] = ref;
  final inquiry = host.inquiry?.runtime.state.store;
  if (inquiry != null) {
    for (final type in entityTypes) {
      for (final row in inquiry.db.select(
        'SELECT * FROM $type WHERE deleted=0',
      )) {
        final data = jsonDecode(row['data'] as String) as Map;
        add(
          ObjectRef(
            moduleId: 'inquiry',
            objectType: type,
            objectId: row['id'] as String,
            nativeProjectId: type == 'project'
                ? row['id'] as String
                : data['project_id'] as String?,
            revisionRef: row['version'].toString(),
            contentDigest: sha256
                .convert(utf8.encode(row['data'] as String))
                .toString(),
          ),
        );
      }
    }
  }
  final research = host.research?.store;
  if (research != null) {
    for (final project in research.projects()) {
      add(
        ObjectRef(
          moduleId: 'research',
          objectType: 'project',
          objectId: project.id,
          nativeProjectId: project.id,
          contentDigest: sha256
              .convert(
                utf8.encode(
                  jsonEncode([
                    project.title,
                    project.question,
                    project.nextStep,
                  ]),
                ),
              )
              .toString(),
        ),
      );
      for (final document in research.documents(project.id)) {
        final file = File(document.absolutePath);
        final digest = file.existsSync()
            ? (await sha256.bind(file.openRead()).first).toString()
            : 'missing';
        add(
          ObjectRef(
            moduleId: 'research',
            objectType: 'document',
            objectId: document.id,
            nativeProjectId: project.id,
            contentDigest: digest,
          ),
        );
      }
      for (final entry in research.entries(project.id)) {
        add(
          ObjectRef(
            moduleId: 'research',
            objectType: 'entry',
            objectId: entry.id,
            nativeProjectId: project.id,
            contentDigest: sha256
                .convert(utf8.encode(jsonEncode(entry.data)))
                .toString(),
          ),
        );
      }
    }
  }
  for (final document in host.services.knowledge.documents()) {
    if (await host.services.knowledge.isCurrent(document.id)) {
      final ref = document.source;
      objects.putIfAbsent(objectIdentity(ref), () => ref);
    }
  }
  if (scope.kind == AssistantScopeKind.global) {
    return ResolvedAssistantScope(
      requested: scope,
      objects: objects.values.toList(),
    );
  }
  final workspace = scope.workspaceId;
  if (workspace != null &&
      !host.workspaces.all().any((w) => w.id == workspace)) {
    throw StateError('Unknown workspace');
  }
  bool inWorkspace(ObjectRef ref) {
    if (workspace == null) return true;
    final binding = host.workspaces.binding(workspace, ref.moduleId);
    return binding != null && binding.nativeProjectId == ref.nativeProjectId;
  }

  if (scope.kind == AssistantScopeKind.workspace) {
    return ResolvedAssistantScope(
      requested: scope,
      objects: objects.values.where(inWorkspace).toList(),
    );
  }
  final selected = <ObjectRef>[];
  for (final requested in scope.objects) {
    final current = objects[objectIdentity(requested)];
    if (current == null ||
        !inWorkspace(current) ||
        (requested.revisionRef != null &&
            requested.revisionRef != current.revisionRef) ||
        (requested.contentDigest != null &&
            requested.contentDigest != current.contentDigest)) {
      throw StateError(
        'Selected object is missing, changed or outside workspace',
      );
    }
    selected.add(current);
  }
  return ResolvedAssistantScope(requested: scope, objects: selected);
}

void registerBusinessTools(MuyonHost host) {
  final registry = host.tools;
  // Reuse the mature application's actual query, comparison, budget and
  // matching rules, rather than rebuilding simplified calculations.
  for (final definition in agentTools) {
    final function = definition['function'] as Map;
    final name = function['name'] as String;
    registry.register(
      providerId: 'inquiry',
      descriptor: ToolDescriptor(
        toolId: 'inquiry.$name',
        moduleId: 'inquiry',
        effect: ToolEffect.read,
        description: '${function['description'] ?? ''}',
        parameterSchema: _businessSchema(function['parameters'] as Map),
      ),
      supportedScopes: {AssistantScopeKind.global},
      dataModuleIds: {'inquiry'},
      handler: (call) async {
        call.cancellation.throwIfCancelled();
        await host.activateInquiry();
        final store = host.inquiry?.runtime.state.store;
        if (store == null) {
          throw StateError(host.inquiryError ?? 'Inquiry unavailable');
        }
        final parameters = call.request.parameters;
        void requireScoped(String type, Object? id) {
          if (id == null) return;
          if (!call.resolvedScope.objects.any(
            (ref) =>
                ref.moduleId == 'inquiry' &&
                ref.objectType == type &&
                ref.objectId == id,
          )) {
            throw StateError('Requested record is outside the resolved scope');
          }
        }

        if (name == 'get') {
          requireScoped(parameters['type'] as String, parameters['id']);
        }
        if (name == 'related') {
          final link = links.firstWhere(
            (link) => link.name == parameters['link'],
          );
          requireScoped(link.to, parameters['id']);
        }
        for (final target in const {
          'project_id': 'project',
          'product_id': 'product',
          'item_id': 'spec_item',
          'inquiry_id': 'inquiry',
          'supplier_id': 'supplier',
        }.entries) {
          requireScoped(target.value, parameters[target.key]);
        }
        final decoded = jsonDecode(
          store.runTool(name, jsonEncode(call.request.parameters)),
        );
        final data = decoded is Map
            ? Map<String, Object?>.from(decoded)
            : {'result': decoded};
        final refs = <ObjectRef>[];
        void collect(Object? value) {
          if (value is Map) {
            final id = value['id'];
            if (id is String) {
              refs.addAll(
                call.resolvedScope.objects.where(
                  (r) => r.moduleId == 'inquiry' && r.objectId == id,
                ),
              );
            }
            for (final child in value.values) {
              collect(child);
            }
          } else if (value is List) {
            for (final child in value) {
              collect(child);
            }
          }
        }

        collect(data);
        if (call.request.parameters['project_id'] case final String id) {
          refs.addAll(
            call.resolvedScope.objects.where(
              (r) =>
                  r.moduleId == 'inquiry' &&
                  r.objectType == 'project' &&
                  r.objectId == id,
            ),
          );
        }
        return ToolCallResult(
          status: data.containsKey('error')
              ? ToolCallStatus.failed
              : ToolCallStatus.succeeded,
          summary: data.containsKey('error')
              ? '${data['error']}'
              : '${function['description']}',
          data: data,
          objectRefs: refs.toSet().toList(),
        );
      },
    );
  }
  registry.register(
    providerId: 'research',
    descriptor: ToolDescriptor(
      toolId: 'research.objects',
      moduleId: 'research',
      effect: ToolEffect.read,
      description:
          '在本次范围内检索科研对象：项目、文档和研究条目，按标题子串过滤，最多返回 50 条引用与标题。'
          '只读取本机科研库，不修改数据，也不发送到设备外。',
      parameterSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'additionalProperties': false,
      },
    ),
    handler: (call) async {
      final query = (call.request.parameters['query'] as String? ?? '')
          .toLowerCase();
      final rows = <Map<String, Object?>>[];
      final refs = <ObjectRef>[];
      for (final ref in call.resolvedScope.objects.where(
        (r) => r.moduleId == 'research',
      )) {
        final store = host.research!.store;
        final String title;
        if (ref.objectType == 'project') {
          title = store
              .projects()
              .where((p) => p.id == ref.objectId)
              .first
              .title;
        } else if (ref.objectType == 'document') {
          title = store
              .documents(ref.nativeProjectId!)
              .where((d) => d.id == ref.objectId)
              .first
              .relativePath;
        } else {
          title = store
              .entries(ref.nativeProjectId!)
              .where((e) => e.id == ref.objectId)
              .first
              .title;
        }
        if (query.isNotEmpty && !title.toLowerCase().contains(query)) continue;
        refs.add(ref);
        rows.add({'ref': ref.toJson(), 'title': title});
        if (rows.length == 50) break;
      }
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${rows.length} 个科研对象',
        data: {'objects': rows, 'limit': 50},
        objectRefs: refs,
      );
    },
  );
  registry.register(
    providerId: 'inquiry',
    descriptor: ToolDescriptor(
      toolId: 'inquiry.object',
      moduleId: 'inquiry',
      effect: ToolEffect.read,
      description:
          '按类型与 id 读取一条本次范围内的询价业务记录（供应商、物料、报价、项目等），返回记录字段。'
          '只读取本机询价库，不修改数据，也不发送到设备外。',
      parameterSchema: {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'enum': entityTypes},
          'id': {'type': 'string'},
        },
        'required': ['type', 'id'],
        'additionalProperties': false,
      },
    ),
    handler: (call) async {
      final ref = call.resolvedScope.objects
          .where(
            (r) =>
                r.moduleId == 'inquiry' &&
                r.objectType == call.request.parameters['type'] &&
                r.objectId == call.request.parameters['id'],
          )
          .firstOrNull;
      if (ref == null) throw StateError('Object outside scope');
      final record = host.inquiry!.runtime.state.store.get(
        ref.objectType,
        ref.objectId,
      )!;
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '读取 ${record.data['name'] ?? ref.objectType}',
        data: {'record': record.data},
        objectRefs: [ref],
      );
    },
  );
}
