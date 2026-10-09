import 'package:flutter/material.dart';

import 'fixture_ports.dart';
import 'preview_app.dart';
import 'workspace_preview.dart';
import 'browser_workspace_store.dart';

void main() => runApp(
  Uri.base.queryParameters['workspace'] == '1'
      ? MaterialApp(
          home: WorkspacePreview(store: createBrowserWorkspaceStore()),
        )
      : PreviewApp(fixture: comparisonFixture()),
);
