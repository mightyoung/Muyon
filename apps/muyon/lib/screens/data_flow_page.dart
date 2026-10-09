import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../app/bootstrap.dart';

/// One synchronous, read-only snapshot of what left (or may leave) the
/// device: model/network requests, finished tool calls and host approvals.
///
/// The ledger stores endpoint, digests, sizes and state only — never payload
/// content — so this snapshot is safe to display.
@immutable
class DataFlowSnapshot {
  const DataFlowSnapshot({
    required this.outbound,
    required this.toolCalls,
    required this.approvals,
  });

  final List<Map<String, Object?>> outbound;
  final List<ToolCallResult> toolCalls;
  final List<Map<String, Object?>> approvals;

  factory DataFlowSnapshot.readFrom(MuyonHost host) => DataFlowSnapshot(
    outbound: host.outbound.recent(),
    toolCalls: host.tools.history(),
    approvals: [
      for (final row in host.workspaces.database.raw.select(
        'SELECT tool_id,destination,issued_at,expires_at,state,consumed_at '
        'FROM tool_approvals ORDER BY issued_at DESC, rowid DESC LIMIT 100',
      ))
        Map<String, Object?>.from(row),
    ],
  );
}

/// 数据去向: where model requests and tool calls actually went, with status,
/// destination and failure reasons. Never shows payload content.
class DataFlowPage extends StatefulWidget {
  const DataFlowPage({super.key, required this.host, this.read});

  final MuyonHost host;

  /// Overridden in tests to prove the read-failure state; defaults to
  /// [DataFlowSnapshot.readFrom].
  final DataFlowSnapshot Function()? read;

  @override
  State<DataFlowPage> createState() => _DataFlowPageState();
}

class _DataFlowPageState extends State<DataFlowPage> {
  DataFlowSnapshot? snapshot;
  String? error;
  String caller = '';
  String status = '';

  @override
  void initState() {
    super.initState();
    _assign();
  }

  void _assign() {
    try {
      final value =
          (widget.read ?? () => DataFlowSnapshot.readFrom(widget.host))();
      snapshot = value;
      if (!value.outbound.any((row) => row['caller'] == caller)) caller = '';
      if (!value.outbound.any((row) => row['status'] == status)) status = '';
      error = null;
    } catch (failure) {
      snapshot = null;
      error = '$failure';
    }
  }

  void _reload() => setState(_assign);

  List<Map<String, Object?>> get _requests {
    final data = snapshot?.outbound ?? const <Map<String, Object?>>[];
    return [
      for (final row in data)
        if ((caller.isEmpty || row['caller'] == caller) &&
            (status.isEmpty || row['status'] == status))
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    final data = snapshot;
    return ListView(
      padding: const EdgeInsets.all(MuyonTokens.space4),
      children: [
        Text('数据去向', style: theme.textTheme.titleLarge),
        const SizedBox(height: MuyonTokens.space2),
        Text(
          '实际发生的模型请求与工具调用：端点、位置、大小、状态与错误。'
          '记录只保存摘要与大小，不保存发送内容。',
          style: theme.textTheme.bodySmall,
        ),
        if (error != null) ...[
          const SizedBox(height: MuyonTokens.space4),
          _FailureCard(message: error!, onRetry: _reload),
        ] else if (data != null) ...[
          const SizedBox(height: MuyonTokens.space4),
          _filters(tokens),
          const SizedBox(height: MuyonTokens.space4),
          _Section(title: '模型与外部请求', child: _requestsView(tokens, theme, data)),
          _Section(
            title: '工具调用记录',
            child: _toolCallsView(tokens, theme, data.toolCalls),
          ),
          _Section(
            title: '批准记录',
            child: _approvalsView(tokens, theme, data.approvals),
          ),
        ],
      ],
    );
  }

  Widget _filters(MuyonTokens tokens) {
    final callers = <String>{
      for (final row in snapshot?.outbound ?? const <Map<String, Object?>>[])
        if (row['caller'] is String) row['caller'] as String,
    }.toList()..sort();
    final statuses = <String>{
      for (final row in snapshot?.outbound ?? const <Map<String, Object?>>[])
        if (row['status'] is String) row['status'] as String,
    }.toList();

    Widget callerField() => DropdownButtonFormField<String>(
      key: const ValueKey('data-flow-caller-filter'),
      initialValue: caller,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '调用方'),
      items: [
        const DropdownMenuItem(value: '', child: Text('全部调用方')),
        for (final value in callers)
          DropdownMenuItem(value: value, child: Text(value)),
      ],
      onChanged: (value) => setState(() => caller = value ?? ''),
    );

    Widget statusField() => DropdownButtonFormField<String>(
      key: const ValueKey('data-flow-status-filter'),
      initialValue: status,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '状态'),
      items: [
        const DropdownMenuItem(value: '', child: Text('全部状态')),
        for (final value in statuses)
          DropdownMenuItem(value: value, child: Text(_requestStatus(value))),
      ],
      onChanged: (value) => setState(() => status = value ?? ''),
    );

