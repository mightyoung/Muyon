import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'fixture_ports.dart';

UiPlanningRequest publicPlanningRequest(
  UiPlanningMode mode, {
  int revision = 0,
}) {
  final f = runtimeFixture();
  return UiPlanningRequest(
    question:
        'Compare these invented public quotes and show the quantity draft.',
    answer: f.answer,
    conversationMessages: [
      {
        'role': 'user',
        'content':
            'Compare these invented public quotes and show the quantity draft.',
      },
      {'role': 'assistant', 'content': f.answer},
    ],
    conversationVersion: 'public-1',
    coverage: 'complete_public_fixture',
    taskId: 'public-ui4b',
    turnId: 'public-turn-1',
    snapshot: f.snapshot,
    intent: f.intent,
    currentView: UiCurrentView(
      surfaceId: f.plan.plan!.surfaceId,
      revision: revision,
      values: f.snapshot.initialUiState,
    ),
    catalog: f.catalog!,
    allowedActionRefs: f.intent.allowedActionRefs,
    mode: mode,
  );
}

final publicPlanningProvider = FixtureUiPlanningProvider(
  (request) async => UiPlanningResult(
    decision: UiDisplayDecision.supplement,
    reasonCode: 'public-fixture-only',
    plan: runtimeFixture().plan.plan!.copyWith(
      revision: request.currentView.revision + 1,
    ),
  ),
);

/// Both modes deliberately run an identical public fixture through the same
/// port/validator/renderer. This is not evidence of either real model's quality.
class PlanningPreview extends StatefulWidget {
  const PlanningPreview({super.key});
  @override
  State<PlanningPreview> createState() => _PlanningPreviewState();
}

class _PlanningPreviewState extends State<PlanningPreview> {
  UiPlanningMode mode = UiPlanningMode.intelligent;
  UiSurfaceController? controller;
  UiPlanningRequest? request;
  UiPlanningResult? result;
  int elapsedMicros = 0;
  String? explanation;
  String? error;
  @override
  void initState() {
    super.initState();
    plan();
  }

  Future<void> plan() async {
    final selected = mode;
    final r = publicPlanningRequest(selected);
    final watch = Stopwatch()..start();
    try {
      final output = await publicPlanningProvider.plan(r);
      watch.stop();
      final checked = validateUiPlan(
        output.plan!,
        r.snapshot,
        r.intent,
        r.catalog,
      );
      if (!checked.isValid) throw StateError('Fixture validation failed');
      if (!mounted || selected != mode) return;
      controller?.dispose();
      late UiSurfaceController attached;
      attached = UiSurfaceController(
        checked.validatedPlan!,
        onEvent: (event) async {
          final pending = attached.pendingAction(event.eventId);
          if (pending != null) {
            attached.acceptReceipt(
              UiBusinessReceipt(
                eventId: event.eventId,
                operationKeyRef: pending.binding.operationKeyRef!,
                draftRevision: pending.binding.expectedDraftRevision!,
                status: UiReceiptStatus.succeeded,
                message: 'Simulated public memory only; no host Store changed',
                isSimulated: true,
              ),
            );
          } else {
            setState(
              () => explanation =
                  'Simulated semantic explanation; no actual model called.',
            );
          }
        },
      );
      setState(() {
        controller = attached;
        request = r;
        result = output;
        elapsedMicros = watch.elapsedMicroseconds;
        error = null;
        explanation = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Fixture unavailable; original answer retained.',
        );
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('UI-4b public planning')),
    body: SingleChildScrollView(
      child: Column(
        children: [
          const Text(
            'Both modes use fixture Provider · local model not connected · real model effect untested',
          ),
          Wrap(
            children: [
              for (final value in UiPlanningMode.values)
                TextButton(
                  onPressed: () {
                    setState(() => mode = value);
                    plan();
                  },
                  child: Text(
                    value == UiPlanningMode.intelligent
                        ? 'Intelligent fixture'
                        : 'Motivation fixture',
                  ),
                ),
            ],
          ),
          Text('mode: ${mode.name} · fixture latency: $elapsedMicros µs'),
          const Text('No network · cost 0 · public fixture only'),
          if (explanation != null) Text(explanation!),
          if (error != null) Text(error!),
          if (request != null && result != null)
            SemanticUiSurface(
              snapshot: request!.snapshot,
              intent: request!.intent,
              catalog: request!.catalog,
              result: result!,
              originalAnswer: request!.answer,
              controller: controller,
            ),
        ],
      ),
    ),
  );
}
