import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'fixture_ports.dart';

class WorkspacePreview extends StatefulWidget {
  const WorkspacePreview({super.key, required this.store});
  final UiWorkspaceStore store;
  @override
  State<WorkspacePreview> createState() => _WorkspacePreviewState();
}

class _WorkspacePreviewState extends State<WorkspacePreview> {
  UiWorkspaceController? controller;
  String? error;
  bool navigating = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final f = runtimeFixture();
      final checked = validateUiPlan(
        f.plan.plan!,
        f.snapshot,
        f.intent,
        f.catalog!,
      ).validatedPlan!;
      final c = await UiWorkspaceController.open(
        store: widget.store,
        taskId: 'public-ui3b',
        scopeKey: 'public-only',
        plan: checked,
      );
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => controller = c);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> save() async {
    try {
      await controller!.flush();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> openPublicReference({required bool source}) async {
    final c = controller;
    if (c == null || navigating || c.readOnly) return;
    setState(() => navigating = true);
    try {
      final current = c.surface.current;
      final excerpt = source ? current.snapshot.sources.values.first : null;
      final ref = source
          ? ObjectRef(
              moduleId: excerpt!.artifact.moduleId,
              objectType: 'document',
              objectId: excerpt.artifact.artifactId,
              contentDigest: excerpt.artifact.contentDigest,
            )
          : current.snapshot.facts.values.first.object;
      final node = current.plan.nodes.firstWhere(
        (n) => n.bindings.values.any(
          (b) => b.kind == (source ? BindingKind.sourceSpan : BindingKind.fact),
        ),
      );
      final anchor = NavigationAnchor(
        conversationId: 'public-ui2a-conversation',
        taskId: c.taskId,
        surfaceId: current.plan.surfaceId,
        nodeId: node.id,
        scrollOffset: c.scrollOffset,
        objectRef: ref,
        sourceDigest: excerpt?.artifact.contentDigest ?? ref.contentDigest,
        artifactRef: excerpt?.artifact,
      );
      c.returnAnchor = jsonEncode(anchor.toJson());
      await c.flush();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(source ? 'Public source' : 'Public object'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulated navigation · public fixture · no product files or module calls',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    source
                        ? excerpt!.originalText
                        : '${ref.moduleId} / ${ref.objectType} / ${ref.objectId}',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => navigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      return Scaffold(
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text('Saved draft retained; load failed: $error'),
        ),
      );
    }
    return Column(
      children: [
        Material(
          child: SafeArea(
            bottom: false,
            child: Wrap(
              children: [
                TextButton(
                  onPressed: save,
                  child: const Text('Save checkpoint'),
                ),
                TextButton(
                  onPressed: () async {
                    final p = c.surface.current;
                    c.surface.applyPatch(
                      UiPatch(
                        patchId: 'public-${p.plan.revision + 1}',
                        surfaceId: p.plan.surfaceId,
                        baseRevision: p.plan.revision,
                        nextRevision: p.plan.revision + 1,
                        snapshotRevision: p.snapshot.ref,
                        ops: [
                          UiPatchOperation.replace(
                            p.plan.nodes.first.copyWith(
                              properties: {
                                'title':
                                    'Public persistent revision ${p.plan.revision + 1}',
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                    await save();
                  },
                  child: const Text('Patch workspace'),
                ),
                if (error != null) Text('Save failed: $error'),
              ],
            ),
          ),
        ),
        Expanded(
          child: UiWorkspaceView(
            controller: c,
            originalAnswer: runtimeFixture().answer,
            references: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: navigating || c.readOnly
                      ? null
                      : () => openPublicReference(source: false),
                  child: const Text('Open public object'),
                ),
                TextButton(
                  onPressed: navigating || c.readOnly
                      ? null
                      : () => openPublicReference(source: true),
                  child: const Text('Open public source'),
                ),
              ],
            ),
            banner: 'Public fixture storage · browser projection only · no product SQLite/model/network calls',
          ),
        ),
      ],
    );
  }
}
