import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/bootstrap.dart';
import 'app/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    const configured = String.fromEnvironment('MUYON_DATA_DIR');
    final root = configured.isEmpty
        ? p.join((await getApplicationSupportDirectory()).path, 'muyon', 'data')
        : Directory(configured).absolute.path;
    final host = await MuyonHost.open(root);
    runApp(MuyonApp(host: host));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText('无法打开 Muyon\n$error'),
            ),
          ),
        ),
      ),
    );
  }
}
