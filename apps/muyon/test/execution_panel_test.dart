import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/execution_panel.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

/// E7 acceptance: durable assistant-task records with goal, stage, device,
/// wait reason, error, result and object references; actions appear only in
/// states that actually support them.
void main() {
  late Directory tmp;
  late MuyonHost host;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('execution-panel-');
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

  Map<String, Object?> payload({
    required String id,
    required PersonalTaskState state,
    String prompt = '整理本周询价结果',
    String stage = 'queued',
    String device = 'device-1',
    String? waitingFor,
    String? error,
    String? summary,
    String? owner,
    List<ObjectRef> refs = const [],
  }) => {
    'kind': 'personal',
    'executionId': id,
    'conversationId': 'conversation-$id',
    'prompt': prompt,
    'state': state.name,
    'stage': stage,
    'executionDeviceId': device,
    'scope': const AssistantScope.global().toJson(),
    'updatedAt': DateTime.utc(2026, 10, 5, 12).toIso8601String(),
    'references': [for (final ref in refs) ref.toJson()],
    'waitingFor': ?waitingFor,
    'error': ?error,
    'summary': ?summary,
    'owner': ?owner,
  };

  Future<void> addTask(
    WidgetTester tester,
    String id,
    PersonalTaskState state, {
    String? waitingFor,
    String? error,
    String? summary,
    String? owner,
    String stage = 'queued',
    List<ObjectRef> refs = const [],
  }) => tester.runAsync(
    () => host.workspaces.database.write(
      (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
        id,
        state.name,
        jsonEncode(
          payload(
            id: id,
            state: state,
            waitingFor: waitingFor,
            error: error,
            summary: summary,
            owner: owner,
            stage: stage,
            refs: refs,
          ),
        ),
      ]),
    ),
  );

  Widget page({
    double scale = 1,
    List<String>? cancelled,
    List<String>? paused,
    List<String>? resumed,
    List<ObjectRef>? opened,
  }) => MaterialApp(
    theme: muyonTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: ExecutionPanel(
        tasks: host.foundation.tasks(),
        onCancel: (task) async => cancelled?.add(task.id),
        onPause: (task) async => paused?.add(task.id),
        onResume: (task) async => resumed?.add(task.id),
        onOpenObject: (ref) => opened?.add(ref),
      ),
    ),
  );

  void resize(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  const reference = ObjectRef(
    moduleId: 'inquiry',
    objectType: 'supplier',
    objectId: 'supplier-1',
    nativeProjectId: 'project-1',
  );

  testWidgets('shows goal, stage, device, wait reason, error and result', (
    tester,
  ) async {
    resize(tester, 1280);
    await open(tester);
    await addTask(
      tester,
      'waiting',
      PersonalTaskState.waitingConfirmation,
      waitingFor: '确认工具操作',
    );
    await addTask(
      tester,
      'failed',
      PersonalTaskState.failed,
      error: '工具参数、可用性或范围校验未通过',
    );
    await addTask(
      tester,
      'done',
      PersonalTaskState.succeeded,
      summary: '已列出 3 家供应商',
      refs: const [reference],
    );
    final opened = <ObjectRef>[];
    await tester.pumpWidget(page(opened: opened));
    await tester.pumpAndSettle();

    expect(find.text('整理本周询价结果'), findsNWidgets(3));
    expect(find.textContaining('等待 确认工具操作'), findsOneWidget);
    expect(find.textContaining('错误 工具参数、可用性或范围校验未通过'), findsOneWidget);
    expect(find.textContaining('结果 已列出 3 家供应商'), findsOneWidget);
    expect(find.textContaining('设备 device-1'), findsNWidgets(3));
    expect(find.textContaining('阶段'), findsWidgets);
    expect(find.text('等待你确认'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);

    await tester.tap(find.text('inquiry · supplier'));
    await tester.pumpAndSettle();
    expect(opened, [reference]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions follow the actual task state', (tester) async {
    resize(tester, 1280);
    await open(tester);
    final cases = <PersonalTaskState, (List<String>, List<String>)>{
      PersonalTaskState.queued: (['取消'], ['暂停', '恢复']),
      PersonalTaskState.waitingConfirmation: (['取消', '暂停'], ['恢复']),
      PersonalTaskState.paused: (['恢复'], ['取消', '暂停']),
      PersonalTaskState.interrupted: (['恢复'], ['取消', '暂停']),
      PersonalTaskState.failed: (['恢复'], ['取消', '暂停']),
      PersonalTaskState.succeeded: ([], ['取消', '暂停', '恢复']),
      PersonalTaskState.cancelled: ([], ['取消', '暂停', '恢复']),
    };
    for (final entry in cases.entries) {
      await tester.runAsync(
        () => host.workspaces.database.write(
          (db) => db.execute('DELETE FROM execution_records'),
        ),
      );
      await addTask(tester, 'task-${entry.key.name}', entry.key);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      Finder button(String label) => label == '恢复'
          ? find.widgetWithText(FilledButton, '恢复（再次确认）')
          : find.widgetWithText(OutlinedButton, label);
      for (final label in entry.value.$1) {
        expect(
          button(label),
          findsOneWidget,
          reason: '${entry.key.name} 应显示 $label',
        );
      }
      for (final label in entry.value.$2) {
        expect(
          button(label),
          findsNothing,
          reason: '${entry.key.name} 不应显示 $label',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancel request in flight shows 取消中… and no second cancel', (
    tester,
  ) async {
    resize(tester, 390);
    await open(tester);
    await addTask(
      tester,
      'task-cancelling',
      PersonalTaskState.running,
      stage: 'cancelling',
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('取消中…'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '取消'), findsNothing);
  });

  testWidgets('interrupted states say the outcome is unknown', (tester) async {
    resize(tester, 390);
    await open(tester);
    await addTask(tester, 'interrupted', PersonalTaskState.interrupted);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('已中断（结果未知）'), findsOneWidget);
    expect(find.textContaining('结果未知，重试前请先核实'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform-owned tasks offer no per-item actions', (tester) async {
    resize(tester, 390);
    await open(tester);
    await addTask(
      tester,
      'platform',
      PersonalTaskState.running,
      owner: 'platform',
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.textContaining('平台任务'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '取消'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '暂停'), findsNothing);
    expect(find.widgetWithText(FilledButton, '恢复（再次确认）'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons call back with the exact task', (tester) async {
    resize(tester, 1280);
    await open(tester);
    await addTask(tester, 'waiting', PersonalTaskState.waitingConfirmation);
    await addTask(tester, 'paused', PersonalTaskState.paused);
    final cancelled = <String>[];
    final paused = <String>[];
    final resumed = <String>[];
    await tester.pumpWidget(
      page(cancelled: cancelled, paused: paused, resumed: resumed),
    );
    await tester.pumpAndSettle();

    // Cancel belongs to the waiting task; resume to the paused one.
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '暂停'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '恢复（再次确认）'));
    await tester.pumpAndSettle();
    expect(cancelled, ['waiting']);
    expect(paused, ['waiting']);
    expect(resumed, ['paused']);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('renders at $width and 200% text', (tester) async {
      resize(tester, width);
      await open(tester);
      await addTask(
        tester,
        'waiting',
        PersonalTaskState.waitingConfirmation,
        waitingFor: '确认向所选端点发送以下内容',
      );
      await addTask(
        tester,
        'failed',
        PersonalTaskState.failed,
        error: '模型请求被拒绝或失败时不会保存答案',
        refs: const [reference],
      );
      await addTask(
        tester,
        'interrupted',
        PersonalTaskState.interrupted,
        summary: '一段较长的结果摘要，用于验证文字放大后的换行与按钮重排不会溢出。',
        refs: const [reference],
      );
      await tester.pumpWidget(page(scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