    return LayoutBuilder(
      builder: (context, size) => size.maxWidth < 520
          ? Column(
              children: [
                callerField(),
                const SizedBox(height: MuyonTokens.space2),
                statusField(),
              ],
            )
          : Row(
              children: [
                Expanded(child: callerField()),
                const SizedBox(width: MuyonTokens.space3),
                Expanded(child: statusField()),
              ],
            ),
    );
  }

  Widget _requestsView(
    MuyonTokens tokens,
    ThemeData theme,
    DataFlowSnapshot data,
  ) {
    if (data.outbound.isEmpty) {
      return const _Quiet('暂无数据发送记录。');
    }
    final rows = _requests;
    if (rows.isEmpty) {
      return const _Quiet('没有符合筛选的记录。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final row in rows) _RequestCard(row: row)],
    );
  }

  Widget _toolCallsView(
    MuyonTokens tokens,
    ThemeData theme,
    List<ToolCallResult> calls,
  ) {
    if (calls.isEmpty) return const _Quiet('暂无工具调用记录。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final call in calls)
          _Row(
            icon: _callIcon(call.status),
            color: _callColor(tokens, call.status),
            title: call.summary,
            subtitle: [
              '工具调用 · ${_callStatus(call.status)}',
              if (call.status == ToolCallStatus.interrupted) '结果未知，重试前请先核实。',
            ].join('\n'),
          ),
      ],
    );
  }

  Widget _approvalsView(
    MuyonTokens tokens,
    ThemeData theme,
    List<Map<String, Object?>> approvals,
  ) {
    if (approvals.isEmpty) return const _Quiet('暂无批准记录。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in approvals)
          _Row(
            icon: Icons.verified_user_outlined,
            color: tokens.ink3,
            title: '${row['tool_id']}',
            subtitle: [
              '目的地 ${row['destination'] ?? '本地'}',
              '发放 ${_time(row['issued_at'])} · 到期 ${_time(row['expires_at'])}',
              '状态 ${_approvalState(row['state'])}',
            ].join('\n'),
          ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.row});
  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    final status = row['status'];
    final proxy = row['cloud_proxy'] == 1 || row['cloud_proxy'] == true;
    final interrupted = status == 'interrupted';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MuyonTokens.space1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.sunken,
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: MuyonTokens.space2,
                runSpacing: MuyonTokens.space1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    _requestIcon(status),
                    size: 18,
                    color: _requestColor(tokens, status),
                  ),
                  Text(
                    '${row['caller']} · ${_requestStatus(status)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: MuyonTokens.space1),
              SelectableText(
                [
                  '时间 ${_time(row['started_at'])}'
                      '${row['finished_at'] == null ? '' : ' → ${_time(row['finished_at'])}'}',
                  '端点 ${row['endpoint']}',
                  '位置 ${_location(row['location'])} · ${proxy ? '经云代理' : '直连'}',
                  '模型 ${row['model_id']}',
                  '载荷 ${_bytes(row['payload_bytes'])} · ${row['item_count']} 条',
                  if (row['http_status'] != null) 'HTTP ${row['http_status']}',
                  if (row['error'] != null) '说明 ${row['error']}',
                ].join('\n'),
                style: theme.textTheme.bodySmall,
              ),
              if (interrupted) ...[
                const SizedBox(height: MuyonTokens.space1),
                Text(
                  '结果未知，重试前请先核实。',
                  style: theme.textTheme.bodySmall?.copyWith(color: tokens.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyonTokens.space4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.rule),
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: MuyonTokens.space2),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MuyonTokens.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: MuyonTokens.space2),
            child: Icon(icon, size: 18, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                SelectableText(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall);
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.redBg,
        borderRadius: BorderRadius.circular(MuyonTokens.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(MuyonTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '读取失败',
              style: theme.textTheme.titleSmall?.copyWith(color: tokens.red),
            ),
            const SizedBox(height: MuyonTokens.space1),
            SelectableText(message, style: theme.textTheme.bodySmall),
            const SizedBox(height: MuyonTokens.space2),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

String _time(Object? value) {
  if (value is! String) return '';
  final at = DateTime.tryParse(value);
  if (at == null) return value;
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _bytes(Object? value) {
  final bytes = value is int ? value : int.tryParse('$value') ?? 0;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _location(Object? value) => switch (value) {
  'local' => '本机',
  'ownDevice' => '本人其他设备',
  'remote' => '远程',
  _ => '$value',
};

String _requestStatus(Object? value) => switch (value) {
  'sending' => '发送中',
  'succeeded' => '成功',
  'failed' => '失败',
  'cancelled' => '已取消',
  'timeout' => '超时',
  'interrupted' => '中断（结果未知）',
  _ => '$value',
};

IconData _requestIcon(Object? value) => switch (value) {
  'sending' => Icons.schedule_outlined,
  'succeeded' => Icons.check_circle_outline,
  'failed' => Icons.error_outline,
  'cancelled' => Icons.cancel_outlined,
  'timeout' => Icons.timer_off_outlined,
  'interrupted' => Icons.help_outline,
  _ => Icons.circle_outlined,
};

Color _requestColor(MuyonTokens tokens, Object? value) => switch (value) {
  'succeeded' => tokens.green,
  'failed' || 'timeout' => tokens.red,
  'interrupted' => tokens.amber,
  _ => tokens.ink3,
};

String _callStatus(ToolCallStatus value) => switch (value) {
  ToolCallStatus.succeeded => '成功',
  ToolCallStatus.failed => '失败',
  ToolCallStatus.invalidArguments => '参数需修正',
  ToolCallStatus.cancelled => '已取消',
  ToolCallStatus.interrupted => '中断（结果未知）',
  ToolCallStatus.blocked => '被阻止',
};

IconData _callIcon(ToolCallStatus value) => switch (value) {
  ToolCallStatus.succeeded => Icons.check_circle_outline,
  ToolCallStatus.failed => Icons.error_outline,
  ToolCallStatus.invalidArguments => Icons.edit_outlined,
  ToolCallStatus.cancelled => Icons.cancel_outlined,
  ToolCallStatus.interrupted => Icons.help_outline,
  ToolCallStatus.blocked => Icons.block_outlined,
};

Color _callColor(MuyonTokens tokens, ToolCallStatus value) => switch (value) {
  ToolCallStatus.succeeded => tokens.green,
  ToolCallStatus.failed => tokens.red,
  ToolCallStatus.interrupted => tokens.amber,
  _ => tokens.ink3,
};

String _approvalState(Object? value) => switch (value) {
  'issued' => '已发放（尚未使用）',
  'consumed' => '已使用',
  'invalidated' => '已失效',
  _ => '$value',
};
