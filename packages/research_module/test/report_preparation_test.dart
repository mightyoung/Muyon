import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/src/core/exchange.dart';
import 'package:research_module/src/core/store.dart';

void main() {
  late Directory temp;
  late WorkbenchStore store;
  late ResearchExchange exchange;
  final generatedAt = DateTime.utc(2026, 10, 11, 12);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('report-preparation-');
    store = WorkbenchStore.open(p.join(temp.path, 'app'));
    // Handwritten records make IDs and the historic report body deterministic.
    store.db.execute('''
INSERT INTO projects(id,title,question,next_step) VALUES('p','中文研究','为什么？','寻找反证');
INSERT INTO projects(id,title,question,next_step) VALUES('foreign','其他研究','','');
INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES('d','p','材料.md','materials.md',NULL);
INSERT INTO entries(id,project_id,kind,title,data) VALUES('e','p','claims','正文主张','{"id":"c1","rev":2,"statement":"正文主张"}');
INSERT INTO entries(id,project_id,kind,title,data) VALUES('title-only','p','claims','仅在笔记标题关联','{"id":"c2","rev":1}');
INSERT INTO entries(id,project_id,kind,title,data) VALUES('uncited','p','claims','未引用记录','{"id":"c3","rev":1}');
INSERT INTO tasks(id,revision,project_id,title,goal,spec) VALUES('t',3,'p','任务','目标','{}');
INSERT INTO runs(id,task_id,task_revision,status,accepted,data) VALUES('r','t',3,'succeeded',1,'{"metrics":{"分数":0.8},"artifacts":["结果.csv"]}');
INSERT INTO runs(id,task_id,task_revision,status,accepted,data) VALUES('uncited-run','t',3,'succeeded',1,'{}');
INSERT INTO runs(id,task_id,task_revision,status,accepted,data) VALUES('unaccepted-run','t',3,'succeeded',0,'{}');
INSERT INTO notes(id,document_id,locator,text,page_number,quoted_text,entry_id) VALUES('n','d','段落二','中文笔记',2,'原文摘录','title-only');
INSERT INTO sections(id,project_id,heading,level,position,argument,support) VALUES('s1','p','发现',1,1,'有限论证','partial');
INSERT INTO sections(id,project_id,heading,level,position,argument,support) VALUES('s2','p','复核',2,2,'','unassessed');
INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('o1','p','发现','e','s1');
INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('o2','p','发现','r','s1');
INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('o3','p','发现','n','s1');
INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('o4','p','复核','e','s2');
INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('o5','p','复核','r','s2');
INSERT INTO paper_bindings(document_id,paper_id,paper_rev,method,hash_ok,ambiguous) VALUES('d','paper',1,'manual',1,0);
''');
    const document = '# 手写材料\n\n原文摘录。\n';
    store.db.execute('UPDATE documents SET sha256=? WHERE id=?', [
      sha256.convert(utf8.encode(document)).toString(),
      'd',
    ]);
    exchange = ResearchExchange(store.scoped('p'));
  });

  tearDown(() {
    store.close();
    temp.deleteSync(recursive: true);
  });

  const entryBody = '''正文主张

来源记录：[claims/c1@2] e

```json
{
  "id": "c1",
  "rev": 2,
  "statement": "正文主张"
}
```
''';
  const runBody = '''执行记录：r，任务 t r3，状态 succeeded

指标：{"分数":0.8}

产物：["结果.csv"]

人工关联为证据；此状态不代表科学结论已验证。
''';
  // This is the existing exportReport output, including every blank line.
  const golden =
      '# 中文研究\n\n为什么？\n\n下一步：寻找反证\n\n'
      '## 发现\n\n有限论证\n\n证据支持程度：部分支持\n\n'
      '**证据 1**\n\n$entryBody\n'
      '**证据 2**\n\n$runBody\n'
      '**证据 3**\n\n精读证据：n\n\n来源：材料.md · p. 2 · 段落二\n\n'
      '> 原文摘录\n\n关联研究对象：仅在笔记标题关联\n\n中文笔记\n\n'
      '### 复核\n\n证据支持程度：未评估\n\n'
      '**证据 1**\n\n$entryBody\n'
      '**证据 2**\n\n$runBody\n'
      '## 精读笔记\n\n'
      '### 材料.md · 段落二 · p. 2\n\n'
      '> 原文摘录\n\n关联研究对象：仅在笔记标题关联\n\n中文笔记\n\n';

  Map<String, List<Map<String, Object?>>> businessSnapshot() => {
    for (final table in [
      'notes',
      'paper_bindings',
      'entries',
      'sections',
      'outline',
      'runs',
      'projects',
      'documents',
      'tasks',
    ])
      table: store.db
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
  };

  test(
    'prepares exact historic report UTF-8 and legacy wrapper bytes',
    () async {
      final before = businessSnapshot();
      final preparation = exchange.prepareReport('p', generatedAt: generatedAt);
      final bytes = utf8.encode(golden);
      expect(preparation, isA<LocalExportPreparation>());
      expect(preparation.kind, LocalExportKind.report);
      expect(preparation.mimeType, 'text/markdown');
      expect(preparation.formatVersion, isNotEmpty);
      expect(preparation.preparationVersion, greaterThanOrEqualTo(1));
      expect(preparation.generatedAt, generatedAt);
      expect(preparation.bytes, bytes);
      expect(preparation.byteCount, bytes.length);
      expect(preparation.byteCount, greaterThan(golden.length));
      expect(preparation.sha256, sha256.convert(bytes).toString());
      expect(preparation.manifestDigest, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(businessSnapshot(), before);
      final destination = p.join(temp.path, 'export');
      final file = File(await exchange.exportReport('p', destination));
      expect(file.readAsBytesSync(), bytes);
      expect(businessSnapshot(), before);
    },
  );

  test(
    'counts emitted object identities once, not reads or title mentions',
    () {
      final preparation = exchange.prepareReport('p', generatedAt: generatedAt);
      expect(preparation.objectCounts, {
        'note': 1,
        'section': 2,
        'entry': 1,
        'run': 1,
      });
      expect(preparation.dedupedObjectCount, 5);
      final keys = preparation.sources
          .map((s) => '${s.objectType}/${s.objectId}')
          .toList();
      expect(keys.toSet().length, keys.length);
      expect(
        keys,
        containsAll([
          'project/p',
          'document/d',
          'note/n',
          'section/s1',
          'section/s2',
          'entry/e',
          'entry/title-only',
          'run/r',
        ]),
      );
      expect(keys, isNot(contains('entry/uncited')));
      expect(keys, isNot(contains('run/uncited-run')));
      expect(keys, isNot(contains('run/unaccepted-run')));
      for (final source in preparation.sources) {
        expect(source.moduleId, 'research');
        expect(source.contentDigest, matches(RegExp(r'^[0-9a-f]{64}$')));
        if (source.objectType == 'run') {
          expect(source.revisionRef, isNotNull);
        }
      }
    },
  );

  test(
    'frozen bytes, sources and counts survive caller and later source edits',
    () {
      final preparation = exchange.prepareReport('p', generatedAt: generatedAt);
      final bytes = List<int>.from(preparation.bytes);
      final digest = preparation.sha256;
      final manifest = preparation.manifestDigest;
      final sources = List<ObjectRef>.from(preparation.sources);
      expect(() => preparation.bytes[0] = 0, throwsUnsupportedError);
      expect(() => preparation.sources.clear(), throwsUnsupportedError);
      expect(
        () => preparation.objectCounts['entry'] = 999,
        throwsUnsupportedError,
      );
      final freshEntry = store.entries('p').firstWhere((e) => e.id == 'e');
      freshEntry.data['statement'] = '调用方更改';
      store.db.execute("UPDATE entries SET title='新标题',data='{}' WHERE id='e'");
      store.db.execute("UPDATE notes SET text='新笔记' WHERE id='n'");
      expect(preparation.bytes, bytes);
      expect(preparation.sha256, digest);
      expect(preparation.manifestDigest, manifest);
      expect(preparation.sources, sources);
      expect(utf8.decode(preparation.bytes), golden);
    },
  );

  test('preparation contract copies external bytes, sources and counts', () {
    final original = exchange.prepareReport('p', generatedAt: generatedAt);
    final mutable = Uint8List.fromList(original.bytes);
    final mutableSources = List<ObjectRef>.from(original.sources);
    final mutableCounts = Map<String, int>.from(original.objectCounts);
    final frozen = ResearchReportPreparation(
      generatedAt: generatedAt,
      bytes: mutable,
      sources: mutableSources,
      objectCounts: mutableCounts,
    );
    final manifest = frozen.manifestDigest;
    mutable[0] = 0;
    mutableSources.clear();
    mutableCounts['entry'] = 999;
    expect(frozen.bytes, original.bytes);
    expect(frozen.sha256, original.sha256);
    expect(frozen.sources, original.sources);
    expect(frozen.objectCounts, original.objectCounts);
    expect(frozen.dedupedObjectCount, original.dedupedObjectCount);
    expect(frozen.manifestDigest, manifest);
    expect(frozen.manifestDigest, original.manifestDigest);
  });

  test('stable manifest changes when a rendered source changes', () {
    final before = exchange.prepareReport('p', generatedAt: generatedAt);
    final repeat = exchange.prepareReport('p', generatedAt: generatedAt);
    expect(repeat.bytes, before.bytes);
    expect(repeat.sha256, before.sha256);
    expect(repeat.manifestDigest, before.manifestDigest);
    store.db.execute("UPDATE entries SET title='更改正文标题' WHERE id='e'");
    final changed = exchange.prepareReport('p', generatedAt: generatedAt);
    expect(utf8.decode(changed.bytes), contains('更改正文标题'));
    expect(changed.sha256, isNot(before.sha256));
    expect(changed.manifestDigest, isNot(before.manifestDigest));
  });

  test(
    'scoped preparation rejects another project without any business write',
    () {
      final before = businessSnapshot();
      expect(
        () => exchange.prepareReport('foreign', generatedAt: generatedAt),
        throwsStateError,
      );
      expect(businessSnapshot(), before);
    },
  );
}
