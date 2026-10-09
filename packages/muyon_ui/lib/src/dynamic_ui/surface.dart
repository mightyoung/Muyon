import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'catalog.dart';
import '../dynamic/fallback.dart';
import '../dynamic/surface.dart';

/// Preview/host adapter: validated shared runtime plus complete original text.
class SemanticUiSurface extends StatelessWidget {
  const SemanticUiSurface({
    super.key,
    required this.snapshot,
    required this.intent,
    required this.result,
    required this.originalAnswer,
    this.catalog,
    this.onEvent,
    this.controller,
  });
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiPlanningResult result;
  final String originalAnswer;
  final UiCatalog? catalog;
  final UiEventSink? onEvent;
  final UiSurfaceController? controller;
  @override
  Widget build(BuildContext context) {
    final plan = result.plan;
    final checked = result.errors.isEmpty && plan != null
        ? validateUiPlan(plan, snapshot, intent, catalog ?? minimalUiCatalog)
        : null;
    final failed =
        result.errors.isNotEmpty || (plan != null && checked?.isValid != true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(originalAnswer),
        ),
        if (failed) ...[
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Interactive view unavailable. Original answer retained.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: snapshotFallback(snapshot, intent),
          ),
        ] else if (checked?.validatedPlan case final valid?)
          DynamicUiSurface(
            plan: valid,
            onEvent: onEvent,
            controller: controller,
          ),
      ],
    );
  }
}
