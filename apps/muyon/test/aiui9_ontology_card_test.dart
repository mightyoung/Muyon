import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/ontology_cards/inquiry_ontology_card_adapter.dart';
import 'package:muyon/assistant/ontology_cards/ontology_card.dart';
import 'package:muyon/assistant/ontology_cards/ontology_card_snapshot.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:path/path.dart' as p;

Map<String, Object?> _supplier(String name) => {
  'name': name, 'aliases': <String>[], 'address': null,
  'categories': <String>[], 'notes': null, 'merged_into': null,
  'rating': null, 'rating_note': null,
};

const _ref = ObjectRef(moduleId: 'inquiry', objectType: 'fixture',
    objectId: 'fixture-id', revisionRef: '3', contentDigest: 'digest');

OntologyCardSnapshot _fixture({
  List<OntologyFieldSpec>? fields,
  Map<String, Object?> values = const {'name': 'saved'},
  Map<String, Object?> suggestions = const {},
  int apiVersion = 2,
  bool knownType = true,
  bool updateTool = false,
  List<SnapshotFact>? facts,
}) => OntologyCardSnapshot.fromHostSnapshot(
  ontology: ModuleOntology(objectTypes: [
    if (knownType) ObjectTypeSpec(name: 'fixture', label: '夹具',
      description: '', iconKey: '', titleField: 'name', fields: fields ?? const [
        OntologyFieldSpec(name: 'name', label: '名称', description: '',
          kind: FieldKind.text, required: true, sensitivity: Sensitivity.none),
      ]),
  ]),
  moduleApiVersion: apiVersion,
  object: _ref,
  scope: ResolvedAssistantScope(requested: const AssistantScope.global(),
      objects: const [_ref]),
  snapshot: DataSnapshot(ref: const SnapshotRef('host-snapshot', 3), facts: {
    if (facts != null)
      for (var i = 0; i < facts.length; i++) '$i': facts[i]
    else
      for (final entry in values.entries) entry.key: SnapshotFact(
        object: _ref, field: entry.key, value: entry.value,
        state: FactState.verified),
  }),
  hasRegisteredUpdateTool: updateTool,
  suggestions: suggestions,
);

Widget _app(OntologyCardSnapshot snapshot) => MaterialApp(
  theme: muyonTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: OntologyCard(snapshot: snapshot))),
);

