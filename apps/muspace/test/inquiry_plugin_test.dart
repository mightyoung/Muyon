import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muspace/app/app_shell.dart';
import 'package:muspace/app/bootstrap.dart';
import 'package:supplier_core/supplier_core.dart';

void main() {
  test(
    'Folio uses host dataset, queued same handle, persistence and shutdown',
    () async {
      final root = Directory.systemTemp.createTempSync('muspace-inquiry-');
      var host = await MuSpaceHost.open(root.path);
      try {
        await Future.wait([host.activateInquiry(), host.activateInquiry()]);
        expect(host.inquiryError, isNull);
        final store = host.inquiry!.runtime.state.store;
        final saved = store.save('supplier', {
          for (final field in Supplier.fields) field: null,
          'name': '迁入供应商',
          'aliases': <String>[],
          'categories': <String>[],
        });
        final result = await store.inBackground((background) {
          expect(identical(background.db, store.db), isTrue);
          return background.db
              .select('SELECT count(*) n FROM supplier')
              .single['n'];
        });
        expect(result, 1);
        expect(host.inquiry!.runtime.state.lan, isNull);
        expect(
          File('${root.path}/modules/inquiry/files/supplier.db').existsSync(),
          isFalse,
        );
        await host.close();
        host = await MuSpaceHost.open(root.path);
        await host.activateInquiry();
        expect(host.inquiryError, isNull);
        expect(
          host.inquiry!.runtime.state.store
              .get('supplier', saved)!
              .data['name'],
          '迁入供应商',
        );
        expect(host.inquiry!.runtime.state.aiTasks, isEmpty);
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  testWidgets('platform opens the complete Folio module with one MaterialApp', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('muspace-inquiry-ui-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuSpaceHost.open(root.path)))!;
    try {
      await tester.runAsync(() => host.activateInquiry());
      await tester.pumpWidget(MuSpaceApp(host: host));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.tap(find.text('Folio · 询价台账'));
      await tester.pumpAndSettle();
      expect(find.byType(InquiryHome), findsOneWidget);
      expect(find.text('MuSpace · Folio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
