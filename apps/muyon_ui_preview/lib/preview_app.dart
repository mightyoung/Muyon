import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'fixture_ports.dart';

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key, required this.fixture});
  final PreviewFixture fixture;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Muyon semantic preview',
    theme: muyonTheme(Brightness.light),
    home: _PreviewHome(initial: fixture),
  );
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome({required this.initial});
  final PreviewFixture initial;
  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  late PreviewFixture fixture;
  UiSurfaceController? controller;
  int memoryQuantity = 10;
  String? explanation;
  @override
  void initState() {
    super.initState();
    load(widget.initial);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void load(PreviewFixture next) {
    controller?.removeListener(changed);
    controller?.dispose();
    controller = null;
    fixture = next;
    memoryQuantity = 10;
    explanation = null;
    if (next.catalog == dynamicUiCatalog) {
      final validated = validateUiPlan(
        next.plan.plan!,
        next.snapshot,
        next.intent,
        dynamicUiCatalog,
      ).validatedPlan!;
      late UiSurfaceController attached;
      attached = UiSurfaceController(
        validated,
        onEvent: (event) async {
          final request = attached.pendingAction(event.eventId);
          if (request != null) {
            final quantity = int.tryParse('${request.inputs['quantity']}');
            if (quantity != null) memoryQuantity = quantity;
            attached.acceptReceipt(
              UiBusinessReceipt(
                eventId: event.eventId,
                operationKeyRef: request.binding.operationKeyRef!,
                draftRevision: request.binding.expectedDraftRevision!,
                status: quantity == null
                    ? UiReceiptStatus.failed
                    : UiReceiptStatus.succeeded,
                message: 'Public memory quantity: $memoryQuantity',
                isSimulated: true,
              ),
            );
          } else {
            explanation =
                'Simulated semantic explanation requested. No model called.';
            changed();
          }
        },
      );
      controller = attached;
      attached.addListener(changed);
    }
  }

  @override
  void dispose() {
    controller?.removeListener(changed);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Muyon · public fixture preview')),
    body: SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => load(comparisonFixture())),
                        child: const Text('Fixture A'),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => load(comparisonFixture(alternative: true)),
                        ),
                        child: const Text('Fixture B'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => load(runtimeFixture())),
                        child: const Text('UI-4a fixture'),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => load(comparisonFixture(invalid: true)),
                        ),
                        child: const Text('Invalid plan fallback'),
                      ),
                    ],
                  ),
                ),
                if (controller != null) ...[
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Simulated business port · public memory only · no database/model/network calls',
                    ),
                  ),
                  Text(
                    'Current surface revision: ${controller!.current.plan.revision}',
                  ),
                  if (explanation != null) Text(explanation!),
                  TextButton(
                    onPressed: () {
                      final current = controller!.current;
                      controller!.applyPatch(
                        UiPatch(
                          patchId: 'public-patch-${current.plan.revision + 1}',
                          surfaceId: current.plan.surfaceId,
                          baseRevision: current.plan.revision,
                          nextRevision: current.plan.revision + 1,
                          snapshotRevision: current.snapshot.ref,
                          ops: [
                            UiPatchOperation.replace(
                              current.plan.nodes.first.copyWith(
                                properties: {
                                  'title':
                                      'Public comparison · revision ${current.plan.revision + 1}',
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Apply complete patch'),
                  ),
                ],
                SemanticUiSurface(
                  snapshot: fixture.snapshot,
                  intent: fixture.intent,
                  result: fixture.plan,
                  originalAnswer: fixture.answer,
                  catalog: fixture.catalog,
                  controller: controller,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
