import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:sqlite3/sqlite3.dart';

class _Fixture {
  _Fixture(this.storage, this.database)
      : repository = FoundationRepository(database);
  final StorageManager storage;
  final ManagedConnection database;
  final FoundationRepository repository;
  bool _closed = false;

  static Future<_Fixture> open(Directory root) async {
    final storage = StorageManager(root.path);
    try {
      return _Fixture(storage, await storage.open('host', WorkspaceRepository.schema));
    } catch (_) {
      await storage.close();
      rethrow;
    }
  }

  String? bytes(String key) {
    final rows = database.raw.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> putRaw(String key, String value) => database.write((db) {
    db.execute('INSERT OR REPLACE INTO settings VALUES(?,?)', [key, value]);
  });

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await storage.close();
    } finally {
      repository.dispose();
    }
  }
}

void main() {
  for (final mode in UiPresentationMode.values) {
    test('saved ${mode.name} restores after SQLite close and reopen', () async {
      final root = Directory.systemTemp.createTempSync('aiui-three-tier-');
      var f = await _Fixture.open(root);
      var preference = UiPresentationPreference(f.repository);
      try {
        expect(preference.mode, UiPresentationMode.textOnly);
        expect(f.bytes(UiPresentationPreference.key), isNull);
        await preference.save(mode);
        expect(preference.mode, mode);
        expect(f.bytes(UiPresentationPreference.key), jsonEncode(mode.storageValue));
        await preference.close();
        await f.close();
        f = await _Fixture.open(root);
        preference = UiPresentationPreference(f.repository);
        expect(preference.mode, mode);
        expect(f.bytes(UiPresentationPreference.key), jsonEncode(mode.storageValue));
      } finally {
        await preference.close();
        await f.close();
        root.deleteSync(recursive: true);
      }
    });

    test('${mode.name} gates planning and content by this host request only', () async {
      final root = Directory.systemTemp.createTempSync('aiui-policy-');
      final f = await _Fixture.open(root);
      final preference = UiPresentationPreference(f.repository);
      try {
        await preference.save(mode);
        final ordinary = UiPresentationRequest.ordinary();
        final explicit = UiPresentationRequest.explicitControl();
        final ordinaryPolicy = preference.freezeFor(ordinary);
        final explicitPolicy = preference.freezeFor(explicit);
        expect(ordinaryPolicy.allowsPlanningFor(ordinary), mode == UiPresentationMode.automatic);
        expect(ordinaryPolicy.allowsContentFor(ordinary), mode == UiPresentationMode.automatic);
        expect(explicitPolicy.allowsPlanningFor(explicit), mode != UiPresentationMode.textOnly);
        expect(explicitPolicy.allowsContentFor(explicit), mode != UiPresentationMode.textOnly);
        expect(explicitPolicy.allowsPlanningFor(ordinary), isFalse);
        expect(explicitPolicy.allowsContentFor(UiPresentationRequest.explicitControl()), isFalse);
        expect(ordinaryPolicy.allowsContentFor(explicit), isFalse);
        expect(f.bytes(UiPresentationPreference.key), jsonEncode(mode.storageValue));
      } finally {
        await preference.close();
        await f.close();
        root.deleteSync(recursive: true);
      }
    });
  }

  test('only fresh missing keys can use a future automatic default', () async {
    final root = Directory.systemTemp.createTempSync('aiui-missing-');
    final f = await _Fixture.open(root);
    final conservative = UiPresentationPreference(f.repository);
    final futureDefault = UiPresentationPreference(f.repository,
      missingDefault: UiPresentationMode.automatic);
    try {
      expect(conservative.mode, UiPresentationMode.textOnly);
      expect(futureDefault.mode, UiPresentationMode.automatic);
      expect(f.bytes(UiPresentationPreference.key), isNull);
      expect(f.bytes(UiPresentationPreference.legacyKey), isNull);
    } finally {
      await conservative.close();
      await futureDefault.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });

  for (final raw in ['null', 'broken-json', 'true', '17', '"unknown"',
      '{"mode":"automatic"}']) {
    test('present invalid mode $raw remains text-only and byte-preserved on reopen', () async {
      final root = Directory.systemTemp.createTempSync('aiui-mode-bad-');
      var f = await _Fixture.open(root);
      UiPresentationPreference? preference;
      try {
        await f.putRaw(UiPresentationPreference.key, raw);
        preference = UiPresentationPreference(f.repository,
          missingDefault: UiPresentationMode.automatic);
        expect(preference.mode, UiPresentationMode.textOnly);
        expect(f.bytes(UiPresentationPreference.key), raw);
        await preference.close();
        await f.close();
        f = await _Fixture.open(root);
        preference = UiPresentationPreference(f.repository,
          missingDefault: UiPresentationMode.automatic);
        expect(preference.mode, UiPresentationMode.textOnly);
        expect(f.bytes(UiPresentationPreference.key), raw);
      } finally {
        await preference?.close();
        await f.close();
        root.deleteSync(recursive: true);
      }
    });
  }

  for (final raw in ['false', 'true', 'null', 'broken-json']) {
    test('legacy $raw does not become automatic or get rewritten on restart', () async {
      final root = Directory.systemTemp.createTempSync('aiui-mode-legacy-');
      var f = await _Fixture.open(root);
      UiPresentationPreference? preference;
      try {
        await f.putRaw(UiPresentationPreference.legacyKey, raw);
        preference = UiPresentationPreference(f.repository,
          missingDefault: UiPresentationMode.automatic);
        expect(preference.mode, UiPresentationMode.textOnly);
        await preference.close();
        await f.close();
        f = await _Fixture.open(root);
        preference = UiPresentationPreference(f.repository,
          missingDefault: UiPresentationMode.automatic);
        expect(preference.mode, UiPresentationMode.textOnly);
        expect(f.bytes(UiPresentationPreference.legacyKey), raw);
        expect(f.bytes(UiPresentationPreference.key), isNull);
      } finally {
        await preference?.close();
        await f.close();
        root.deleteSync(recursive: true);
      }
    });
  }

  test('explicit typed save supersedes a legacy off without altering the old bytes', () async {
    final root = Directory.systemTemp.createTempSync('aiui-mode-choice-');
    var f = await _Fixture.open(root);
    UiPresentationPreference? preference;
    try {
      await f.putRaw(UiPresentationPreference.legacyKey, 'false');
      preference = UiPresentationPreference(f.repository);
      await preference.save(UiPresentationMode.few);
      await preference.close();
      await f.close();
      f = await _Fixture.open(root);
      preference = UiPresentationPreference(f.repository);
      expect(preference.mode, UiPresentationMode.few);
      expect(f.bytes(UiPresentationPreference.legacyKey), 'false');
      expect(f.bytes(UiPresentationPreference.key), '"few"');
    } finally {
      await preference?.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });

  test('accepted saves commit in order before close, late saves cannot install', () async {
    final root = Directory.systemTemp.createTempSync('aiui-mode-drain-');
    var f = await _Fixture.open(root);
    final preference = UiPresentationPreference(f.repository);
    final entered = Completer<void>(), release = Completer<void>();
    Future<void>? blocker;
    try {
      blocker = f.database.exclusiveAsync((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final automatic = preference.save(UiPresentationMode.automatic);
      final few = preference.save(UiPresentationMode.few);
      final closing = preference.close();
      expect(preference.mode, UiPresentationMode.textOnly);
      expect(f.bytes(UiPresentationPreference.key), isNull);
      await expectLater(preference.save(UiPresentationMode.textOnly), throwsStateError);
      final request = UiPresentationRequest.explicitControl();
      expect(preference.freezeFor(request).allowsContentFor(request), isFalse);
      release.complete();
      await Future.wait([automatic, few, closing, blocker]);
      expect(preference.mode, UiPresentationMode.few);
      expect(f.bytes(UiPresentationPreference.key), '"few"');
      await f.close();
      f = await _Fixture.open(root);
      final restored = UiPresentationPreference(f.repository);
      try {
        expect(restored.mode, UiPresentationMode.few);
      } finally {
        await restored.close();
      }
    } finally {
      if (!release.isCompleted) release.complete();
      await blocker;
      await preference.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });

  test('storage rejection preserves memory, policy and bytes; later save still works', () async {
    final root = Directory.systemTemp.createTempSync('aiui-mode-fail-');
    final f = await _Fixture.open(root);
    final preference = UiPresentationPreference(f.repository);
    try {
      await preference.save(UiPresentationMode.automatic);
      final request = UiPresentationRequest.ordinary();
      final oldPolicy = preference.freezeFor(request);
      await f.database.write((db) => db.execute('''
CREATE TRIGGER refuse_few BEFORE INSERT ON settings
WHEN NEW.key='assistant.uiPresentation.mode.v1' AND NEW.value='"few"'
BEGIN SELECT RAISE(ABORT, 'fixture storage failure'); END;
'''));
      await expectLater(preference.save(UiPresentationMode.few), throwsA(isA<SqliteException>()));
      expect(preference.mode, UiPresentationMode.automatic);
      expect(f.bytes(UiPresentationPreference.key), '"automatic"');
      expect(oldPolicy.allowsPlanningFor(request), isTrue);
      expect(preference.freezeFor(request).allowsPlanningFor(request), isTrue);
      await preference.save(UiPresentationMode.textOnly);
      expect(preference.mode, UiPresentationMode.textOnly);
      expect(f.bytes(UiPresentationPreference.key), '"text_only"');
      expect(oldPolicy.allowsContentFor(request), isFalse);
    } finally {
      await preference.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });

  test('successful mode changes invalidate old request policies including ABA', () async {
    final root = Directory.systemTemp.createTempSync('aiui-mode-generation-');
    final f = await _Fixture.open(root);
    final preference = UiPresentationPreference(f.repository);
    try {
      await preference.save(UiPresentationMode.automatic);
      final ordinary = UiPresentationRequest.ordinary();
      final automatic = preference.freezeFor(ordinary);
      await preference.save(UiPresentationMode.few);
      expect(automatic.allowsPlanningFor(ordinary), isFalse);
      final explicit = UiPresentationRequest.explicitControl();
      final few = preference.freezeFor(explicit);
      expect(few.allowsContentFor(explicit), isTrue);
      await preference.save(UiPresentationMode.automatic);
      expect(automatic.allowsContentFor(ordinary), isFalse);
      expect(few.allowsContentFor(explicit), isFalse);
      expect(preference.freezeFor(ordinary).allowsPlanningFor(ordinary), isFalse);
      final freshOrdinary = UiPresentationRequest.ordinary();
      final current = preference.freezeFor(freshOrdinary);
      expect(current.allowsPlanningFor(freshOrdinary), isTrue);
      await preference.close();
      expect(current.allowsPlanningFor(freshOrdinary), isFalse);
    } finally {
      await preference.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });

  test('few ABA cannot refreeze an old explicit flag into a new allowed policy', () async {
    final root = Directory.systemTemp.createTempSync('aiui-request-replay-');
    final f = await _Fixture.open(root);
    final preference = UiPresentationPreference(f.repository);
    try {
      await preference.save(UiPresentationMode.few);
      final oldRequest = UiPresentationRequest.explicitControl();
      final oldPolicy = preference.freezeFor(oldRequest);
      expect(oldPolicy.allowsPlanningFor(oldRequest), isTrue);
      // The same current request may be checked by planning and rendering.
      expect(preference.freezeFor(oldRequest).allowsContentFor(oldRequest), isTrue);
      await preference.save(UiPresentationMode.textOnly);
      await preference.save(UiPresentationMode.few);
      final replay = preference.freezeFor(oldRequest);
      expect(oldPolicy.allowsPlanningFor(oldRequest), isFalse);
      expect(replay.allowsPlanningFor(oldRequest), isFalse);
      expect(replay.allowsContentFor(oldRequest), isFalse);
      final freshRequest = UiPresentationRequest.explicitControl();
      final freshPolicy = preference.freezeFor(freshRequest);
      expect(freshPolicy.allowsPlanningFor(freshRequest), isTrue);
      expect(freshPolicy.allowsContentFor(oldRequest), isFalse);
      expect(f.bytes(UiPresentationPreference.key), '"few"');
    } finally {
      await preference.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });

  test('bound request cannot move to another owner or revive after SQLite restart', () async {
    final root = Directory.systemTemp.createTempSync('aiui-request-owner-');
    var f = await _Fixture.open(root);
    var preference = UiPresentationPreference(f.repository);
    UiPresentationPreference? other;
    try {
      await preference.save(UiPresentationMode.few);
      final oldRequest = UiPresentationRequest.explicitControl();
      final oldPolicy = preference.freezeFor(oldRequest);
      other = UiPresentationPreference(f.repository);
      expect(other.mode, UiPresentationMode.few);
      // Both owners have one successful save; rejection must depend on owner.
      await other.save(UiPresentationMode.few);
      expect(other.freezeFor(oldRequest).allowsPlanningFor(oldRequest), isFalse);
      expect(oldPolicy.allowsPlanningFor(oldRequest), isTrue);
      await other.close();
      await preference.close();
      await f.close();
      f = await _Fixture.open(root);
      preference = UiPresentationPreference(f.repository);
      expect(preference.mode, UiPresentationMode.few);
      await preference.save(UiPresentationMode.few);
      expect(preference.freezeFor(oldRequest).allowsContentFor(oldRequest), isFalse);
      expect(oldPolicy.allowsContentFor(oldRequest), isFalse);
      final ordinary = UiPresentationRequest.ordinary();
      expect(preference.freezeFor(ordinary).allowsPlanningFor(ordinary), isFalse);
      final fresh = UiPresentationRequest.explicitControl();
      expect(preference.freezeFor(fresh).allowsContentFor(fresh), isTrue);
      expect(f.bytes(UiPresentationPreference.key), '"few"');
    } finally {
      await other?.close();
      await preference.close();
      await f.close();
      root.deleteSync(recursive: true);
    }
  });
}
