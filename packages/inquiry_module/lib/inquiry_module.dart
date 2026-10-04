import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supplier_core/supplier_core.dart';

import 'src/app/app_state.dart';
import 'src/app/secret_store.dart';
import 'src/app/shell.dart';
import 'src/app/theme.dart';

export 'src/app/app_state.dart' show AppState;
export 'src/app/secret_store.dart' show InquirySecretStore;

class InquiryRuntime {
  InquiryRuntime.attach({
    required Store store,
    required Directory dataDirectory,
    required AiJobStore aiJobs,
    required InquirySecretStore secrets,
    Map<String, Object?> initialSettings = const {},
  }) : state = AppState.attach(
         store: store,
         dataDir: dataDirectory,
         aiJobs: aiJobs,
         secrets: secrets,
         initialSettings: initialSettings,
       );
  final AppState state;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await state.shutdown();
    state.dispose();
  }
}

/// Shares the host Navigator, localization and window lifecycle.
class InquiryHome extends StatelessWidget {
  const InquiryHome({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      Tokens.dark = switch (state.setting('appearance')) {
        'dark' => true,
        'light' => false,
        _ => Theme.of(context).brightness == Brightness.dark,
      };
      return Theme(
        data: buildTheme(),
        child: Shell(state: state, embedded: true),
      );
    },
  );
}
