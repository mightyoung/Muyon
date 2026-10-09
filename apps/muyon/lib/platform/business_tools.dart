import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../app/bootstrap.dart';
import 'inquiry_write_tools.dart';
import 'host_tool_registration.dart';
import 'scope_resolver.dart';

String objectIdentity(ObjectRef ref) => scopeIdentity(ref);

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
/// A thin wrapper: the single resolver is `ScopeResolver` (ADR-0004 §5.2).
Future<ResolvedAssistantScope> resolveAssistantScope(
  MuyonHost host,
  AssistantScope scope,
) => host.scopeResolver.resolve(scope);

/// Compatibility entry for callers of the original host catalog.
void registerBusinessTools(MuyonHost host) {
  registerInquiryTools(host);
  registerNonInquiryBusinessTools(host);
}

/// Inquiry is declared by its V2 adapter in production.
void registerNonInquiryBusinessTools(MuyonHost host) {
  host.modules.registerTools(moduleIds: ['prototype', 'research']);
}

/// Existing inquiry declarations, shared by the compatibility and V2 paths.
void registerInquiryTools(MuyonHost host, {HostToolRegistration? register}) {
  final registerTool = register ?? host.tools.register;
  registerInquiryWriteTools(host, register: registerTool);
  // Reuse the mature application's actual query, comparison, budget and
  // matching rules, rather than rebuilding simplified calculations.
  for (final definition in agentTools) {
    final function = definition['function'] as Map;
    final name = function['name'] as String;
    registerTool(
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
        final result = store.runToolResult(
          name,
          jsonEncode(call.request.parameters),
        );
        final decoded = result.legacyValue;
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
          status: switch (result.status) {
            AgentToolStatus.succeeded => ToolCallStatus.succeeded,
            AgentToolStatus.invalidArguments => ToolCallStatus.invalidArguments,
            AgentToolStatus.failed => ToolCallStatus.failed,
          },
          summary: result.error ?? '${function['description']}',
          data: data,
          objectRefs: refs.toSet().toList(),
        );
      },
    );
  }
  registerTool(
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
