import 'package:flutter_test/flutter_test.dart';
import 'package:muspace_module_api/muspace_module_api.dart';

void main() {
  const ref=ObjectRef(moduleId:'research',objectType:'document',objectId:'one',nativeProjectId:'p');
  const versioned=ObjectRef(moduleId:'research',objectType:'document',objectId:'one',nativeProjectId:'p',revisionRef:'r1',contentDigest:'digest');
  test('global scope contains no invented workspace or native project',() {
    const global=AssistantScope.global();
    expect(global.workspaceId,isNull);
    expect(global.objects,isEmpty);
    expect(AssistantScope.fromJson(global.toJson()).kind,AssistantScopeKind.global);
    final resolved=ResolvedAssistantScope(requested:global,objects:[versioned]);
    expect(resolved.moduleIds,{'research'});
  });
  test('selection copied and host may fill omitted revision/digest only',() {
    final selected=[ref];
    final scope=AssistantScope.selectedObjects(selected,workspaceId:'w');
    selected.clear();
    final resolved=ResolvedAssistantScope(requested:scope,objects:[versioned]);
    expect(resolved.objects.single.contentDigest,'digest');
    expect(()=>resolved.objects.clear(),throwsUnsupportedError);
    expect(()=>ResolvedAssistantScope(requested:AssistantScope.selectedObjects([versioned]),objects:[ref]),throwsArgumentError);
    expect(()=>ResolvedAssistantScope(requested:scope,objects:[versioned,
      const ObjectRef(moduleId:'inquiry',objectType:'supplier',objectId:'other')]),throwsArgumentError);
    expect(()=>AssistantScope.selectedObjects([ref,versioned]),throwsArgumentError);
  });
  test('tool request recursively freezes inputs and result references',() {
    final nested=<String,Object?>{'items':<Object?>['initial']};
    final request=ToolCallRequest(invocationId:'call',toolId:'tool',scope:const AssistantScope.global(),parameters:nested);
    (nested['items'] as List).add('changed');
    expect(request.parameters['items'],['initial']);
    expect(()=> (request.parameters['items'] as List).clear(),throwsUnsupportedError);
    final result=ToolCallResult(status:ToolCallStatus.succeeded,summary:'result',objectRefs:[versioned]);
    expect(ToolCallResult.fromJson(result.toJson()).objectRefs.single,versioned);
  });
}
