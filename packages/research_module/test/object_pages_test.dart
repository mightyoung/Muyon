import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:research_module/research_module.dart';

/// Read-only research object pages: every page renders its title, stale
/// revisions say so, and an unassessed run has no assessment section.
void main() {
  Widget page(Widget body) => MaterialApp(
    theme: muyonTheme(Brightness.light),
    home: Scaffold(body: body),
  );

  testWidgets('entry page shows kind, title, body and source', (tester) async {
    await tester.pumpWidget(
      page(
        ResearchEntryPage(
          entry: ResearchEntry(
            id: 'e1',
            projectId: 'p1',
            kind: 'claims',
            title: '主张标题',
            data: {'statement': '正文陈述', 'source': '论文 A'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('主张标题'), findsOneWidget);
    expect(find.textContaining('主张'), findsWidgets);
    expect(find.text('正文陈述'), findsOneWidget);
    expect(find.text('论文 A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outline page shows heading, owning section and content', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        const ResearchOutlinePage(
          heading: '提纲标题',
          sectionHeading: '段落一',
          content: '来源 · 论文 A',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('提纲标题'), findsOneWidget);
    expect(find.text('段落一'), findsOneWidget);
    expect(find.text('来源 · 论文 A'), findsOneWidget);
  });

  testWidgets('section page shows heading, outline and argument', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        const ResearchSectionPage(
          heading: '段落一',
          projectTitle: '项目甲',
          argument: '论述内容',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('段落一'), findsOneWidget);
    expect(find.text('项目甲'), findsOneWidget);
    expect(find.text('论述内容'), findsOneWidget);
  });

  testWidgets('task page shows title, revision, status and goal', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        ResearchTaskPage(
          task: const ResearchTask(
            id: 't1',
            projectId: 'p1',
            title: '任务标题',
            goal: '任务说明',
            revision: 2,
            spec: {},
          ),
          latestRunStatus: 'completed',
          isLatestRevision: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('任务标题'), findsOneWidget);
    expect(find.text('r2'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('任务说明'), findsOneWidget);
    expect(find.text('不是最新修订'), findsNothing);
  });

  testWidgets('task page marks an older revision', (tester) async {
    await tester.pumpWidget(
      page(
        ResearchTaskPage(
          task: const ResearchTask(
            id: 't1',
            projectId: 'p1',
            title: '任务标题',
            goal: '',
            revision: 1,
            spec: {},
          ),
          isLatestRevision: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('不是最新修订'), findsOneWidget);
  });

  testWidgets('run page shows task, revision, status and assessment', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        ResearchRunPage(
          run: ResearchRun(
            id: 'r1',
            taskId: 't1',
            status: 'completed',
            taskRevision: 2,
            accepted: true,
            data: const {
              'workbench_assessment': {
                'result': 'supporting',
                'discriminating': true,
                'reason': '证据一致',
              },
            },
          ),
          taskTitle: '任务标题',
          isLatestRevision: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('任务标题'), findsWidgets);
    expect(find.text('r2'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('已接纳为证据'), findsOneWidget);
    expect(find.textContaining('支持'), findsOneWidget);
    expect(find.textContaining('证据一致'), findsOneWidget);
  });

  testWidgets('run page without an assessment has no assessment section', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        ResearchRunPage(
          run: ResearchRun(
            id: 'r1',
            taskId: 't1',
            status: 'failed',
            taskRevision: 1,
            accepted: false,
            data: const {},
          ),
          taskTitle: '任务标题',
          isLatestRevision: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('评价'), findsNothing);
    expect(find.text('研究结论'), findsNothing);
    expect(find.text('不是最新修订'), findsOneWidget);
  });

  testWidgets('card page shows body, revision and citations', (tester) async {
    await tester.pumpWidget(
      page(
        const ResearchCardPage(
          bodyMarkdown: '# 卡片标题\n\n正文内容',
          revisionId: 'rev-2',
          citations: ['c1 · document doc-1 · 第2页 · “引用”'],
          isLatestRevision: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('卡片标题'), findsOneWidget);
    expect(find.textContaining('正文内容'), findsOneWidget);
    expect(find.text('rev-2'), findsOneWidget);
    expect(find.textContaining('doc-1'), findsOneWidget);
    expect(find.text('不是最新修订'), findsNothing);
  });

  testWidgets('card page marks an older revision', (tester) async {
    await tester.pumpWidget(
      page(
        const ResearchCardPage(
          bodyMarkdown: '',
          revisionId: 'rev-1',
          citations: [],
          isLatestRevision: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('研究卡'), findsOneWidget);
    expect(find.text('不是最新修订'), findsOneWidget);
  });
}
