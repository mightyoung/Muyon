import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../../app/bootstrap.dart';
import '../../platform/grants/grant.dart';
import '../../platform/grants/grant_store.dart';
import '../data_flow_page.dart';

/// Presentation only: never exposes raw audit detail, scopes or credentials.
String assistantEndpointDisplay(String? destination) {
  if (destination == null) {
    return '本地';
  }
  final uri = Uri.tryParse(destination);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return '目的地已绑定（详情隐藏）';
  }
  return '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
}

class AssistantControlAudit {
  const AssistantControlAudit(this.action, this.at);
  final String action;
  final DateTime? at;
}

class AssistantControlRule {
  AssistantControlRule(AssistantGrant grant, List<Map<String, Object?>> rows,
      DateTime now)
      : tool = grant.toolId,
        category = switch (grant.category) {
          GrantCategory.model => '模型请求',
          GrantCategory.write => '写入',
          GrantCategory.outbound => '外传',
        },
        duration = switch (grant.duration) {
          GrantDuration.once => '仅这一次',
          GrantDuration.task => '本次任务',
          GrantDuration.conversation => '本次对话',
          GrantDuration.timed => '限时',
          GrantDuration.always => '始终',
        },
        destination = assistantEndpointDisplay(grant.destination),
        status = grant.revokedAt != null
            ? '已撤销'
            : grant.expiresAt != null && !now.isBefore(grant.expiresAt!)
                ? '已过期'
                : grant.maxUses != null && grant.uses >= grant.maxUses!
                    ? '次数已用尽'
                    : '规则已保存',
        audit = List.unmodifiable([
          for (final row in rows)
            AssistantControlAudit(
              switch (row['action']) {
                'created' => '已创建',
                'used' => '已使用',
                'revoked' => '已撤销',
                _ => '其他变更',
              },
              row['at'] is String ? DateTime.tryParse(row['at'] as String) : null,
            ),
        ]);
  final String tool, category, duration, destination, status;
  final List<AssistantControlAudit> audit;
}

class AssistantControlSnapshot {
  AssistantControlSnapshot(List<AssistantControlRule> rules)
      : rules = List.unmodifiable(rules);
  final List<AssistantControlRule> rules;

  factory AssistantControlSnapshot.read(GrantStore grants,
      {required DateTime now}) => AssistantControlSnapshot([
        for (final grant in grants.list())
          AssistantControlRule(grant, grants.audit(grant.id), now),
      ]);
}

/// Reads the actual authorization store. Has no grant issuer or policy writer.
class AssistantControlPage extends StatefulWidget {
  const AssistantControlPage({
    super.key,
    required this.read,
    required this.dataFlow,
  });
  factory AssistantControlPage.host({Key? key, required MuyonHost host}) =>
      AssistantControlPage(
        key: key,
        read: () async => AssistantControlSnapshot.read(
          host.assistantGrants,
          now: DateTime.now().toUtc(),
        ),
        dataFlow: DataFlowPage(host: host),
      );
  final Future<AssistantControlSnapshot> Function() read;
  final Widget dataFlow;

  @override
  State<AssistantControlPage> createState() => _AssistantControlPageState();
}

class _AssistantControlPageState extends State<AssistantControlPage> {
  AssistantControlSnapshot? _snapshot;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _snapshot = null;
    });
    try {
      final snapshot = await widget.read();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void didUpdateWidget(AssistantControlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.read != widget.read) {
      _load();
    }
  }

  void _details(AssistantControlRule rule) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('授权规则详情')),
        body: ListView(
          padding: const EdgeInsets.all(MuyonTokens.space4),
          children: [
            Text(rule.tool),
            Text('${rule.category} · ${rule.duration} · ${rule.status}'),
            Text('目的地 ${rule.destination}'),
            const Text('范围已绑定；实际执行仍会检查当前范围、有效期和一次性审批。'),
            const Divider(),
            const Text('变更审计'),
            if (rule.audit.isEmpty) const Text('暂无变更记录'),
            for (final event in rule.audit)
              ListTile(
                title: Text(event.action),
                subtitle: Text(event.at?.toUtc().toIso8601String() ?? '时间未知'),
              ),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(MuyonTokens.space4),
        children: [
          Text('助手控制中心', style: Theme.of(context).textTheme.titleLarge),
          const Text('只读查看已保存的授权规则和变更记录。规则存在不代表本次执行已获准。'),
          ListTile(
            title: const Text('数据去向'),
            subtitle: const Text('查看已有模型请求与工具调用记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('数据去向')),
                body: widget.dataFlow,
              ),
            )),
          ),
          const Divider(),
          const Text('已授权规则'),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_failed) ...[
            const Text('读取失败，请重试'),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
          if (!_loading && !_failed) ...[
            if (_snapshot!.rules.isEmpty) const Text('暂无授权规则'),
            for (final rule in _snapshot!.rules)
              ListTile(
                title: Text(rule.tool),
                subtitle: Text('${rule.category} · ${rule.duration} · ${rule.status}\n目的地 ${rule.destination}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _details(rule),
              ),
            TextButton(onPressed: _load, child: const Text('刷新')),
          ],
        ],
      );
}