void main() {
  group('host inquiry snapshot', () {
    late Directory root;
    late MuyonHost host;
    late String id;
    late ObjectRef ref;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('aiui9-');
      host = await MuyonHost.open(p.join(root.path, 'data'));
      await host.activateInquiry();
      id = host.inquiry!.runtime.state.store.save('supplier', _supplier('已保存供应商'));
      final scope = await resolveAssistantScope(host, const AssistantScope.global());
      ref = scope.objects.singleWhere((r) => r.objectId == id);
    });
    tearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    test('read records full revision/digest and keeps suggestions separate', () async {
      final before = host.inquiry!.runtime.state.store.get('supplier', id)!;
      final card = await InquiryOntologyCardAdapter.read(host: host,
        scope: AssistantScope.selectedObjects([ref]), object: ref,
        suggestions: const {'name': '建议供应商', 'injected': 'not an ontology field'});
      expect(card.object, ref);
      expect(card.snapshotRef.revision, before.version);
      expect(card.hasRegisteredUpdateTool, isTrue);
      expect(card.fields.singleWhere((f) => f.name == 'name').value, '已保存供应商');
      expect(card.fields.singleWhere((f) => f.name == 'name').suggestion, '建议供应商');
      expect(card.fields.any((f) => f.name == 'injected'), isFalse);
      expect(host.inquiry!.runtime.state.store.get('supplier', id)!.data, before.data);
      expect(host.inquiry!.runtime.state.store.get('supplier', id)!.version, before.version);
    });
    test('old revision cannot read a new saved record', () async {
      host.inquiry!.runtime.state.store.save('supplier', _supplier('更新'), id: id);
      await expectLater(InquiryOntologyCardAdapter.read(host: host,
        scope: AssistantScope.selectedObjects([ref]), object: ref), throwsStateError);
    });
    test('object outside selected scope cannot be displayed', () async {
      final second = host.inquiry!.runtime.state.store.save('supplier', _supplier('其他'));
      final refs = await resolveAssistantScope(host, const AssistantScope.global());
      final other = refs.objects.singleWhere((r) => r.objectId == second);
      await expectLater(InquiryOntologyCardAdapter.read(host: host,
        scope: AssistantScope.selectedObjects([other]), object: ref), throwsStateError);
    });
    test('global supplier is not granted by an unrelated workspace', () async {
      final workspace = await host.workspaces.create('工作区');
      await expectLater(InquiryOntologyCardAdapter.read(host: host,
        scope: AssistantScope.workspace(workspace.id), object: ref), throwsStateError);
    });
    test('deleted pinned record cannot become a card', () async {
      host.inquiry!.runtime.state.store.delete('supplier', id);
      await expectLater(InquiryOntologyCardAdapter.read(host: host,
        scope: const AssistantScope.global(), object: ref), throwsStateError);
    });
  });

  testWidgets('real host read maps into component with disabled submit and no writes', (tester) async {
    final root = Directory.systemTemp.createTempSync('aiui9-widget-');
    MuyonHost? host;
    try {
      final result = await tester.runAsync(() async {
        host = await MuyonHost.open(p.join(root.path, 'data'));
        await host!.activateInquiry();
        final store = host!.inquiry!.runtime.state.store;
        final id = store.save('supplier', _supplier('宿主事实'));
        final scope = await resolveAssistantScope(host!, const AssistantScope.global());
        final ref = scope.objects.singleWhere((r) => r.objectId == id);
        final card = await InquiryOntologyCardAdapter.read(host: host!,
          scope: AssistantScope.selectedObjects([ref]), object: ref,
          suggestions: const {'name': '模型建议'});
        return (card, id, store.get('supplier', id)!.version);
      });
      await tester.pumpWidget(_app(result!.$1));
      expect(find.byType(KeyValue), findsOneWidget);
      expect(find.text('宿主事实'), findsOneWidget);
      expect(find.text('模型建议'), findsOneWidget);
      expect(find.text('名称 · 建议（尚未写入）'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(host!.inquiry!.runtime.state.store.get('supplier', result.$2)!.version, result.$3);
      expect(host!.inquiry!.runtime.state.store.get('supplier', result.$2)!.data['name'], '宿主事实');
      expect(host!.workspaces.database.raw.select('SELECT * FROM tool_invocation_receipts'), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async { await host?.close(); });
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('sensitive values and credentials never reach text or semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final card = _fixture(fields: [
      for (final sensitivity in Sensitivity.values)
        OntologyFieldSpec(name: sensitivity.name, label: sensitivity.name,
          description: '', kind: FieldKind.text, sensitivity: sensitivity),
    ], values: {for (final s in Sensitivity.values) s.name: 'secret-${s.name}'},
       suggestions: {for (final s in Sensitivity.values) s.name: 'suggested-${s.name}'});
    expect(card.fields.any((f) => f.name == 'credential'), isFalse);
    expect(card.fields.where((f) => f.masked).length, 3);
    await tester.pumpWidget(_app(card));
    for (final s in [Sensitivity.personal, Sensitivity.commercial,
                     Sensitivity.credential, Sensitivity.unreviewed]) {
      expect(find.text('secret-${s.name}'), findsNothing);
      expect(find.text('suggested-${s.name}'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('secret-${s.name}|suggested-${s.name}')), findsNothing);
    }
    expect(find.text('secret-none'), findsOneWidget);
    expect(find.text('suggested-none'), findsOneWidget);
  });

  testWidgets('unknown type and higher version safely retain read-only fallback', (tester) async {
    for (final card in [_fixture(knownType: false), _fixture(apiVersion: 3, updateTool: true)]) {
      expect(card.fallback, isTrue);
      expect(card.hasRegisteredUpdateTool, isFalse);
      await tester.pumpWidget(_app(card));
      expect(find.text('不支持的本体版本或类型，请在原页面编辑'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    }
  });

  test('mixed objects and duplicate fields fail before rendering', () {
    final fact = SnapshotFact(object: _ref, field: 'name', value: 'saved', state: FactState.verified);
    expect(() => _fixture(facts: [fact, fact]), throwsStateError);
    expect(() => _fixture(facts: [SnapshotFact(object: const ObjectRef(
      moduleId: 'inquiry', objectType: 'fixture', objectId: 'other',
      revisionRef: '3', contentDigest: 'digest'), field: 'name',
      value: 'outside', state: FactState.verified)]), throwsStateError);
  });

  testWidgets('references and opaque object values cannot activate a route', (tester) async {
    final card = _fixture(fields: const [
      OntologyFieldSpec(name: 'link', label: '关联', description: '',
        kind: FieldKind.ref, target: 'supplier', sensitivity: Sensitivity.none),
      OntologyFieldSpec(name: 'nested', label: '结构', description: '',
        kind: FieldKind.object, sensitivity: Sensitivity.none),
    ], values: const {'link': 'old-or-cross-scope-id', 'nested': {'token': 'nested-secret'}});
    await tester.pumpWidget(_app(card));
    expect(find.text('关联对象（未活化）：old-or-cross-scope-id'), findsOneWidget);
    expect(find.text('结构化值，请在原页面查看'), findsOneWidget);
    expect(find.textContaining('nested-secret'), findsNothing);
    expect(find.byType(ObjectChip), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  test('malformed declared values are not serialized as trusted facts', () {
    final card = _fixture(fields: const [
      OntologyFieldSpec(name: 'boolean', label: '布尔', description: '',
        kind: FieldKind.boolean, sensitivity: Sensitivity.none),
      OntologyFieldSpec(name: 'enum', label: '枚举', description: '',
        kind: FieldKind.enumeration, values: {'valid': '合法'}, sensitivity: Sensitivity.none),
    ], values: const {'boolean': 'not-bool', 'enum': 'injected'});
    expect(card.fields.every((f) => f.value == '无法读取，请在原页面查看'), isTrue);
  });
  test('all current FieldKind values have explicit read-only display handling', () {
    final values = <FieldKind, Object>{
      FieldKind.text: '文字', FieldKind.textList: ['甲', '乙'],
      FieldKind.decimal: '12.50', FieldKind.integer: 4,
      FieldKind.boolean: true, FieldKind.date: '2026-10-10',
      FieldKind.instant: '2026-10-10T00:00:00Z', FieldKind.enumeration: 'ok',
      FieldKind.ref: 'object-id', FieldKind.refList: ['object-id'],
      FieldKind.object: {'opaque': true},
    };
    final card = _fixture(fields: [
      for (final kind in FieldKind.values)
        OntologyFieldSpec(name: kind.name, label: kind.name, description: '',
          kind: kind, values: const {'ok': '可用'}, sensitivity: Sensitivity.none),
    ], values: {for (final entry in values.entries) entry.key.name: entry.value});
    expect(card.fields.length, FieldKind.values.length);
    expect(card.fields.every((f) => !f.value.contains('无法读取')), isTrue);
    expect(card.fields.singleWhere((f) => f.kind == FieldKind.boolean).value, '是');
    expect(card.fields.singleWhere((f) => f.kind == FieldKind.enumeration).value, '可用');
    expect(card.fields.singleWhere((f) => f.kind == FieldKind.textList).value, '甲、乙');
  });

  test('unverified saved content is not promoted to a current fact', () {
    final card = _fixture(facts: [SnapshotFact(object: _ref, field: 'name',
        value: 'untrusted', state: FactState.conflict)]);
    expect(card.fields.single.value, '未核验，请在原页面查看');
  });

}
