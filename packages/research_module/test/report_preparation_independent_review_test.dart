import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/src/core/exchange.dart';
import 'package:research_module/src/core/store.dart';
import 'package:sqlite3/sqlite3.dart';

class MutableReportSource extends ObjectRef {
  MutableReportSource()
    : super(moduleId: 'research', objectType: 'entry', objectId: 'entry');

  String currentId = 'entry';
  String currentDigest = 'a' * 64;

  @override
  String get objectId => currentId;
  @override
  String get contentDigest => currentDigest;
}

Map<String, Object?> snapshot(Database db) => {
  for (final row in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    row['name'] as String: db
        .select('SELECT * FROM "${row['name']}" ORDER BY rowid')
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
};

void main() {
  test('report preparation snapshots mutable source values', () {
    final source = MutableReportSource();
    final incoming = [source];
    final prepared = ResearchReportPreparation(
      generatedAt: DateTime.utc(2026, 10, 11),
      bytes: utf8.encode('冻结报告'),
      sources: incoming,
      objectCounts: const {'entry': 1},
    );
    final manifest = prepared.manifestDigest;
    source.currentId = 'replaced';
    source.currentDigest = 'b' * 64;
    incoming.clear();
    expect(prepared.sources.single.objectId, 'entry');
    expect(prepared.sources.single.contentDigest, 'a' * 64);
    expect(identical(prepared.sources.single, source), isFalse);
    expect(prepared.manifestDigest, manifest);
    expect(utf8.decode(prepared.bytes), '冻结报告');
  });

  test(
    'preparation and scope refusal preserve all tables across connections',
    () {
      final temp = Directory.systemTemp.createTempSync('le02-review-');
      final store = WorkbenchStore.open(temp.path);
      try {
        store.db.execute(
          "INSERT INTO projects(id,title,question,next_step) VALUES('p','只读研究','','')",
        );
        store.db.execute(
          "INSERT INTO projects(id,title,question,next_step) VALUES('foreign','外部','','')",
        );
        final observer = sqlite3.open(
          p.join(temp.path, 'workbench.sqlite'),
          mode: OpenMode.readOnly,
        );
        try {
          final before = snapshot(observer);
          final changes = store.db
              .select('SELECT total_changes() AS n')
              .single['n'];
          final files = temp
              .listSync(recursive: true)
              .map((f) => f.path)
              .toSet();
          final exchange = ResearchExchange(store.scoped('p'));
          final prepared = exchange.prepareReport(
            'p',
            generatedAt: DateTime.utc(2026, 10, 11),
          );
          expect(utf8.decode(prepared.bytes), contains('只读研究'));
          expect(
            () => exchange.prepareReport(
              'foreign',
              generatedAt: DateTime.utc(2026, 10, 11),
            ),
            throwsStateError,
          );
          expect(
            store.db.select('SELECT total_changes() AS n').single['n'],
            changes,
          );
          expect(snapshot(observer), before);
          expect(
            temp.listSync(recursive: true).map((f) => f.path).toSet(),
            files,
          );
        } finally {
          observer.close();
        }
      } finally {
        store.close();
        temp.deleteSync(recursive: true);
      }
    },
  );
}
