import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:research_module/src/core/store.dart';
import 'package:research_module/src/app/workbench_app.dart';
import 'package:research_module/src/app/theme.dart';

class WorkbenchApp extends StatelessWidget {
  const WorkbenchApp({
    super.key,
    required this.store,
    this.loadMarkdown,
    this.pickImportFile,
    this.saveExportFile,
  });
  final WorkbenchStore store;
  final Future<String> Function(String path)? loadMarkdown;
  final Future<String?> Function(List<String> extensions)? pickImportFile;
  final Future<Uri?> Function(String name, Uint8List bytes, String mimeType)?
  saveExportFile;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '研究工作台',
    debugShowCheckedModeBanner: false,
    theme: workbenchTheme(),
    darkTheme: workbenchTheme(dark: true),
    themeMode: ThemeMode.system,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ResearchHome(
      projectId: store.projects().firstOrNull?.id ?? 'unbound',
      store: store,
      loadMarkdown: loadMarkdown,
      pickImportFile: pickImportFile,
      saveExportFile: saveExportFile,
    ),
  );
}


