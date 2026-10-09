import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/ui_navigation_fixture.dart';

void main() {
  testWidgets('artifact_id_is_not_an_arbitrary_file_path', (tester) async {
    final f = await NavigationFixture.open(tester);
    final path = File('${f.root.path}/unregistered.md')
      ..writeAsStringSync('UNREGISTERED PRIVATE FIXTURE');
    final artifact = ArtifactRef(
      moduleId: 'knowledge',
      artifactId: path.path,
      contentDigest: 'unregistered',
    );
    const ref = ObjectRef(
      moduleId: 'knowledge',
      objectType: 'document',
      objectId: 'unregistered',
    );
    await f.show(tester, f.plan(ref, artifact: artifact));
    await tester.tap(find.text('查看原文 · source'));
    await NavigationFixture.frames(tester);
    expect(find.textContaining('未提供可用预览'), findsOneWidget);
    expect(find.textContaining('UNREGISTERED PRIVATE FIXTURE'), findsNothing);
    await tester.pageBack();
    await NavigationFixture.frames(tester);
    expect(find.text('原对话回答'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final changed in [false, true]) {
    testWidgets(
      changed
          ? 'changed_source_marks_anchor_stale'
          : 'actual_markdown_file_preview_returns_to_workspace',
      (tester) async {
        final f = await NavigationFixture.open(tester);
        final source = File('${f.root.path}/public.md')
          ..writeAsStringSync('# 公开文件原文\n\n真实段落内容');
        final document = (await tester.runAsync(
          () => f.host.services.knowledge.importFile(source.path),
        ))!;
        final artifact = ArtifactRef(
          moduleId: 'knowledge',
          artifactId: document.id,
          contentDigest: document.digest,
        );
        await f.show(tester, f.plan(document.source, artifact: artifact));
        if (changed) File(document.path).writeAsStringSync('# 已变化文件\n新段落内容');
        expect(find.text('查看原文 · source'), findsOneWidget);
        await tester.ensureVisible(find.text('查看原文 · source'));
        await tester.tap(find.text('查看原文 · source'));
        await NavigationFixture.frames(tester, count: 20);
        expect(
          find.textContaining(changed ? '新段落内容' : '真实段落内容'),
          findsOneWidget,
        );
        expect(
          find.textContaining('原定位已失效'),
          changed ? findsOneWidget : findsNothing,
        );
        final stored = (await HostUiWorkspaceStore(
          f.host.foundation,
          taskId: 'task',
        ).load('comparison'))!;
        final anchor = jsonDecode(stored.returnAnchor!) as Map;
        expect(anchor['sourceDigest'], document.digest);
        expect(anchor['artifactRef']['artifactId'], document.id);
        await tester.pageBack();
        await NavigationFixture.frames(tester);
        expect(find.text('原对话回答'), findsOneWidget);
        expect(
          (await HostUiWorkspaceStore(
            f.host.foundation,
            taskId: 'task',
          ).load('comparison'))!.returnAnchor,
          stored.returnAnchor,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
