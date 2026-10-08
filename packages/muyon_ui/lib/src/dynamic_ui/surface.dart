import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../navigation_layout.dart';
import '../primitives.dart';
import 'catalog.dart';

/// One renderer for preview and later host integration. It accepts only the
/// implemented catalog, validates before rendering, and preserves full text.
class SemanticUiSurface extends StatefulWidget {
  const SemanticUiSurface({
    super.key,
    required this.snapshot,
    required this.intent,
    required this.result,
    required this.originalAnswer,
  });
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiPlanningResult result;
  final String originalAnswer;
  @override
  State<SemanticUiSurface> createState() => _SemanticUiSurfaceState();
}

class _SemanticUiSurfaceState extends State<SemanticUiSurface> {
  late UiSessionState session;
  final controllers = <String, TextEditingController>{};
  ValidatedUiPlan? validated;
  int eventCounter = 0;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    session = UiSessionState(widget.snapshot);
    load();
  }

  void load() {
    validated = null;
    failed = widget.result.errors.isNotEmpty;
    final plan = widget.result.plan;
    if (failed || plan == null) return;
    final checked = validateUiPlan(
      plan,
      widget.snapshot,
      widget.intent,
      minimalUiCatalog,
    );
    failed = !checked.isValid;
    if (!failed) {
      final next = checked.validatedPlan!;
      // Rebuilding an unchanged input does not represent a new whole plan.
      if (identical(session.currentPlan?.plan, plan)) {
        validated = session.currentPlan;
      } else if (session.accept(next)) {
        validated = next;
      } else {
        failed = true;
      }
    }
  }

  @override
  void didUpdateWidget(covariant SemanticUiSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.snapshot, oldWidget.snapshot)) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      controllers.clear();
      session = UiSessionState(widget.snapshot);
    }
    load();
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void dispatch(UiNode node, String kind, [Object? payload]) {
    final plan = validated;
    if (plan == null) return;
    final outcome = session.dispatch(
      UiEvent(
        eventId: 'local-${++eventCounter}',
        surfaceId: plan.plan.surfaceId,
        nodeId: node.id,
        observedRevision: plan.plan.revision,
        kind: kind,
        payload: payload,
      ),
      plan,
      minimalUiCatalog,
    );
    if (outcome == UiEventOutcome.applied) setState(() {});
  }

  Widget renderNode(UiNode node, Map<String, UiNode> nodes) {
    Object? value(String slot) => session.resolve(node.bindings[slot]!);
    switch (node.component) {
      case 'PageScaffold':
        return PageScaffold(
          title: node.properties['title']! as String,
          description: 'Public fictitious data · in-session edits only',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final id in node.children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: renderNode(nodes[id]!, nodes),
                ),
            ],
          ),
        );
      case 'Field':
        final draft = node.bindings['draft']!;
        final controller = controllers.putIfAbsent(
          draft.id,
          () => TextEditingController(
            text: session.resolve(draft)?.toString() ?? '',
          ),
        );
        final fact = widget.snapshot.facts[node.bindings['value']!.id]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${node.properties['label']}: ${value('value')}'),
            Text(
              'Fact state: ${fact.state.name}${fact.unit == null ? '' : ' · ${fact.unit}'}',
            ),
            TextFormField(
              key: ValueKey('${node.id}-field'),
              controller: controller,
              decoration: const InputDecoration(labelText: 'Draft quantity'),
              keyboardType: TextInputType.number,
              readOnly: !node.events.containsKey('change'),
              onChanged: node.events.containsKey('change')
                  ? (text) => dispatch(node, 'change', text)
                  : null,
            ),
          ],
        );
      case 'Table':
        return Table(
          columnWidths: const {0: FlexColumnWidth()},
          children: [
            TableRow(
              children: [
                Text('${node.properties['label']}: ${value('value')}'),
              ],
            ),
          ],
        );
      case 'SourceList':
        final expanded = session.isExpanded(node.id);
        final original = value('source');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton(
              key: ValueKey('${node.id}-expand'),
              onPressed: node.events.containsKey('tap')
                  ? () => dispatch(node, 'tap')
                  : null,
              child: Text(
                expanded ? 'Hide original source' : 'Show original source',
              ),
            ),
            if (expanded)
              SelectableText(
                original?.toString() ??
                    'Source changed. Original span is stale.',
              ),
          ],
        );
      case 'ObjectChip':
        final fact = widget.snapshot.facts[node.bindings['value']!.id]!;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ObjectChip(
              key: ValueKey('${node.id}-detail'),
              label: node.properties['label']! as String,
              onPressed: node.events.containsKey('tap')
                  ? () => dispatch(node, 'tap')
                  : null,
            ),
            StatusBadge(
              status: fact.state == FactState.conflict
                  ? BusinessStatus.warning
                  : BusinessStatus.neutral,
            ),
            Text(fact.state.name),
          ],
        );
      default:
        throw StateError('Unimplemented validated component ${node.component}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = validated?.plan;
    final nodes = {for (final node in plan?.nodes ?? <UiNode>[]) node.id: node};
    final detail = nodes[session.detailNode];
    final detailValue = detail?.bindings['value'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(widget.originalAnswer),
        ),
        if (failed)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Interactive view unavailable. Original answer retained.',
            ),
          ),
        if (plan != null && detail == null)
          renderNode(nodes[plan.root]!, nodes),
        if (plan != null && detail != null)
          PageScaffold(
            title: '${detail.properties['label']} detail',
            actions: [
              TextButton(
                key: const ValueKey('detail-back'),
                onPressed: detail.events.containsKey('back')
                    ? () => dispatch(detail, 'back')
                    : null,
                child: const Text('Back to comparison'),
              ),
            ],
            child: Text(
              detailValue == null
                  ? 'Detail value unavailable.'
                  : 'Snapshot value: ${session.resolve(detailValue)}',
            ),
          ),
      ],
    );
  }
}
