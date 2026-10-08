import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

ConfirmItem item(ConfirmationKind kind) => ConfirmItem(
  kind: kind,
  what: '发送或修改需要核对的长内容',
  who: '项目与供应商对象名称',
  payload: '这是一段可以展开检查的完整发送内容，包括中文与 emoji 😀',
  digest: 'a1b2c3d4' * 16,
  consequence: '内容发出后无法撤回，请核对目的地与影响',
);
const states = [
  BusinessStatus.pending,
  BusinessStatus.confirmed,
  BusinessStatus.rejected,
  BusinessStatus.authorized,
  BusinessStatus.expired,
  BusinessStatus.scopeChanged,
  BusinessStatus.contentReview,
  BusinessStatus.blocked,
  BusinessStatus.externalContent,
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);
  for (final kind in ConfirmationKind.values) {
    for (final status in states) {
      testWidgets('$kind $status has exact v6 action tier', (tester) async {
        ConfirmationChoice? decision;
        await mount(
          tester,
          ConfirmCard(
            item: item(kind),
            status: status,
            onDecision: (v) => decision = v,
          ),
        );
        expect(find.text(status.label), findsOneWidget);
        for (final label in ['做什么', '对谁', '发送内容', '摘要散列', '后果'])
          expect(find.text(label), findsOneWidget);
        final active =
            [
              BusinessStatus.pending,
              BusinessStatus.expired,
              BusinessStatus.scopeChanged,
              BusinessStatus.contentReview,
              BusinessStatus.externalContent,
            ].contains(status) &&
            kind != ConfirmationKind.read;
        final expected = active
            ? switch (kind) {
                ConfirmationKind.write => ['仅这一次', '拒绝', '更多'],
                ConfirmationKind.outboundNew => ['仅发送这一次', '拒绝'],
                ConfirmationKind.outboundKnown => ['仅发送这一次', '本次对话允许', '拒绝'],
                ConfirmationKind.model => ['仅这一次', '本次对话允许发往此端点', '拒绝'],
                _ => <String>[],
              }
            : <String>[];
        if (status == BusinessStatus.contentReview ||
            status == BusinessStatus.externalContent)
          expected.remove('更多');
        if (status == BusinessStatus.externalContent) {
          expected.remove('本次对话允许');
          expected.remove('本次对话允许发往此端点');
        }
        final labels = tester
            .widgetList<TextButton>(find.byType(TextButton))
            .map((b) => (b.child as Text).data)
            .where((s) => s != '展开内容' && s != '收起内容')
            .toList();
        expect(labels, expected);
        expect(find.text('始终允许'), findsNothing);
        if (active) {
          await tester.ensureVisible(find.text('拒绝'));
          await tester.tap(find.text('拒绝'));
          expect(decision, ConfirmationChoice.reject);
        }
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      });
    }
  }
  for (final config in [
    for (final brightness in Brightness.values)
      for (final width in [320.0, 390.0, 1280.0])
        (brightness: brightness, width: width),
  ]) {
    final width = config.width;
    final brightness = config.brightness;
    testWidgets(
      'confirmation fields expand and grow at $width/200% $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(
            tester,
            ConfirmCard(item: item(ConfirmationKind.write), onDecision: (_) {}),
            width: width,
            brightness: brightness,
          );
          for (final button in tester.widgetList<TextButton>(
            find.byType(TextButton),
          )) {
            minimum(tester, find.byWidget(button));
          }
          await tester.tap(find.text('展开内容'));
          await tester.pump();
          expect(
            find.text(item(ConfirmationKind.write).payload),
            findsOneWidget,
          );
          expect(
            find.text(item(ConfirmationKind.write).digest),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('更多'));
          await tester.tap(find.text('更多'));
          await tester.pump();
          expect(find.text('本次任务'), findsOneWidget);
          expect(find.text('本次对话'), findsOneWidget);
          expect(find.text('始终允许'), findsOneWidget);
          for (final label in ['本次任务', '本次对话', '始终允许'])
            minimum(tester, find.bySemanticsLabel(label));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
    testWidgets(
      'batch and warn banner external-content restrictions $width/200% $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var all = 0, individual = 0, rejected = 0;
          await mount(
            tester,
            BatchConfirmCard(
              items: [
                item(ConfirmationKind.write),
                item(ConfirmationKind.outboundNew),
              ],
              externalContent: true,
              onAllowAll: () => all++,
              onIndividual: () => individual++,
              onReject: () => rejected++,
            ),
            width: width,
            brightness: brightness,
          );
          expect(find.text('全部允许'), findsNothing);
          expect(find.byType(WarnBanner), findsOneWidget);
          final byItem = find.bySemanticsLabel('逐项决定');
          minimum(tester, byItem);
          await tester.ensureVisible(byItem);
          await tester.tap(byItem);
          expect(individual, 1);
          await tester.ensureVisible(find.text('拒绝'));
          await tester.tap(find.text('拒绝'));
          expect(rejected, 1);
          expect(all, 0);
          await mount(
            tester,
            BatchConfirmCard(
              items: [item(ConfirmationKind.write)],
              onAllowAll: () => all++,
            ),
            width: width,
            brightness: brightness,
          );
          await tester.tap(find.text('全部允许'));
          expect(all, 1);
          await mount(
            tester,
            WarnBanner(actionLabel: '查看暂停的授权', onAction: () => individual++),
            width: width,
            brightness: brightness,
          );
          expect(find.bySemanticsLabel('本任务包含外部内容，已暂停自动放行'), findsOneWidget);
          minimum(tester, find.bySemanticsLabel('查看暂停的授权'));
          await tester.tap(find.text('查看暂停的授权'));
          expect(individual, 2);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  }
  testWidgets('completed batch is read-only', (tester) async {
    await mount(
      tester,
      BatchConfirmCard(
        items: [item(ConfirmationKind.write)],
        state: BatchState.completed,
        onAllowAll: () {},
      ),
    );
    expect(find.text('已决定'), findsOneWidget);
    expect(find.text('全部允许'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
  for (final kind in [
    ConfirmationKind.write,
    ConfirmationKind.outboundKnown,
    ConfirmationKind.model,
  ]) {
    for (final status in [
      BusinessStatus.pending,
      BusinessStatus.expired,
      BusinessStatus.contentReview,
    ]) {
      testWidgets(
        'external task flag restricts $kind $status to one-time decision',
        (tester) async {
          ConfirmationChoice? result;
          await mount(
            tester,
            ConfirmCard(
              item: item(kind),
              status: status,
              externalContent: true,
              onDecision: (choice) => result = choice,
            ),
          );
          expect(find.text('更多'), findsNothing);
          expect(find.text('本次对话允许'), findsNothing);
          expect(find.text('本次对话允许发往此端点'), findsNothing);
          expect(find.byType(WarnBanner), findsOneWidget);
          final once = kind == ConfirmationKind.outboundKnown
              ? '仅发送这一次'
              : '仅这一次';
          await tester.ensureVisible(find.text(once));
          await tester.tap(find.text(once));
          expect(
            result,
            kind == ConfirmationKind.outboundKnown
                ? ConfirmationChoice.sendOnce
                : ConfirmationChoice.once,
          );
          await tester.binding.setSurfaceSize(null);
        },
      );
    }
  }
}
