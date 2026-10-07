part of 'platform_shell.dart';

extension _PersonalSections on _PlatformShellState {
  Widget personal() => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => list([
      ListTile(
        title: const Text('个人资料'),
        subtitle: Text(
          '${host.workspaces.setting('personalName') ?? '本人'}\n设备 ID：${host.workspaces.setting('deviceId')}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => action(() async {
            final name = TextEditingController(
              text: host.workspaces.setting('personalName') as String? ?? '',
            );
            final result = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('个人名称'),
                content: TextField(controller: name),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, name.text.trim()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            );
            name.dispose();
            if (result != null) {
              await host.workspaces.setSetting('personalName', result);
            }
            repo.refresh();
          }),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.psychology_alt_outlined),
        title: const Text('记忆与整理'),
        subtitle: const Text('查看、编辑、停用、删除记忆；整理建议与撤回'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => page('记忆', memoryPage()),
      ),
    ]),
  );
  Future<void> addProfile() async {
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final model = TextEditingController();
    final secret = TextEditingController();
    var location = ModelLocation.local;
    var purpose = ModelPurpose.chat;
    String? secretError;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('添加自选模型'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ModelPurpose>(
                  initialValue: purpose,
                  decoration: const InputDecoration(labelText: '模型用途'),
                  items: ModelPurpose.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v == ModelPurpose.chat ? '对话与工具' : '向量化'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => purpose = value!),
                ),
                DropdownButtonFormField<ModelLocation>(
                  initialValue: location,
                  items: ModelLocation.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(switch (v) {
                            ModelLocation.local => '本机',
                            ModelLocation.ownDevice => '本人其他设备',
                            ModelLocation.remote => '自选远程',
                          }),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => location = value!),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                TextField(
                  controller: endpoint,
                  decoration: const InputDecoration(
                    labelText: '端点 URL',
                    hintText:
                        'https://api.deepseek.com 或 http://127.0.0.1:11434/v1',
                    helperText: '只填到域名或 /v1 时自动补全对话或向量路径',
                  ),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: '模型名称'),
                ),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'API Key（仅存入系统凭据）',
                    errorText: secretError,
                  ),
                  onChanged: (_) {
                    if (secretError != null) update(() => secretError = null);
                  },
                ),
                const Text('非本机端点需要凭据；远程使用 HTTPS。不会自动切换到其他模型。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              // A key with a line break, space or full-width character could
              // never be sent; refuse it rather than trimming it silently.
              onPressed: () =>
                  secret.text.isNotEmpty && !isSendableCredential(secret.text)
                  ? update(() => secretError = invalidCredentialMessage)
                  : Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await action(() async {
        final id = const Uuid().v4();
        final ref = secret.text.isEmpty ? null : 'model-$id';
        final profile = ModelProfile(
          id: id,
          endpoint: Uri.parse(endpoint.text.trim()),
          location: location,
          modelId: model.text.trim(),
          endpointIdentity: name.text.trim(),
          credentialRef: ref,
          purpose: purpose,
          // New chat models stream by default; tools stay in compatibility
          // mode until the person declares or tests otherwise.
          capabilities: purpose == ModelPurpose.chat
              ? const ModelCapabilities(
                  streaming: true,
                  source: CapabilitySource.preset,
                )
              : ModelCapabilities.compat,
        );
        if (ref != null) {
          await const MethodChannelSecretStore().write(ref, secret.text);
        }
        await profiles.save(profile);
        if (purpose == ModelPurpose.chat) {
          await host.workspaces.setSetting('activeModelProfileId', id);
        }
        repo.refresh();
      });
    }
    name.dispose();
    endpoint.dispose();
    model.dispose();
    secret.dispose();
  }

  /// "测试连接": the probe goes through the assistant's gate, the gateway's
  /// one outbound channel and the ledger; its result is stored next to the
  /// profile's capabilities and takes effect only when the person adopts it.
  Future<void> testConnection(ModelProfile profile) async {
    final probe = CapabilityProbe(
      gateway: host.services.gateway,
      gate: host.personalAgent.gate,
    );
    await testProfileConnection(
      context,
      profile: profile,
      profiles: profiles,
      run: (p, {required extended, required confirm}) =>
          probe.run(p, extended: extended, confirm: confirm),
      onChanged: repo.refresh,
    );
  }

  Widget memoryPage() => MemoryPage(
    repo: repo,
    dream: host.dream,
    profiles: () => [
      for (final p in profiles.all())
        if (p.purpose == ModelPurpose.chat) p,
    ],
  );

  Widget storagePage() => DataStoragePage(
    readStatus: () => StorageStatus.read(host),
    createBackup: (target) =>
        host.trackOperation(() => BackupService.create(host.storage, target)),
    restore: widget.onRestore,
    pickDirectory: widget.pickDirectory,
    dataFlow: DataFlowPage(host: host),
    mcpServers: McpServersPage.host(host: host),
  );

  Widget settings() => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => list([
      DropdownButtonFormField<ThemeMode>(
        initialValue: widget.themeMode,
        decoration: const InputDecoration(labelText: '外观'),
        items: ThemeMode.values
            .map(
              (mode) => DropdownMenuItem(value: mode, child: Text(mode.name)),
            )
            .toList(),
        onChanged: (value) => widget.onTheme(value!),
      ),
      SwitchListTile(
        title: const Text('减少动态效果'),
        value: host.workspaces.setting('reduceMotion') == true,
        onChanged: (value) => action(() async {
          await host.workspaces.setSetting('reduceMotion', value);
          repo.refresh();
        }),
      ),
      ListTile(
        title: const Text('数据与存储'),
        subtitle: Text(host.storage.rootPath),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => page('数据与存储', storagePage()),
      ),
      const Text('模型与数据去向'),
      ProfileMigrationNotice(
        key: const ValueKey('profile-migration-notice-slot'),
        read: () => pendingModelProfilesNotice(host.workspaces),
        clear: () => clearModelProfilesNotice(host.workspaces),
      ),
      DropdownButtonFormField<String>(
        initialValue:
            profiles.all().any(
              (p) =>
                  p.purpose == ModelPurpose.chat &&
                  p.id == host.workspaces.setting('activeModelProfileId'),
            )
            ? host.workspaces.setting('activeModelProfileId') as String
            : '',
        decoration: const InputDecoration(labelText: '主对话模型（Folio 共用）'),
        items: [
          const DropdownMenuItem(value: '', child: Text('未指定 · 离线工具可用')),
          for (final profile in profiles.all().where(
            (p) => p.purpose == ModelPurpose.chat,
          ))
            DropdownMenuItem(
              value: profile.id,
              child: Text(profile.endpointIdentity),
            ),
        ],
        onChanged: (value) => action(() async {
          await host.workspaces.setSetting('activeModelProfileId', value!);
          repo.refresh();
        }),
      ),
      FilledButton.icon(
        onPressed: addProfile,
        icon: const Icon(Icons.add),
        label: const Text('添加模型'),
      ),
      for (final profile in profiles.all())
        ModelProfileTile(
          key: ValueKey('profile-${profile.id}'),
          profile: profile,
          onStreaming: (on) => action(() async {
            // Read again: a detection result may have been stored meanwhile.
            final current = profiles.all().firstWhere(
              (p) => p.id == profile.id,
            );
            await profiles.save(
              current.copyWith(
                capabilities: current.capabilities.copyWith(
                  streaming: on,
                  source: CapabilitySource.userDeclared,
                ),
              ),
            );
            repo.refresh();
          }),
          onTest: () => testConnection(profile),
          onDelete: () => action(() async {
            await profiles.remove(profile.id);
            if (profile.credentialRef != null) {
              await const MethodChannelSecretStore().remove(
                profile.credentialRef!,
              );
            }
            repo.refresh();
          }),
        ),
      const Divider(),
      const Text('权限与能力'),
      const Text('只读业务查询可在明确范围内执行；写入和外传逐次确认。未注册能力不会自动替换为云服务。'),
      for (final tool in host.tools.list())
        ListTile(
          title: Text(tool.descriptor.toolId),
          subtitle: Text(
            '${tool.accessLevel.name} · ${tool.available ? '可调用' : tool.unavailableReason ?? '不可用'}',
          ),
        ),
    ]),
  );
}
