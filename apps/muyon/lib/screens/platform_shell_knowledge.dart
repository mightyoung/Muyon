part of 'platform_shell.dart';

extension _KnowledgeSections on _PlatformShellState {
  Future<void> importFile() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty || files.first.path == null) return;
    await action(
      () => host.trackOperation(() async {
        final document = await host.services.knowledge.importFile(
          files.first.path!,
        );
        await host.services.knowledge.index(document.id);
      }),
    );
  }

  Widget knowledge() => list([
    Text('数据与知识', style: Theme.of(context).textTheme.titleLarge),
    const Text('原文件与来源对象保留；全文检索无需模型。扫描图片的 OCR 状态单独显示。'),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : importFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('导入文件'),
        ),
        OutlinedButton.icon(
          onPressed: () => action(() async {
            final scope = await host.tools.resolveScope(
              const AssistantScope.global(),
            );
            if (mounted) {
              await page(
                '业务对象目录',
                list([
                  for (final ref in scope.objects)
                    ListTile(
                      title: Text('${ref.moduleId} · ${ref.objectType}'),
                      subtitle: Text(ref.objectId),
                      onTap: () => openObject(ref),
                      trailing: const Icon(Icons.open_in_new),
                    ),
                ]),
              );
            }
          }),
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('查找业务对象'),
        ),
      ],
    ),
    TextField(
      controller: query,
      decoration: InputDecoration(
        labelText: '离线全文检索',
        suffixIcon: IconButton(
          onPressed: () => action(() async {
            final result = await host.services.knowledge.search(query.text);
            hits = [
              for (final hit in result)
                {
                  'title': hit.title,
                  'text': hit.text,
                  'page': hit.pageIndex + 1,
                  'ref': hit.sourceRef,
                },
            ];
          }),
          icon: const Icon(Icons.search),
        ),
      ),
      onSubmitted: (_) => action(() async {
        final result = await host.services.knowledge.search(query.text);
        hits = [
          for (final hit in result)
            {
              'title': hit.title,
              'text': hit.text,
              'page': hit.pageIndex + 1,
              'ref': hit.sourceRef,
            },
        ];
      }),
    ),
    for (final hit in hits)
      Card(
        child: ListTile(
          title: Text('${hit['title']} · 第${hit['page']}页'),
          subtitle: Text(
            '${hit['text']}',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openObject(hit['ref'] as ObjectRef),
        ),
      ),
    const Divider(),
    for (final document in host.services.knowledge.documents())
      ListTile(
        title: Text(document.title),
        subtitle: Text('${document.status}\n${document.summary}'),
        isThreeLine: true,
        onTap: () => openObject(document.source),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => action(
            () => host.trackOperation(() async {
              if (value == 'index') {
                await host.services.knowledge.index(document.id);
              }
              if (value == 'delete') {
                await host.services.knowledge.delete(document.id);
              }
            }),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'index', child: Text('重建索引')),
            PopupMenuItem(value: 'delete', child: Text('删除平台副本')),
          ],
        ),
      ),
  ]);
  Future<void> runTool(RegisteredToolInfo info) async {
    final parameters = TextEditingController(text: '{}');
    final destination = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(info.descriptor.toolId),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ')
                    .convert(info.descriptor.parameterSchema),
              ),
              TextField(
                controller: parameters,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '参数 JSON'),
              ),
              if (info.accessLevel == ToolAccessLevel.external)
                TextField(
                  controller: destination,
                  decoration: const InputDecoration(labelText: '明确发送目的地'),
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
            child: const Text('校验并调用'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await action(() async {
        var request = ToolCallRequest(
          invocationId: const Uuid().v4(),
          toolId: info.descriptor.toolId,
          scope: const AssistantScope.global(),
          parameters: Map<String, Object?>.from(
            jsonDecode(parameters.text) as Map,
          ),
          destination: destination.text.isEmpty
              ? null
              : destination.text.trim(),
        );
        final prepared = await host.tools.prepare(request);
        if (info.accessLevel != ToolAccessLevel.read) {
          if (!mounted) return;
          final approve = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认本次操作'),
              content: SingleChildScrollView(
                child: SelectableText(
                  '${info.accessLevel.name}\n目的地：${request.destination ?? '本地'}\n参数：${jsonEncode(request.parameters)}\n范围对象：${prepared.resolvedScope.objects.length}\n输入摘要：${prepared.parameterDigest}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('仅确认这一次'),
                ),
              ],
            ),
          );
          if (approve != true) return;
          request = request.withApproval(await host.tools.approve(prepared));
        }
        final result = await host.trackOperation(
          () => host.tools.invoke(request),
        );
        if (mounted) {
          await page(
            '调用结果',
            list([
              SelectableText(result.summary),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(result.data),
              ),
              for (final ref in result.objectRefs)
                ListTile(
                  title: Text('${ref.moduleId} · ${ref.objectType}'),
                  subtitle: Text(ref.objectId),
                  onTap: () => openObject(ref),
                ),
            ]),
          );
        }
      });
    }
    parameters.dispose();
    destination.dispose();
  }

  Widget tools() => list([
    Text('接口与工具', style: Theme.of(context).textTheme.titleLarge),
    const Text('页面与助手调用同一注册表；参数与权限由宿主校验。'),
    for (final info in host.tools.list())
      Card(
        child: ListTile(
          title: Text(info.descriptor.toolId),
          subtitle: Text(
            '${info.providerId} · ${info.accessLevel.name}\n${info.available ? '可用' : info.unavailableReason ?? '不可用'}',
          ),
          isThreeLine: true,
          onTap: info.available ? () => runTool(info) : null,
          trailing: const Icon(Icons.play_arrow_outlined),
        ),
      ),
  ]);
}
