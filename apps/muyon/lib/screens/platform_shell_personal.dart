part of 'platform_shell.dart';

extension _PersonalSections on _PlatformShellState {
  Future<void> editMemory([PersonalMemory? memory]) async {
    final content = TextEditingController(text: memory?.content);
    final source = TextEditingController(text: memory?.source ?? '本人手动确认');
    final expiry = TextEditingController(
      text: memory?.expiresAt?.toIso8601String().split('T').first,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有来源的个人记忆'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: content,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '偏好、背景、决定或已验证经验'),
              ),
              TextField(
                controller: source,
                decoration: const InputDecoration(
                  labelText: '来源（原文、对象、记录或本人确认）',
                ),
              ),
              TextField(
                controller: expiry,
                decoration: const InputDecoration(
                  labelText: '过期日期 YYYY-MM-DD（可留空）',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await action(
        () => repo
            .saveMemory(
              id: memory?.id,
              content: content.text,
              source: source.text,
              scope: memory?.scope ?? const AssistantScope.global(),
              sourceRef: memory?.sourceRef,
              verified: memory?.verified ?? true,
              expiresAt: expiry.text.trim().isEmpty
                  ? null
                  : DateTime.parse(expiry.text.trim()),
            )
            .then((_) {}),
      );
    }
    content.dispose();
    source.dispose();
    expiry.dispose();
  }

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
      const Text('记忆保留来源与过期状态；模型建议不会自动扩大操作权限。'),
      FilledButton.icon(
        onPressed: () => editMemory(),
        icon: const Icon(Icons.add),
        label: const Text('添加记忆'),
      ),
      for (final memory in repo.memories(includeExpired: true))
        ListTile(
          title: Text(memory.content),
          subtitle: Text(
            '${memory.source}\n${memory.isExpired ? '已过期' : '有效'} ${memory.expiresAt ?? ''}',
          ),
          isThreeLine: true,
          onTap: () => editMemory(memory),
          trailing: IconButton(
            tooltip: '删除记忆',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => action(() => repo.deleteMemory(memory.id)),
          ),
        ),
      const Divider(),
      const Text('记忆整理'),
      const Text('后台按来源记录生成只读整理候选，保留全部来源，等待本人处理；不自动扩大操作权限。'),
      OutlinedButton.icon(
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('查看整理建议与来源摘要'),
        onPressed: () {
          final review = host.memoryReview.current;
          page(
            '记忆整理预览',
            list([
              Text(
                '重复候选 ${review.duplicates.length} 组 · 内容变化候选 ${review.conflicts.length} 组 · 过期 ${review.expired.length} 条',
              ),
              const Text('内容变化仅提示复核，不代表已确认矛盾；摘要逐条保留来源，不生成新事实。'),
              for (final group in review.duplicates) ...[
                const Text('相同内容，来源需要逐一保留或人工合并'),
                for (final memory in group)
                  ListTile(
                    title: Text(memory.content),
                    subtitle: Text(memory.source),
                    onTap: () => editMemory(memory),
                  ),
              ],
              for (final group in review.conflicts) ...[
                const Text('同一属性出现不同内容，请检查决定是否发生变化'),
                for (final memory in group)
                  ListTile(
                    title: Text(memory.content),
                    subtitle: Text(memory.source),
                    onTap: () => editMemory(memory),
                  ),
              ],
              const Divider(),
              const Text('有效记忆与来源摘要'),
              SelectableText(review.summary.join('\n\n')),
            ]),
          );
        },
      ),
      const Text('Dream、语义矛盾识别和自动经验提炼仍属于后续增强。'),
    ]),
  );
  Future<void> addProfile() async {
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final model = TextEditingController();
    final secret = TextEditingController();
    var location = ModelLocation.local;
    var purpose = ModelPurpose.chat;
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
                    labelText: '完整端点 URL',
                    hintText: 'http://127.0.0.1:11434/v1/chat/completions',
                  ),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: '模型名称'),
                ),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key（仅存入系统凭据）',
                  ),
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
              onPressed: () => Navigator.pop(context, true),
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
        onTap: () => page(
          '数据与存储',
          DataStoragePage(
            readStatus: () => StorageStatus.read(host),
            createBackup: (target) => host.trackOperation(
              () => BackupService.create(host.storage, target),
            ),
            restore: widget.onRestore,
            pickDirectory: widget.pickDirectory,
          ),
        ),
      ),
      const Text('模型与数据去向'),
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
        ListTile(
          title: Text(profile.endpointIdentity),
          subtitle: Text(
            '${profile.location.name} · ${profile.modelId}\n${profile.endpoint}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: '删除模型配置',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => action(() async {
              await profiles.remove(profile.id);
              if (profile.credentialRef != null) {
                await const MethodChannelSecretStore().remove(
                  profile.credentialRef!,
                );
              }
              repo.refresh();
            }),
          ),
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
