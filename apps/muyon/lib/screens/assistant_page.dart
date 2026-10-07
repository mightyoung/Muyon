import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../assistant/personal_agent.dart';
import '../platform/foundation_repository.dart';
import '../services/models/profile_repository.dart';
import '../services/models/model_gateway.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.repo,
    required this.agent,
    required this.profiles,
    this.scope,
    this.conversationId,
    this.onOpenReference,
  });
  final FoundationRepository repo;
  final PersonalAgent agent;
  final ProfileRepository profiles;
  final AssistantScope? scope;
  final String? conversationId;
  final void Function(ObjectRef)? onOpenReference;
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

/// Title of the confirmation dialog for a task waiting at [stage].
String confirmTitle(String stage) => switch (stage) {
  'model' => '确认发送给模型',
  'compaction' => '确认发送较早内容做摘要',
  _ => '确认工具操作',
};

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  String? _conversationId;
  String _profileId = '';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _conversationId =
        widget.conversationId ??
        widget.repo
            .conversations()
            .where(
              (c) =>
                  PersonalAgent.digest(c.scope.toJson()) ==
                  PersonalAgent.digest(
                    (widget.scope ?? const AssistantScope.global()).toJson(),
                  ),
            )
            .firstOrNull
            ?.id;
    widget.repo.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.repo.removeListener(_refresh);
    _input.dispose();
    super.dispose();
  }

  AssistantScope get _scope =>
      widget.repo.conversation(_conversationId ?? '')?.scope ??
      widget.scope ??
      const AssistantScope.global();
  Future<String> _ensureConversation() async {
    if (_conversationId != null) return _conversationId!;
    final matching = widget.repo.conversations().where(
      (c) =>
          PersonalAgent.digest(c.scope.toJson()) ==
          PersonalAgent.digest(_scope.toJson()),
    );
    final c = matching.isNotEmpty
        ? matching.first
        : await widget.repo.createConversation(
            title: _scope.kind == AssistantScopeKind.global ? '主对话' : '专题对话',
            scope: _scope,
          );
    _conversationId = c.id;
    if (mounted) setState(() {});
    return c.id;
  }

  void _error(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final id = await _ensureConversation();
      final profiles = widget.profiles
          .all()
          .where((p) => p.purpose == ModelPurpose.chat)
          .toList();
      final selected = _profileId.isEmpty
          ? null
          : profiles.firstWhere((p) => p.id == _profileId);
      _input.clear();
      await widget.agent.start(
        conversationId: id,
        prompt: prompt,
        profile: selected,
      );
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(PersonalTask task) async {
    final digest = task.payload['requestDigest'] as String;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirmTitle(task.stage)),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.waitReason ?? '请核对操作范围。'),
                const SizedBox(height: 12),
                SelectableText(
                  const JsonEncoder.withIndent('  ')
                      .convert(task.payload['preview']),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认本次操作'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await widget.agent.confirm(task.id, requestDigest: digest);
      } catch (e) {
        _error(e);
      }
    }
  }

  Future<void> _tool() async {
    // Internal channels only run inside their module's reviewed flow.
    final available = widget.agent.tools
        .list()
        .where((t) => t.available && t.descriptor.modelSelectable)
        .toList();
    if (available.isEmpty) {
      _error('当前没有可用工具');
      return;
    }
    final input = TextEditingController(text: '{}');
    var selected = available.first.descriptor.toolId;
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('本地工具'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selected,
                      isExpanded: true,
                      items: [
                        for (final t in available)
                          DropdownMenuItem(
                            value: t.descriptor.toolId,
                            child: Text(
                              t.descriptor.toolId,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => selected = value!),
                      decoration: const InputDecoration(labelText: '选择工具'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '参数要求：${jsonEncode(available.firstWhere((t) => t.descriptor.toolId == selected).descriptor.parameterSchema)}',
                    ),
                    TextField(
                      controller: input,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: '工具参数（JSON）',
                      ),
                    ),
                    const Text('查询与计算可离线运行；写入或外传会再次请求确认。'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('准备操作'),
              ),
            ],
          ),
        ),
      );
      if (yes == true) {
        final parameters = Map<String, Object?>.from(
          jsonDecode(input.text) as Map,
        );
        final id = await _ensureConversation();
        await widget.agent.startTool(
          conversationId: id,
          toolId: selected,
          parameters: parameters,
        );
      }
    } catch (e) {
      _error(e);
    } finally {
      input.dispose();
    }
  }

  Future<void> _newConversation() async {
    final input = TextEditingController(
      text: _scope.kind == AssistantScopeKind.global ? '新对话' : '专题对话',
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建对话'),
        content: TextField(
          controller: input,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    input.dispose();
    if (title == null || title.trim().isEmpty) return;
    final c = await widget.repo.createConversation(
      title: title,
      scope: widget.scope ?? const AssistantScope.global(),
    );
    if (mounted) setState(() => _conversationId = c.id);
  }

  @override
  Widget build(BuildContext context) {
    final conversations = widget.repo
        .conversations()
        .where(
          (c) =>
              widget.scope == null ||
              PersonalAgent.digest(c.scope.toJson()) ==
                  PersonalAgent.digest(widget.scope!.toJson()),
        )
        .toList();
    final messages = _conversationId == null
        ? <AssistantMessage>[]
        : widget.repo.messages(_conversationId!);
    final tasks = _conversationId == null
        ? <PersonalTask>[]
        : widget.repo.tasks(conversationId: _conversationId);
    final profiles = widget.profiles
        .all()
        .where((p) => p.purpose == ModelPurpose.chat)
        .toList();
    final currentProfile = profiles
        .where((p) => p.id == _profileId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人助手'),
        actions: [
          IconButton(
            onPressed: _newConversation,
            tooltip: '新建对话',
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('conversation-$_conversationId'),
                    initialValue:
                        conversations.any((c) => c.id == _conversationId)
                        ? _conversationId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '会话'),
                    items: [
                      for (final c in conversations)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(c.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) => setState(() => _conversationId = id),
                  ),
                  const SizedBox(height: 8),
                  Text(switch (_scope.kind) {
                    AssistantScopeKind.global => '范围：个人全局（工具调用时由宿主核对可见对象）',
                    AssistantScopeKind.workspace =>
                      '范围：工作区 ${_scope.workspaceId}',
                    AssistantScopeKind.selectedObjects =>
                      '范围：${_scope.objects.length} 个选定对象',
                  }),
                  if (_scope.objects.isNotEmpty)
                    Text(
                      _scope.objects
                          .map(
                            (r) =>
                                '${r.moduleId}/${r.objectType}/${r.objectId}',
                          )
                          .join(' · '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  if (messages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '在这里开始个人对话，或通过本地工具查询资料、执行计算。外传和写入前会展示本次操作范围。',
                      ),
                    ),
                  for (final message in messages)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.role == 'user' ? '你' : '助手',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            SelectableText(message.content),
                            if (message.references.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final ref in message.references)
                                    ActionChip(
                                      label: Text(
                                        '${ref.moduleId}/${ref.objectType}/${ref.objectId}',
                                      ),
                                      onPressed: widget.onOpenReference == null
                                          ? null
                                          : () => widget.onOpenReference!(ref),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  for (final task in tasks.take(8))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_stateLabel(task.state)} · ${task.executionDeviceId}',
                            ),
                            if (task.waitReason != null) Text(task.waitReason!),
                            if (task.error != null) Text(task.error!),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (task.state ==
                                    PersonalTaskState.waitingConfirmation)
                                  FilledButton(
                                    onPressed: () => _confirm(task),
                                    child: const Text('查看并确认'),
                                  ),
                                if (task.state ==
                                    PersonalTaskState.waitingConfirmation)
                                  TextButton(
                                    onPressed: () => widget.agent
                                        .pause(task.id)
                                        .catchError(_error),
                                    child: const Text('暂停'),
                                  ),
                                if (!task.terminal &&
                                    task.stage == 'cancelling')
                                  const Text('取消中…')
                                else if (!task.terminal)
                                  TextButton(
                                    onPressed: () => widget.agent
                                        .cancel(task.id)
                                        .catchError(_error),
                                    child: const Text('取消'),
                                  ),
                                if ([
                                  PersonalTaskState.paused,
                                  PersonalTaskState.interrupted,
                                  PersonalTaskState.failed,
                                ].contains(task.state))
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await widget.agent.resume(task.id);
                                      } catch (e) {
                                        _error(e);
                                      }
                                    },
                                    child: const Text('新尝试并重新确认'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: currentProfile?.id ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '执行方式'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('离线工具（不调用模型）'),
                      ),
                      for (final p in profiles)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.id} · ${p.location.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() => _profileId = id ?? ''),
                  ),
                  if (currentProfile != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '目标：${currentProfile.endpoint}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '输入消息'),
                    onSubmitted: (_) => _send(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _tool,
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('本地工具'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.send),
                        label: Text(_busy ? '准备中' : '发送'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(PersonalTaskState state) => switch (state) {
    PersonalTaskState.queued => '排队中',
    PersonalTaskState.waitingConfirmation => '等待确认',
    PersonalTaskState.running => '正在执行',
    PersonalTaskState.succeeded => '已完成',
    PersonalTaskState.failed => '执行失败',
    PersonalTaskState.cancelled => '已取消',
    PersonalTaskState.paused => '已暂停',
    PersonalTaskState.interrupted => '已中断',
  };
}
