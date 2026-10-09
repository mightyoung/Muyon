import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late MuyonHost host;
  var counter = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('prototype-tools-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<ToolCallResult> call(String toolId, Map<String, Object?> params) =>
      host.tools.invoke(
        ToolCallRequest(
          invocationId: 'inv-${counter++}',
          toolId: toolId,
          scope: const AssistantScope.global(),
          parameters: params,
        ),
      );

  test('list_pages and page_detail return data and ObjectRefs', () async {
    await host.activatePrototype();
    final build = Directory(p.join(root.path, 'dist'))..createSync();
    File(p.join(build.path, 'index.html')).writeAsStringSync('<p>x</p>');
    final store = host.prototype!.store;
    final v = await store.importBuild(sourceDir: build.path, title: 'MES 原型');
    final fb = await store.addFeedback(versionId: v.id, text: '手机上按钮太小');

    final list = await call('prototype.list_pages', {});
    expect(list.status, ToolCallStatus.succeeded);
    final row = (list.data['pages'] as List).single as Map;
    expect(row['title'], 'MES 原型');
    expect(row['versionCount'], 1);
    expect(row['feedbackCount'], 1);
    expect(row['latestVersion'], 'v1');
    expect(list.objectRefs.single.objectType, 'page');
    expect(list.objectRefs.single.objectId, v.pageId);

    final detail = await call('prototype.page_detail', {'page_id': v.pageId});
    expect(detail.status, ToolCallStatus.succeeded);
    expect(detail.objectRefs.map((r) => r.objectType).toSet(), {
      'page',
      'version',
      'feedback',
    });
    expect(detail.objectRefs.every((r) => r.moduleId == 'prototype'), isTrue);
    expect((detail.data['versions'] as List).single['label'], 'v1');
    expect((detail.data['feedback'] as List).single['text'], '手机上按钮太小');
    expect(detail.objectRefs.any((r) => r.objectId == fb.id), isTrue);

    final missing = await call('prototype.page_detail', {'page_id': 'ghost'});
    expect(missing.status, ToolCallStatus.failed);
    expect(missing.objectRefs, isEmpty);
  });

  test('legacy prototype reads stay read-only; feedback is a local write', () {
    final prototype = [
      for (final info in host.tools.list())
        if (info.descriptor.moduleId == 'prototype') info.descriptor,
    ];
    final reads = prototype.where((d) => d.effect == ToolEffect.read).toList();
    expect(reads.map((d) => d.toolId).toSet(), {
      'prototype.list_pages',
      'prototype.page_detail',
    });
    expect(reads.every((d) => d.effect == ToolEffect.read), isTrue);
    expect(prototype.map((d) => d.toolId).toSet(), {
      'prototype.list_pages', 'prototype.page_detail', 'prototype.add_feedback',
    });
    expect(prototype.singleWhere((d) => d.toolId == 'prototype.add_feedback').effect,
      ToolEffect.write);
    expect(prototype.every((d) => d.effect == ToolEffect.read || d.effect == ToolEffect.write), isTrue);
    expect(prototype.every((d) => d.description.isNotEmpty), isTrue);
  });
}
