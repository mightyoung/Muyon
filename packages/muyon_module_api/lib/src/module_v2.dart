import 'package:flutter/widgets.dart';

import 'coverage.dart';
import 'module.dart';
import 'ontology.dart';
import 'optional_capabilities.dart';
import 'storage.dart';
import 'tool_registrar.dart';

/// Module API v2 (ADR-0004 §4.2). Additive: it extends [BusinessModule] and
/// leaves every v1 member untouched.
abstract interface class BusinessModuleV2 implements BusinessModule {
  /// `apiVersion == 2`.
  @override
  ModuleManifest get manifest;

  /// Objects, relations, actions; [ModuleOntology.empty] for none.
  ModuleOntology get ontology;

  /// Navigation sections. v2 modules return `const []` from `routes`.
  List<ModuleSection> get sections;

  /// Extra physical databases (inquiry: jobs, hub). Default `const []`.
  List<AuxiliarySchema> get auxiliarySchemas;

  /// Declares tools. The host calls this at start-up, before activation.
  void registerTools(ToolRegistrar registrar);
  List<SearchSource> get searchSources;
  CapabilityCoverage get coverage;
}

/// Platform capability a module asks for in its manifest.
class CapabilityRequest {
  const CapabilityRequest({
    required this.id,
    this.required = false,
    required this.reason,
  });
  final String id;
  final bool required;
  final String reason;
}

/// Optional interfaces a module declares it implements; the host cross-checks.
enum ModuleFeature {
  importPipeline,
  exchange,
  objectPages,
  publishChecks,
  resultRenderers,
}

/// Where a module's external tools may go. Only ever narrows.
class NetworkPolicy {
  const NetworkPolicy({this.fixedHosts = const {}, this.publicWeb = false});
  final Set<String> fixedHosts;

  /// Any public https destination (the existing SSRF checks still apply).
  final bool publicWeb;
  static const none = NetworkPolicy();
}

/// Host side of a [ModuleSection]: what a section builder may ask for.
abstract interface class ModuleSectionHost {
  String get moduleId;

  /// The activated runtime, or null when the module is not ready.
  T? runtime<T extends ModuleRuntime>();
}

/// A navigation section declared by a module.
class ModuleSection {
  const ModuleSection({
    required this.id,
    required this.label,
    this.tagline,
    this.iconKey,
    this.group,
    this.order = 0,
    this.requiresWorkspace = false,
    this.showInModuleMenu = true,
    required this.builder,
  });
  final String id, label;
  final String? tagline, iconKey, group;
  final int order;
  final bool requiresWorkspace;

  /// Listed in the workspace page's module menu. (Not in ADR-0004: needed to
  /// keep today's menu, which omits the prototype module, unchanged.)
  final bool showInModuleMenu;
  final Widget Function(BuildContext context, ModuleSectionHost host) builder;
}

class AuxiliarySchema {
  AuxiliarySchema(this.id, this.schema) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw ArgumentError('Invalid database id: $id');
    }
  }
  final String id;
  final ModuleSchema schema;
}

/// Optional shell navigation for a section that opens a bound workspace.
/// The host owns workspace selection and binding; modules own declarations.
abstract interface class WorkspaceSectionHost implements ModuleSectionHost {
  Widget workspacePage(BuildContext context);
}
