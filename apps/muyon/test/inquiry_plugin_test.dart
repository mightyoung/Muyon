import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:supplier_core/supplier_core.dart';

import 'support/conversation_workspace_fixture.dart';

void main() {
  test(
    'Folio uses host dataset, queued same handle, persistence and shutdown',
    () async {
      final root = Directory.systemTemp.createTempSync('muyon-inquiry-');
      var host = await MuyonHost.open(root.path);
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
        host = await MuyonHost.open(root.path);
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
    final root = Directory.systemTemp.createTempSync('muyon-inquiry-ui-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.runAsync(() => host.activateInquiry());
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('资料')));
      await tester.pumpAndSettle();
      final entry = find.widgetWithText(ListTile, 'Folio · 询价台账');
      final dataScroll = find.descendant(of: find.byType(ListView), matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ));
      expect(dataScroll, findsOneWidget);
      await tester.scrollUntilVisible(entry, 100, scrollable: dataScroll);
      await tester.pumpAndSettle();
      expect(entry.hitTestable(), findsOneWidget);
      await workspaceOperation(tester, () => tester.tap(entry.hitTestable()));
      await workspaceVisible(tester, find.byType(InquiryHome));
      expect(find.byType(InquiryHome), findsOneWidget);
      expect(find.text('Muyon · Folio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
