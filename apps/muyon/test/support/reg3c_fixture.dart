import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

// Shared, assertion-free bodies from the OC15/16/17/19/20 and REG3c tests.
// Keep their fixed P/Q/E IDs, write order, and session disposal unchanged.

Future<ObjectRef> currentResearchRef(
  MuyonHost host,
  String type,
  String id,
  String project,
) async {
  final session = await host.research!.openScopeSession();
  try {
    return (await session.resolve(
      ObjectRef(
        moduleId: 'research',
        objectType: type,
        objectId: id,
        nativeProjectId: project,
      ),
    ))!.ref;
  } finally {
    await session.dispose();
  }
}

Future<void> seedPqeResearch(MuyonHost host) async {
  await host.activateResearch();
  final store = host.research!.store;
  await store.write(() {
    store.db.execute(
      'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
      ['P', '研究', '问题', '下一步'],
    );
    store.db.execute(
      'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
      ['Q', '另一项目', '', ''],
    );
    store.db.execute(
      'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
      ['E', 'P', 'claim', '证据', '{}'],
    );
  });
}

Future<ToolCallResult> invokeApprovedResearchCall(
  MuyonHost host,
  ToolCallRequest call,
) async {
  final approval = await host.tools.approve(await host.tools.prepare(call));
  return host.tools.invoke(call.withApproval(approval));
}

Future<List<OutlineSection>> seedPSections(
  MuyonHost host,
  List<String> titles,
) async {
  final store = host.research!.store;
  final created = <OutlineSection>[];
  await store.write(() {
    for (final title in titles) {
      created.add(store.addSection('P', title));
    }
  });
  return created;
}

// Same E2 insertion and two citations, using the caller's captured store.
Future<void> seedPEvidenceLinks(
  WorkbenchStore store,
  List<OutlineSection> created,
) => store.write(() {
  store.db.execute(
    'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
    ['E2', 'P', 'claim', '证据2', '{}'],
  );
  store.scoped('P').cite(created.first.id, 'E');
  store.scoped('P').cite(created.first.id, 'E2');
});
