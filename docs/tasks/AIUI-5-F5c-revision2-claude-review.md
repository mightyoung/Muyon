# Real Claude independent fixed-diff review: round2

Fixed candidate afce5b96ccd236f0847ecc967e7c49ba021cb074 versus baseline5713105479ebdfae64da8a89fe0bd2304fc26216, with pinned developb6b56d0929f622b9fae123c17046ba6715672320. CLI2.1.295; actual init modelclaude-sonnet-5-5; effortlow; CLAUDE_CODE_MAX_OUTPUT_TOKENS24000; permission-modeacceptEdits with existing tool permissions, no bypass/config/credential changes. Session22e65245-74da-4d60-927e-db96ac8f0c98; result success/is_errorfalse/end_turn,4turns,85629ms, shell exit0, permission_denials[].

Caller provided an immutable git diff and complete changed source/test files; Claude additionally used readonly Bash to verify Git HEAD and inspect Prose/edit_spec/apps flush/readOnly callers. No files edited and no tests run by Claude. Local PASS numbers are caller evidence, explicitly not independently rerun by reviewer. Raw invocation prompt/jsonl/stderr/exit/result stay outsideGit in /tmp/aiui-f5b-logs. Latest implementation is native Codex under explicit parent authorization, not claimed Claude-authored.

## Raw completed report

# 独立复审结果:HEAD afce5b96

我只读源码,没有编辑文件,也没有跑任何测试。你给的 API190 / UI525 / SQLite10 PASS 我按你的说明采信,没有复验。

我核对了 `git rev-parse HEAD`,确实是 afce5b96。我读了 `layout.dart` 的 `Prose`、`edit_spec.dart` 的 `normalize` 和 `usesTypedEdits`,并 grep 了 apps 对 `flush` 和 `readOnly` 的调用点。

## 结论:无硬阻断项

五项修复我读下来都成立。发现一个中等回归(P2),它不在你要求核的五项里,在 typed 恢复和 rebase 的交界处。

## 五项逐条

### 1. Prose 模型来源:成立

- `component_adapter.dart:125-131` 按 `\n\s*\n` 拆段,每段加前缀「模型所述:」,再用 `\n\n` 拼回。
- `Prose` 自身也用同一正则拆段,所以每个 `SelectableText` 都带标记。
- `textEquivalent` 取传入的 `text`,语义标签和复制动作因此也带标记。
- 改动只在 adapter,通用 `Prose` 控件没动。

### 2. 单列 CompareTable 排序:成立,没有擅定多列策略

- 只有 `columns.length == 1 && sort == 'value'` 才排序,比较规则是 num 对 num 用 `compareTo`,否则用 `'$av'.compareTo`。这与旧 `Table` 的契约一致。
- 平局按原始位置打破,所以排序稳定。
- 渲染行、marks 的行号和行按钮都用同一个 `rows` 副本。
- 排序用的是 `.toList()` 的副本,不会改 collection 本身。
- 多列保持原序。

### 3. Choice/Checklist 的 ID 作为业务输入:成立

`surface.dart:473-501`:

- `spec.view`、`selected` 为 null、host 的 `expected` 或 `selected` 不通过 `spec.reject`,都返回 `invalid`。
- `expected` 先 `normalize` 再用 `listEquals` 比较内容,不再用引用相等。
- 通过后传入 `List.unmodifiable(selected)`。
- 重复提交仍然被 `_lockedOperations` 挡成 `duplicate`。
- 非 ID 的引用(fact、state、已确认记录)仍走原来的标量分支。
- 未登记 spec 的 `uiState` 键没有走新分支,原因是 `spec is UiItemIdsEdit` 为假,所以不会误伤。
- 带 unreadable 原因的 ID 键,在 `UiSessionState.dispatch` 里就返回 `invalid`,到不了业务路由。

### 4. schema2 的 selection/manual/view 编解码:成立

- `toJson` 只在 `schemaVersion == 2` 时写入四个新字段。
- 构造函数的约束互相一致:library-2 必须是 schema 2,`selectionOverrides` 和 `viewSelections` 的键必须在 `selections` 里,ID 不能重复,数量不超过 `UiCollectionLimits.rows`。
- collection 引用只在 `schemaVersion == 2 && catalogVersion == 'library-2'` 时才解码,其他组合抛错。
- `HostUiWorkspaceStore._decode` 把超限字节和解码失败包成 `UiWorkspaceUnreadable`,带原始 JSON。
- `UiWorkspaceController.open` 在这种情况下置 `readOnly` 和 `saveError`。只有同 task、surface、scope 才保留可读草稿,否则不暴露。
- 只读状态下 `flush` 会抛错,所以不会把新内容写回。
- 保存前先编码并检查字节数,超 256KiB 时在进入 write 之前就拒绝,旧 revision 保留。

### 5. typed 恢复重新校验:成立

`restoreWorkspace`:

