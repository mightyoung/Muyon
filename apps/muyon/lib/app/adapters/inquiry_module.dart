import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart' as domain;

import '../../platform/business_tools.dart';
import '../../platform/storage_manager.dart';
import '../../services/models/profile_repository.dart';
import '../bootstrap.dart';
import '../host_tool_registrar.dart';
import '../inquiry_plugin.dart';
import '../legacy_module_bridge.dart';
import '../../services/documents/document_parser.dart';

export 'package:inquiry_module/inquiry_module.dart'
    show
        PreparedInquiryDraft,
        InquiryImportRecord,
        InquiryRecordStatus,
        SelectedInquiryInput,
        InquiryImportPurpose;

/// Host-side adaptation of the existing inquiry owner (ADR-0004 §10.4).
/// No domain rules, databases or authorization authority are duplicated.
class InquiryBusinessModule implements BusinessModuleV2 {
  InquiryBusinessModule(this._host);
  final MuyonHost Function() _host;

  @override
  final manifest = ModuleManifest(
    id: 'inquiry',
    apiVersion: 2,
    displayName: 'Folio · 询价台账',
    tagline: '完整供应商、询价报价和成本业务',
    iconKey: 'receipt_long',
    features: {ModuleFeature.importPipeline},
  );
  @override
  ModuleSchema get schema => InquiryPlugin.schema;
  @override
  List<AuxiliarySchema> get auxiliarySchemas => [
    AuxiliarySchema('inquiry_jobs', InquiryPlugin.jobsSchema),
    AuxiliarySchema('inquiry_hub', InquiryPlugin.hubSchema),
  ];
  @override
  List<ModuleRoute> get routes => const [];
  @override
  List<ModuleSection> get sections => inquiryDeclaration().sections;
  @override
  List<SearchSource> get searchSources => const []; // REG-4c, no new retrieval.

  @override
  void registerTools(ToolRegistrar registrar) {
    // This adapter is trusted host code. Keep host-only effectIntent and
    // result guards verbatim; neither is an authorization offered to modules.
    if (registrar is! HostToolRegistrar) {
      throw ArgumentError('Inquiry requires the existing host registrar');
    }
    registerInquiryTools(_host(), register: registrar.registerHostTool);
  }

  @override
  Future<ModuleRuntime> activate(ModuleResources resources) async {
    final host = _host();
    final owner = host.inquiry ??= await InquiryPlugin.attach(
      database: resources.database as ManagedConnection,
      jobsDatabase: resources.auxiliary['inquiry_jobs']! as ManagedConnection,
      hubDatabase: resources.auxiliary['inquiry_hub']! as ManagedConnection,
      filesRoot: resources.files.rootPath,
      deviceId: host.workspaces.setting('deviceId') as String,
      modelProfiles: ProfileRepository(host.workspaces),
      modelGateway: host.services.gateway,
      tools: host.tools,
      approveModelRequest: (preview) =>
          host.approveInquiryModelRequest?.call(preview) ?? Future.value(false),
    );
    host.inquiryError = null;
    return InquiryModuleRuntime(
      owner,
      resources.files,
      isActive: () => host.modules.scopeAuthorityRevision('inquiry') != null,
    );
  }

  @override
  ModuleOntology get ontology => inquiryOntology;
  @override
  CapabilityCoverage get coverage => CapabilityCoverage(
    surfaces: const [
      Surface('package:supplier_core/supplier_core.dart', 'Store'),
    ],
    operations: [
      for (final definition in domain.agentTools)
        Operation(
          id: (definition['function'] as Map)['name'] as String,
          kind: OpKind.query,
          tools: ['inquiry.${(definition['function'] as Map)['name']}'],
        ),
      Operation(id: 'object', kind: OpKind.query, tools: ['inquiry.object']),
      Operation(
        id: 'context_import',
        kind: OpKind.write,
        members: {'prepareImport', 'commitImport', 'receipt'},
        notExposed: const NotExposed(
          NotExposedKind.humanOnly,
          '文件上下文复核由人工选择功能、校验字段并确认记录集合；没有模型提交工具。',
        ),
      ),

      for (final name in const [
        'create_inquiry',
        'record_quote',
        'set_item_qty',
        'set_inquiry_status',
      ])
        Operation(id: name, kind: OpKind.write, tools: ['inquiry.$name']),
    ],
  );
}

