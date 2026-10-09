import 'package:muyon_module_api/muyon_module_api.dart';

import '../assistant/ui_planning.dart';

const uiPlanningToolId = 'assistant.plan_ui';
const uiPlanningToolDescription =
    'Plan existing host facts after answering. Host supplies full question, answer, conversation and catalogs. Pass actual snapshot/surface versions. Cannot execute business actions or grant permissions.';
const uiPlanningToolSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'snapshotId': {'type': 'string'},
    'expectedSnapshotRevision': {'type': 'integer'},
    'surfaceId': {'type': 'string'},
    'expectedSurfaceRevision': {'type': 'integer'},
  },
  'required': [
    'snapshotId',
    'expectedSnapshotRevision',
    'surfaceId',
    'expectedSurfaceRevision',
  ],
  'additionalProperties': false,
};
ToolDescriptor get uiPlanningToolDescriptor => ToolDescriptor(
  toolId: uiPlanningToolId,
  moduleId: 'muyon',
  effect: ToolEffect.read,
  description: uiPlanningToolDescription,
  parameterSchema: uiPlanningToolSchema,
);
Future<ToolCallResult> runUiPlanningTool(
  UiPlanningHarness harness,
  String taskId,
  ToolCallRequest request,
) async {
  final value = await harness.plan(taskId, expected: request.parameters);
  return ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: 'Presentation: ${value.result.reasonCode}',
    data: {
      'decision': value.result.decision.name,
      'reasonCode': value.result.reasonCode,
      'surfaceId': value.validated?.plan.surfaceId,
      'revision': value.validated?.plan.revision,
    },
  );
}
