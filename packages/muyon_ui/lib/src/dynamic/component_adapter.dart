import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../ui_components/business.dart';
import '../ui_components/data.dart';
import '../ui_components/inputs.dart';
import '../ui_components/layout.dart';
import '../ui_components/state.dart';
import 'catalog.dart';
import 'surface.dart';

typedef UiComponentAdapter = Widget Function(UiAdapterContext context);

/// The sole library-2 adapter table; existing twelve adapters reuse the same
/// renderer and controller. No planning or validation authority lives here.
final uiComponentAdapters = Map<String, UiComponentAdapter>.unmodifiable(
  <String, UiComponentAdapter>{
    for (final name in dynamicUiCatalog.components.keys)
      name: (UiAdapterContext context) => context.legacy(),
    for (final name in libraryComponentNames) name: _libraryComponent,
  },
);

class UiAdapterContext {
  UiAdapterContext({
    required this.capture,
    required this.controller,
    required this.node,
    required this.nodes,
    required this.renderChild,
    required this.legacy,
  });
  final UiRenderCapture capture;
  final UiSurfaceController controller;
  final UiNode node;
  final Map<String, UiNode> nodes;
  final Widget Function(UiNode node) renderChild;
  final Widget Function() legacy;
  DataSnapshot get snapshot => capture.plan.snapshot;
  UiSessionState get session => controller.session;
  Object? value(String slot) => node.bindings[slot] == null
      ? null
      : session.resolve(node.bindings[slot]!);
  List<String> selection(String slot) =>
      session.selections[node.bindings[slot]!.id]!;
  UiEditSpec spec(String slot) => snapshot.editSpecs[node.bindings[slot]!.id]!;
  UiCollection collection(String slot) =>
      snapshot.collections[node.bindings[slot]!.id]!;
  List<Widget> get children => [
    for (final id in node.children) renderChild(nodes[id]!),
  ];
  bool has(String kind) => node.events.containsKey(kind);
  void dispatch(String kind, [Object? payload]) {
    controller.dispatchCaptured(capture, node, kind, payload);
  }

  String text(Object? value) => value?.toString() ?? '未提供';
  String label(String key, [String fallback = '']) =>
      node.properties[key] as String? ?? fallback;
  FactState? state(BindingRef ref) => switch (ref.kind) {
    BindingKind.fact => snapshot.facts[ref.id]?.state,
    BindingKind.computed => snapshot.computedEvidence[ref.id]?.state,
    _ => null,
  };
  String? unit(BindingRef? ref) => ref == null
      ? null
      : switch (ref.kind) {
          BindingKind.fact => snapshot.facts[ref.id]?.unit,
          BindingKind.computed => snapshot.computedEvidence[ref.id]?.unit,
          _ => null,
        };
  String cell(UiRow row, String column) =>
      text(session.resolve(row.cells[column]!));
  String evidence(BindingRef ref) {
    final fact = snapshot.facts[ref.id];
    final computed = snapshot.computedEvidence[ref.id];
    final sources = ref.kind == BindingKind.fact
        ? fact?.sourceRefs
        : computed?.sourceRefs;
    return '${state(ref)?.name ?? "unknown"}${unit(ref) == null ? "" : " · ${unit(ref)}"}'
        '${sources == null || sources.isEmpty ? " · 来源未提供" : " · 来源 ${sources.join('、')}"}';
  }
}

Widget renderLibrary2Component(UiAdapterContext context) {
  final node = context.node;
  final refs = <BindingRef>{};
  for (final ref in node.bindings.values) {
    if (ref.kind == BindingKind.collection) {
      for (final row in context.snapshot.collections[ref.id]!.rows) {
        refs.addAll(row.cells.values);
      }
    } else {
      refs.add(ref);
    }
  }
  return Column(
    key: ValueKey('aiui2-${node.id}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      uiComponentAdapters[node.component]!(context),
      for (final ref in refs)
        if (ref.kind == BindingKind.fact || ref.kind == BindingKind.computed)
          Text(
            '${ref.id}: ${context.text(context.session.resolve(ref))} · ${context.evidence(ref)}',
          ),
      for (final ref in refs.where((ref) => ref.kind == BindingKind.uiState))
        if (context.session.userOverrides.containsKey(ref.id) ||
            context.session.selectionOverrides.contains(ref.id))
          Text('${ref.id} · 人工 override'),
    ],
  );
}

