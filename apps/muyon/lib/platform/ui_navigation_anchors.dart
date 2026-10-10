import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart' show NavigationAnchor;
import 'package:muyon_ui/dynamic_ui.dart';

import '../app/bootstrap.dart';
import '../app/module_host.dart';
import '../screens/artifact_preview.dart';
import 'object_pages.dart';
import 'ui_workspace_store.dart';

export 'package:muyon_module_api/ui_contract.dart' show NavigationAnchor;

extension StoredNavigationAnchor on HostUiWorkspaceStore {
  Future<NavigationAnchor?> loadNavigationAnchor(String surfaceId) async {
    final saved = await load(surfaceId);
    if (saved?.returnAnchor == null) return null;
    try {
      final anchor = NavigationAnchor.fromJson(
        jsonDecode(saved!.returnAnchor!) as Map<String, dynamic>,
      );
      final task = repository.task(taskId);
      return anchor.taskId == taskId &&
              anchor.surfaceId == surfaceId &&
              anchor.conversationId == task?.conversationId
          ? anchor
          : null;
    } on FormatException {
      return null; // An older anchor is retained, never reinterpreted as a route.
    } on TypeError {
      return null;
    }
  }
}

class UiReferenceNavigation {
  UiReferenceNavigation({
    required this.context,
    required this.host,
    required this.controller,
    this.canPresent,
  });
  final BuildContext context;
  final MuyonHost host;
  final UiWorkspaceController controller;
  /// App presentation admission only; identity/authority validation is unchanged.
  final bool Function()? canPresent;

  void _requireCurrentAnchor(NavigationAnchor anchor) {
    final current = controller.surface.current;
    if (anchor.taskId != controller.taskId ||
        anchor.surfaceId != current.plan.surfaceId ||
        anchor.conversationId !=
            host.foundation.task(controller.taskId)?.conversationId ||
        !current.plan.nodes.any((n) => n.id == anchor.nodeId) ||
        !anchor.scrollOffset.isFinite ||
        anchor.scrollOffset < 0 ||
        controller.readOnly ||
        HostUiWorkspaceStore(host.foundation, taskId: controller.taskId).scopeKey !=
            controller.scopeKey) {
      throw StateError('Return workspace unavailable');
    }
  }

  Future<void> _checkpoint(NavigationAnchor anchor) async {
    _requireCurrentAnchor(anchor);
    controller.returnAnchor = jsonEncode(anchor.toJson());
    controller.scrollOffset = anchor.scrollOffset;
    await controller.flush();
  }

  void _requireReference(ObjectRef ref, NavigationAnchor returnTo) {
    if (ref != returnTo.objectRef ||
        !controller.surface.current.snapshot.facts.values.any(
          (f) => f.object == ref,
        )) {
      throw StateError('Reference outside current snapshot');
    }
  }

  String? _sourceStamp(String moduleId) => host.scopeAuthority.stamp(
    const AssistantScope.global(), {moduleId},
  );

  void _requireAuthority(String moduleId, String permission, String source) {
    if (host.modules.scopeAuthorityRevision(moduleId) != permission ||
        _sourceStamp(moduleId) != source) {
      throw StateError('Object or source authority changed');
    }
  }

  Future<void> openReference(ObjectRef ref, NavigationAnchor returnTo) async {
    _requireReference(ref, returnTo);
    _requireCurrentAnchor(returnTo);
    final known = host.registry.modules.any((m) => m.manifest.id == ref.moduleId);
    if (known &&
        ((ref.revisionRef ?? '').isEmpty || (ref.contentDigest ?? '').isEmpty)) {
      throw StateError('Object version proof unavailable');
    }
    final initialState = host.modules.state(ref.moduleId);
    var permission = host.modules.scopeAuthorityRevision(ref.moduleId);
    var source = permission == null ? null : _sourceStamp(ref.moduleId);
    if (known && permission != null) {
      if (source == null) throw StateError('Object source authority unavailable');
      _requireAuthority(ref.moduleId, permission, source);
    } else if (known && initialState.status != ModuleStatus.inactive) {
      throw StateError('Object permission unavailable');
    }
    await _checkpoint(returnTo);
    if (!context.mounted || !(canPresent?.call() ?? true)) return;
    _requireCurrentAnchor(returnTo);
    _requireReference(ref, returnTo);
    if (known) {
      if (permission == null) {
        // An inactive module may be prepared only after the draft saved. A
        // revocation changes its state before durable work, so it cannot be
        // silently retried as part of this navigation.
        if (!identical(initialState, host.modules.state(ref.moduleId))) {
          throw StateError('Object permission changed during checkpoint');
        }
        await host.modules.runtimeFor(ref.moduleId);
        if (!context.mounted || !(canPresent?.call() ?? true)) return;
        _requireCurrentAnchor(returnTo);
        _requireReference(ref, returnTo);
        permission = host.modules.scopeAuthorityRevision(ref.moduleId);
        source = _sourceStamp(ref.moduleId);
        if (permission == null || source == null) {
          throw StateError('Object source authority unavailable');
        }
      }
      _requireAuthority(ref.moduleId, permission, source!);
    }
    ModuleObjectPage? opened;
    try {
      // Removed modules get only the host's saved-reference text. No runtime,
      // session, object page or file is consulted for this fallback.
      if (known) {
        opened = await openModuleObjectPage(context, host, ref);
        if (opened == null) throw StateError('Object no longer resolves');
      }
      if (!context.mounted || !(canPresent?.call() ?? true)) return;
      _requireCurrentAnchor(returnTo);
      _requireReference(ref, returnTo);
      if (known) _requireAuthority(ref.moduleId, permission!, source!);
      final page = opened;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(page?.title ?? '已保存引用')),
            body:
                page?.page ??
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('对象或插件当前不可用；原对话与草稿仍保留，可以返回继续。'),
                ),
          ),
        ),
      );
    } finally {
      await opened?.dispose();
    }
  }

  void _requireArtifact(ArtifactRef ref, NavigationAnchor returnTo) {
    final supplied = returnTo.artifactRef;
    if (supplied == null ||
        supplied.moduleId != ref.moduleId ||
        supplied.artifactId != ref.artifactId ||
        supplied.contentDigest != ref.contentDigest ||
        !controller.surface.current.snapshot.sources.values.any(
          (s) =>
              s.artifact.moduleId == ref.moduleId &&
              s.artifact.artifactId == ref.artifactId &&
              s.artifact.contentDigest == ref.contentDigest,
        )) {
      throw StateError('Source outside current snapshot');
    }
  }

  Future<void> openArtifact(ArtifactRef ref, NavigationAnchor returnTo) async {
    _requireArtifact(ref, returnTo);
    await _checkpoint(returnTo);
    if (!context.mounted || !(canPresent?.call() ?? true)) return;
    _requireCurrentAnchor(returnTo);
    _requireArtifact(ref, returnTo);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ArtifactPreview(host: host, reference: ref, anchor: returnTo),
      ),
    );
  }
}
