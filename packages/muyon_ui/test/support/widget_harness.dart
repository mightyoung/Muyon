import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

bool _fontLoaded = false;
Future<void> loadUiTestFont() async {
  if (_fontLoaded) return;
  var directory = Directory.current;
  File? font;
  for (var i = 0; i < 8; i++) {
    final candidate = File(
      '${directory.path}/apps/muyon/assets/fonts/NotoSansSC-VF.ttf',
    );
    if (candidate.existsSync()) {
      font = candidate;
      break;
    }
    directory = directory.parent;
  }
  if (font == null) throw StateError('Bundled Noto Sans SC test font missing');
  final loader = FontLoader('Noto Sans SC')
    ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final mono = File('/System/Library/Fonts/Menlo.ttc');
  final monoBytes = mono.existsSync()
      ? mono.readAsBytesSync()
      : font.readAsBytesSync();
  final codeFont = FontLoader(monoFamily)
    ..addFont(Future.value(ByteData.sublistView(monoBytes)));
  await codeFont.load();
  _fontLoaded = true;
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double scale = 2,
  Brightness brightness = Brightness.light,
}) async {
  await loadUiTestFont();
  await tester.binding.setSurfaceSize(Size(width, 1000));
  await tester.pumpWidget(
    MaterialApp(
      theme: muyonTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void minimum(WidgetTester tester, Finder finder) {
  final r = tester.getRect(finder);
  expect(r.width, greaterThanOrEqualTo(48));
  expect(r.height, greaterThanOrEqualTo(48));
}
