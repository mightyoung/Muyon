import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'confirmation.dart';
import 'navigation_layout.dart';
import 'overlays.dart';
import 'primitives.dart';
import 'theme.dart';

const componentNames = [
  'PageScaffold',
  'MasterDetail',
  'StatusBadge',
  'ObjectChip',
  'SegmentedPill',
  'IconRail',
  'BottomIconBar',
  'ConfirmCard',
  'BatchConfirmCard',
  'WarnBanner',
  'ScopeChip',
  'MuyonDialog',
  'MuyonToast',
  'RoundIconButton',
  'TitlePill',
];

/// Production builds have no catalog route or catalog launch target.
Map<String, WidgetBuilder> muyonDebugRoutes() =>
    kDebugMode ? {'/debug/components': (_) => const ComponentCatalog()} : {};

class ComponentCatalog extends StatefulWidget {
  const ComponentCatalog({
    super.key,
    this.initialComponent = 'StatusBadge',
    this.initialBrightness = Brightness.light,
  });
  final String initialComponent;
  final Brightness initialBrightness;
  @override
  State<ComponentCatalog> createState() => _ComponentCatalogState();
}

class _ComponentCatalogState extends State<ComponentCatalog> {
  late String component = widget.initialComponent;
  late bool dark = widget.initialBrightness == Brightness.dark;
  int selected = 0;
  ConfirmItem item(ConfirmationKind kind) => ConfirmItem(
    kind: kind,
    what: '核对并处理所选项目内容',
    who: '当前项目 · 云川供应商',
    payload: '发送的完整内容包含中文与 emoji 😀，展开后可以逐字核对。',
    digest: 'a1b2c3d4' * 8,
    consequence: kind.outbound ? '内容发出后无法撤回' : '仅影响明确选择的对象',
  );
  void notify(BuildContext context, String message) =>
      MuyonToast.show(context, message: message);
  List<Widget> samples(BuildContext context) => switch (component) {
    'PageScaffold' => [
      for (final state in PageState.values)
        PageScaffold(
          title: '项目内容',
          description: '标题与说明随内容和文字缩放增高',
          state: state,
          onAction: () => notify(context, state.label),
          child: const Text('内容已就绪'),
        ),
    ],
    'MasterDetail' => [
      const MasterDetail(master: Text('主列表 · 详情关闭')),
      MasterDetail(
        master: const Text('主列表 · 详情打开'),
        detail: const Text('完整详情内容，不固定详情宽度'),
        onClose: () => notify(context, '已关闭详情'),
      ),
    ],
    'StatusBadge' => [
      for (final status in BusinessStatus.values) StatusBadge(status: status),
    ],
    'ObjectChip' => [
      ObjectChip(label: '可回跳对象', onPressed: () => notify(context, '对象回跳示例')),
      const ObjectChip(label: '不可操作对象'),
      const ObjectChip(label: '旧报价', missing: true),
    ],
    'SegmentedPill' => [
      for (final count in [2, 3])
        for (var i = 0; i < count; i++)
          SegmentedPill(
            labels: ['全部', '项目', '归档'].take(count).toList(),
            selected: i,
            onChanged: (value) => notify(context, '选择 $value'),
          ),
    ],
    'IconRail' => [
      for (var i = 0; i < 5; i++)
        IconRail(
          selected: i,
          onChanged: (value) => setState(() => selected = value),
        ),
    ],
    'BottomIconBar' => [
      BottomIconBar(
        selected: selected,
        onChanged: (value) => setState(() => selected = value),
      ),
      for (var i = 0; i < 5; i++)
        BottomIconBar(
          selected: i,
          onChanged: (value) => setState(() => selected = value),
        ),
    ],
    'ConfirmCard' => [
      for (final kind in ConfirmationKind.values)
        for (final status in [
          BusinessStatus.pending,
          BusinessStatus.confirmed,
          BusinessStatus.rejected,
          BusinessStatus.authorized,
          BusinessStatus.expired,
          BusinessStatus.scopeChanged,
          BusinessStatus.contentReview,
          BusinessStatus.blocked,
          BusinessStatus.externalContent,
        ])
          ConfirmCard(
            item: item(kind),
            status: status,
            onDecision: (choice) => notify(context, choice.label),
          ),
    ],
    'BatchConfirmCard' => [
      for (final external in [false, true])
        for (final state in BatchState.values)
          BatchConfirmCard(
            items: [
              item(ConfirmationKind.write),
              item(ConfirmationKind.outboundNew),
            ],
            state: state,
            externalContent: external,
            onAllowAll: () => notify(context, '全部允许示例'),
            onIndividual: () => notify(context, '逐项决定示例'),
            onReject: () => notify(context, '拒绝示例'),
          ),
      const BatchConfirmCard(items: []),
    ],
    'WarnBanner' => [
      const WarnBanner(),
      WarnBanner(
        actionLabel: '查看暂停的授权',
        onAction: () => notify(context, '本任务中暂停'),
      ),
    ],
    'ScopeChip' => [
      for (final scope in ['全局', '工作区', '项目', '选中 2 个对象'])
        ScopeChip(
          label: scope,
          objects: scope == '选中 2 个对象' ? ['论文', '报价'] : [],
        ),
    ],
    'MuyonDialog' => [
      for (final label in ['确认', '确认删除', '禁用确认'])
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => MuyonDialog(
              title: '核对范围与后果',
              message: '完整说明会随文字增高；超出视口可以滚动。',
              confirmLabel: label,
              onConfirm: label == '禁用确认'
                  ? null
                  : () => notify(context, '已确认示例'),
            ),
          ),
          child: Text('打开$label对话框'),
        ),
    ],
    'MuyonToast' => [
      for (final status in [
        BusinessStatus.success,
        BusinessStatus.failed,
        BusinessStatus.warning,
        BusinessStatus.neutral,
      ])
        MuyonToast(
          message: '完整结果说明，不截断内容',
          status: status,
          actionLabel: '查看结果',
          onAction: () => notify(context, '结果示例'),
        ),
    ],
    'RoundIconButton' => [
      for (final filled in [false, true])
        RoundIconButton(
          label: filled ? '主色创建' : '描边创建',
          icon: Icons.add,
          filled: filled,
          onPressed: () => notify(context, '创建示例'),
        ),
      const RoundIconButton(label: '暂不可创建', icon: Icons.add),
    ],
    'TitlePill' => [
      const TitlePill(label: '纯标题胶囊'),
      TitlePill(label: '打开插件菜单', onPressed: () => notify(context, '菜单示例')),
    ],
    _ => throw ArgumentError.value(component, 'initialComponent'),
  };
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Theme(
      data: muyonTheme(dark ? Brightness.dark : Brightness.light),
      child: Builder(
        builder: (context) {
          final children = samples(context);
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '组件目录',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      RoundIconButton(
                        label: dark ? '切换浅色' : '切换深色',
                        icon: dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        onPressed: () => setState(() => dark = !dark),
                      ),
                    ],
                  ),
                  Semantics(
                    label: '选择组件',
                    child: DropdownButton<String>(
                      value: component,
                      isExpanded: true,
                      itemHeight: null,
                      items: [
                        for (final name in componentNames)
                          DropdownMenuItem(
                            value: name,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(name),
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => component = value);
                      },
                    ),
                  ),
                  const Text('仅 debug · 内容自适应 · 所有示例不连接助手'),
                  const SizedBox(height: 16),
                  for (var i = 0; i < children.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '状态 ${i + 1}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          children[i],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
