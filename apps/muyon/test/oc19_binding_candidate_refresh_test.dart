import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

// OC-19: characterizes confirm_binding when a real refresh import adds a new
// ambiguous candidate for the same document: only the selected target's own
// digest must stay stable; the candidate set growing does not invalidate the
// approval, and confirming P drops the competing Q and R. If the refresh
// changes P's own binding fields instead, the old digest refuses with no write.
void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  const notes = '# 获取的笔记\n\n候选绑定特征测试。\n';

  setUp(() async {
    root = Directory.systemTemp.createTempSync('oc19-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
    await host.activateResearch();
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id, String project) async {
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

  ToolCallRequest request(
    String tool,
    Map<String, Object?> params,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'oc19-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  String jsonl(List<Map<String, Object?>> rows) => rows
      .map((row) => '${jsonEncode({'schema_version': 2, ...row})}\n')
      .join();

  Map<String, Object?> paper(String id, int rev) => {
    'id': id,
    'rev': rev,
    'source_id': 's1',
    'source_rev': 1,
    'title': '候选 $id',
    'reading_depth': 'metadata',
    'review_status': 'needs_review',
  };

  Map<String, Object?> source() => {
    'id': 's1',
    'rev': 1,
    'url': 'https://example.invalid/1',
    'status': 'active',
    'material_binding': {
      'path': 'related_work/acquired/h/snap/notes.md',
      'sha256': sha256.convert(utf8.encode(notes)).toString(),
    },
  };

  void writeSource(Directory dir, List<Map<String, Object?>> papers) {
    void write(String relative, String text) {
      File(p.join(dir.path, relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    write('research/sources.jsonl', jsonl([source()]));
    write('research/papers.jsonl', jsonl(papers));
    write('research/claims.jsonl', '');
    write('research/opportunities.jsonl', '');
    write('related_work/acquired/h/snap/notes.md', notes);
  }

  List<PaperBinding> bindings(String project) =>
      [...host.research!.store.bindings(project)]
        ..sort((a, b) => a.paperId.compareTo(b.paperId));

  List<List<Object?>> bindingRows(String project) => [
    for (final b in bindings(project))
      [b.documentId, b.paperId, b.paperRev, b.method, b.hashOk, b.ambiguous],
  ];

  Future<Map<String, Object?>> bindingRow(
    String project,
    String doc,
    String paperId,
  ) async {
    final listed = await host.tools.invoke(
      request(
        'research.list_bindings',
        {'project_id': project},
        [await current('project', project, project)],
      ),
    );
    expect(listed.status, ToolCallStatus.succeeded, reason: listed.summary);
    return Map<String, Object?>.from(
      (listed.data['bindings'] as List).cast<Map>().firstWhere(
        (b) => b['documentId'] == doc && b['paperId'] == paperId,
      ),
    );
  }

  // Imports the skill package into a fresh project and returns what the two
  // tests need: the project, the single document and the source directory.
  Future<({String projectId, String documentId, Directory source})>
  importFixture(List<Map<String, Object?>> papers) async {
    final source = Directory(p.join(root.path, 'source'))..createSync();
    writeSource(source, papers);
    final project = await ResearchExchange(host.research!.store)
        .importResearch(source.path);
    return (
      projectId: project.id,
      documentId: host.research!.store.documents(project.id).single.id,
      source: source,
    );
  }

  test('confirm_binding still confirms target after refresh import adds a competing candidate', () async {
    final fixture = await importFixture([paper('P', 1), paper('Q', 1)]);
    final projectId = fixture.projectId;
    final documentId = fixture.documentId;
    expect(bindings(projectId).map((b) => (b.paperId, b.ambiguous)), [
      ('P', true),
      ('Q', true),
    ]);
    final approved = await bindingRow(projectId, documentId, 'P');
    final documentRef = await current('document', documentId, projectId);
    final call = request(
      'research.confirm_binding',
      {
        'document_id': documentId,
        'paper_id': 'P',
        'expected_digest': approved['digest'],
      },
      [documentRef],
    );
    final approval = await host.tools.approve(await host.tools.prepare(call));

    // Real refresh import (same source directory, one new paper record):
    // the document bytes stay the same, so D is rewritten identically.
    writeSource(fixture.source, [paper('P', 1), paper('Q', 1), paper('R', 1)]);
    final refreshed = await ResearchExchange(host.research!.store)
        .importResearch(fixture.source.path, intoProjectId: projectId);
    expect(refreshed.id, projectId);

    // Premises: R now exists as an ambiguous candidate and P is unchanged.
    expect(bindings(projectId).map((b) => (b.paperId, b.ambiguous)), [
      ('P', true),
      ('Q', true),
      ('R', true),
    ], reason: '前提：刷新后新增候选 R');
    final recheck = await bindingRow(projectId, documentId, 'P');
    expect(recheck['digest'], approved['digest'], reason: '前提：P 的摘要确实未变');
    expect(
      (await current('document', documentId, projectId)).contentDigest,
      documentRef.contentDigest,
    );

    final result = await host.tools.invoke(call.withApproval(approval));
    expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    final remaining = bindings(projectId)
        .where((b) => b.documentId == documentId);
    expect(remaining.map((b) => b.paperId), ['P']);
    expect(remaining.single.ambiguous, isFalse);
    expect(remaining.single.method, endsWith('+manual'));
    expect(bindings(projectId).map((b) => b.paperId).toSet(), {'P'});
  });

  test('confirm_binding refuses when the target row itself changed', () async {
    final fixture = await importFixture([paper('P', 1), paper('Q', 1)]);
    final projectId = fixture.projectId;
    final documentId = fixture.documentId;
    final approved = await bindingRow(projectId, documentId, 'P');
    final documentRef = await current('document', documentId, projectId);
    final call = request(
      'research.confirm_binding',
      {
        'document_id': documentId,
        'paper_id': 'P',
        'expected_digest': approved['digest'],
      },
      [documentRef],
    );
    final approval = await host.tools.approve(await host.tools.prepare(call));

    // The refresh revises P itself (paper rev 1 -> 2), so the binding row's
    // paperRev changes and the digest taken before the refresh is stale.
    writeSource(fixture.source, [paper('P', 1), paper('P', 2), paper('Q', 1)]);
    await ResearchExchange(host.research!.store)
        .importResearch(fixture.source.path, intoProjectId: projectId);

    // Premise: P's digest really changed with the refresh.
    final recheck = await bindingRow(projectId, documentId, 'P');
    expect(recheck['paperRev'], 2);
    expect(recheck['digest'], isNot(approved['digest']));
    final before = bindingRows(projectId);

    final result = await host.tools.invoke(call.withApproval(approval));
    expect(result.status, isNot(ToolCallStatus.succeeded));
    expect(result.changes, isEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
    expect(bindingRows(projectId), before);
    expect(bindings(projectId).map((b) => (b.paperId, b.ambiguous)), [
      ('P', true),
      ('Q', true),
    ]);
  });
}
