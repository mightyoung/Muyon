import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'support/legacy_scope_resolver.dart';

/// REG-2b: the host has one scope resolver. This compares it, item by item and
/// in order, with a frozen copy of the function it replaced, on every scope
/// kind and after every kind of change, across the three existing modules and
/// the knowledge base.
void main() {
  late Directory root;
  late Directory source;
  late MuyonHost host;
  String? researchWorkspace;

  setUp(() async {
    researchWorkspace = null;
    root = Directory.systemTemp.createTempSync('scope-diff-');
    source = Directory.systemTemp.createTempSync('scope-diff-src-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (source.existsSync()) source.deleteSync(recursive: true);
  });

  Map<String, Object?> supplier(String name) => {
    'name': name,
    'aliases': <String>[],
    'categories': <String>[],
    'address': null,
    'notes': null,
    'merged_into': null,
    'rating': null,
    'rating_note': null,
  };

  Map<String, Object?> project() => {
    'code': 'P-1',
    'name': '差分项目',
    'status': 'active',
    'type': 'market',
    'level': 'A',
    'customer': null,
    'contract_no': null,
    'contract_amount': null,
    'department': null,
    'leader': null,
    'start_date': null,
    'end_date': null,
    'currency': 'CNY',
    'tax_mode': 'included',
    'markup_rate': '0',
    'notes': null,
  };

  late String supplierId;
  late String projectId;

  Future<void> seed() async {
    await host.activateInquiry();
    final store = host.inquiry!.runtime.state.store;
    supplierId = store.save('supplier', supplier('差分供应商'));
    store.save('supplier', supplier('第二供应商'));
    projectId = store.save('project', project());

    File(p.join(source.path, 'paper.md')).writeAsStringSync('研究内容 摘要');
    File(p.join(source.path, 'second.md')).writeAsStringSync('第二份资料');
    await host.activateResearch();
    final workspace = await host.workspaces.create('W');
    researchWorkspace = workspace.id;
    final binding = WorkspaceBinding(
      workspaceId: workspace.id,
      moduleId: 'research',
      nativeProjectId: 'W',
    );
    final prepared = await host.research!.prepareImport(
      SelectedInput(path: source.path, displayName: 'W'),
      ImportTarget.create(binding),
    );
    final coordinator = ImportCoordinator(host.workspaces);
    await coordinator.commit(
      host.research!,
      prepared,
      await coordinator.record(prepared),
    );
    await host.workspaces.create('空工作区');

    await host.activatePrototype();
    final build = Directory(p.join(root.path, 'dist'))..createSync();
    File(p.join(build.path, 'index.html')).writeAsStringSync('<p>x</p>');
    final version = await host.prototype!.store.importBuild(
      sourceDir: build.path,
      title: '差分原型',
    );
    await host.prototype!.store.addFeedback(
      versionId: version.id,
      text: '按钮太小',
    );

    final note = File(p.join(root.path, 'note.txt'))
      ..writeAsStringSync('knowledge needle');
    final doc = await host.services.knowledge.importFile(note.path);
    await host.services.knowledge.index(doc.id);
  }

  /// Runs both implementations; a thrown error counts as a result, so the two
  /// must refuse the same requests with the same error type and message.
  Future<(Object, Object)> both(AssistantScope scope) async {
    Future<Object> run(
      Future<ResolvedAssistantScope> Function(MuyonHost, AssistantScope) f,
    ) async {
      try {
        final resolved = await f(host, scope);
        return jsonEncode(resolved.toJson());
      } catch (error) {
        return '${error.runtimeType}: $error';
      }
    }

    return (
      await run(legacyResolveAssistantScope),
      await run(resolveAssistantScope),
    );
  }

  Future<void> agree(String label, AssistantScope scope) async {
    final (old, current) = await both(scope);
    expect(current, old, reason: label);
  }

  Future<List<ObjectRef>> everything() async =>
      (await legacyResolveAssistantScope(
        host,
        const AssistantScope.global(),
      )).objects;

  Future<void> everyScope(String phase) async {
    final all = await everything();
    await agree('$phase: global', const AssistantScope.global());
    if (researchWorkspace case final workspace?) {
      await agree(
        '$phase: research workspace',
        AssistantScope.workspace(workspace),
      );
    }
    for (final workspace in host.workspaces.all()) {
      await agree(
        '$phase: workspace ${workspace.title}',
        AssistantScope.workspace(workspace.id),
      );
    }
    await agree('$phase: unknown workspace', AssistantScope.workspace('ghost'));
    // One selection per module and type, with and without a workspace.
    final seen = <String>{};
    for (final ref in all) {
      if (!seen.add('${ref.moduleId}/${ref.objectType}')) continue;
      await agree(
        '$phase: select ${ref.moduleId}/${ref.objectType} pinned',
        AssistantScope.selectedObjects([ref]),
      );
      await agree(
        '$phase: select ${ref.moduleId}/${ref.objectType} unpinned',
        AssistantScope.selectedObjects([
          ObjectRef(
            moduleId: ref.moduleId,
            objectType: ref.objectType,
            objectId: ref.objectId,
            nativeProjectId: ref.nativeProjectId,
          ),
        ]),
      );
      await agree(
        '$phase: select ${ref.moduleId}/${ref.objectType} in research workspace',
        AssistantScope.selectedObjects([ref], workspaceId: researchWorkspace),
      );
      await agree(
        '$phase: select ${ref.moduleId}/${ref.objectType} wrong revision',
        AssistantScope.selectedObjects([
          ObjectRef(
            moduleId: ref.moduleId,
            objectType: ref.objectType,
            objectId: ref.objectId,
            nativeProjectId: ref.nativeProjectId,
            revisionRef: 'not-a-revision',
          ),
        ]),
      );
      await agree(
        '$phase: select ${ref.moduleId}/${ref.objectType} wrong digest',
        AssistantScope.selectedObjects([
          ObjectRef(
            moduleId: ref.moduleId,
            objectType: ref.objectType,
            objectId: ref.objectId,
            nativeProjectId: ref.nativeProjectId,
            contentDigest: 'not-a-digest',
          ),
        ]),
      );
    }
    if (all.isNotEmpty) {
      await agree(
        '$phase: select several at once',
        AssistantScope.selectedObjects([for (final ref in all.take(4)) ref]),
      );
    }
    await agree(
      '$phase: select something that does not exist',
      AssistantScope.selectedObjects([
        const ObjectRef(
          moduleId: 'inquiry',
          objectType: 'supplier',
          objectId: 'ghost',
        ),
      ]),
    );
    await agree(
      '$phase: select from a module that does not exist',
      AssistantScope.selectedObjects([
        const ObjectRef(moduleId: 'nowhere', objectType: 'x', objectId: '1'),
      ]),
    );
  }

  test(
    'the fixture really covers all three modules and the knowledge base',
    () async {
      await seed();
      final all = await everything();
      expect(all.map((r) => r.moduleId).toSet(), {
        'inquiry',
        'research',
        'prototype',
        'knowledge',
      });
      expect(
        all.map((r) => '${r.moduleId}/${r.objectType}'),
        containsAll([
          'inquiry/supplier',
          'inquiry/project',
          'research/project',
          'research/document',
          'prototype/page',
        ]),
      );
      expect(all.length, greaterThan(8));
    },
  );

  test('every scope resolves exactly as the old function did', () async {
    await seed();
    await everyScope('fresh');
  });

  test('and after the data changes underneath', () async {
    await seed();
    final store = host.inquiry!.runtime.state.store;
    // A research document edited on disk, then removed.
    final document = host.research!.store.documents('W').first;
    File(document.absolutePath).writeAsStringSync('改过的内容');
    await everyScope('edited file');
    File(document.absolutePath).deleteSync();
    await everyScope('missing file');
    // An inquiry row changed (new version, new digest) and one soft-deleted.
    store.save('supplier', supplier('改名供应商'), id: supplierId);
    await everyScope('inquiry edited');
    store.delete('project', projectId);
    await everyScope('inquiry deleted');
    // A knowledge source that changed after it was indexed drops out of both.
    final note = File(p.join(root.path, 'note.txt'));
    note.writeAsStringSync('changed after indexing');
    await everyScope('knowledge changed');
  });

  test('a host with nothing in it agrees too', () async {
    await agree('empty global', const AssistantScope.global());
    await everyScope('empty');
  });
}
