import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/fake_v2_module.dart';

class _Candidates extends ResolvableRuntime implements ScopeCandidates {
  _Candidates(super.objects, this.candidates, {super.lie});
  final List<ObjectRef> candidates;
  @override
  Future<List<ObjectRef>> scopeCandidates() async => candidates;
}

void main() {
  for (final lie in [false,true]) {
    test('module candidates keep global type and identity boundary (lie=$lie)', () async {
      const valid = ObjectRef(moduleId:'candidate',objectType:'item',objectId:'A');
      const private = ObjectRef(moduleId:'candidate',objectType:'private',objectId:'B');
      const foreign = ObjectRef(moduleId:'foreign',objectType:'item',objectId:'C');
      final runtime = _Candidates({'item/A':valid,'private/B':private,'item/C':foreign},
        [private,foreign,valid],lie:lie);
      final module = FakeV2Module('candidate',runtimeFactory:(_) => runtime,
        ontology:ModuleOntology(objectTypes:[
          for (final type in ['item','private']) ObjectTypeSpec(name:type,label:type,
            description:'candidate test',iconKey:'description',titleField:'title',fields:[],
            inGlobalScope:type=='item'),
        ]));
      final root=Directory.systemTemp.createTempSync('reg3a-candidates-');
      final host=await MuyonHost.open(root.path,modules:[module]);
      try {
        final scope=await host.scopeResolver.resolve(const AssistantScope.global());
        expect(scope.objects,lie ? isEmpty : orderedEquals([valid]));
        expect(runtime.sessionsOpened,runtime.sessionsDisposed);
      } finally {await host.close();root.deleteSync(recursive:true);}
    });
  }
}
