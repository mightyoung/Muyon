import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui_preview/subconversation_preview.dart';
import 'package:muyon_ui_preview/workspace_store.dart';

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'public child close and explicit latest retain immutable history at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final values = <String, String>{};
        final store = FixtureWorkspaceStore(
          read: (key) => values[key],
          write: (key, value) {
            values[key] = value;
          },
        );
        await tester.pumpWidget(
          MaterialApp(home: SubconversationPreview(store: store)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('查询最新'));
        await tester.pumpAndSettle();
        expect(find.textContaining('只读历史引用：子成果 v1'), findsOneWidget);
        await tester.tap(find.text('打开子对话'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '公开待发问题');
        await tester.tap(find.text('模拟子成果更新'));
        await tester.pump();
        await tester.tap(find.text('保存并关闭'));
        await tester.pumpAndSettle();
        expect(find.textContaining('只读历史引用：子成果 v2'), findsNothing);
        await tester.tap(find.text('查询最新'));
        await tester.pumpAndSettle();
        expect(find.textContaining('只读历史引用：子成果 v1'), findsOneWidget);
        expect(find.textContaining('只读历史引用：子成果 v2'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(
            home: SubconversationPreview(
              key: const ValueKey('reload'),
              store: store,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开子对话'));
        await tester.pumpAndSettle();
        expect(find.text('公开待发问题'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