- 逐层校验:key 是否还在、view 属性是否一致、view 键是否又变成了 host draft、`validateSpec` 和 `reject`(含范围、日期、ID membership)。
- 任何抛异常都归为 `spec_exception`。
- 被拒的值只进 `readable` 和 reasons,不进 `_values`、`_selections` 和各 override 层。
- 恢复后 `readOnly` 为真,`flush` 抛错,旧字节不动。
- 被拒的 ID 列表整体保留,不做过滤。
- 已保存的初始(未编辑)selection 不会覆盖当前 host 默认值。

## 发现的问题

### P2(非硬阻断,建议修):含被拒草稿的 checkpoint 重开后永久只读,且无恢复路径

**触发步骤**(`state.dart` / `workspace.dart`):

1. 在 library-2 下,用户手动把 `k` 改成 9.0。
2. host 发布新快照,把 `k` 的 `max` 降到 5。
3. `prepareRebase` 把 9.0 判为 `range`,放进 `readableDraft`,这时 workspace 仍可写。
4. 控制器通过 `_changed` 触发 `flush`,`_capture` 把 `readableDraft` 持久化(`workspace.dart` 的 `readableDraft: session.readableDraft`)。
5. 重开后 `restoreWorkspace` 的开头把 `saved.readableDraft` 的每个键预置为 `retained_unreadable`。
6. 这些原因不会在后面的循环里被清掉,因为被拒值不在 override 层里。
7. 循环结束后 `_unreadableReasons` 非空,`UiWorkspaceController.open` 置 `readOnly = true`,`saveError = 'workspace_edit_spec:retained_unreadable'`。
8. 之后 `adoptExtracted` 会直接 return,`flush` 会抛错。
9. 在线时本来可以用 `adoptExtracted` 或 `editField` 修复,重开后失去了这条路径,而且旧 bytes 不会被重写。

这是新引入的行为。之前 `readableDraft` 根本不持久化,没有这个陷阱。

**我的判断**:这和「非法旧值保持可读不活化,旧 bytes 只读」的要求一致,所以不算硬阻断。但在线可修、重开后不可修,两种状态不一致,用户无法清除。

**可选修法**:在 `restoreWorkspace` 里区分两类。
- 来自 `saved.readableDraft` 且当前 spec 仍然拒绝的,保持不活化,但不单独触发 `readOnly`。
- 本次恢复中新判定为被拒的,才触发 `readOnly`。

## 技术限制(不阻断,供记录)

1. **`restoreWorkspace` 对 legacy catalog 变严了**:`viewValues` 里 key 已被移除时,旧代码静默跳过,现在记为 `key_removed` 并让 workspace 只读。仅影响含 `viewValues` 的 checkpoint。
2. **旧 checkpoint 兼容**:历史上用默认 `schemaVersion=1` 保存的 library-2 checkpoint,现在会在 `fromJson` 里被构造函数拒绝,读成 `workspace_codec`,只读。因为 develop 尚未采纳,这个分支也未合并,影响面有限。
3. **256KiB 上限对旧数据**:此前已写入、超过上限的 checkpoint,现在会读成 `workspace_byte_limit`,只读。
4. **未知 `readOnly` 的 `flush` 语义**:`restoreWorkspace` 之后因 `unreadableReasons` 非空而置 `readOnly`,此时 `saveError` 非空,`flush` 会抛错,而不是以前的静默 no-op。apps 现有调用点(`inquiry_list_review`、`import_review_projection`、`ui_navigation_anchors`)用的是 legacy catalog,并且大多先判断 `readOnly` 再 `flush`,我没发现实际冲突。
5. **排序**:空值按字符串 `'null'` 参与排序,与旧 `Table` 一致。混合 num 和 String 的比较不是全序,只保证不抛错。
6. **Prose 边界**:空文本或首尾空段会产生一个只有「模型所述:」的空声明段。属展示瑕疵,不影响安全。
7. **未读回的内容**:`ReadOnly` 下 `readableDraft` 里混入了 `extracted`(host 的初始值)。这只影响展示,不影响业务输入。

## Review verdict

**APPROVE WITH CONDITIONS(无硬阻断)。** 五项修复在源码层面成立。越权和业务输入方面,被拒值和只读状态下的 ID 都到不了业务端口。数据丢失方面,CAS、旧 bytes 保留和超限拒写都成立。

建议在合并前处理 P2,或把它明确记录为已知限制。我没有执行任何测试,上面的 PASS 数据来自你的说明。

## Native disposition

Five requested blockers are accepted as repaired; no hard blocker was reported. The additional P2 is recorded, not silently waived: a persisted rejected/readable draft makes the reopened workspace readOnly, and the existing adoption UI has no clear/recovery path. This follows the currently adopted incompatible-restore rule, which preserves bytes and blocks activation. The suggested distinction that would make some invalid restored drafts writable is not implemented because it changes that rule. A narrowly authorized explicit recovery/discard operation, retaining identity/spec/CAS checks, is a separate technical decision for the integrator; there is no automatic migration or loosening of authorization. This limitation must remain visible in the PR/handoff.

Other review boundaries remain explicit: historical branch-only library-2/schema1 checkpoints decode readOnly; old >256KiB checkpoints are readOnly; legacy removed view keys are now readable/readOnly; mixed number/String/null sorting exactly reuses the old comparator (not a newly defined total order); multi-column sort policy is deferred. These are not claimed production migrations.


