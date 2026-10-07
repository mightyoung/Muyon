import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../services/models/capability_probe.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/profile_repository.dart';

/// Runs a probe for the dialog; the shell supplies one bound to the host's
/// gateway, gate and ledger.
typedef ProbeRunner = Future<ProbeOutcome> Function(
  ModelProfile profile, {
  required bool extended,
  required Future<bool> Function(ProbeConfirmation) confirm,
});

/// One saved model on the settings page: what it is, the streaming switch,
/// "测试连接" and the last detection result.
class ModelProfileTile extends StatelessWidget {
  const ModelProfileTile({
    super.key,
    required this.profile,
    required this.onStreaming,
    required this.onTest,
    required this.onDelete,
  });
  final ModelProfile profile;
  final ValueChanged<bool> onStreaming;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chat = profile.purpose == ModelPurpose.chat;
    final detected = profile.detectedCapabilities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(profile.endpointIdentity),
          subtitle: Text(
            '${profile.location.name} · ${profile.modelId}\n${profile.endpoint}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: '删除模型配置',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ),
        if (chat) ...[
          SwitchListTile(
            key: ValueKey('streaming-${profile.id}'),
            dense: true,
            title: const Text('流式显示'),
            subtitle: const Text('边生成边显示草稿；关闭后等回复完整再显示'),
            value: profile.capabilities.streaming,
            onChanged: onStreaming,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MuyonTokens.space4),
            child: Wrap(
              spacing: MuyonTokens.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('test-${profile.id}'),
                  onPressed: onTest,
                  icon: const Icon(Icons.network_check),
                  label: const Text('测试连接'),
                ),
                Text(
                  _summary(profile.capabilities, detected),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _summary(
    ModelCapabilities now,
    DetectedCapabilities? detected,
  ) {
    final mode = now.nativeTools ? '原生工具' : '兼容模式';
    final source = switch (now.source) {
      CapabilitySource.detected => '（测试连接）',
      CapabilitySource.preset => '（预设）',
      CapabilitySource.userDeclared => '（手动设置）',
      CapabilitySource.migrated => '（迁移）',
      CapabilitySource.unknown => '',
    };
    final pending = detected != null && detected.differsFrom(now)
        ? ' · 有未采用的检测结果'
        : '';
    return '$mode$source$pending';
  }
}

/// The one-time notice after the capability migration ("streaming is now on
/// for your existing models"). It reads the notice when it first appears,
/// clears it at once, and keeps showing it until dismissed, so it is seen
/// once and never comes back.
class ProfileMigrationNotice extends StatefulWidget {
  const ProfileMigrationNotice({
    super.key,
    required this.read,
    required this.clear,
  });

  /// The pending count, or null when there is nothing to tell.
  final int? Function() read;
  final Future<void> Function() clear;

  @override
  State<ProfileMigrationNotice> createState() => _ProfileMigrationNoticeState();
}

class _ProfileMigrationNoticeState extends State<ProfileMigrationNotice> {
  int? _count;
  @override
  void initState() {
    super.initState();
    _count = widget.read();
    if (_count != null) {
      unawaited(widget.clear().catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_count == null) return const SizedBox.shrink();
    final tokens = MuyonTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyonTokens.space3),
      child: DecoratedBox(
        key: const ValueKey('profile-migration-notice'),
        decoration: BoxDecoration(
          color: tokens.accentTint,
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space3),
          child: Row(
            children: [
              const Expanded(child: Text('已为已有模型启用流式显示，可在每个模型上关闭')),
              TextButton(
                onPressed: () => setState(() => _count = null),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showConnectionTestDialog(
  BuildContext context, {
  required ModelProfile profile,
  required ProbeRunner run,
  required Future<void> Function(DetectedCapabilities) onDetected,
  required Future<void> Function(ModelCapabilities) onAdopt,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => ConnectionTestDialog(
    profile: profile,
    run: run,
    onDetected: onDetected,
    onAdopt: onAdopt,
  ),
);

enum _Phase { options, confirming, running, result, stopped, failed }

/// "测试连接" (ADR-0005 §4.5). The probe asks the person before every
/// request; what it finds is shown next to the current settings and written
/// only when "采用" is clicked.
class ConnectionTestDialog extends StatefulWidget {
  const ConnectionTestDialog({
    super.key,
    required this.profile,
    required this.run,
    required this.onDetected,
    required this.onAdopt,
  });
  final ModelProfile profile;
  final ProbeRunner run;

  /// Store the result next to the capabilities (never in them).
  final Future<void> Function(DetectedCapabilities) onDetected;

  /// Write the adopted capabilities to the profile.
  final Future<void> Function(ModelCapabilities) onAdopt;

  @override
  State<ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

class _ConnectionTestDialogState extends State<ConnectionTestDialog> {
  _Phase _phase = _Phase.options;
  bool _extended = false;
  ProbeConfirmation? _asking;
  Completer<bool>? _answer;
  DetectedCapabilities? _detected;
  String? _stoppedBy;
  bool _adopted = false;
  bool _rejected = false;

  @override
  void dispose() {
    // Closing the dialog while a card is open is a "no".
    final pending = _answer;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    super.dispose();
  }

  Future<bool> _confirm(ProbeConfirmation card) {
    final answer = Completer<bool>();
    if (!mounted) return Future.value(false);
    setState(() {
      _asking = card;
      _answer = answer;
      _phase = _Phase.confirming;
    });
    return answer.future;
  }

  void _decide(bool yes) {
    final answer = _answer;
    if (answer == null || answer.isCompleted) return;
    setState(() {
      _phase = yes ? _Phase.running : _Phase.stopped;
      _stoppedBy = yes ? null : 'declined';
    });
    answer.complete(yes);
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.running);
    try {
      final outcome = await widget.run(
        widget.profile,
        extended: _extended,
        confirm: _confirm,
      );
      if (!mounted) return;
      final detected = outcome.detected;
      if (detected != null) await widget.onDetected(detected);
      if (!mounted) return;
      setState(() {
        _detected = detected;
        _stoppedBy = outcome.stoppedBy;
        _rejected = outcome.rejected;
        _phase = detected == null ? _Phase.stopped : _Phase.result;
      });
    } catch (_) {
      // Never show the error text: it could carry endpoint content.
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _adopt() async {
    final detected = _detected!;
    await widget.onAdopt(detected.adoptedOver(widget.profile.capabilities));
    if (mounted) setState(() => _adopted = true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.running || _phase == _Phase.confirming;
    return AlertDialog(
      title: Text('测试连接 · ${widget.profile.endpointIdentity}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(child: _body(context)),
      ),
      actions: [
        if (_phase == _Phase.confirming) ...[
          TextButton(
            key: const ValueKey('probe-decline'),
            onPressed: () => _decide(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('probe-confirm'),
            onPressed: () => _decide(true),
            child: const Text('确认发送本次探测'),
          ),
        ] else ...[
          if (_phase == _Phase.result &&
              !_adopted &&
              _detected!.differsFrom(widget.profile.capabilities))
            FilledButton(
              key: const ValueKey('probe-adopt'),
              onPressed: _adopt,
              child: const Text('采用'),
            ),
          if (_phase == _Phase.options)
            FilledButton(
              key: const ValueKey('probe-start'),
              onPressed: _start,
              child: const Text('开始测试'),
            ),
          TextButton(
            key: const ValueKey('probe-close'),
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(_phase == _Phase.options ? '取消' : '关闭'),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_phase) {
      case _Phase.options:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.profile.endpoint}\n${widget.profile.modelId}'),
            const SizedBox(height: MuyonTokens.space3),
            const Text(
              '只在你点击时运行：向该端点发送固定的探测内容（不含你的任何资料），'
              '检测原生工具调用、流式与用量上报。每次发送前都会请你确认。',
            ),
            CheckboxListTile(
              key: const ValueKey('probe-extended'),
              contentPadding: EdgeInsets.zero,
              value: _extended,
              onChanged: (v) => setState(() => _extended = v ?? false),
              title: const Text('同时检测 JSON 模式与并行工具调用（多发送 1 次请求）'),
            ),
          ],
        );
      case _Phase.confirming:
        final card = _asking!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 ${card.index}/${card.total} 次请求',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: MuyonTokens.space2),
            Text(card.notice, key: const ValueKey('probe-notice')),
            Text('目标：${card.profile.endpoint}'),
            const SizedBox(height: MuyonTokens.space2),
            const Text('固定探测内容：'),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(card.payload),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: MuyonTokens.space2),
            SelectableText('摘要：${card.digest}'),
          ],
        );
      case _Phase.running:
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: MuyonTokens.space3),
            Text('正在测试…'),
          ],
        );
      case _Phase.stopped:
        return Text(switch (_stoppedBy) {
          'denied' => '本次探测未获放行，没有发送任何内容。',
          'cancelled' => '已取消。',
          _ => '已取消，没有发送任何内容；设置未改变。',
        }, key: const ValueKey('probe-stopped'));
      case _Phase.failed:
        return const Text('测试没有完成；设置未改变。');
      case _Phase.result:
        return _result(context, _detected!);
    }
  }

  Widget _result(BuildContext context, DetectedCapabilities d) {
    final now = widget.profile.capabilities;
    String verdict(ProbeVerdict v) => switch (v) {
      ProbeVerdict.yes => '是',
      ProbeVerdict.no => '否',
      ProbeVerdict.unconfirmed => '未确认（按“否”处理）',
      ProbeVerdict.undetermined => '未能判定（不改变设置）',
      ProbeVerdict.notTested => '未检测',
    };
    String onOff(bool v) => v ? '开' : '关';
    String size(int? v) => v == null ? '未设置' : '$v';
    final rows = <(String, String, String)>[
      ('原生工具调用', verdict(d.nativeTools), onOff(now.nativeTools)),
      ('流式', verdict(d.streaming), onOff(now.streaming)),
      ('用量上报', verdict(d.reportsUsage), onOff(now.reportsUsage)),
      if (d.jsonObject != ProbeVerdict.notTested)
        ('JSON 模式', verdict(d.jsonObject), onOff(now.jsonObject)),
      if (d.parallelToolCalls != ProbeVerdict.notTested)
        ('并行工具调用', verdict(d.parallelToolCalls), onOff(now.parallelToolCalls)),
      if (d.contextTokens != null)
        ('上下文窗口（预设）', size(d.contextTokens), size(now.contextTokens)),
      if (d.maxOutputTokens != null)
        ('最大输出（预设）', size(d.maxOutputTokens), size(now.maxOutputTokens)),
    ];
    final theme = Theme.of(context);
    final differs = d.differsFrom(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          key: const ValueKey('probe-result'),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(1.5),
          },
          children: [
            TableRow(
              children: [
                for (final h in ['项目', '检测到', '当前设置'])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: MuyonTokens.space1,
                    ),
                    child: Text(h, style: theme.textTheme.labelLarge),
                  ),
              ],
            ),
            for (final (name, found, current) in rows)
              TableRow(
                children: [
                  for (final cell in [name, found, current])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: MuyonTokens.space1,
                      ),
                      child: Text(cell),
                    ),
                ],
              ),
          ],
        ),
        if (_rejected) ...[
          const SizedBox(height: MuyonTokens.space3),
          const Text(
            '端点以 400/422 拒绝（可能是工具、流式或其他参数），请手动确认',
            key: ValueKey('probe-rejected-note'),
          ),
        ],
        const SizedBox(height: MuyonTokens.space3),
        Text(
          _adopted
              ? '已采用。新任务按新设置运行，已开始的任务不受影响。'
              : differs
              ? '检测结果尚未生效；点“采用”后才会写入该模型的设置，已开始的任务不受影响。'
              : '检测结果与当前设置一致，无需采用。',
          key: const ValueKey('probe-effect-note'),
        ),
      ],
    );
  }
}

/// "测试连接" for one saved profile: opens the dialog, stores the result next
/// to the profile's capabilities (never in them), and writes the capabilities
/// only when the person adopts it. Each write re-reads the profile, so a
/// switch flipped meanwhile is kept.
Future<void> testProfileConnection(
  BuildContext context, {
  required ModelProfile profile,
  required ProfileRepository profiles,
  required ProbeRunner run,
  VoidCallback? onChanged,
}) {
  Future<void> store(ModelProfile Function(ModelProfile current) change) async {
    final current = profiles.all().firstWhere((p) => p.id == profile.id);
    await profiles.save(change(current));
    onChanged?.call();
  }

  return showConnectionTestDialog(
    context,
    profile: profile,
    run: run,
    onDetected: (detected) =>
        store((p) => p.copyWith(detectedCapabilities: detected)),
    onAdopt: (adopted) => store((p) => p.copyWith(capabilities: adopted)),
  );
}
