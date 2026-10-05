import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/src/app/lan_transfer_page.dart';
import 'package:research_module/src/app/workbench_app.dart';
import 'package:research_module/src/core/store.dart';

void main() {
  late Directory temp;
  late WorkbenchStore store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('hosted-lan-');
    store = WorkbenchStore.open(p.join(temp.path, 'app'));
  });
  tearDown(() {
    store.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester, {required bool hosted}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ResearchHome(store: store, projectId: 'unbound', hosted: hosted),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('hosted workbench has no LAN transfer entry or page', (
    tester,
  ) async {
    await pumpHome(tester, hosted: true);
    expect(find.byTooltip('局域网传输'), findsNothing);
    expect(find.byIcon(Icons.wifi_tethering_outlined), findsNothing);
    expect(find.byType(LanTransferPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone workbench keeps its LAN transfer entry', (
    tester,
  ) async {
    await pumpHome(tester, hosted: false);
    expect(find.byTooltip('局域网传输'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