/// The compatibility InquiryPlugin remains the one service/close owner.
class InquiryModuleRuntime
    implements ModuleRuntime, ScopeResolvable, ImportCapable {
  InquiryModuleRuntime(
    this.owner,
    ModuleFiles files, {
    required bool Function() isActive,
  }) : imports = InquiryImportPipeline(
         state: owner.runtime.state,
         files: files,
         isActive: isActive,
         parseText: (input) async => (await DocumentParser().parseInput(
           input.path,
           input.displayName,
         )).pages.join('\n'),
       );
  final InquiryPlugin owner;
  final InquiryImportPipeline imports;
  @override
  Future<PreparedImport> prepareImport(
    SelectedInput input,
    ImportTarget target,
  ) async {
    return imports.prepare(input, target);
  }

  @override
  Future<ImportReceipt> commitImport(
    PreparedImport input,
    ImportIntent intent,
  ) async => imports.commit(input, intent);
  @override
  Future<ImportReceipt?> receipt(String operationId) async =>
      imports.receipt(operationId);
  Future<PreparedInquiryDraft> resumeImport(String draftId) async =>
      imports.resume(draftId);
  @override
  Future<ModuleSession> openSession(WorkspaceBinding binding) async =>
      _InquirySession(owner, binding.nativeProjectId);
  @override
  Future<ModuleSession> openScopeSession() async =>
      _InquirySession(owner, null);
}

class _InquirySession implements ModuleSession {
  _InquirySession(this.owner, this.project);
  final InquiryPlugin owner;
  final String? project;
  @override
  Future<ObjectView?> resolve(ObjectRef ref) async {
    if (ref.moduleId != 'inquiry' ||
        !domain.entityTypes.contains(ref.objectType)) {
      return null;
    }
    final rows = owner.runtime.state.store.db.select(
      'SELECT id,data,version FROM ${ref.objectType} WHERE id=? AND deleted=0',
      [ref.objectId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final raw = row['data'] as String;
    final data = jsonDecode(raw) as Map;
    final nativeProject = ref.objectType == 'project'
        ? ref.objectId
        : data['project_id'] as String?;
    if (ref.nativeProjectId != nativeProject ||
        (project != null && project != nativeProject)) {
      return null;
    }
    final revision = row['version'].toString();
    final digest = sha256.convert(utf8.encode(raw)).toString();
    if ((ref.revisionRef != null && ref.revisionRef != revision) ||
        (ref.contentDigest != null && ref.contentDigest != digest)) {
      return null;
    }
    return ObjectView(
      ref: ObjectRef(
        moduleId: 'inquiry',
        objectType: ref.objectType,
        objectId: ref.objectId,
        nativeProjectId: nativeProject,
        revisionRef: revision,
        contentDigest: digest,
      ),
      title: '${data['name'] ?? data['title'] ?? data['code'] ?? ref.objectId}',
    );
  }

  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) => null;
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() async {} // Session never closes the shared owner.
}

// Field classifications fixed by the accepted ADR-0004 Q7 decision.
Sensitivity _sensitivity(String type, String field) {
  if ((type == 'contact' &&
          const {'name', 'phone', 'wechat', 'email'}.contains(field)) ||
      (type == 'quotation' &&
          const {'contact_snapshot', 'inquirer_name'}.contains(field)) ||
      (type == 'project' && field == 'leader')) {
    return Sensitivity.personal;
  }
  if ((type == 'project' &&
          const {
            'customer',
            'contract_no',
            'contract_amount',
            'markup_rate',
          }.contains(field)) ||
      (type == 'project_item' &&
          const {'unit_cost', 'unit_price'}.contains(field)) ||
      (type == 'quotation' &&
          const {
            'price',
            'extra_cost',
            'deal_price',
            'price_tiers',
          }.contains(field))) {
    return Sensitivity.commercial;
  }
  return Sensitivity.none;
}

final inquiryOntology = ModuleOntology(
  objectTypes: [
    for (final type in domain.ontology.values)
      ObjectTypeSpec(
        name: type.name,
        label: type.label,
        description: type.description,
        iconKey: 'receipt_long',
        titleField: type.fields.any((field) => field.name == 'name')
            ? 'name'
            : type.fields.first.name,
        inGlobalScope: true,
        versioned: true,
        page: const ObjectPageSupport.none(
          'Existing inquiry pages remain in the inquiry section',
        ),
        fields: [
          for (final field in type.fields)
            OntologyFieldSpec(
              name: field.name,
              label: field.label,
              description: field.description,
              kind: FieldKind.values.byName(field.kind.name),
              required: field.required,
              values: field.values,
              target: field.target,
              sensitivity: _sensitivity(type.name, field.name),
            ),
        ],
      ),
  ],
  relations: [
    for (final link in domain.links)
      RelationSpec(
        name: link.name,
        from: link.from,
        field: link.field,
        to: link.to,
        many: link.many,
        queryTool: 'inquiry.related',
      ),
  ],
  actions: [
    for (final action in domain.actions)
      ActionSpec(
        name: action.name,
        label: action.label,
        description: action.description,
        tool: action.name == 'create_inquiry' ? 'inquiry.create_inquiry' : null,
        humanOnlyReason: action.name == 'create_inquiry' ? null : 'Existing page action; additional tool exposure is outside REG-4a',
      ),
  ],
  rules: [for (final rule in domain.rules) RuleSpec(rule.name, rule.text)],
);
