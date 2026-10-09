import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart' show NavigationAnchor;
import 'package:muyon_ui/dynamic_ui.dart';

import '../app/bootstrap.dart';
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
  bool get _mayPresent => context.mounted && (canPresent?.call() ?? true);

  Future<void> _checkpoint(NavigationAnchor anchor) async {
    final current = controller.surface.current;
    if (anchor.taskId != controller.taskId ||
        anchor.surfaceId != current.plan.surfaceId ||
        anchor.conversationId !=
            host.foundation.task(controller.taskId)?.conversationId ||
        !current.plan.nodes.any((n) => n.id == anchor.nodeId) ||
        !anchor.scrollOffset.isFinite ||
        anchor.scrollOffset < 0 ||
        controller.readOnly) {
      throw StateError('Return workspace unavailable');
    }
    controller.returnAnchor = jsonEncode(anchor.toJson());
    controller.scrollOffset = anchor.scrollOffset;
    await controller.flush();
  }

  Future<void> openReference(ObjectRef ref, NavigationAnchor returnTo) async {
    if (ref != returnTo.objectRef ||
        !controller.surface.current.snapshot.facts.values.any(
          (f) => f.object == ref,
        )) {
      throw StateError('Reference outside current snapshot');
    }
    await _checkpoint(returnTo);
    if (!_mayPresent) return;
    ModuleObjectPage? opened;
    try {
      opened = await openModuleObjectPage(context, host, ref);
      if (!_mayPresent) return;
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

  Future<void> openArtifact(ArtifactRef ref, NavigationAnchor returnTo) async {
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
    await _checkpoint(returnTo);
    if (!_mayPresent) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ArtifactPreview(host: host, reference: ref, anchor: returnTo),
      ),
    );
  }
}
