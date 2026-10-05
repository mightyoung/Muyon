import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/app_state.dart';
import 'package:inquiry_module/src/app/theme.dart';
import 'package:inquiry_module/src/features/records/open_record.dart';
import 'package:supplier_core/supplier_core.dart';

/// Found on an Android phone (360 dp): a project opened through openRecord
/// (e.g. right after "新建项目") used the desktop layout, which overflowed
/// and left the budget tab and its "添加物料" button at zero width.
void main() {
  testWidgets('a project opened on a phone uses the compact layout', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('open_record_layout');
    final store = Store.open('${dir.path}/library.db', device: '测试机');
    final state = AppState.test(store, dir);
    addTearDown(() {
      state.dispose();
      store.close();
      dir.deleteSync(recursive: true);
    });
    final project = store.save('project', {
      for (final f in Project.fields) f: null,
      'code': 'P-1',
      'name': 'Pump Station Retrofit',
      'status': 'active',
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
      'contract_amount': '1200000',
    });
    tester.view.physicalSize = const Size(1260, 2800);
    tester.view.devicePixelRatio = 3.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openRecord(context, state, 'project', project),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final add = find.text('添加物料');
    expect(add, findsWidgets);
    expect(tester.getSize(add.first).width, greaterThan(0));
  });
}
