import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/src/core/claim_draft_preparation.dart';
import 'package:research_module/src/core/store.dart';
import 'package:research_module/src/research_module.dart' show ResearchSession;

String digest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

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
    store.db.execute(
      "INSERT INTO projects(id,title,question,next_step,layout,skill_root) VALUES('p','研究','','','research-skill-v2',''),('other','其他','','','research-skill-v2','')",
    );
    for (final id in ['d', 'pdf', 'unbound', 'foreign']) {
      final text = id == 'pdf' ? '%PDF-1.4 synthetic' : '原始引文，中文材料。';
      File(p.join(store.rootPath, '$id.${id == 'pdf' ? 'pdf' : 'md'}'))
          .writeAsStringSync(text);
      store.db.execute(
        'INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES(?,?,?,?,?)',
        [
          id,
          id == 'foreign' ? 'other' : 'p',
          '$id.${id == 'pdf' ? 'pdf' : 'md'}',
          '$id.${id == 'pdf' ? 'pdf' : 'md'}',
          sha256.convert(utf8.encode(text)).toString(),
        ],
      );
      store.db.execute(
        'INSERT INTO notes(id,document_id,locator,text,quoted_text,evidence_kind) VALUES(?,?,?,?,?,?)',
        ['n-$id', id, '段落一', '有限结论', '原始引文', 'paper_statement'],
      );
    }
    for (final id in ['d', 'pdf']) {
      store.db.execute('INSERT INTO paper_bindings VALUES(?,?,?,?,?,?)', [
        id,
        'paper',
        1,
        'manual',
        1,
        0,
      ]);
    }
    store.db.execute(
      'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
      [
        'paper-local',
        'p',
        'papers',
        '旧论文',
        jsonEncode({
          'schema_version': 2,
          'id': 'paper',
          'rev': 1,
          'source_id': 'source',
          'source_rev': 1,
          'version': 'v1',
        }),
      ],
    );
    store.db.execute(
      'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
      [
        'paper-new',
        'p',
        'papers',
        '新论文',
        jsonEncode({
          'schema_version': 2,
          'id': 'paper',
          'rev': 2,
          'source_id': 'source',
          'source_rev': 1,
          'version': 'v1',
        }),
      ],
    );
    store.db.execute(
      'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
      [
        'source-local',
        'p',
        'sources',
        '来源',
        jsonEncode({'schema_version': 2, 'id': 'source', 'rev': 1}),
      ],
    );
  });
  tearDown(() {
    store.close();
    temp.deleteSync(recursive: true);
  });

  ResolvedAssistantScope scope(List<String> ids, {bool project = true}) {
    final refs = <ObjectRef>[
      if (project)
        ObjectRef(
          moduleId: 'research',
          objectType: 'project',
          objectId: 'p',
          nativeProjectId: 'p',
          contentDigest: digest(['研究', '', '']),
        ),
      for (final id in ids)
        ObjectRef(
          moduleId: 'research',
          objectType: 'note',
          objectId: id,
          nativeProjectId: 'p',
          contentDigest: digest(
            Map<String, Object?>.from(
              store.db.select('SELECT * FROM notes WHERE id=?', [id]).single,
            ),
          ),
        ),
    ];
    return ResolvedAssistantScope(
      requested: const AssistantScope.global(),
      objects: refs,
    );
  }

  Future<ResearchClaimDraftPreparation> prepare(
    List<String> ids, {
    ResolvedAssistantScope? selected,
  }) =>
      ResearchClaimDraftPreparer(
        store,
        readDocument: (ref) async {
          reads++;
          await duringRead?.call();
          final doc = store
              .documents('p')
              .singleWhere((d) => d.id == ref.objectId);
          return File(doc.absolutePath).readAsBytesSync();
        },
      ).prepareClaimDrafts(
        projectId: 'p',
        noteIds: ids,
        scope:
            selected ??
            scope(ids.where((id) => id.isNotEmpty).toSet().toList()),
        generatedAt: at,
      );

  List<Map<String, dynamic>> rows(LocalExportPreparation prepared) =>
      const LineSplitter()
          .convert(utf8.decode(prepared.bytes))
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
  Map<String, Object?> state() => {
    for (final table in [
      'projects',
      'documents',
      'notes',
      'entries',
      'paper_bindings',
      'tasks',
      'runs',
      'sections',
      'outline',
    ])
      table: store.db
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
  };
  Future<void> refuses(
    List<String> ids, {
    ResolvedAssistantScope? selected,
  }) async {
    Object? error;
    try {
      await prepare(ids, selected: selected);
    } on Object catch (e) {
      error = e;
    }
    expect(error, isA<StateError>());
  }

  test(
    'freezes UTF8 draft bytes and source pins without files or business writes',
    () async {
      final before = state(),
          beforeFiles = Directory(
            temp.path,
          ).listSync(recursive: true).map((f) => f.path).toList()..sort();
      final changes = store.db
          .select('SELECT total_changes() AS n')
          .single['n'];
      final prepared = await prepare(['n-d', 'n-pdf']);
      expect(
        store.db.select('SELECT total_changes() AS n').single['n'],
        changes,
      );
      expect(reads, 2);
      expect(state(), before);
      final afterFiles = Directory(
        temp.path,
      ).listSync(recursive: true).map((f) => f.path).toList()..sort();
      expect(afterFiles, beforeFiles);
      expect(prepared.sha256, sha256.convert(prepared.bytes).toString());
      expect(
        prepared.byteCount,
        greaterThan(utf8.decode(prepared.bytes).length),
      );
      expect(prepared.dedupedObjectCount, 2);
      expect(
        prepared.sources.map((s) => s.objectType),
        containsAll(['project', 'note', 'document', 'entry']),
      );
      expect(rows(prepared).map((r) => r['paper_rev']), everyElement(1));
      expect(
        rows(prepared).map((r) => r['review_status']),
        everyElement('needs_review'),
      );
    },
  );
  test('rejects V1 even though isSkill accepts the layout prefix', () async {
    store.db.execute(
      "UPDATE projects SET layout='research-skill-v1' WHERE id='p'",
    );
    await refuses(['n-d']);
  });
  test('rejects current V1 logs despite a V2 project layout', () async {
    store.db.execute(
      "UPDATE entries SET data=json_remove(data,'\$.schema_version') WHERE id='source-local'",
    );
    await refuses(['n-d']);
  });
  test('rejects empty selection', () async {
    await refuses([]);
  });
  test('rejects an empty note ID mixed with a valid note', () async {
    await refuses(['n-d', '']);
  });
  test('rejects duplicate notes as a whole operation', () async {
    await refuses(['n-d', 'n-d']);
  });
  test('rejects foreign notes mixed with a valid note', () async {
    await refuses(['n-d', 'n-foreign'], selected: scope(['n-d', 'n-foreign']));
  });
  test('requires selected project explicitly in resolved scope', () async {
    await refuses(['n-d'], selected: scope(['n-d'], project: false));
  });
  test('rejects valid project note absent from resolved scope', () async {
    await refuses(['n-d', 'n-pdf'], selected: scope(['n-d']));
  });
  test('rejects stale selected note content pins', () async {
    final selected = scope(['n-d']);
    store.db.execute("UPDATE notes SET text='changed' WHERE id='n-d'");
    await refuses(['n-d'], selected: selected);
  });
  test(
    'two binding rows exclude the note even with a first unambiguous row',
    () async {
      store.db.execute(
        "INSERT INTO paper_bindings VALUES('d','z-other-paper',1,'manual',1,0)",
      );
      final prepared = await prepare(['n-d', 'n-pdf']);
      expect(rows(prepared), hasLength(1));
      expect(prepared.exclusions.single.id, 'n-d');
    },
  );
  test('one ambiguous binding excludes the selected note', () async {
    store.db.execute(
      "UPDATE paper_bindings SET ambiguous=1 WHERE document_id='d'",
    );
    final prepared = await prepare(['n-d', 'n-pdf']);
    expect(rows(prepared), hasLength(1));
    expect(prepared.exclusions.single.id, 'n-d');
  });
  test(
    'duplicate exact paper revision excludes rather than selecting first',
    () async {
      store.db.execute(
        "INSERT INTO entries SELECT 'duplicate-paper',project_id,kind,title,data FROM entries WHERE id='paper-local'",
      );
      await refuses(['n-d']);
    },
  );
  test(
    'hashOk false remains exportable with a prominent frozen warning',
    () async {
      store.db.execute(
        "UPDATE paper_bindings SET hash_ok=0 WHERE document_id='d'",
      );
      final prepared = await prepare(['n-d']);
      expect(rows(prepared).single['workbench']['hash_mismatch'], true);
      expect(prepared.warnings, contains(contains('hash')));
    },
  );
  test(
    'actual source bytes differing from document pin are excluded',
    () async {
      File(p.join(store.rootPath, 'd.md')).writeAsStringSync('changed bytes');
      final prepared = await prepare(['n-d', 'n-pdf']);
      expect(rows(prepared), hasLength(1));
      expect(prepared.exclusions.single.id, 'n-d');
    },
  );
  test('partial selection manifest freezes excluded note identities', () async {
    final prepared = await prepare(['n-d', 'n-unbound']);
    expect(prepared.exclusions.single.id, 'n-unbound');
    expect(prepared.warnings, contains(contains('partial')));
  });
  test('all ineligible refuses an empty export', () async {
    await refuses(['n-unbound']);
  });
  test('frozen IDs time bytes and manifest survive later DB edits', () async {
    final prepared = await prepare(['n-d']);
    final content = List<int>.from(prepared.bytes),
        manifest = prepared.manifestDigest;
    store.db.execute("UPDATE notes SET text='later' WHERE id='n-d'");
    expect(prepared.bytes, content);
    expect(prepared.manifestDigest, manifest);
    expect(prepared.generatedAt, at);
    expect(() => prepared.bytes[0] = 0, throwsUnsupportedError);
  });
  test(
    'historical document remains eligible without upgrading paper revision',
    () async {
      store.db.execute(
        "INSERT INTO documents SELECT 'd-new',project_id,relative_path,snapshot_path,sha256 FROM documents WHERE id='d'",
      );
      final prepared = await prepare(['n-d']);
      expect(rows(prepared).single['paper_rev'], 1);
      final entryIds = prepared.sources
          .where((r) => r.objectType == 'entry')
          .map((r) => r.objectId);
      expect(entryIds, contains('paper-local'));
      expect(entryIds, isNot(contains('paper-new')));
      expect(rows(prepared).single['text_binding']['path'], 'd.md');
    },
  );
  test('PDF and missing quote do not fabricate text binding', () async {
    store.db.execute("UPDATE notes SET quoted_text='' WHERE id='n-d'");
    final prepared = await prepare(['n-d', 'n-pdf']);
    for (final row in rows(prepared)) {
      expect(row.containsKey('text_binding'), false);
      expect(row['material_access'], 'unchecked');
    }
  });
  test('schema version must be integer two, not a numeric lookalike', () async {
    store.db.execute(
      "UPDATE entries SET data=json_set(data,'\$.schema_version',2.0) WHERE id='source-local'",
    );
    await refuses(['n-d']);
  });

  test('typed all-ineligible failure freezes each exclusion', () async {
    ClaimDraftPreparationFailure? error;
    try {
      await prepare(['n-unbound']);
    } on ClaimDraftPreparationFailure catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(error!.code, 'no_exportable_notes');
    expect(error.exclusions.single.id, 'n-unbound');
    expect(() => error!.exclusions.clear(), throwsUnsupportedError);
  });

  for (final mutation in ['note', 'binding', 'delete', 'paper', 'project']) {
    test(
      'after awaited read rechecks $mutation source state and refuses',
      () async {
        duringRead = () async {
          switch (mutation) {
            case 'note':
              store.db.execute(
                "UPDATE notes SET text='changed in callback' WHERE id='n-d'",
              );
            case 'binding':
              store.db.execute(
                "INSERT INTO paper_bindings VALUES('d','z-second',1,'manual',1,0)",
              );
            case 'delete':
              store.db.execute("DELETE FROM notes WHERE id='n-d'");
            case 'paper':
              store.db.execute(
                "UPDATE entries SET title='changed in callback' WHERE id='paper-local'",
              );
            case 'project':
              store.db.execute(
                "UPDATE projects SET layout='research-skill-v1' WHERE id='p'",
              );
          }
        };
        ClaimDraftPreparationFailure? error;
        try {
          await prepare(['n-d']);
        } on ClaimDraftPreparationFailure catch (e) {
          error = e;
        }
        expect(error?.code, 'source_changed_during_preparation');
        expect(reads, 1);
      },
    );
  }

  test('partial proposal freezes explicit selection inclusion and nested draft rows', () async {
    final prepared = await prepare(['n-d', 'n-unbound']);
    expect(prepared.selectedNoteIds, ['n-d', 'n-unbound']);
    expect(prepared.includedNoteIds, ['n-d']);
    expect(prepared.objectCounts, {'claimDraft': 1});
    expect(() => prepared.selectedNoteIds.clear(), throwsUnsupportedError);
    expect(
      () => prepared.rows.single['workbench'] = ['fake'],
      throwsUnsupportedError,
    );
    expect(
      () => (prepared.rows.single['workbench'] as Map)['quote'] = 'fake',
      throwsUnsupportedError,
    );
  });

  test(
    'two notes on one document read the same pinned bytes only once',
    () async {
      store.db.execute(
        "INSERT INTO notes(id,document_id,locator,text,quoted_text) VALUES('n-second','d','二','另一条','原始引文')",
      );
      final prepared = await prepare(['n-d', 'n-second']);
      expect(reads, 1);
      expect(
        prepared.sources.where((s) => s.objectType == 'document'),
        hasLength(1),
      );
      expect(prepared.rows.map((r) => r['id']).toSet(), hasLength(2));
    },
  );

  test(
    'duplicate exact source revision is an exclusion, not first match',
    () async {
      store.db.execute(
        "INSERT INTO entries SELECT 'duplicate-source',project_id,kind,title,data FROM entries WHERE id='source-local'",
      );
      await refuses(['n-d']);
      expect(reads, 0);
    },
  );

  test(
    'missing source bytes produce an exclusion without file writes',
    () async {
      File(p.join(store.rootPath, 'd.md')).deleteSync();
      final before = state();
      final prepared = await prepare(['n-d', 'n-pdf']);
      expect(prepared.exclusions.single.reason, 'source_unavailable');
      expect(state(), before);
    },
  );

  test(
    'untrusted snapshot paths never enter the document reader contract',
    () async {
      final seen = <ObjectRef>[];
      final prepared =
          await ResearchClaimDraftPreparer(
            store,
            readDocument: (ref) async {
              seen.add(ref);
              return utf8.encode('原始引文，中文材料。');
            },
          ).prepareClaimDrafts(
            projectId: 'p',
            noteIds: ['n-d'],
            scope: scope(['n-d']),
            generatedAt: at,
          );
      expect(prepared.rows, hasLength(1));
      expect(seen.single.objectId, 'd');
      expect(
        seen.single.contentDigest,
        sha256.convert(utf8.encode('原始引文，中文材料。')).toString(),
      );
      expect(seen.single.revisionRef, isNull);
    },
  );
  test(
    'oversized UTF8 source is excluded before decoding or draft creation',
    () async {
      final bytes = List<int>.filled(16 * 1024 * 1024 + 1, 65);
      store.db.execute("UPDATE documents SET sha256=? WHERE id='d'", [
        sha256.convert(bytes).toString(),
      ]);
      ClaimDraftPreparationFailure? error;
      try {
        await ResearchClaimDraftPreparer(
          store,
          readDocument: (_) async => bytes,
        ).prepareClaimDrafts(
          projectId: 'p',
          noteIds: ['n-d'],
          scope: scope(['n-d']),
          generatedAt: at,
        );
      } on ClaimDraftPreparationFailure catch (e) {
        error = e;
      }
      expect(error!.exclusions.single.reason, 'source_too_large');
    },
  );

  test('JSONL draft line exceeding one MiB is excluded', () async {
    store.db.execute("UPDATE notes SET text=? WHERE id='n-d'", [
      'x' * (1024 * 1024),
    ]);
    ClaimDraftPreparationFailure? error;
    try {
      await prepare(['n-d']);
    } on ClaimDraftPreparationFailure catch (e) {
      error = e;
    }
    expect(error!.exclusions.single.reason, 'draft_line_too_large');
  });

  test('selected scope refusal performs no document reads', () async {
    await refuses(['n-d', 'n-pdf'], selected: scope(['n-d']));
    expect(reads, 0);
  });
  test(
    'prepared selected source pins match the resolved current references',
    () async {
      final selected = scope(['n-d']);
      final prepared = await prepare(['n-d'], selected: selected);
      expect(
        prepared.sources
            .singleWhere((r) => r.objectType == 'project')
            .contentDigest,
        selected.objects
            .singleWhere((r) => r.objectType == 'project')
            .contentDigest,
      );
      expect(
        prepared.sources
            .singleWhere((r) => r.objectType == 'note')
            .contentDigest,
        selected.objects
            .singleWhere((r) => r.objectType == 'note')
            .contentDigest,
      );
    },
  );

  for (final type in ['project', 'note']) {
    test(
      'resolved $type revision pin must match the current DB reference',
      () async {
        final original = scope(['n-d']);
        final objects = [
          for (final ref in original.objects)
            ObjectRef(
              moduleId: ref.moduleId,
              objectType: ref.objectType,
              objectId: ref.objectId,
              nativeProjectId: ref.nativeProjectId,
              contentDigest: ref.contentDigest,
              revisionRef: ref.objectType == type
                  ? 'stale-revision'
                  : ref.revisionRef,
            ),
        ];
        await refuses(
          ['n-d'],
          selected: ResolvedAssistantScope(
            requested: const AssistantScope.global(),
            objects: objects,
          ),
        );
        expect(reads, 0);
      },
    );
  }

  test('Windows absolute document path is excluded before trusted reader invocation', () async {
    store.db.execute(
      "UPDATE documents SET relative_path='C:/outside.md' WHERE id='d'",
    );
    await refuses(['n-d']);
    expect(reads, 0);
  });
  for (final defect in ['paper-id', 'source-id', 'source-rev']) {
    test(
      'invalid pinned scientific $defect is excluded before reading',
      () async {
        switch (defect) {
          case 'paper-id':
            store.db.execute(
              "UPDATE paper_bindings SET paper_id='' WHERE document_id='d'",
            );
            store.db.execute(
              "UPDATE entries SET data=json_set(data,'\$.id','') WHERE id='paper-local'",
            );
          case 'source-id':
            store.db.execute(
              "UPDATE entries SET data=json_set(data,'\$.source_id','') WHERE id='paper-local'",
            );
            store.db.execute(
              "UPDATE entries SET data=json_set(data,'\$.id','') WHERE id='source-local'",
            );
          case 'source-rev':
            store.db.execute(
              "UPDATE entries SET data=json_set(data,'\$.source_rev',0) WHERE id='paper-local'",
            );
            store.db.execute(
              "UPDATE entries SET data=json_set(data,'\$.rev',0) WHERE id='source-local'",
            );
        }
        ClaimDraftPreparationFailure? error;
        try {
          await prepare(['n-d']);
        } on ClaimDraftPreparationFailure catch (e) {
          error = e;
        }
        expect(error?.code, 'no_exportable_notes');
        expect(error!.exclusions.single.id, 'n-d');
        expect(reads, 0);
      },
    );
  }

  test('all prepared source refs resolve through the official ResearchSession', () async {
    final prepared = await prepare(['n-d', 'n-pdf']);
    final session = ResearchSession(
      store.scoped('p'),
      const WorkspaceBinding(
        workspaceId: 'w',
        moduleId: 'research',
        nativeProjectId: 'p',
      ),
    );
    try {
      for (final ref in prepared.sources) {
        final view = await session.resolve(ref);
        expect(
          view,
          isNotNull,
          reason:
              'unresolvable preparation source: ${ref.objectType}/${ref.objectId}',
        );
        expect(view!.ref, ref);
      }
    } finally {
      await session.dispose();
    }
  });

  test(
    'host manifest exposes deep-frozen binding facts and all selection facts',
    () async {
      final prepared = await prepare(['n-d', 'n-unbound']);
      Map? manifest;
      try {
        manifest = (prepared as dynamic).manifest as Map;
      } on NoSuchMethodError {
        manifest = null;
      }
      expect(manifest, isNotNull);
      expect(manifest!['selectedNoteIds'], ['n-d', 'n-unbound']);
      expect(manifest['includedNoteIds'], ['n-d']);
      expect((manifest['sourceState'] as Map)['bindings'], isNotEmpty);
      expect(() => manifest!['fake'] = true, throwsUnsupportedError);
      expect(
        () => ((manifest!['sourceState'] as Map)['bindings'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((manifest!['sourceState'] as Map)['bindings'] as List)
                    .first['paper_rev'] =
                99,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'current V1 unrelated authoritative row refuses V2 layout as a whole',
    () async {
      store.db.execute(
        "INSERT INTO entries(id,project_id,kind,title,data) VALUES('legacy-claim','p','claims','old','{\"id\":\"old\",\"rev\":1}')",
      );
      await refuses(['n-d']);
      expect(reads, 0);
    },
  );
  for (final unavailable in [false, true]) {
    test(
      'partial proposal omits unresolvable ${unavailable ? 'missing' : 'changed'} document source refs',
      () async {
        final file = File(p.join(store.rootPath, 'd.md'));
        if (unavailable) {
          file.deleteSync();
        } else {
          file.writeAsStringSync('different fixture bytes');
        }
        final prepared = await prepare(['n-d', 'n-pdf']);
        final session = ResearchSession(
          store.scoped('p'),
          const WorkspaceBinding(
            workspaceId: 'w',
            moduleId: 'research',
            nativeProjectId: 'p',
          ),
        );
        try {
          for (final ref in prepared.sources) {
            expect(
              await session.resolve(ref),
              isNotNull,
              reason: 'excluded source must remain in host manifest, not current resolvable refs',
            );
          }
          expect(
            prepared.sources
                .where((r) => r.objectType == 'document')
                .map((r) => r.objectId),
            ['pdf'],
          );
          expect(
            (prepared.manifest['sourceState'] as Map)['documents'],
            hasLength(3),
          );
        } finally {
          await session.dispose();
        }
      },
    );
  }
}
