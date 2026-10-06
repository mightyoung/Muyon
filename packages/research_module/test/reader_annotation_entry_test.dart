import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:research_module/src/core/store.dart';
import 'package:research_module/src/reader/reader_page.dart';

void main() {
  late Directory temp;
  late WorkbenchStore store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('reader-annotate-');
    store = WorkbenchStore.open(temp.path);
    store.db.execute(
      'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
      ['project', 'Study', '', ''],
    );
    store.db.execute(
      'INSERT INTO documents(id,project_id,relative_path,snapshot_path) VALUES(?,?,?,?)',
      ['document', 'project', 'paper.md', 'paper.md'],
    );
  });
  tearDown(() {
    store.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: ReaderPage(
          store: store,
          document: store.documents('project').single,
          loadMarkdown: (_) async => '# Study\n\nEvidenceable sentence here.',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('新建批注 opens the notes form with the note focused at $width', (
      tester,
    ) async {
      await pump(tester, width);
      await tester.tap(find.byTooltip('新建批注'));
      await tester.pumpAndSettle();
      final note = tester.widget<TextField>(
        find.widgetWithText(TextField, '精读笔记 / 批注'),
      );
      expect(note.focusNode!.hasFocus, isTrue);
      expect(find.text('摘录并批注'), findsNothing, reason: 'nothing selected');
    });
  }

  testWidgets('selecting text offers 摘录并批注 and fills the quote', (
    tester,
  ) async {
    await pump(tester, 390);
    expect(find.text('摘录并批注'), findsNothing);
    final target = find.textContaining('Evidenceable', findRichText: true);
    await tester.longPressAt(tester.getTopLeft(target) + const Offset(12, 10));
    await tester.pumpAndSettle();
    expect(find.text('摘录并批注'), findsOneWidget);
    expect(find.textContaining('已选中'), findsOneWidget);
    await tester.tap(find.text('摘录并批注'));
    await tester.pumpAndSettle();
    final quote = tester.widget<TextField>(
      find.widgetWithText(TextField, '原文引句（可选）'),
    );
    expect(quote.controller!.text, isNotEmpty);
    expect(
      'Evidenceable sentence here.'.contains(quote.controller!.text),
      isTrue,
    );
    expect(find.text('保存笔记'), findsWidgets);
  });

  testWidgets('取消选择 hides the bar', (tester) async {
    await pump(tester, 390);
    final target = find.textContaining('Evidenceable', findRichText: true);
    await tester.longPressAt(tester.getTopLeft(target) + const Offset(12, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消选择'));
    await tester.pumpAndSettle();
    expect(find.text('摘录并批注'), findsNothing);
  });
}
