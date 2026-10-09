import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

/// AIUI-2: every library component, in every state, at 320 wide and 200%
/// text; tap targets; semantics; interactions only when ready; the catalog
/// schemas; token-only colours and their contrast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);

  Future<void> show(
    WidgetTester tester,
    String name,
    UiComponentState state, {
    void Function(String)? onEvent,
    Brightness brightness = Brightness.light,
  }) async {
    await mount(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: librarySample(name, state, onEvent: onEvent),
      ),
      brightness: brightness,
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  String textOf(String name) =>
      (librarySample(name, UiComponentState.ready) as dynamic).textEquivalent
          as String;

  group('every component and state at 320/200%', () {
    for (final name in libraryGalleryNames) {
      for (final brightness in Brightness.values) {
        testWidgets('$name ${brightness.name}', (tester) async {
          for (final state in libraryStates) {
            await show(tester, name, state, brightness: brightness);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$name $state');
          }
        });
      }
    }
  });

  group('text equivalent', () {
    for (final name in libraryGalleryNames) {
      testWidgets('$name is announced and degrades to it', (tester) async {
        final handle = tester.ensureSemantics();
        final text = textOf(name);
        expect(text.trim(), isNotEmpty);
        await show(tester, name, UiComponentState.ready);
        expect(find.bySemanticsLabel(text), findsOneWidget);
        await show(tester, name, UiComponentState.degraded);
        expect(find.text(text), findsOneWidget, reason: 'shown as text');
        expect(find.bySemanticsLabel('已降级为文字：$text'), findsOneWidget);
        await show(tester, name, UiComponentState.loading);
        expect(find.bySemanticsLabel('加载中：$text'), findsOneWidget);
        await show(tester, name, UiComponentState.error);
        expect(find.bySemanticsLabel(RegExp('^出错：')), findsOneWidget);
        handle.dispose();
      });
    }

    test('the chart text carries its whole data table', () {
      final text = textOf('Chart');
      for (final part in ['甲 1350元', '乙 1280元', '丙 1410元']) {
        expect(text, contains(part));
      }
    });

    test('compare marks are words, not only colours', () {
      final text = textOf('CompareTable');
      expect(text, contains('1,280（最优）'));
      expect(text, contains('22 天（不满足）'));
      expect(text, contains('待补（未核验）'));
    });
  });

  /// Controls by key, with the semantics label each must expose.
  const controls = <String, List<(String key, Pattern label)>>{
    'Tabs': [('tab-0', '报价，第 1 个，共 3 个')],
    'Disclosure': [('disclosure-toggle', '查看计算口径')],
    'Choice': [('choice-货到付款', '货到付款'), ('choice-custom-add', '添加')],
    'Form': [('form-submit', '提交确认')],
    'NumberStepper': [('stepper-minus', '减少 数量'), ('stepper-plus', '增加 数量')],
    'Slider': [('slider-target', '价格权重')],
    'Toggle': [('toggle', '只看资质齐全的')],
    'DateField': [('date-field', '修改截止日期，当前2026-11-30')],
    'SourceCard': [('source-open', '查看原文')],
    'FileCard': [('file-open', '打开文件「询价清单.xlsx」')],
    'Checklist': [('check-1', '核对资质')],
  };

  group('controls', () {
    for (final entry in controls.entries) {
      testWidgets('${entry.key}: 48 target and a label at 200%', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await show(tester, entry.key, UiComponentState.ready);
        for (final (key, label) in entry.value) {
          final finder = find.byKey(ValueKey(key));
          expect(finder, findsOneWidget, reason: key);
          minimum(tester, finder);
          expect(
            find.bySemanticsLabel(label),
            findsWidgets,
            reason: '$key labelled $label',
          );
        }
        handle.dispose();
      });

      testWidgets('${entry.key}: acts only when ready', (tester) async {
        final events = <String>[];
        final (key, _) = entry.value.first;
        if (entry.key == 'DateField') return; // opens a dialog; covered below
        await show(
          tester,
          entry.key,
          UiComponentState.readOnly,
          onEvent: events.add,
        );
        await tester.tap(find.byKey(ValueKey(key)), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(events, isEmpty, reason: 'read-only does nothing');
      });
    }

    testWidgets('ready controls report their event', (tester) async {
      final events = <String>[];
      for (final (name, key) in [
        ('Choice', 'choice-货到付款'),
        ('Form', 'form-submit'),
        ('NumberStepper', 'stepper-plus'),
        ('Toggle', 'toggle'),
        ('SourceCard', 'source-open'),
        ('FileCard', 'file-open'),
        ('Checklist', 'check-1'),
      ]) {
        events.clear();
        await show(tester, name, UiComponentState.ready, onEvent: events.add);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(events, hasLength(1), reason: name);
      }
    });

    testWidgets('date field opens a picker only when ready', (tester) async {
      await show(tester, 'DateField', UiComponentState.readOnly);
      await tester.tap(find.byKey(const ValueKey('date-field')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      await show(tester, 'DateField', UiComponentState.ready);
      await tester.tap(find.byKey(const ValueKey('date-field')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('tabs and disclosure switch locally', (tester) async {
      await show(tester, 'Tabs', UiComponentState.ready);
      expect(find.text('报价内容'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pump();
      expect(find.text('交期内容'), findsOneWidget);
      await show(tester, 'Disclosure', UiComponentState.ready);
      expect(find.text('含税单价 × 数量，不含运费'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('disclosure-toggle')));
      await tester.pump();
      expect(find.text('含税单价 × 数量，不含运费'), findsNothing);
    });
  });

  group('UI-1a components with library states', () {
    testWidgets('ready is unchanged; read-only disables; others use the '
        'frame', (tester) async {
      var taps = 0;
      Widget chip(UiComponentState s) =>
          ObjectChip(label: '项目', onPressed: () => taps++, uiState: s);
      await mount(tester, chip(UiComponentState.ready));
      await tester.tap(find.text('项目'));
      expect(taps, 1);
      await mount(tester, chip(UiComponentState.readOnly));
      await tester.tap(find.text('项目'), warnIfMissed: false);
      expect(taps, 1);
      for (final (state, text) in [
        (UiComponentState.loading, '加载中…'),
        (UiComponentState.error, '无法显示这部分内容'),
        (UiComponentState.degraded, '对象：项目'),
      ]) {
        for (final widget in <Widget>[
          chip(state),
          StatusBadge(status: BusinessStatus.pending, uiState: state),
          ScopeChip(label: '项目', uiState: state),
          WarnBanner(uiState: state),
        ]) {
          await mount(tester, widget);
          expect(tester.takeException(), isNull);
          if (widget is ObjectChip) expect(find.text(text), findsOneWidget);
        }
      }
      var decided = 0;
      const item = ConfirmItem(
        kind: ConfirmationKind.write,
        what: '新增询价单',
        who: '当前项目',
        payload: '内容',
        digest: 'd',
        consequence: '写入本地',
      );
      await mount(
        tester,
        ConfirmCard(
          item: item,
          onDecision: (_) => decided++,
          uiState: UiComponentState.readOnly,
        ),
      );
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        if (button.child is Text &&
            ConfirmationChoice.values.any(
              (c) => c.label == (button.child! as Text).data,
            )) {
          expect(button.onPressed, isNull);
        }
      }
      expect(decided, 0);
      await mount(
        tester,
        BatchConfirmCard(
          items: const [item],
          onAllowAll: () => decided++,
          uiState: UiComponentState.readOnly,
        ),
      );
      await tester.tap(find.text('全部允许'), warnIfMissed: false);
      expect(decided, 0);
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('catalog', () {
    test('every library component is registered with a schema', () {
      for (final name in libraryComponentNames) {
        expect(libraryUiCatalog.components, contains(name), reason: name);
      }
      expect(libraryComponentNames, hasLength(21));
      for (final name in dynamicUiCatalog.components.keys) {
        expect(
          libraryUiCatalog.components[name],
          same(dynamicUiCatalog.components[name]),
          reason: '$name kept as in dynamic-1',
        );
      }
    });

    test('every event action exists; inputs only edit; submit is business', () {
      for (final entry in libraryUiCatalog.components.entries) {
        for (final actions in entry.value.eventActions.values) {
          for (final action in actions) {
            expect(
              libraryUiCatalog.actions,
              contains(action),
              reason: entry.key,
            );
          }
        }
      }
      for (final name in [
        'Choice',
        'NumberStepper',
        'Slider',
        'Toggle',
        'DateField',
        'Checklist',
      ]) {
        expect(
          libraryUiCatalog.components[name]!.eventActions.values.expand(
            (a) => a,
          ),
          everyElement('edit'),
          reason: name,
        );
      }
      expect(libraryUiCatalog.actions['submit']!.route, UiActionRoute.business);
    });

    test('chart and data components take numbers only from bindings', () {
      final chart = libraryUiCatalog.components['Chart']!;
      expect(chart.requiredBindings, contains('data'));
      for (final name in ['Chart', 'Metric', 'KeyValue', 'CompareTable']) {
        final schema = libraryUiCatalog.components[name]!;
        expect(
          schema.properties.keys.toSet().intersection({
            'data',
            'value',
            'rows',
            'points',
          }),
          isEmpty,
          reason: '$name has no data property',
        );
      }
    });

    test('the planner catalog is unchanged by the library', () {
      expect(dynamicUiCatalog.version, 'dynamic-1');
      expect(dynamicUiCatalog.components.keys.toSet(), {
        'PageScaffold',
        'Field',
        'Table',
        'SourceList',
        'ObjectChip',
        'MasterDetail',
        'StatusBadge',
        'ScopeChip',
        'WarnBanner',
        'SegmentedPill',
        'ConfirmCard',
        'BatchConfirmCard',
      });
    });

    testWidgets('the debug catalog renders every library sample', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final name in libraryGalleryNames) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(name),
            theme: muyonTheme(Brightness.light),
            home: ComponentCatalog(initialComponent: name),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(name), findsWidgets);
        expect(find.textContaining('状态 '), findsWidgets);
        expect(tester.takeException(), isNull, reason: name);
      }
    });
  });

  group('colours', () {
    test('library code uses v6 tokens, never literal colours', () {
      final dir = Directory('lib/src/ui_components');
      for (final file in dir.listSync().whereType<File>()) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('Color(0x')), reason: file.path);
        expect(
          RegExp(r'Colors\.(?!transparent\b)\w+').hasMatch(source),
          isFalse,
          reason: file.path,
        );
      }
    });

    double luminance(Color c) {
      double linear(double v) => v <= .04045
          ? v / 12.92
          : math.pow((v + .055) / 1.055, 2.4).toDouble();
      return .2126 * linear(c.r) + .7152 * linear(c.g) + .0722 * linear(c.b);
    }

    double contrast(Color a, Color b) =>
        (math.max(luminance(a), luminance(b)) + .05) /
        (math.min(luminance(a), luminance(b)) + .05);

    for (final brightness in Brightness.values) {
      test('$brightness pairs the library adds meet 4.5:1', () {
        final t = MuyonTokens.forBrightness(brightness);
        for (final (name, fg, bg) in [
          ('selected tab/option', t.accent, t.accentTint),
          ('table header', t.ink2, t.groupRow),
          ('table cell', t.ink, t.groupRow),
          ('best cell', t.ink, t.greenBg),
          ('unmet cell', t.ink, t.redBg),
          ('unverified cell', t.ink, t.warnBg),
          ('placeholder', t.ink3, t.sunken),
          ('degraded text', t.ink, t.sunken),
          ('muted label', t.ink3, t.surface),
          ('secondary', t.ink2, t.surface),
        ]) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness $name',
          );
        }
      });
    }
  });
}
