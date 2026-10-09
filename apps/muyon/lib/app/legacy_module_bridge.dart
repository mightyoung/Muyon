import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:supplier_core/supplier_core.dart';

import '../platform/scope_resolver.dart';
import 'app_shell.dart';
import 'bootstrap.dart';
import 'module_host.dart';

// LegacyModuleBridge (ADR-0004 §4.6): what the host still knows by name about
// the three modules that are not on contract v2 yet. REG-3 (research,
// prototype) and REG-4 (inquiry) migrate them and delete their entries here.

/// What the shell hands to a section builder. A v1 module's section is the
/// page the shell used to open itself, so it needs the shell's theme plumbing.
class ShellSectionHost implements WorkspaceSectionHost {
  const ShellSectionHost({
    required this.moduleId,
    required this.host,
    required this.themeMode,
    required this.onTheme,
  });
  @override
  final String moduleId;
  final MuyonHost host;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;

  @override
  T? runtime<T extends ModuleRuntime>() => host.modules.runtime<T>(moduleId);
  @override
  Widget workspacePage(BuildContext context) => WorkspacePage(
    host: host, themeMode: themeMode, onTheme: onTheme, initialModule: moduleId,
  );

}

Widget _workspacePage(ModuleSectionHost section, String module) {
  final shell = section as ShellSectionHost;
  return WorkspacePage(
    host: shell.host,
    themeMode: shell.themeMode,
    onTheme: shell.onTheme,
    initialModule: module,
  );
}

/// Unchanged inquiry navigation declaration shared with the V2 adapter.
ModuleDeclaration inquiryDeclaration() => ModuleDeclaration(
  moduleId: 'inquiry',
  displayName: 'Folio · 询价台账',
  tagline: '完整供应商、询价报价和成本业务',
  iconKey: 'receipt_long',
  sections: [
    ModuleSection(
      id: 'inquiry',
      label: 'Folio · 询价与成本',
      builder: (context, section) => _workspacePage(section, 'inquiry'),
    ),
  ],
);

/// The three modules, in the order the host always listed them. Texts are the
/// ones the home page and the module menu showed before they were declared.
List<LegacyModuleBridge> legacyBridges(MuyonHost host) => [
  LegacyModuleBridge(
    id: 'inquiry',
    declaration: inquiryDeclaration(),
    scopeSource: _InquiryScope(host),
  ),
  LegacyModuleBridge(
    id: 'research',
    declaration: ModuleDeclaration(
      moduleId: 'research',
      displayName: '科研工作台',
      tagline: '原文阅读、批注、研究过程和成果',
      iconKey: 'menu_book',
      sections: [
        ModuleSection(
          id: 'research',
          label: '科研工作台',
          requiresWorkspace: true,
          builder: (context, section) => _workspacePage(section, 'research'),
        ),
      ],
    ),
    afterActivate: (runtime) async {
      await host.acceptedResearchImports.reconcileCommitted(
        runtime as ResearchRuntime,
      );
    },
  ),

];

abstract class _LegacyScope implements ScopeSource {
  _LegacyScope(this.host);
  final MuyonHost host;
  @override
  bool get resolvesDirectly => false;
  @override
  Future<ObjectRef?> resolve(ObjectRef requested) =>
      throw StateError('Legacy scope sources are looked up by enumeration');
}

/// Inquiry rows, read straight from its tables (moved from the old
/// `resolveAssistantScope`, unchanged).
class _InquiryScope extends _LegacyScope {
  _InquiryScope(super.host);
  @override
  String get moduleId => 'inquiry';
  @override
  Future<void> prepare() async {
    await host.modules.activate('inquiry');
  }

  @override
  Future<List<ObjectRef>> enumerate() async {
    if (host.modules.state('inquiry').status != ModuleStatus.ready ||
        host.modules.runtime<ModuleRuntime>('inquiry') == null) {
      return const [];
    }
    final inquiry = host.inquiry?.runtime.state.store;
    if (inquiry == null) return const [];
    final refs = <ObjectRef>[];
    for (final type in entityTypes) {
      for (final row in inquiry.db.select(
        'SELECT * FROM $type WHERE deleted=0',
      )) {
        final data = jsonDecode(row['data'] as String) as Map;
        refs.add(
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
    return refs;
  }
}
