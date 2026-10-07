import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../app/bootstrap.dart';
import '../platform/mcp_adapter.dart';
import '../services/models/credential_redaction.dart';
import '../services/models/model_gateway.dart' show SecretStore;
import '../services/models/secret_store.dart';

/// Secrets the MCP page reads *and* writes. [MethodChannelSecretStore] already
/// has these methods; tests inject an in-memory double.
abstract interface class McpSecrets implements SecretStore {
  Future<void> write(String reference, String value);
  Future<void> remove(String reference);
}

/// Default store: the platform secret channel (Windows credential storage on
/// Windows), the same one used for model profiles.
class PlatformMcpSecrets implements McpSecrets {
  const PlatformMcpSecrets();
  static const _store = MethodChannelSecretStore();
  @override
  Future<String?> read(String reference) => _store.read(reference);
  @override
  Future<void> write(String reference, String value) =>
      _store.write(reference, value);
  @override
  Future<void> remove(String reference) => _store.remove(reference);
}

/// One configured MCP server. The token itself never lives here; only the
/// secret-store reference `mcp-<id>` does.
@immutable
class McpServerRecord {
  const McpServerRecord({
    required this.id,
    required this.endpoint,
    this.credentialRef,
  });
  final String id;
  final Uri endpoint;
  final String? credentialRef;
  String get tokenRef => 'mcp-$id';
  Map<String, Object?> toJson() => {
    'id': id,
    'endpoint': endpoint.toString(),
    'credentialRef': credentialRef,
  };
}

/// Persistence and connection actions the page performs. [HostMcpServerStore]
/// is the real implementation; widget tests inject a double so UI states need
/// no database, while the real store is covered by host-level tests.
abstract interface class McpServerStore {
  List<McpServerRecord> load();
  Future<void> save(McpServerRecord record, String token);
  Future<void> remove(McpServerRecord record);
  Future<McpConnection> connect(McpServerRecord record);
}

/// Host-backed store: configuration (never the token) in the workspace
/// setting `mcpServers`, tokens only in the secret store, tools disabled with
/// a reason when a server is removed.
class HostMcpServerStore implements McpServerStore {
  HostMcpServerStore(this.host, this.secrets);
  final MuyonHost host;
  final McpSecrets secrets;

  @override
  List<McpServerRecord> load() {
    final value = host.workspaces.setting('mcpServers');
    if (value is! List) return [];
    return [
      for (final item in value)
        if (item is Map && item['id'] is String && item['endpoint'] is String)
          McpServerRecord(
            id: item['id'] as String,
            endpoint: Uri.parse(item['endpoint'] as String),
            credentialRef: item['credentialRef'] as String?,
          ),
    ];
  }

  Future<void> _write(List<McpServerRecord> servers) =>
      host.workspaces.setSetting('mcpServers', [
        for (final server in servers) server.toJson(),
      ]);

  @override
  Future<void> save(McpServerRecord record, String token) async {
    await _write([...load().where((server) => server.id != record.id), record]);
    if (token.isNotEmpty) {
      await secrets.write(record.tokenRef, token);
    }
  }

  @override
  Future<void> remove(McpServerRecord record) async {
    await _write(load().where((server) => server.id != record.id).toList());
    await secrets.remove(record.tokenRef);
    for (final tool in host.tools.list()) {
      if (tool.providerId == 'mcp:${record.id}') {
        host.tools.setAvailability(
          tool.descriptor.toolId,
          available: false,
          reason: '服务器已移除',
        );
      }
    }
  }

  @override
  Future<McpConnection> connect(McpServerRecord record) => McpAdapter.connect(
    host.tools,
    McpServerConfig(
      id: record.id,
      endpoint: record.endpoint,
      credentialRef: record.credentialRef,
    ),
    secrets: secrets,
  );
}

/// MCP 服务器: add, edit, remove and connect external tool servers. Connecting
/// is strictly on demand — nothing goes to the network at startup. Removing a
/// server disables the tools it registered (the registry has no unregister
/// endpoint) and deletes its token.
class McpServersPage extends StatefulWidget {
  const McpServersPage({super.key, required this.store});

  /// Production wiring: the host-backed store with platform secrets.
  McpServersPage.host({
    super.key,
    required MuyonHost host,
    McpSecrets secrets = const PlatformMcpSecrets(),
  }) : store = HostMcpServerStore(host, secrets);

