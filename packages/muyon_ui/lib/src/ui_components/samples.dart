import 'package:flutter/material.dart';

import '../primitives.dart' show StatusTone;
import 'business.dart';
import 'data.dart';
import 'inputs.dart';
import 'layout.dart';
import 'state.dart';

/// Fixed samples of every library component (AIUI-2), shared by the debug
/// catalog, the widget tests and the goldens so all three show the same thing.
///
/// [onEvent] receives a short description of each interaction; samples never
/// change real data.
Widget librarySample(
  String name,
  UiComponentState state, {
  void Function(String event)? onEvent,
}) {
  void emit(String event) => onEvent?.call(event);
  return switch (name) {
    'Heading' => Heading(text: '华东泵站询价', level: 2, state: state),
    'Prose' => Prose(
      text: '三家供应商都已回价。\n\n乙家的单价最低，但交期比要求晚一周，需要再确认。',
      state: state,
    ),
    'Section' => Section(
      title: '报价概况',
      state: state,
      children: const [Text('共 3 家回价，1 家未回复')],
    ),
    'Columns' => Columns(
      state: state,
      children: const [Text('左栏：需求摘要'), Text('右栏：候选供应商')],
    ),
    'Tabs' => MuyonTabs(
      labels: const ['报价', '交期', '资质'],
      state: state,
      children: const [Text('报价内容'), Text('交期内容'), Text('资质内容')],
    ),
    'Disclosure' => Disclosure(
      title: '查看计算口径',
      initiallyExpanded: true,
      state: state,
      child: const Text('含税单价 × 数量，不含运费'),
    ),
    'KeyValue' => KeyValue(
      items: const [('项目', '华东泵站改造'), ('预算', '120 万元'), ('截止', '2026-11-30')],
      state: state,
    ),
    'Metric' => Metric(
      label: '最低含税单价',
      value: '1,280',
      unit: '元/台',
      delta: '比预算低 6%',
      tone: StatusTone.success,
      state: state,
    ),
    'CompareTable' => CompareTable(
      columns: const ['供应商', '单价', '交期', '资质'],
      rows: const [
        ['甲', '1,350', '15 天', '齐全'],
        ['乙', '1,280', '22 天', '齐全'],
        ['丙', '1,410', '12 天', '待补'],
      ],
      marks: const {
        (1, 1): CompareMark.best,
        (1, 2): CompareMark.unmet,
        (2, 3): CompareMark.unverified,
      },
      state: state,
    ),
    'Chart' => Chart(
      kind: ChartKind.bar,
      title: '各家单价',
      unit: '元',
      points: const [
        ChartPoint('甲', 1350),
        ChartPoint('乙', 1280),
        ChartPoint('丙', 1410),
      ],
      state: state,
    ),
    'Choice' => Choice(
      label: '付款方式',
      options: const ['预付 30%', '货到付款'],
      selected: const {'预付 30%'},
      allowCustom: true,
      onChanged: (v) => emit('选择 ${v.join('、')}'),
      state: state,
    ),
    'Form' => MuyonForm(
      title: '新建询价',
      submitLabel: '提交确认',
      onSubmit: () => emit('提交表单'),
      state: state,
      children: const [Text('物料：离心泵'), Text('数量：12 台')],
    ),
    'NumberStepper' => NumberStepper(
      label: '数量',
      value: 12,
      min: 1,
      max: 99,
      unit: '台',
      onChanged: (v) => emit('数量 $v'),
      state: state,
    ),
    'Slider' => MuyonSlider(
      label: '价格权重',
      value: 60,
      unit: '%',
      divisions: 10,
      onChanged: (v) => emit('权重 $v'),
      state: state,
    ),
    'Toggle' => Toggle(
      label: '只看资质齐全的',
      value: true,
      onChanged: (v) => emit('开关 $v'),
      state: state,
    ),
    'DateField' => DateField(
      label: '截止日期',
      value: DateTime(2026, 11, 30),
      onChanged: (v) => emit('日期 $v'),
      state: state,
    ),
    'SourceCard' => SourceCard(
      title: '乙家报价单.pdf',
      location: '第 2 页',
      excerpt: '含税单价 1,280 元/台，交期 22 天。',
      onOpen: () => emit('查看原文'),
      state: state,
    ),
    'FileCard' => FileCard(
      name: '询价清单.xlsx',
      sizeText: '48 KB',
      onOpen: () => emit('打开文件'),
      state: state,
    ),
    'ProgressCard' => ProgressCard(
      title: '解析报价单',
      progress: 0.6,
      step: '第 3 步，共 5 步：核对单位',
      state: state,
    ),
    'Checklist' => Checklist(
      items: const [
        ChecklistItem('确认数量', checked: true),
        ChecklistItem('核对资质'),
      ],
      onToggle: (i, v) => emit('勾选 $i $v'),
      state: state,
    ),
    'Timeline' => Timeline(
      events: const [
        TimelineEvent('10-08', '发出询价', detail: '3 家'),
        TimelineEvent('10-09', '收到回价'),
      ],
      state: state,
    ),
    'Table' => MuyonTable(
      columns: const ['物料', '数量'],
      rows: const [
        ['离心泵', '12 台'],
        ['阀门', '30 个'],
      ],
      state: state,
    ),
    _ => throw ArgumentError.value(name, 'name', 'not a library component'),
  };
}

/// Every state a sample is shown in, in display order.
const libraryStates = UiComponentState.values;
