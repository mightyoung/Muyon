import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/src/core/exchange.dart';
import 'package:research_module/src/core/store.dart';

String digest(Object? value) => sha256.convert(utf8.encode(jsonEncode(value))).toString();

void main() {
  late Directory temp;
  late WorkbenchStore store;
  final at = DateTime.utc(2026, 10, 12, 12);
  var reads = 0;
  Future<void> Function()? duringRead;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('le03-owned-');
    store = WorkbenchStore.open(p.join(temp.path, 'app'));
    reads = 0;
    duringRead = null;
    store.db.execute("INSERT INTO projects(id,title,layout,skill_root) VALUES('p','研究','research-skill-v2',''),('other','其他','research-skill-v2','')");
    for (final id in ['d', 'pdf', 'unbound', 'foreign']) {
      final text = id == 'pdf' ? '%PDF-1.4 synthetic' : '原始引文，中文材料。';
      File(p.join(store.rootPath, '$id.${id == 'pdf' ? 'pdf' : 'md'}')).writeAsStringSync(text);
      store.db.execute('INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES(?,?,?,?,?)', [id, id == 'foreign' ? 'other' : 'p', '$id.${id == 'pdf' ? 'pdf' : 'md'}', '$id.${id == 'pdf' ? 'pdf' : 'md'}', sha256.convert(utf8.encode(text)).toString()]);
      store.db.execute('INSERT INTO notes(id,document_id,locator,text,quoted_text,evidence_kind) VALUES(?,?,?,?,?,?)', ['n-$id', id, '段落一', '有限结论', '原始引文', 'paper_statement']);
    }
    for (final id in ['d', 'pdf']) {
      store.db.execute('INSERT INTO paper_bindings VALUES(?,?,?,?,?,?)', [id, 'paper', 1, 'manual', 1, 0]);
    }
    store.db.execute('INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)', ['paper-local', 'p', 'papers', '旧论文', jsonEncode({'schema_version':2,'id':'paper','rev':1,'source_id':'source','source_rev':1,'version':'v1'})]);
    store.db.execute('INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)', ['paper-new', 'p', 'papers', '新论文', jsonEncode({'schema_version':2,'id':'paper','rev':2,'source_id':'source','source_rev':1,'version':'v1'})]);
    store.db.execute('INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)', ['source-local', 'p', 'sources', '来源', jsonEncode({'schema_version':2,'id':'source','rev':1})]);
  });
  tearDown(() { store.close(); temp.deleteSync(recursive:true); });

  ResolvedAssistantScope scope(List<String> ids, {bool project = true}) {
    final refs = <ObjectRef>[
      if (project) ObjectRef(moduleId:'research',objectType:'project',objectId:'p',nativeProjectId:'p',contentDigest:digest(['研究','',''])),
      for (final id in ids) ObjectRef(moduleId:'research',objectType:'note',objectId:id,nativeProjectId:'p',contentDigest:digest(Map<String,Object?>.from(store.db.select('SELECT * FROM notes WHERE id=?',[id]).single))),
    ];
    return ResolvedAssistantScope(requested: const AssistantScope.global(), objects: refs);
  }

  // RED driver invokes the real existing exporter; no production stub.
  // Implementation replaces this driver, retaining the behavioral assertions.
  Future<LocalExportPreparation> prepare(List<String> ids, {ResolvedAssistantScope? selected}) async {
    final result = await ResearchExchange(store).exportClaimDrafts('p',ids,p.join(temp.path,'legacy-out'),now:at);
    final bytes = File(result.path).readAsBytesSync();
    return LocalExportPreparation(kind:LocalExportKind.claimDrafts,formatVersion:'research-claim-drafts-v2',mimeType:'application/x-ndjson',generatedAt:at,bytes:bytes,sha256:sha256.convert(bytes).toString(),sources:const [],dedupedObjectCount:result.rows.length,exclusions:[for(final e in result.skipped) LocalExportExclusion(e.$1,e.$2)],warnings:const [],preparationVersion:1,manifestDigest:digest(result.rows));
  }

  List<Map<String,dynamic>> rows(LocalExportPreparation prepared) => const LineSplitter().convert(utf8.decode(prepared.bytes)).map((line)=>jsonDecode(line) as Map<String,dynamic>).toList();
  Map<String,Object?> state() => {for(final table in ['projects','documents','notes','entries','paper_bindings','tasks','runs','sections','outline']) table: store.db.select('SELECT * FROM $table ORDER BY rowid').map((r)=>Map<String,Object?>.from(r)).toList()};
  List<String> files() => Directory(store.rootPath).listSync(recursive:true).map((f)=>p.relative(f.path,from:store.rootPath)).toList()..sort();
  Future<void> refuses(List<String> ids, {ResolvedAssistantScope? selected}) async {
    Object? error;
    try { await prepare(ids, selected:selected); } on Object catch(e) { error=e; }
    expect(error,isA<StateError>());
  }

  test('freezes UTF8 draft bytes and source pins without files or business writes',() async {
    final before=state(), beforeFiles=Directory(temp.path).listSync(recursive:true).map((f)=>f.path).toList()..sort();
    final prepared=await prepare(['n-d','n-pdf']);
    expect(state(),before);
    final afterFiles=Directory(temp.path).listSync(recursive:true).map((f)=>f.path).toList()..sort();
    expect(afterFiles,beforeFiles);
    expect(prepared.sha256,sha256.convert(prepared.bytes).toString());
    expect(prepared.byteCount,greaterThan(utf8.decode(prepared.bytes).length));
    expect(prepared.dedupedObjectCount,2);
    expect(prepared.sources.map((s)=>s.objectType),containsAll(['project','note','document','paper_binding','entry']));
    expect(rows(prepared).map((r)=>r['paper_rev']),everyElement(1));
    expect(rows(prepared).map((r)=>r['review_status']),everyElement('needs_review'));
  });
  test('rejects V1 even though isSkill accepts the layout prefix',() async {
    store.db.execute("UPDATE projects SET layout='research-skill-v1' WHERE id='p'");
    await refuses(['n-d']);
  });
  test('rejects current V1 logs despite a V2 project layout',() async {
    store.db.execute("UPDATE entries SET data=json_remove(data,'$.schema_version') WHERE id='source-local'");
    await refuses(['n-d']);
  });
  test('rejects empty selection',() async { await refuses([]); });
  test('rejects an empty note ID mixed with a valid note',() async { await refuses(['n-d','']); });
  test('rejects duplicate notes as a whole operation',() async { await refuses(['n-d','n-d']); });
  test('rejects foreign notes mixed with a valid note',() async { await refuses(['n-d','n-foreign'],selected:scope(['n-d','n-foreign'])); });
  test('requires selected project explicitly in resolved scope',() async { await refuses(['n-d'],selected:scope(['n-d'],project:false)); });
  test('rejects valid project note absent from resolved scope',() async { await refuses(['n-d','n-pdf'],selected:scope(['n-d'])); });
  test('rejects stale selected note content pins',() async {
    final selected=scope(['n-d']);store.db.execute("UPDATE notes SET text='changed' WHERE id='n-d'");
    await refuses(['n-d'],selected:selected);
  });
  test('two binding rows exclude the note even with a first unambiguous row',() async {
    store.db.execute("INSERT INTO paper_bindings VALUES('d','other-paper',1,'manual',1,0)");
    final prepared=await prepare(['n-d','n-pdf']);
    expect(rows(prepared),hasLength(1));expect(prepared.exclusions.single.id,'n-d');
  });
  test('one ambiguous binding excludes the selected note',() async {
    store.db.execute("UPDATE paper_bindings SET ambiguous=1 WHERE document_id='d'");
    final prepared=await prepare(['n-d','n-pdf']);
    expect(rows(prepared),hasLength(1));expect(prepared.exclusions.single.id,'n-d');
  });
  test('duplicate exact paper revision excludes rather than selecting first',() async {
    store.db.execute("INSERT INTO entries SELECT 'duplicate-paper',project_id,kind,title,data FROM entries WHERE id='paper-local'");
    await refuses(['n-d']);
  });
  test('hashOk false remains exportable with a prominent frozen warning',() async {
    store.db.execute("UPDATE paper_bindings SET hash_ok=0 WHERE document_id='d'");
    final prepared=await prepare(['n-d']);
    expect(rows(prepared).single['workbench']['hash_mismatch'],true);
    expect(prepared.warnings,contains(contains('hash')));
  });
  test('actual source bytes differing from document pin are excluded',() async {
    File(p.join(store.rootPath,'d.md')).writeAsStringSync('changed bytes');
    final prepared=await prepare(['n-d','n-pdf']);
    expect(rows(prepared),hasLength(1));expect(prepared.exclusions.single.id,'n-d');
  });
  test('partial selection manifest freezes excluded note identities',() async {
    final prepared=await prepare(['n-d','n-unbound']);
    expect(prepared.exclusions.single.id,'n-unbound');
    expect(prepared.warnings,contains(contains('partial')));
  });
  test('all ineligible refuses an empty export',() async { await refuses(['n-unbound']); });
  test('frozen IDs time bytes and manifest survive later DB edits',() async {
    final prepared=await prepare(['n-d']);final content=List<int>.from(prepared.bytes), manifest=prepared.manifestDigest;
    store.db.execute("UPDATE notes SET text='later' WHERE id='n-d'");
    expect(prepared.bytes,content);expect(prepared.manifestDigest,manifest);expect(prepared.generatedAt,at);
    expect(()=>prepared.bytes[0]=0,throwsUnsupportedError);
  });
  test('historical document remains eligible without upgrading paper revision',() async {
    store.db.execute("INSERT INTO documents SELECT 'd-new',project_id,relative_path,snapshot_path,sha256 FROM documents WHERE id='d'");
    final prepared=await prepare(['n-d']);expect(rows(prepared).single['paper_rev'],1);
    expect(rows(prepared).single['text_binding']['path'],'d.md');
  });
  test('PDF and missing quote do not fabricate text binding',() async {
    store.db.execute("UPDATE notes SET quoted_text='' WHERE id='n-d'");
    final prepared=await prepare(['n-d','n-pdf']);
    for(final row in rows(prepared)) {expect(row.containsKey('text_binding'),false);expect(row['material_access'],'unchecked');}
  });
}
