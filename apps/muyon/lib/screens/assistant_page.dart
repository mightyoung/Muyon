import '../app/bootstrap.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supplier_core/supplier_core.dart' show assistantReadableSummary;
import 'package:muyon_module_api/muyon_module_api.dart';

import '../assistant/agent_drafts.dart';
import '../assistant/personal_agent.dart';
import '../platform/foundation_repository.dart';
import '../services/models/profile_repository.dart';
import '../services/models/model_gateway.dart';
import 'draft_view.dart';
import '../platform/assistant_subconversations.dart';
import 'assistant_subconversation_panel.dart';
import 'dynamic_workspace.dart';
import '../platform/ui_workspace_store.dart';

import 'package:muyon_module_api/ui_contract.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.repo,
    required this.agent,
    required this.profiles,
    this.scope,
    this.host,
    this.conversationId,
    this.onOpenReference,
    this.initialWorkspace,
    this.onWorkspaceChanged,
  });
  final SubconversationWorkspace? initialWorkspace;
  final ValueChanged<SubconversationWorkspace>? onWorkspaceChanged;
  final FoundationRepository repo;
  final PersonalAgent agent;
  final ProfileRepository profiles;
  final AssistantScope? scope;
  final MuyonHost? host;
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

/// A brief model-send overview; the complete unchanged preview stays below it.
String _confirmationSummary(PersonalTask task) {
  final preview = task.payload['preview'];
  if ((task.stage == 'model' || task.stage == 'compaction') && preview is Map) {
    final profile = preview['profile'];
    final messages = preview['messages'];
    final tools = preview['tools'];
    return assistantReadableSummary({
      'endpoint': preview['endpoint'],
      if (profile is Map) '模型': profile['modelId'],
      'scope': preview['scope'],
      'dataCategories': preview['dataCategories'],
      '发送消息': messages is List ? '${messages.length} 条（原文见原始请求详情）' : '见原始请求详情',
      if (tools is List) '可用工具': '${tools.length} 项（完整定义见原始请求详情）',
      if (preview.containsKey('compacted')) 'compacted': preview['compacted'],
      if (preview.containsKey('maxOutputTokens'))
        'maxOutputTokens': preview['maxOutputTokens'],
    });
  }
  return assistantReadableSummary(preview);
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  String? _conversationId;
  String _profileId = '';
  bool _busy = false;
  bool _openingChild = false;
  late final ScrollController _scroll;
  AssistantSubconversations get _children =>
      AssistantSubconversations(widget.repo);
  bool get _child =>
      _conversationId != null && _children.isChild(_conversationId!);
  bool get _childAvailable {
    if (!_child) return true;
    try {
      return _children.validateConversation(_conversationId!);
    } catch (_) {
      return false;
    }
  }

  void _saveUi() {
    widget.onWorkspaceChanged?.call(
      SubconversationWorkspace(
        draftText: _input.text,
        scrollOffset: _scroll.hasClients
            ? _scroll.offset
            : (widget.initialWorkspace?.scrollOffset ?? 0),
        selectedProfileId: _profileId,
      ),
    );
  }

  /// Drafts of replies being streamed, and those that ended without a
  /// message. Only here, in memory: leaving the page drops them (ADR-0005
  /// §5.3, Q4).
  final _drafts = <String, AgentDraft>{};
  StreamSubscription<AgentDraft>? _draftSub;
  @override
  void initState() {
    super.initState();
    _input.text = widget.initialWorkspace?.draftText ?? '';
    _profileId = widget.initialWorkspace?.selectedProfileId ?? '';
    _scroll = ScrollController(
      initialScrollOffset: widget.initialWorkspace?.scrollOffset ?? 0,
    );
    _scroll.addListener(_saveUi);
    _input.addListener(_saveUi);
    _draftSub = widget.agent.drafts.listen((draft) {
      if (!mounted) return;
      setState(() {
        if (draft.stage == DraftStage.committed) {
          _drafts.remove(draft.taskId);
        } else {
          _drafts[draft.taskId] = draft;
        }
      });
    });
    final running = widget.repo.tasks().map((t) => widget.agent.draftOf(t.id));
    for (final draft in running.nonNulls) {
      _drafts[draft.taskId] = draft;
    }
    _conversationId =
        widget.conversationId ??
        widget.repo
            .conversations()
            .where(
              (c) =>
                  !_children.isChild(c.id) &&
                  PersonalAgent.digest(c.scope.toJson()) ==
                      PersonalAgent.digest(
                        (widget.scope ?? const AssistantScope.global())
                            .toJson(),
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
    _draftSub?.cancel();
    widget.repo.removeListener(_refresh);
    _scroll.dispose();
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
          !_children.isChild(c.id) &&
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
    if (!_childAvailable) {
      _error('父任务归属或范围已改变；输入已保留');
      return;
    }
    final submittedText = _input.text;
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
      await widget.agent.start(
        conversationId: id,
        prompt: prompt,
        profile: selected,
      );
      if (mounted && _input.text == submittedText) _input.clear();
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
                SelectableText(_confirmationSummary(task)),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('原始请求详情'),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ')
                          .convert(task.payload['preview']),
                    ),
                  ],
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
        .where(
          (t) =>
              t.available &&
              t.descriptor.modelSelectable &&
              (!_child || t.descriptor.effect == ToolEffect.read),
        )
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

  Future<void> _openChild(
    PersonalTask task, [
    SubconversationRef? existing,
  ]) async {
    if (_openingChild) return;
    setState(() => _openingChild = true);
    try {
      SubconversationRef ref;
      if (existing != null) {
        ref = existing;
      } else {
        final text = await showDialog<String>(
          context: context,
          builder: (_) => const _SubconversationGoalDialog(),
        );
        if (text == null || text.trim().isEmpty) return;
        ref = await _children.openSubconversation(task.id, text);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(8),
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AssistantSubconversationPanel(
              service: _children,
              ref: ref,
              agent: widget.agent,
              profiles: widget.profiles,
              host: widget.host,
              onOpenReference: widget.onOpenReference,
            ),
          ),
        ),
      );
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _openingChild = false);
    }
  }

  Widget _subconversationEntries(PersonalTask task) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final ref in _children.children(task.id)) ...[
        Wrap(
          children: [
            TextButton(
              onPressed: _openingChild ? null : () => _openChild(task, ref),
              child: Text(
                '打开子对话 · ${widget.repo.conversation(ref.childConversationId)?.title ?? ref.childConversationId}',
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await _children.readLatestSubconversation(ref);
                } catch (e) {
                  _error(e);
                }
              },
              child: const Text('查询最新'),
            ),
          ],
        ),
        for (final read in _children.reads(ref))
          ExpansionTile(
            title: Text('只读引用 · ${read.readAt}'),
            subtitle: Text(
              read.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  '子对话回复（未核验目标达成；历史对象引用需重新核对）\n${read.summary}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(jsonEncode(read.value)),
              ),
            ],
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final conversations = widget.repo
        .conversations()
        .where(
          (c) =>
              !_children.isChild(c.id) &&
              (widget.scope == null ||
                  PersonalAgent.digest(c.scope.toJson()) ==
                      PersonalAgent.digest(widget.scope!.toJson())),
        )
        .toList();
    final messages = _conversationId == null
        ? <AssistantMessage>[]
        : widget.repo.messages(_conversationId!);
    final tasks = _conversationId == null
        ? <PersonalTask>[]
        : widget.repo.tasks(conversationId: _conversationId);
    final taskCards = [
      ...tasks.take(8),
      if (!_child)
        for (final task in tasks.skip(8))
          if (_children.children(task.id).isNotEmpty) task,
    ];
    final profiles = widget.profiles
        .all()
        .where((p) => p.purpose == ModelPurpose.chat)
        .toList();
    final currentProfile = profiles
        .where((p) => p.id == _profileId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !_child,
        title: Text(_child ? '只读子对话' : '个人助手'),
        actions: [
          if (!_child)
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
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .4,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final problem in _children.problems())
                        Text('损坏的子对话记录已保留（只读）：$problem'),
                      if (!_child)
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
                                child: Text(
                                  c.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) =>
                              setState(() => _conversationId = id),
                        ),
                      if (!_child)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('回答后规划交互页面'),
                          subtitle: const Text('失败保留文字；模型外发仍需既有授权'),
                          value: widget.agent.uiPlanningEnabled,
                          onChanged: (value) => setState(
                            () => widget.agent.configureUiPlanning(
                              enabled: value,
                            ),
                          ),
                        ),
                      if (!_child && widget.agent.uiPlanningEnabled)
                        DropdownButton<UiPlanningMode>(
                          value: widget.agent.currentUiPlanningMode,
                          items: const [
                            DropdownMenuItem(
                              value: UiPlanningMode.intelligent,
                              child: Text('Intelligent UI · 本地 Provider'),
                            ),
                            DropdownMenuItem(
                              value: UiPlanningMode.motivation,
                              child: Text('Motivation UI · 当前授权模型'),
                            ),
                          ],
                          onChanged: (mode) => setState(
                            () => widget.agent.configureUiPlanning(mode: mode),
                          ),
                        ),
                      if (_child && !_childAvailable)
                        const Text('父任务归属或范围已改变；保留旧现场，发送已停用'),
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
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
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
                  for (final task in taskCards)
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
                            if (_drafts[task.id] != null) ...[
                              const SizedBox(height: 8),
                              DraftView(draft: _drafts[task.id]!),
                            ],
                            if (!_child) _subconversationEntries(task),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (!_child)
                                  TextButton(
                                    onPressed: _openingChild
                                        ? null
                                        : () => _openChild(task),
                                    child: const Text('子对话'),
                                  ),
                                if (!_child &&
                                    widget.agent.uiPlanningEnabled &&
                                    task.state == PersonalTaskState.succeeded)
                                  TextButton(
                                    onPressed: () async {
                                      await widget.agent.planUi(task.id);
                                      _refresh();
                                    },
                                    child: const Text('规划此回答'),
                                  ),
                                if (!_child &&
                                    widget.agent.uiPlanningEnabled &&
                                    widget.agent
                                            .uiPresentation(task.id)
                                            ?.validated !=
                                        null)
                                  TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => DynamicWorkspace(
                                          repository: widget.repo,
                                          host: widget.host,
                                          taskId: task.id,
                                          surfaceId: widget.agent
                                              .uiPresentation(task.id)!
                                              .validated!
                                              .plan
                                              .surfaceId,
                                          plan: widget.agent
                                              .uiPresentation(task.id)!
                                              .validated,
                                          originalAnswer: task.summary ?? '',
                                          tools: widget.agent.tools,
                                          agent: widget.agent,
                                        ),
                                      ),
                                    ),
                                    child: const Text('打开交互页面'),
                                  ),
                                for (final surface in HostUiWorkspaceStore(
                                  widget.repo,
                                  taskId: task.id,
                                ).surfaces())
                                  TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => DynamicWorkspace(
                                          repository: widget.repo,
                                          host: widget.host,
                                          taskId: task.id,
                                          surfaceId: surface,
                                          tools: widget.agent.tools,
                                        ),
                                      ),
                                    ),
                                    child: Text('已保存草稿 · $surface'),
                                  ),
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
                    onChanged: (id) {
                      setState(() => _profileId = id ?? '');
                      _saveUi();
                    },
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
                        onPressed: _childAvailable ? _tool : null,
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('本地工具'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || !_childAvailable ? null : _send,
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

class _SubconversationGoalDialog extends StatefulWidget {
  const _SubconversationGoalDialog();
  @override
  State<_SubconversationGoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_SubconversationGoalDialog> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('子对话目标'),
    content: TextField(
      controller: input,
      autofocus: true,
      decoration: const InputDecoration(labelText: '输入问题（发送后才执行）'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('打开'),
      ),
    ],
  );
}
