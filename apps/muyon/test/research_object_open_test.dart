import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/object_pages.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

/// The shell's openObject goes through the module session's objectPage for
/// research objects, keeps the reader + assistant layout for documents, falls
/// back to the JSON page when nothing matches, and disposes the session after
/// the page closes.
void main() {
  late Directory tmp;
  late MuyonHost host;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('research-open-');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    host = (await tester.runAsync(
      () => MuyonHost.open(p.join(tmp.path, 'data')),
    ))!;
    addTearDown(() async {
      await tester.runAsync(() => host.close());
    });
  }

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await host.activateInquiry();
      await host.activateResearch();
      final store = host.research!.store;
      store.db.execute(
        "INSERT INTO projects(id,title,question,next_step,layout,skill_root) "
        "VALUES('p1','项目甲','','','generic','')",
      );
      final docs = Directory(p.join(store.rootPath, 'docs'))
        ..createSync(recursive: true);
      const content = '# 论文标题\n\n论文正文';
      File(p.join(docs.path, 'paper.md')).writeAsStringSync(content);
      final digest = sha256.convert(utf8.encode(content)).toString();
      store.db.execute(
        "INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) "
        "VALUES('d1','p1','paper.md','docs/paper.md','$digest')",
      );
      store.db.execute(
        "INSERT INTO entries(id,project_id,kind,title,data) "
        "VALUES('e1','p1','claims','主张标题','{\"statement\":\"正文陈述\",\"source\":\"论文A\"}')",
      );
      // A second project without a workspace binding, for the fallback test.
      store.db.execute(
        "INSERT INTO projects(id,title,question,next_step,layout,skill_root) "
        "VALUES('p2','项目乙','','','generic','')",
      );
      store.db.execute(
        "INSERT INTO entries(id,project_id,kind,title,data) "
        "VALUES('e2','p2','claims','无绑定标题','{\"statement\":\"不应显示\"}')",
      );
      final workspace = await host.workspaces.create('W');
      await host.workspaces.bind(
        WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'research',
          nativeProjectId: 'p1',
        ),
      );
    });
  }

  Future<void> addTaskRef(WidgetTester tester, String id, ObjectRef ref) =>
      tester.runAsync(
        () => host.workspaces.database.write(
          (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
            id,
            'queued',
            jsonEncode({
              'kind': 'personal',
              'executionId': id,
              'conversationId': 'conversation-$id',
              'prompt': '查看对象',
              'state': 'queued',
              'stage': 'queued',
              'executionDeviceId': 'device-1',
              'scope': const AssistantScope.global().toJson(),
              'updatedAt': DateTime.utc(2026, 10, 6).toIso8601String(),
              'references': [ref.toJson()],
            }),
          ]),
        ),
      );

  Widget shell() => MaterialApp(
    home: PlatformShell(
      host: host,
      themeMode: ThemeMode.light,
      onTheme: (_) {},
      onRestore: (_) async {},
    ),
  );

  void resize(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Bounded pumping that tolerates pages which keep a loading indicator
  /// (a reader may keep loading, so pumpAndSettle would never return).
  Future<void> pumpFrames(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The shell resolves the reference and activates modules on the real event
  /// loop; poll with plain pumps until the pushed page shows up (a reader may
  /// keep loading indicators, so no pumpAndSettle here).
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int rounds = 60,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  Future<void> closePage(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openFromPanel(WidgetTester tester, String tile) async {
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('执行面板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tile));
    // The pushed page may keep a loading indicator (the reader does), so pump
    // a bounded number of frames instead of pumpAndSettle here.
    await pumpFrames(tester);
  }

  ObjectRef entryRef([String id = 'e1']) => ObjectRef(
    moduleId: 'research',
    objectType: 'entry',
    objectId: id,
    nativeProjectId: 'p1',
  );

  testWidgets('openObject shows the research entry page, not JSON', (
    tester,
  ) async {
    resize(tester, 390);
    await open(tester);
    await seed(tester);
    final spy = _RecordingRuntime(host.research!.resources);
    host.research = spy;
    await addTaskRef(tester, 'task-entry', entryRef());

    await openFromPanel(tester, 'research · entry');
    await waitFor(tester, find.text('主张标题'));

    // The app bar title and the page heading both show it.
    expect(find.text('主张标题'), findsWidgets);
    expect(find.text('正文陈述'), findsOneWidget);
    expect(find.text('论文A'), findsOneWidget);
    expect(find.textContaining('"moduleId"'), findsNothing);
    expect(tester.takeException(), isNull);

    await closePage(tester);

    // The shell disposed the session it opened for this page (review F3).
    expect(spy.sessions, hasLength(1));
    await expectLater(
      spy.sessions.single.resolve(entryRef()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Session disposed',
        ),
      ),
    );
  });

  testWidgets('openObject keeps the reader and assistant for documents', (
    tester,
  ) async {
    resize(tester, 1280);
    await open(tester);
    await seed(tester);
    const docRef = ObjectRef(
      moduleId: 'research',
      objectType: 'document',
      objectId: 'd1',
      nativeProjectId: 'p1',
    );
    final spy = _RecordingRuntime(host.research!.resources);
    host.research = spy;
    await addTaskRef(tester, 'task-doc', docRef);

    await openFromPanel(tester, 'research · document');
    await waitFor(tester, find.byType(ReaderPage));

    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await closePage(tester);

    // The shell disposed the session it opened for this page (review F3).
    expect(spy.sessions, hasLength(1));
    await expectLater(
      spy.sessions.single.resolve(docRef),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Session disposed',
        ),
      ),
    );
  });

  testWidgets('openObject shows the research task page for task refs', (
    tester,
  ) async {
    resize(tester, 390);
    await open(tester);
    await seed(tester);
    await tester.runAsync(() async {
      host.research!.store.db.execute(
        "INSERT INTO tasks(id,revision,project_id,title,goal,spec) "
        "VALUES('t1',1,'p1','任务甲','任务目标','{}')",
      );
    });
    await addTaskRef(
      tester,
      'task-task',
      const ObjectRef(
        moduleId: 'research',
        objectType: 'task',
        objectId: 't1',
        nativeProjectId: 'p1',
      ),
    );

    await openFromPanel(tester, 'research · task');
    await waitFor(tester, find.byType(ResearchTaskPage));

    expect(find.byType(ResearchTaskPage), findsOneWidget);
    expect(find.text('任务甲'), findsWidgets);
    expect(find.text('r1'), findsOneWidget);
    expect(find.textContaining('"moduleId"'), findsNothing);
    expect(tester.takeException(), isNull);

    await closePage(tester);
  });

  testWidgets('an object without a binding falls back to the JSON page', (
    tester,
  ) async {
    resize(tester, 390);
    await open(tester);
    await seed(tester);
    // Entry e2 lives in project p2, which has no workspace binding.
    await addTaskRef(
      tester,
      'task-unbound',
      const ObjectRef(
        moduleId: 'research',
        objectType: 'entry',
        objectId: 'e2',
        nativeProjectId: 'p2',
      ),
    );

    await openFromPanel(tester, 'research · entry');
    await waitFor(tester, find.textContaining('"moduleId"'));

    expect(find.textContaining('"moduleId"'), findsOneWidget);
    expect(find.text('无绑定标题'), findsNothing);
    expect(tester.takeException(), isNull);

    await closePage(tester);
  });

  testWidgets('the helper returns null without a binding and disposes', (
    tester,
  ) async {
    await open(tester);
    await seed(tester);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    // No binding for this project: no page, caller keeps the JSON fallback.
    final unbound = await tester.runAsync(
      () => openModuleObjectPage(
        context,
        host,
        const ObjectRef(
          moduleId: 'research',
          objectType: 'entry',
          objectId: 'e1',
          nativeProjectId: 'other-project',
        ),
      ),
    );
    expect(unbound, isNull);

    final opened = (await tester.runAsync(
      () => openModuleObjectPage(context, host, entryRef()),
    ))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: opened.page)));
    await tester.pumpAndSettle();
    expect(find.text('主张标题'), findsOneWidget);

    await tester.runAsync(opened.dispose);
    await expectLater(opened.session.resolve(entryRef()), throwsStateError);

    // A deleted object resolves to nothing, so the caller falls back to JSON.
    await tester.runAsync(() async {
      host.research!.store.db.execute("DELETE FROM entries WHERE id='e1'");
    });
    final deleted = await tester.runAsync(
      () => openModuleObjectPage(context, host, entryRef()),
    );
    expect(deleted, isNull);
  });
}

/// Captures the sessions the shell opens, so tests can prove they are
/// disposed after the object page closes (review F3).
class _RecordingRuntime extends ResearchRuntime {
  _RecordingRuntime(super.resources);
  final List<ResearchSession> sessions = [];

  @override
  Future<ResearchSession> openSession(WorkspaceBinding binding) async {
    final session = await super.openSession(binding);
    sessions.add(session);
    return session;
  }
}