  final McpServerStore store;

  @override
  State<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends State<McpServersPage> {
  late List<McpServerRecord> servers = _readServers();
  final Map<String, McpConnection> connections = {};
  final Map<String, String> connectErrors = {};
  String? error;
  bool busy = false;

  List<McpServerRecord> _readServers() {
    try {
      return widget.store.load();
    } catch (failure) {
      error = '读取配置失败：${redactCredentials(failure)}';
      return [];
    }
  }

  String? _endpointProblem(Uri? endpoint) {
    const message = '需要 https 地址；仅本机（localhost/127.0.0.1/::1）可用 http。';
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      return message;
    }
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(endpoint.host);
    if (!(endpoint.scheme == 'https' ||
        (endpoint.scheme == 'http' && loopback))) {
      return message;
    }
    return null;
  }

  Future<void> _save(McpServerRecord record, String token) async {
    await widget.store.save(record, token);
    if (mounted) setState(() => servers = widget.store.load());
  }

  Future<void> _editServer([McpServerRecord? existing]) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => _ServerDialog(
        existing: existing,
        servers: servers,
        endpointProblem: _endpointProblem,
        save: _save,
      ),
    );
  }

  Future<void> _connect(McpServerRecord record) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final connection = await widget.store.connect(record);
      if (mounted) {
        setState(() {
          connections[record.id] = connection;
          connectErrors.remove(record.id);
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          // Shown on the page: never the token, even if an error quotes it.
          connectErrors[record.id] = redactCredentials(
            redactEndpoint('$failure', record.endpoint),
          );
          busy = false;
        });
      }
    }
  }

  Future<void> _remove(McpServerRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除服务器'),
        content: Text(
          '移除「${record.id}」后，它注册过的工具会停用（原因标记为服务器已移除），'
          '访问令牌同时删除；已产生的调用记录保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      await widget.store.remove(record);
      if (mounted) {
        setState(() {
          servers = widget.store.load();
          connections.remove(record.id);
          connectErrors.remove(record.id);
          error = null;
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error =
              '移除失败：${redactCredentials(redactEndpoint('$failure', record.endpoint))}';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(MuyonTokens.space4),
      children: [
        Text('MCP 服务器', style: theme.textTheme.titleLarge),
        const SizedBox(height: MuyonTokens.space2),
        Text(
          '外部工具服务器：调用它们的工具会把参数发给对应服务器，每次调用都需要你逐次确认；'
          '启动时不会自动连接。',
          style: theme.textTheme.bodySmall,
        ),
        if (error != null) ...[
          const SizedBox(height: MuyonTokens.space2),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: MuyonTokens.space3),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : () => _editServer(),
            icon: const Icon(Icons.add),
            label: const Text('添加服务器'),
          ),
        ),
        const SizedBox(height: MuyonTokens.space2),
        if (servers.isEmpty)
          Text('尚未配置 MCP 服务器。', style: theme.textTheme.bodySmall)
        else
          for (final record in servers) _serverCard(context, record),
      ],
    );
  }

  Widget _serverCard(BuildContext context, McpServerRecord record) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    final connection = connections[record.id];
    final connectError = connectErrors[record.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MuyonTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(record.id, style: theme.textTheme.titleSmall),
            SelectableText(
              maskedEndpoint(record.endpoint),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              record.credentialRef == null ? '无访问令牌' : '已保存令牌（系统安全存储）',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: MuyonTokens.space2),
            Wrap(
              spacing: MuyonTokens.space2,
              runSpacing: MuyonTokens.space2,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _connect(record),
                  icon: const Icon(Icons.link),
                  label: const Text('连接'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _editServer(record),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => _remove(record),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移除'),
                ),
              ],
            ),
            if (connectError != null) ...[
              const SizedBox(height: MuyonTokens.space2),
              SelectableText(
                '连接失败：$connectError',
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.red),
              ),
            ],
            if (connection != null) ...[
              const SizedBox(height: MuyonTokens.space2),
              Text(
                '已注册 ${connection.registered.length} 个工具',
                style: theme.textTheme.titleSmall,
              ),
              for (final toolId in connection.registered)
                SelectableText(toolId, style: theme.textTheme.bodySmall),
              if (connection.skipped.isNotEmpty) ...[
                const SizedBox(height: MuyonTokens.space1),
                Text(
                  '跳过 ${connection.skipped.length} 个工具',
                  style: theme.textTheme.titleSmall,
                ),
                for (final entry in connection.skipped.entries)
                  SelectableText(
                    '${entry.key} — ${entry.value}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Add/edit dialog that owns its controllers so they outlive the route's exit
/// animation (disposing them right after `showDialog` returns is too early).
class _ServerDialog extends StatefulWidget {
  const _ServerDialog({
    required this.existing,
    required this.servers,
    required this.endpointProblem,
    required this.save,
  });
  final McpServerRecord? existing;
  final List<McpServerRecord> servers;
  final String? Function(Uri? endpoint) endpointProblem;
  final Future<void> Function(McpServerRecord record, String token) save;
  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController idController = TextEditingController(
    text: widget.existing?.id ?? '',
  );
  late final TextEditingController endpointController = TextEditingController(
    text: widget.existing?.endpoint.toString() ?? '',
  );
  final TextEditingController tokenController = TextEditingController();
  String? idError;
  String? endpointError;
  String? tokenError;
  String? saveError;
  bool saving = false;

  @override
  void dispose() {
    idController.dispose();
    endpointController.dispose();
    tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = idController.text.trim();
    final endpoint = Uri.tryParse(endpointController.text.trim());
    final token = tokenController.text;
    var idMessage = RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(id)
        ? null
        : '标识需以小写字母开头，仅用小写字母、数字、下划线或连字符，最长 32 位。';
    if (idMessage == null &&
        widget.servers.any(
          (server) => server.id == id && server.id != widget.existing?.id,
        )) {
      idMessage = '已存在同名服务器。';
    }
    final endpointMessage = widget.endpointProblem(endpoint);
    // Same rule as model keys: refuse, do not trim, never store or echo it.
    final tokenMessage = token.isNotEmpty && !isSendableCredential(token)
        ? invalidCredentialMessage
        : null;
    if (idMessage != null || endpointMessage != null || tokenMessage != null) {
      setState(() {
        idError = idMessage;
        endpointError = endpointMessage;
        tokenError = tokenMessage;
      });
      return;
    }
    final validEndpoint = endpoint!;
    final ref = token.isNotEmpty ? 'mcp-$id' : widget.existing?.credentialRef;
    try {
      McpServerConfig(id: id, endpoint: validEndpoint, credentialRef: ref);
    } on ArgumentError catch (invalid) {
      setState(() => saveError = '$invalid');
      return;
    }
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await widget.save(
        McpServerRecord(id: id, endpoint: validEndpoint, credentialRef: ref),
        token,
      );
      if (mounted) {
        final names = credentialParamNames(validEndpoint);
        // Not blocking: the server is saved, the person is told what that means.
        if (names.isNotEmpty) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('地址中含有凭据参数（${names.join('、')}），会以明文保存；建议改填到令牌栏。'),
            ),
          );
        }
        Navigator.pop(context, true);
      }
    } catch (failure) {
      setState(() {
        saving = false;
        saveError =
            '保存失败：${redactCredentials(redactEndpoint('$failure', validEndpoint))}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('mcp-id-field'),
              controller: idController,
              enabled: widget.existing == null,
              decoration: InputDecoration(
                labelText: '标识（工具前缀 mcp.<标识>）',
                errorText: idError,
              ),
            ),
            TextField(
              key: const ValueKey('mcp-endpoint-field'),
              controller: endpointController,
              decoration: InputDecoration(
                labelText: '完整端点 URL',
                hintText: 'https://host/mcp',
                errorText: endpointError,
              ),
            ),
            TextField(
              key: const ValueKey('mcp-token-field'),
              controller: tokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.existing?.credentialRef == null
                    ? '访问令牌（可选）'
                    : '访问令牌（已保存，留空保持不变）',
                errorText: tokenError,
              ),
            ),
            const SizedBox(height: MuyonTokens.space2),
            const Text('调用这些工具会把参数发给该服务器，每次调用都需要你逐次确认。'),
            if (saveError != null)
              Text(
                saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: saving ? null : _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
