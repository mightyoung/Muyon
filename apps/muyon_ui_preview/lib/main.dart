import 'package:flutter/material.dart';

import 'fixture_ports.dart';
import 'preview_app.dart';
import 'workspace_preview.dart';
import 'browser_workspace_store.dart';
import 'planning_preview.dart';
import 'subconversation_preview.dart';

void main() => runApp(
  Uri.base.queryParameters['subconversation'] == '1'
      ? MaterialApp(
          home: SubconversationPreview(store: createBrowserWorkspaceStore()),
        )
      : Uri.base.queryParameters['planning'] == '1'
      ? const MaterialApp(home: PlanningPreview())
      : Uri.base.queryParameters['workspace'] == '1'
      ? MaterialApp(
          home: WorkspacePreview(store: createBrowserWorkspaceStore()),
        )
      : PreviewApp(fixture: comparisonFixture()),
);
