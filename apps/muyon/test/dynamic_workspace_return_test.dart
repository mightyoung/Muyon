import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart';

void main() {
  LiveTestWidgetsFlutterBinding();
  late Directory root;
  late StorageManager storage;
  late FoundationRepository repo;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('ui3b-return-');
    storage = StorageManager(root.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    await repo.database.write(
      (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
        'task',
        'paused',
        jsonEncode({
          'kind': 'personal',
          'executionId': 'task',
          'scope': AssistantScope.workspace('w1').toJson(),
        }),
      ]),
    );
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });
  testWidgets('edited_value_survives_patch_reload_and_back on real SQLite', (
    tester,
  ) async {
    final plan = actionPlan();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DynamicWorkspace(
                  repository: repo,
                  taskId: 'task',
                  surfaceId: plan.plan.surfaceId,
                  plan: plan,
                  originalAnswer: 'Original answer',
                ),
              ),
            ),
            child: const Text('Open workspace'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open workspace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '13');
    await tester.pumpAndSettle();
    final c = tester
        .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
        .controller;
    await c.flush();
    await tester.tap(find.byTooltip('返回'));
    await c.flush();
    await tester.pumpAndSettle();
    expect(find.text('Open workspace'), findsOneWidget);
    await tester.tap(find.text('Open workspace'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '13',
    );
    expect(find.text('Original answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final reopened = tester
        .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
        .controller;
    await reopened.flush();
    await tester.pumpWidget(const SizedBox());
    await storage.close();
  });
}
