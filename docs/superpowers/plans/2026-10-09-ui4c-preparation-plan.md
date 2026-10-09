# UI-4c Implementation Plan（准备稿，未执行）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans after leader review. Steps use checkbox (`- [ ]`) syntax for tracking. 不因本文件自动派代理或开始产品实现。

**Goal:** 在现有个人助手增加一层子会话，关闭保留现场，明确读取最新成果且不复制授权。

**Architecture:** FoundationRepository保持权威；settings最小关系/现场CAS，既有PersonalAgent/TaskRecords/AgentResume及UI-2a导航保持。单层panel复用AssistantPage与ConfirmCard，用户发送才运行任务。

**Tech Stack:** Flutter3.47.5/Dart3.13.4、SQLite现有host schema12、muyon_ui v6。

**Spec:** ../specs/2026-10-09-ui4c-preparation-design.md；../../tasks/UI-4c.md。本计划仅准备，产品实现和测试均未运行。

## Global Constraints

- 基线0b64cfa528041081e1df0f4314c8125c883f5245；UI2a未合develop。本片不合develop/main、不部署云、不跑实机。
- 一层子对话；关闭仅存UI不cancel；正文留messages；不复制授权或洗掉外部来源。
- 不改预算/modelcaps/外发/默认planning；不改schema1～12历史定义；不碰REG4b导入领域写。
- 本地模型/软指南不是前置；云公共模拟与Host真实SQLite证据分列，原生能力待末次。

## Review Focus

1. 同次开窗双击或close/reopen创建两个子conversation → creationToken原子唯一测试。
2. 用户已输入但关闭/页面卸载丢draft → close先保存且重新开库恢复测试。
3. 子消息更新恰在引用时 →实际读取版本/readAt，后续变化需重新读取测试。
4. 子授权/外部摘要进入父上下文被当可信 →scope/来源证明不复制测试。
5. 父scope/归属改变后恢复旧panel →保旧草稿只读，拒发送/旧CAS测试。

### Task 1：关系和现场投影

Files：新增apps/muyon/lib/platform/assistant_subconversations.dart；改platform/foundation_repository.dart host-only原子关联创建；测试test/assistant_subconversation_test.dart。

Interfaces：SubconversationRef(parentTaskId,parentConversationId,childConversationId,creationToken)；SubconversationWorkspace(draftText,scrollOffset,selectedProfileId,openState,revision,scopeKey)；openSubconversation/readLatestSubconversation/saveSubconversationWorkspace同spec。

- [ ] 写effective RED：open_atomic_same_creation_token_creates_one_child、one_level_only、workspace_cas_and_reopen_keep_draft、scope_change_keeps_readable_old_draft；断言实际conversations/messages/tasks数量与旧输入，不以编译失败算RED。
- [ ] 在apps/muyon运行flutter test --no-pub test/assistant_subconversation_test.dart，记录实际行为失败。
- [ ] 最小类型/host原子写/CAS；不用previousAttemptId，不建第二会话库，不复制parent payload/authorizations。
- [ ] 原测试GREEN，并跑foundation_scope/storage_recovery/host_schema_compatibility/ui_workspace_store回归；schema12旧库重开无数据删改。
- [ ] 独立可测小提交，记录真实结果，不提前勾选。

### Task 2：最新引用与来源边界

Files：同service测试文件；需要的输入引用薄适配仅在明确来源证明方案复核后加入，未复核不得接agent_model_turn/grant策略。

- [ ] RED：parent_reads_latest_only_when_requested（子v2，未引用父task不变，显式读v2并标版本）、child_summary_does_not_copy_authority、source_change_requires_reread、external_child_summary_is_not_clean_provenance。
- [ ] 读真实FoundationRepository消息/任务/事件；结果卡状态不能当完成回执；显式读保留读取截止版本，实际ObjectRef/ArtifactRef以owner重核。
- [ ] 只读概要GREEN；显式引用先进入父草稿并经既有请求授权；缺host provenance时保持只读，不静默让父模型消费。
- [ ] 跑task_events/agent_resume/assistant_loaded_input_scope_boundaries及现有UI2a对象/文件返回回归；独审后小提交。

### Task 3：单层面板与close语义

Files：新增screens/assistant_subconversation_panel.dart；改screens/assistant_page.dart；同host测试；公开preview新增subconversation_preview.dart及subconversation_smoke_test.dart，仅公开模拟。

- [ ] RED：closing_panel_preserves_child_work、explicit_cancel_uses_existing_agent、reopening_panel_restores_input_scroll、child_cannot_open_grandchild；运行中的实际task关闭前后状态不变，输入保留。
- [ ] 子模式锁定明确conversationId、隐藏主会话切换/新子入口；关闭await CAS持久后dismiss，dispose不cancel。
- [ ] 320/390/1440视口、200%字号、浅/深色、键盘/减少动效widget测试GREEN，复用v6token与现有确认卡；不新造授权按钮。
- [ ] 新测试及personal_agent/agent_resume/task_events、UI2a、REG4b回归GREEN；分包Flutter测试串行避免native assets竞争，独审后提交。

### Task 4：交付验证（仅执行阶段）

- [ ] bash scripts/ci.sh完整八包分析/测试；Mac截图新SHA重新和精确基线比46案例/184PNG，不能沿用例外，不改golden/阈值/skip。
- [ ] flutter build web --release --no-pub公共preview；构建SHA、哈希、公开数据边界登记。受控云访问权限具备后才运行cloud smoke；不具备则交包/明确未验，不能称通过。
- [ ] 全分支新鲜独审；任务分支本地提交/按授权推送、核远端HEAD/精确CI；未获另授权不合develop/main。
- [ ] 进程终止/锁屏/Android/macOS/Windows/PDF/OCR/原生文件权限依R-1-AI-UI-final，未测保持未测。

自审：五类风险均有具体测试；所有执行项未勾选；没有新增额度、模型、授权或导入规则；scope/provenance和云门禁未确定时保持保守只读边界。
