import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);
  TestWidgetsFlutterBinding.ensureInitialized();
  final samples = <String, Widget Function()>{
    'page': () => PageScaffold(
      title: '项目内容',
      description: '完整说明',
      state: PageState.error,
      onAction: () {},
    ),
    'master_detail': () =>
        const MasterDetail(master: Text('主列表'), detail: Text('详情内容')),
    'status': () => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final status in [
          BusinessStatus.pending,
          BusinessStatus.success,
          BusinessStatus.failed,
          BusinessStatus.warning,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StatusBadge(status: status),
          ),
      ],
    ),
    'object': () => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObjectChip(label: '项目 · 华东泵站', onPressed: () {}),
        const ObjectChip(label: '旧报价', missing: true),
      ],
    ),
    'segmented': () => SegmentedPill(
      labels: const ['全部', '当前项目', '归档'],
      selected: 1,
      onChanged: (_) {},
    ),
    'rail': () => IconRail(selected: 2, onChanged: (_) {}),
    'bottom': () => BottomIconBar(selected: 2, onChanged: (_) {}),
    'confirm': () => ConfirmCard(
      item: const ConfirmItem(
        kind: ConfirmationKind.outboundKnown,
        what: '发送询价单',
        who: '云川 · cloud.example/rfq',
        payload: '完整发送内容',
        digest:
            '6f9b4e20c134a87b6f9b4e20c134a87b6f9b4e20c134a87b6f9b4e20c134a87b',
        consequence: '内容发出后无法撤回',
      ),
      onDecision: (_) {},
    ),
    'batch': () => BatchConfirmCard(
      items: const [
        ConfirmItem(
          kind: ConfirmationKind.write,
          what: '新增询价单',
          who: '当前项目',
          payload: '',
          digest: '',
          consequence: '',
        ),
        ConfirmItem(
          kind: ConfirmationKind.outboundNew,
          what: '发送询价单',
          who: '云川',
          payload: '',
          digest: '',
          consequence: '',
        ),
      ],
      externalContent: true,
      onIndividual: () {},
      onReject: () {},
    ),
    'warn': () => WarnBanner(actionLabel: '查看暂停的授权', onAction: () {}),
    'scope': () => const ScopeChip(label: '选中 2 个对象', objects: ['论文', '报价']),
    'dialog': () => MuyonDialog(
      title: '确认删除对象',
      message: '删除后可以在回收站恢复，请核对范围。',
      confirmLabel: '确认删除',
      onConfirm: () {},
    ),
    'toast': () => MuyonToast(
      message: '操作已完成，请核对结果',
      actionLabel: '查看结果',
      onAction: () {},
    ),
    'round_button': () => RoundIconButton(
      label: '创建',
      icon: Icons.add,
      filled: true,
      onPressed: () {},
    ),
    'title': () => TitlePill(label: '插件菜单', onPressed: () {}),
  };

  for (final brightness in Brightness.values) {
    for (final config in [
      (width: 390.0, scale: 1.0, height: 1000.0, suffix: ''),
      (width: 320.0, scale: 2.0, height: 1600.0, suffix: '_320_200'),
    ]) {
      for (final entry in samples.entries) {
        testWidgets('v6 ${brightness.name} ${entry.key}${config.suffix}', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(
            Size(config.width, config.height),
          );
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: muyonTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(config.scale)),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const ValueKey('golden'),
                  child: Scaffold(
                    body: SafeArea(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: entry.value(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('golden')),
              matchesGoldenFile(
                'goldens/${brightness.name}_${entry.key}${config.suffix}.png',
              ),
            );
          } finally {
            await tester.binding.setSurfaceSize(null);
          }
        }, skip: !Platform.isMacOS);
      }
    }
  }
}
