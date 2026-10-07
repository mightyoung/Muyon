import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';
import 'package:supplier_core/supplier_core.dart';

import '../platform/prototype_tools.dart';
import '../platform/scope_resolver.dart';
import '../workspace/import_coordinator.dart';
import 'app_shell.dart';
import 'bootstrap.dart';
import 'module_host.dart';

// LegacyModuleBridge (ADR-0004 §4.6): what the host still knows by name about
// the three modules that are not on contract v2 yet. REG-3 (research,
// prototype) and REG-4 (inquiry) migrate them and delete their entries here.

/// What the shell hands to a section builder. A v1 module's section is the
/// page the shell used to open itself, so it needs the shell's theme plumbing.
class ShellSectionHost implements ModuleSectionHost {
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

/// The prototype home, opened after the module is activated. A failure is
/// shown on the page rather than as a message on the home screen.
class _PrototypeSectionPage extends StatefulWidget {
  const _PrototypeSectionPage(this.host);
  final MuyonHost host;
  @override
  State<_PrototypeSectionPage> createState() => _PrototypeSectionPageState();
}

class _PrototypeSectionPageState extends State<_PrototypeSectionPage> {
  late final Future<void> opening = widget.host.activatePrototype();
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: opening,
    builder: (context, snapshot) {
      final runtime = widget.host.prototype;
      if (runtime != null) return PrototypeHome(store: runtime.store);
      final done = snapshot.connectionState == ConnectionState.done;
      return Scaffold(
        appBar: AppBar(title: const Text('原型页面')),
        body: Center(
          child: done
              ? SelectableText(
                  '原型模块不可用：${widget.host.prototypeError ?? '未知原因'}',
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

/// The three modules, in the order the host always listed them. Texts are the
/// ones the home page and the module menu showed before they were declared.
List<LegacyModuleBridge> legacyBridges(MuyonHost host) => [
  LegacyModuleBridge(
    id: 'inquiry',
    declaration: ModuleDeclaration(
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
    ),
    externalActivate: () async {
      await host.activateInquiry();
      return host.inquiryError;
    },
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
    grants: const {'knowledge', 'models', 'tools'},
    afterActivate: (runtime) async {
      final recovery = await ImportCoordinator(host.workspaces)
          .recover('research', runtime);
      if (recovery.conflicts.isNotEmpty) {
        await host.foundation.notify(
          title: '导入未能完成绑定',
          body: recovery.conflicts.values.join('\n'),
        );
      }
      await host.acceptedResearchImports.reconcileCommitted(
        runtime as ResearchRuntime,
      );
    },
    scopeSource: _ResearchScope(host),
  ),
  LegacyModuleBridge(
    id: prototypeModuleId,
    declaration: ModuleDeclaration(
      moduleId: prototypeModuleId,
      displayName: '原型页面',
      tagline: '导入单页原型，评审版本并记录反馈（不是完整业务系统）',
      iconKey: 'web',
      sections: [
        ModuleSection(
          id: prototypeModuleId,
          label: '原型页面',
          showInModuleMenu: false,
          builder: (context, section) =>
              _PrototypeSectionPage((section as ShellSectionHost).host),
        ),
      ],
    ),
    scopeSource: _PrototypeScope(host),
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
  Future<void> prepare() => host.activateInquiry();
  @override
  Future<List<ObjectRef>> enumerate() async {
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

/// Research projects, documents (hashed from disk) and entries.
class _ResearchScope extends _LegacyScope {
  _ResearchScope(super.host);
  @override
  String get moduleId => 'research';
  @override
  Future<void> prepare() => host.activateResearch();
  @override
  Future<List<ObjectRef>> enumerate() async {
    final research = host.research?.store;
    if (research == null) return const [];
    final refs = <ObjectRef>[];
    for (final project in research.projects()) {
      refs.add(
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
        refs.add(
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
        refs.add(
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
    return refs;
  }
}

class _PrototypeScope extends _LegacyScope {
  _PrototypeScope(super.host);
  @override
  String get moduleId => prototypeModuleId;
  @override
  Future<void> prepare() => host.activatePrototype();
  @override
  Future<List<ObjectRef>> enumerate() async {
    final prototype = host.prototype?.store;
    return prototype == null ? const [] : prototypeScopeRefs(prototype);
  }
}