Widget _libraryComponent(UiAdapterContext c) {
  final n = c.node;
  final label = c.label('label');
  switch (n.component) {
    case 'Heading':
      return Heading(
        text: c.label('text'),
        level: n.properties['level'] as int? ?? 1,
      );
    case 'Prose':
      return Prose(text: c.label('text'));
    case 'Section':
      return Section(title: c.label('title'), children: c.children);
    case 'Columns':
      return Columns(children: c.children);
    case 'Tabs':
      final selected = c.value('selected');
      final position = n.children.indexOf(selected is String ? selected : '');
      return MuyonTabs(
        labels: [
          for (final id in n.children)
            c.nodes[id]!.properties['title'] as String,
        ],
        selectedIndex: n.bindings.containsKey('selected') ? position : null,
        onChanged: c.has('change')
            ? (index) => c.dispatch('change', n.children[index])
            : null,
        children: c.children,
      );
    case 'Disclosure':
      return Disclosure(
        title: c.label('title'),
        initiallyExpanded: n.properties['initiallyExpanded'] as bool? ?? false,
        expanded: n.bindings.containsKey('expanded')
            ? c.value('expanded') as bool?
            : null,
        onChanged: c.has('change')
            ? (value) => c.dispatch('change', value)
            : null,
        child: Column(children: c.children),
      );
    case 'KeyValue':
      final ref = n.bindings['value']!;
      return KeyValue(
        items: [
          (
            ref.kind == BindingKind.fact
                ? c.snapshot.facts[ref.id]!.field
                : ref.id,
            c.text(c.value('value')),
          ),
        ],
      );
    case 'Metric':
      return Metric(
        label: label,
        value: c.text(c.value('value')),
        unit: c.unit(n.bindings['value']) ?? c.label('unit'),
        delta: n.bindings.containsKey('delta')
            ? c.text(c.value('delta'))
            : null,
      );
    case 'CompareTable':
      final collection = c.collection('rows');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompareTable(
            columns: [for (final col in collection.columns) col.label],
            caption: label,
            rows: [
              for (final row in collection.rows)
                [for (final col in collection.columns) c.cell(row, col.id)],
            ],
            marks: {
              for (var row = 0; row < collection.rows.length; row++)
                for (var col = 0; col < collection.columns.length; col++)
                  if (c.state(
                        collection.rows[row].cells[collection.columns[col].id]!,
                      ) !=
                      FactState.verified)
                    (row, col): CompareMark.unverified,
            },
          ),
          for (final row in collection.rows)
            TextButton(
              key: ValueKey('aiui2-${n.id}-row-${row.itemId}'),
              onPressed:
                  c.has('tap') &&
                      c.controller.onOpenObject != null &&
                      c.session.rowObject(n, row.itemId) != null
                  ? () => c.dispatch('tap', row.itemId)
                  : null,
              child: Text('查看 ${c.cell(row, collection.columns.first.id)} 详情'),
            ),
        ],
      );
    case 'Chart':
      final collection = c.collection('data');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chart(
            kind: ChartKind.values.byName(c.label('kind')),
            title: c.label('title'),
            unit: c.label('unit'),
            points: [
              for (final row in collection.rows)
                if (c.session.resolve(row.cells['value']!) != null)
                  ChartPoint(
                    c.cell(row, 'label'),
                    double.parse(c.cell(row, 'value')),
                  ),
            ],
          ),
          // Canonical source values include missing rows; geometry never replaces
          // a missing value with zero or truncates the source decimal string.
          KeyValue(
            items: [
              for (final row in collection.rows)
                (c.cell(row, 'label'), c.cell(row, 'value')),
            ],
          ),
        ],
      );
    case 'Choice':
      final collection = c.collection('options');
      final spec = c.spec('selected') as UiItemIdsEdit;
      return Choice(
        label: label,
        options: [for (final row in collection.rows) c.cell(row, 'label')],
        optionIds: [for (final row in collection.rows) row.itemId],
        selectedIds: c.selection('selected').toSet(),
        multiple: spec.multiple,
        allowCustom: false,
        onChangedIds: c.has('change')
            ? (ids) => c.dispatch('change', UiItemIdsEdit.normalize(ids))
            : null,
      );
    case 'Form':
      return MuyonForm(
        title: c.label('title'),
        submitLabel: c.label('submitLabel', '提交'),
        state: c.has('submit') && c.controller.onEvent != null
            ? UiComponentState.ready
            : UiComponentState.readOnly,
        onSubmit: c.has('submit') && c.controller.onEvent != null
            ? () => c.dispatch('submit')
            : null,
        children: c.children,
      );
    case 'NumberStepper':
    case 'Slider':
      final spec = c.spec('value') as UiNumberEdit;
      final value = c.value('value');
      if (value == null) return Text('$label：未设置');
      if (spec.min == spec.max) return Text('$label：${c.text(value)} · 固定范围');
      final callback = c.has('change')
          ? (double value) => c.dispatch('change', value)
          : null;
      return n.component == 'NumberStepper'
          ? NumberStepper(
              label: label,
              value: (value as num).toDouble(),
              min: spec.min,
              max: spec.max,
              step: spec.step ?? 1,
              unit: c.label('unit'),
              onChanged: callback,
            )
          : MuyonSlider(
              label: label,
              value: (value as num).toDouble(),
              min: spec.min,
              max: spec.max,
              divisions: spec.step == null
                  ? null
                  : ((spec.max - spec.min) / spec.step!).round(),
              unit: c.label('unit'),
              onChanged: callback,
            );
    case 'Toggle':
      final value = c.value('value');
      return value == null
          ? Text('$label：未设置')
          : Toggle(
              label: label,
              value: value as bool,
              onChanged: c.has('change')
                  ? (value) => c.dispatch('change', value)
                  : null,
            );
    case 'DateField':
      final spec = c.spec('value') as UiDateEdit;
      final value = c.value('value');
      return DateField(
        label: label,
        value: value == null ? null : DateTime.parse(value as String),
        first: DateTime.parse(spec.first),
        last: DateTime.parse(spec.last),
        onChanged: c.has('change')
            ? (date) => c.dispatch(
                'change',
                '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              )
            : null,
      );
    case 'SourceCard':
      final source = c.snapshot.sources[n.bindings['source']!.id]!;
      return SourceCard(
        title: c.label('title'),
        excerpt: c.text(c.value('source')),
        location: source.paragraph == null ? null : '段落 ${source.paragraph}',
        onOpen: c.has('tap') ? () => c.dispatch('tap') : null,
      );
    case 'FileCard':
      return FileCard(
        name: c.text(c.value('value')),
        onOpen: c.has('tap') ? () => c.dispatch('tap') : null,
      );
    case 'ProgressCard':
      final value = c.value('value');
      final progress =
          value is num && value.isFinite && value >= 0 && value <= 1
          ? value.toDouble()
          : null;
      return ProgressCard(
        title: c.label('title'),
        progress: progress,
        step: progress == null ? c.text(value) : null,
      );
    case 'Checklist':
      final collection = c.collection('items');
      final ids = n.bindings.containsKey('checked')
          ? c.selection('checked').toSet()
          : <String>{};
      return Checklist(
        items: [
          for (final row in collection.rows)
            ChecklistItem(
              c.cell(row, 'label'),
              checked: ids.contains(row.itemId),
            ),
        ],
        onToggle: n.bindings.containsKey('checked') && c.has('change')
            ? (index, checked) {
                final next = {...ids};
                checked
                    ? next.add(collection.rows[index].itemId)
                    : next.remove(collection.rows[index].itemId);
                c.dispatch('change', UiItemIdsEdit.normalize(next));
              }
            : null,
      );
    case 'Timeline':
      final collection = c.collection('events');
      return Timeline(
        events: [
          for (final row in collection.rows)
            TimelineEvent(
              c.cell(row, 'time'),
              c.cell(row, 'title'),
              detail: row.cells.containsKey('detail')
                  ? c.cell(row, 'detail')
                  : null,
            ),
        ],
      );
    default:
      throw StateError('Unregistered library component ${n.component}');
  }
}