## Final compatibility correction: real Claude follow-up

Fixed source HEAD9c33d8edd0156c158a59c7cad0cf4773d2b44714. Same real CLI2.1.295/modelclaude-sonnet-5-5/effortlow/24000 cap/permission-modeacceptEdits, unchanged proxies/tool permissions; session2141772a-8ee4-4ae3-aa37-36aa13f9e189. Result success/is_errorfalse/end_turn,5turns,41879ms, shell exit0, permission_denials[]. Readonly Bash/Read verified SHA, final source delta and unchanged legacy host regression test; no file edits or test executions by Claude. Raw prompt/stream/stderr/exit/result remain outsideGit in /tmp/aiui-f5b-logs/claude.revision2-checkpoint.* and revision2-checkpoint-claude-prompt.txt. Verdict APPROVE/no blocker, does not reopen any of the five closed findings. Existing P2 remains open.

### Raw completed follow-up report

**Verdict: APPROVE.** I found no blocker in the 4-line compatibility fix, and it does not reopen any of the five closed findings.

**What I ran**
- I ran `git rev-parse HEAD`. It returned `9c33d8edd0156c158a59c7cad0cf4773d2b44714`, which matches your stated HEAD.
- I ran `git diff --stat afce5b96 HEAD`. The only change since my last review is in `packages/muyon_ui/lib/src/dynamic/workspace.dart`, plus two docs files. That change is 7 lines (4 net lines of logic).
- I ran a grep for the host regression test. It is `apps/muyon/test/conversation_shell_recovery_test.dart:402`, and I read it.
- Permissions: I only used Bash and Read, and I did not edit any file. I did not run Flutter, `dart test` or SQLite. I did not re-run any test. Your API190, UI525, SQLite10 and "18 PASS" figures are your own reports and I have not verified them.
- The `git status --short` output was empty, but I did not check the worktree's cleanliness before the commands above.

**The fix, at `workspace.dart:197-205`**
```dart
final compatible = !c.readOnly;
c.surface.session.restoreWorkspace(old, activate: compatible);
if (compatible && c.surface.session.unreadableReasons.isNotEmpty) { readOnly = true; saveError = 'workspace_edit_spec:…'; }
```
- **Incompatible workspace** (`readOnly` is already true from a schema, catalog, intent, snapshot, node or presentation mismatch):
  - All saved values stay readable under `workspace_incompatible`, and none become active.
  - `saveError` stays null. `flush()` at `workspace.dart:~262` returns `Future.value()`, so nothing is written.
  - `onEvent` is null and `readOnlyProbe` blocks dispatch, so there are no business calls. This restores the old silent no-write checkpoint.
  - The test at line 402 checks exactly this: `readOnly` is true, the draft shows `quantity: 人工保留`, there are no TextFields, `actions == 0`, and the SQLite bytes are unchanged after `checkpoint`.
- **Compatible workspace:** `compatible` is true, so the condition is identical to the previous code. A typed value that fails the current spec still sets `readOnly` and `saveError = workspace_edit_spec:<reason>`. That is the `activate=true` path that closed finding 5, so the typed-restore closure is intact.
- **Damaged-bytes path** (`UiWorkspaceUnreadable`): `old` is null there, so the `if (old != null)` block is skipped and the change cannot affect it. `saveError` stays `workspace_codec` or `workspace_byte_limit`, which the future-kind, future-schema and duplicate-ids tests assert.
- **Ordering:** `compatible` is read after all `readOnly` computations and before the surface restore. Nothing between those points reassigns it.

**The five findings, unchanged by this diff**
Prose provenance, CompareTable sort, Choice/Checklist ID routing, schema2 codec and typed restore revalidation all live in files this commit did not touch. The only edited logic is the incompatible-restore branch above.

**Technical limits (not blockers)**
1. **P2, as you recorded it.** A saved `readableDraft` makes `restoreWorkspace` assign `retained_unreadable`, so a compatible reopen becomes `readOnly` with `saveError = workspace_edit_spec:retained_unreadable`. `adoptExtracted` returns early when `readOnly`, so there is no way out. This is a data-safe but permanent lock until a recovery UI exists.
2. **No new test for the fix.** The fix is covered only by the existing host test, and nothing in the package tests asserts the compatible/incompatible split directly. I did not execute that test.
3. **`readableDraft` getter.** `UiWorkspaceController.readableDraft` returns `_stored.displayValues`, which omits `viewValues` and `viewSelections`. Those layers are readable only through the session. This is cosmetic.
4. **Incompatible workspaces show no explicit error.** `saveError` is null, so only `readOnly` signals the state.
5. **Still not claimed by this slice:** the F3b/apps wiring, cache optimization, multi-column CompareTable sort policy, and the 256 KiB bound, which is enforced only on save and on load.

**Verdict: APPROVE.** The new code only restores the historical quiet no-write behaviour for incompatible workspaces. Compatible-workspace save errors are unchanged. My approval rests on source reading, with no re-run of tests.
