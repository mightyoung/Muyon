import 'package:flutter/material.dart';

import 'action_surface.dart';
import 'primitives.dart';
import 'tokens.dart';

/// The five platform destinations in v6 order; no business routing is attached.
const muyonDestinations = [
  (
    label: 'AI 助手',
    icon: Icons.chat_bubble_outline,
    selected: Icons.chat_bubble,
  ),
  (label: '业务插件', icon: Icons.extension_outlined, selected: Icons.extension),
  (
    label: '工作台',
    icon: Icons.space_dashboard_outlined,
    selected: Icons.space_dashboard,
  ),
  (
    label: '数据交换',
    icon: Icons.swap_horizontal_circle_outlined,
    selected: Icons.swap_horizontal_circle,
  ),
  (label: '设置', icon: Icons.settings_outlined, selected: Icons.settings),
];
Widget _item(
  BuildContext context,
  int i,
  int selected,
  ValueChanged<int> onChanged, {
  double minimum = MuyonTokens.minimumTarget,
}) {
  final t = MuyonTokens.of(context);
  final d = muyonDestinations[i];
  final active = i == selected;
  return ActionSurface(
    label: d.label,
    selected: active,
    onPressed: () => onChanged(i),
    minimum: minimum,
    background: active ? t.tint : t.sf,
    foreground: active ? t.ink : t.ink3,
    child: Icon(
      active ? d.selected : d.icon,
      size: MuyonTokens.navigationIconSize,
    ),
  );
}

class IconRail extends StatelessWidget {
  const IconRail({super.key, required this.selected, required this.onChanged})
    : assert(selected >= 0 && selected < 5);
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '平台导航',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.all(4),
            child: _item(context, i, selected, onChanged),
          ),
      ],
    ),
  );
}

class BottomIconBar extends StatelessWidget {
  const BottomIconBar({
    super.key,
    required this.selected,
    required this.onChanged,
  }) : assert(selected >= 0 && selected < 5);
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '平台导航',
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _item(
                  context,
                  i,
                  selected,
                  onChanged,
                  minimum: MuyonTokens.minimumTarget,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

enum PageState {
  ready('内容'),
  loading('进行中'),
  empty('暂无内容'),
  filteredEmpty('没有符合筛选条件的内容'),
  error('加载失败');

  const PageState(this.label);
  final String label;
}

/// Content scaffold: callers own their page scrolling and surrounding navigation.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
    this.state = PageState.ready,
    this.child = const SizedBox(),
    this.message,
    this.onAction,
  });
  final String title;
  final String? description, message;
  final List<Widget> actions;
  final PageState state;
  final Widget child;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return Material(
      color: t.canvas,
      child: Padding(
        padding: const EdgeInsets.all(MuyonTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(description!),
              ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            const SizedBox(height: 16),
            if (state == PageState.ready)
              child
            else
              Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(switch (state) {
                      PageState.loading => Icons.hourglass_empty,
                      PageState.error => Icons.error_outline,
                      PageState.filteredEmpty => Icons.filter_alt_off_outlined,
                      _ => Icons.inbox_outlined,
                    }, color: state == PageState.error ? t.red : t.ink2),
                    Text(
                      state.label,
                      style: TextStyle(
                        color: state == PageState.error ? t.red : t.ink,
                      ),
                    ),
                    if (message != null) Text(message!),
                    if (state != PageState.loading && onAction != null)
                      TextButton(
                        onPressed: onAction,
                        child: Text(switch (state) {
                          PageState.filteredEmpty => '清除筛选',
                          PageState.error => '重试',
                          _ => '创建或导入',
                        }),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MasterDetail extends StatefulWidget {
  const MasterDetail({
    super.key,
    required this.master,
    this.detail,
    this.detailTitle = '详情',
    this.onClose,
  });
  final Widget master;
  final Widget? detail;
  final String detailTitle;
  final VoidCallback? onClose;
  @override
  State<MasterDetail> createState() => _MasterDetailState();
}

class _MasterDetailState extends State<MasterDetail> {
  bool closed = false;
  @override
  void didUpdateWidget(covariant MasterDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail != widget.detail) closed = false;
  }

  void close() {
    setState(() => closed = true);
    widget.onClose?.call();
  }

  Widget pane(BuildContext context, VoidCallback onClose) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              widget.detailTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          RoundIconButton(label: '关闭详情', icon: Icons.close, onPressed: onClose),
        ],
      ),
      widget.detail!,
    ],
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.detail == null || closed) return widget.master;
      if (constraints.maxWidth >= MuyonTokens.masterDetailBreakpoint) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(flex: 3, child: widget.master),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: pane(context, close)),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.master,
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (routeContext) => Scaffold(
                  body: SafeArea(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: pane(routeContext, () {
                          Navigator.of(routeContext).pop();
                          close();
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('打开详情'),
          ),
        ],
      );
    },
  );
}
