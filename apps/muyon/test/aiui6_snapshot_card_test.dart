import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/inquiry_snapshots/inquiry_readonly_snapshot.dart';
import 'package:muyon/assistant/inquiry_snapshots/inquiry_snapshot_card.dart';
import 'package:muyon/assistant/ontology_cards/ontology_card.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/aiui6_snapshot_fixture.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('real read-only inquiry snapshots render at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      InquirySnapshotFixture? fixture;
      try {
        fixture = (await tester.runAsync(InquirySnapshotFixture.open))!;
        final scenes = <(String, InquiryReadonlyScene)>[
          ('inquiry', InquiryReadonlyScene.inquiry),
          ('quotation', InquiryReadonlyScene.quote),
          ('project_item', InquiryReadonlyScene.budgetLine),
        ];

        for (final (key, scene) in scenes) {
          final ref = fixture.refs[key] ??
              (throw StateError('Missing fixture reference: $key'));
          final snapshot = await tester.runAsync(
            () => InquiryReadonlySnapshots.read(
              host: fixture.host,
              scope: AssistantScope.selectedObjects([ref]),
              object: ref,
              suggestions: const {
                'name': '建议预算行',
                'unit_cost': 'MODEL-PRICE',
              },
            ),
          );

          expect(snapshot!.scene, scene);
          final sourceLabel =
              '来源对象 inquiry/${ref.objectType}/${ref.objectId} · 修订 ${ref.revisionRef}';
          final revisionLabel = '保存快照 · 修订 ${ref.revisionRef}';
          await tester.pumpWidget(MaterialApp(
            theme: muyonTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: InquirySnapshotCard(snapshot: snapshot),
              ),
            ),
          ));
          for (final label in [
            '${scene.label} · 已保存事实',
            sourceLabel,
            revisionLabel,
          ]) {
            expect(find.text(label), findsOneWidget);
            expect(
              find.bySemanticsLabel(RegExp(RegExp.escape(label))),
              findsOneWidget,
            );
          }
          expect(
            find.text('来源：询价插件的已保存记录；建议尚未写入'),
            findsOneWidget,
          );
          expect(find.byType(OntologyCard), findsOneWidget);
          expect(find.byType(KeyValue), findsOneWidget);
          if (scene == InquiryReadonlyScene.budgetLine) {
            for (final label in [
              '真实预算行',
              '建议预算行',
              '名称 · 建议（尚未写入）',
            ]) {
              expect(find.text(label), findsOneWidget);
              expect(
                find.bySemanticsLabel(RegExp(RegExp.escape(label))),
                findsOneWidget,
              );
            }
          }
          for (final secret in [
            'MODEL-PRICE',
            '987654.123',
            '123456.789',
            '张三',
          ]) {
            expect(find.text(secret), findsNothing);
            expect(
              find.bySemanticsLabel(RegExp(RegExp.escape(secret))),
              findsNothing,
            );
          }
          expect(find.byType(FilledButton), findsOneWidget);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          await tester.pumpAndSettle();
        }
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async => fixture?.close());
      }
    });
  }
}
