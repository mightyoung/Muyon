# AIUI-5 F5 阶段 1 契约收敛报告（proposed / 未采纳）

执行：真实 Claude Code（CLI 2.1.295；init 实报 `claude-sonnet-5-5`，请求 `--model sonnet --effort low`，输出上限24000；acceptEdits，未跳过权限）。分支 `task/aiui-f5-contract-close`，工作区 `/tmp/muspace-aiui-f5-contract-close`。**重核 `git rev-parse HEAD` = `origin/develop` = `cf672164e4f6c3e7beea8029c8be735e33c3bf19`**（委派时的 `b8a9a523` 已被 PR #15 合并推进）。未实现任何生产代码，Claude未提交/推送/合并；调用者随后负责提交推送与Draft PR，最终SHA/PR见交付回复，未改旧草稿与旧 checker 文件，未触碰其他 worktree、凭证、配置，未下载依赖，未调用付费模型。

## 交付文件
- `docs/design/aiui-f5-contract-proposed.md`（决策包）
- `docs/tasks/AIUI-5-F5b-proposed.md`、`docs/tasks/AIUI-5-F5c-proposed.md`
- `docs/fixtures/aiui5/f5-contract-proposed/`：`manifest.json`、`typed-edits.json`、`collection-stable-row.json`、`library-2.stream-2.model-lines.jsonl`、`stream-version.json`、`snapshot-race.json`、`restore-overrides.json`（均 future-only 数据）

## 已收敛的提案

两轮Claude产出已由调用者Codex初审并整合为单一正文（无生产代码）。六项最终待采纳：版本门槛；五类spec；collection+computed evidence；stable row可信本地导航；完整token+同步publish+保持identity；F5b/F5c/F3b/F4c所有权。见设计§9。补齐computed来源/FactState、source/host/permission generation、Choice稳定ID/Tabs受控、spec上下文/字节限额、人工override/view分层。仍proposed，未虚构用户采纳。


HANDOVER-LEADER、HANDOVER-A、ADR-0001（含后续记录）、AI 原生方案 §5–§6、stream 契约、旧 binding adapter 草稿全文、AIUI-2 followup、AIUI-3（F3a 状态表）及 F3a 报告/复审、AIUI-4 复核、AIUI-5、F5a 报告/预审/复审、NEXT-BATCH 矩阵与复核、F5a 三个 fixture。基线树无 AGENTS/CLAUDE。

## 核对过的生产入口
`snapshot.dart`、`plan.dart`、`validation.dart`、`state.dart`、`workspace.dart`、`stream_protocol.dart`、`intent.dart`、`planning.dart`（module_api/ui）；`dynamic/{catalog,surface,workspace,fallback}.dart`、`ui_components/*` 签名；`ui_planning_events.dart`、`ui_navigation_anchors.dart`、`ui_workspace_store.dart`、`ui_formula_registry.dart`、`screens/dynamic_workspace.dart`。关键发现：library-1 目前零组件可渲染；`dynamic-1` 是生产目录；F3a 要求公式状态为 String 且 state 键集一致；`BindingKind.byName` 在 stream parser 与 workspace decode 处会随新枚举值改变行为；现行 `restoreWorkspace` 对不合规 override 不一致。


## 真实终态与归属

会话 `fb413542-9fd8-477f-9f35-470f2c72d863`，首轮66 turns/633634ms、修订轮14 turns/134431ms，两轮 `result/success`、`end_turn`、`is_error=false`、进程exit0。设计、任务书和7份夹具由真实Claude两轮写出；Codex负责非作者初审、合并冲突的首轮文字、旧目录strict gate/异步本地导航澄清、PR18核对、机械验证和Git交付。未冒称Claude。原始prompt/jsonl/stderr/exit code在 `/tmp/aiui-f5-contract-close-logs/`，不入仓。原生worktree工具无响应未创建目录，取消后git建立隔离目录。主工作树、其他任务、旧draft/checker/测试未改。

## PR18 对齐

调用者直接读取Draft PR18 head `ba5a9edaf541e27bc09f311ad66dd8fceb17deb5` 任务书与14future场景。F3b唯一拥有 `apps/muyon/lib/platform/ui_recompute_adapter.dart`，消费F5c先交的port/token/batch/publish接口；F5c不重复写adapter。首片预算qty decimal String，经真实F3a evaluate。已有 `inquiry.set_item_qty` 仍缺AIUI业务mapping，确认disabled，编辑重算/checkpoint阶段业务0。F4c独立验收；AIUI-4旧恢复测试只读。

## 实际验证

Claude的Python/Node Bash、仓库外PR18 Read被既有权限拒绝，未扩权限；调用者完成这些核对。6JSON/1JSONL共7行解析PASS，所有JSON future-only；正文/manifest33唯一项相等，另与旧checker提取真实目录核对；旧 `python3 scripts/aiui5/check_artifacts.py` PASS（33schema/12case/21无case/66future）；`git diff --check` PASS。这些不证明新validator/codec/Widget通过。基线cf672164精确 [Actions38019908442](https://github.com/mightyoung/Muyon/actions/runs/38019908442) completed/success，只证明基线，本分支headCI另查。

没有Flutter/Dart，不下载依赖。新Dart、4变异、浏览器/真机/真实模型均NOT IMPLEMENTED/NOT RUN。

## 本轮四项最小缺口闭合（PR19 head 9fc56ba6680631b34ed830b9db2aab935b2833b8；真实 Claude sonnet low 修改，调用者已核对真实终态；Claude未运行测试，不虚构运行时 PASS）
修改文件：design（§2 规则 4/6/10/11、§4.1、§4.2 原段落直接更新）、F5b/F5c 任务书、`typed-edits.json`、`snapshot-race.json`、`manifest.json`、本报告。
1. nullable：仅 library-2 `editField`，先确认 state key/spec/`spec.payloadType==目录事件类型`，再按 `spec.nullable` 对 null 跳过粗 `matchesUiValue`，随后 `rejectPayload/rejectInContext`；非 null 与旧目录/其他事件保持原 gate；无 spec 或被拒 null 不改值与 revision；补 `nullableDispatch` 正负 case。
2. 旧 Widget 冒充：`UiRenderCapture` + 加性 `eventForCapture`，渲染路径禁用现场 `eventFor`，覆盖全部回调；dispatchCaptured 在转既有 dispatch 前对旧 capture stale、business operation 只取 capture；F5c publish 严格拒绝 `revision <=` 当前并核 surfaceId/snapshot/intent/catalog；fixture `staleWidgetCapture`（直接调用真实旧闭包）。归属：F5b capture，F5c 严格 publish。
3. 重算范围：候选 plan 所有将显示 computed（含 collection cell）全部以 S8 真实 evaluate，未受影响实例也不得重标，失败则只读降级不发布；无缓存/DAG；fixture `recomputeAllDisplayed`（两实例仅一个依赖 qty）。
4. 严格 payload 拒绝：`'oops'`、`''`、`'.'` 不写 state/override、不增 revision、不重算，不做持久 buffer，Widget 恢复最后接受文本；领域 invalid 用合法 `qty='3'`（如 `unit_mismatch`）。**PR18 场景 `invalid_formula_preserves_draft_without_old_success` 若用 oops 进入 evaluator，需非 owner 验收作者同步调整；本包未改 PR18 文件。**

5. extracted/override 冲突（真实 Claude 修改，调用者已核对终态；未运行测试）：published S8.initialUiState 保宿主 extracted2，人工3仅经 `currentUiState` 传 F3a，`S8_in` 不覆盖 extracted、不写入最终 S8；rebase/restore/_capture 保三层与 override 标记；`adoptExtracted` 清 override 并递增 revision，回2后重算20、旧 confirm 失效。补 `extractedOverrideLayers`（snapshot-race、restore-overrides）。另补公式 state 依赖守卫：必须 `UiStringEdit` 且 `view==false`，`view:true` → `formula_view_state_dep`，补 typed-edits `formulaDependency` 负例。第4项维持最小首片、不新增 raw buffer；PR18 对应调整交其 owner，未改 PR18 文件。

6. H3 最终 admission（真实 Claude 修改，待调用者核对，未运行测试）：design §3.5 补 `UiNavigationToken`/同步 `UiNavigationProbe`；沿用 `ui_navigation_anchors.dart:67–81`，checkpoint 返回后与取得 page/lease 后各重核，final check 与 push 间无 await，失败零 push 并释放已取得 lease，`mounted/canPresent` 仅附加；H3 由 AIUI-4 owner 应用，PR18 owner 需同步，本任务未改 PR18。fixture 补两项撤权用例（leaseDispose 0 / 1）。另统一 `snapshot-race.json` 顶层 `published.snapshot.initialUiState.qty=2`（override 3 + currentUiState 3，总价 30），manifest `closureCases` 补第五项、`formula_view_state_dep`、H3 用例。

## 剩余边界

待父任务采纳六项并另授权F5b；业务mapping/receipt由AIUI-6/REG-4c提供；H3由AIUI-4 owner接当前宿主重核及既有外壳导航。旧拒绝测试继续通过是实现要求，不需另授权改掉拒绝。首版推迟自动迁移、数值状态进F3a、Choice自填、Table/KeyValue集合、最优高亮。草稿PR只交可审文件，不启用生产、不合develop/main、不强推/删分支/部署/付费。

## 本次补修终态与机械验证

同一真实Claude会话/模型/low/24000设置未变，四个窄回合：four-gaps 17 turns/87277ms；fifth-gap 13 turns/45414ms；capture 7 turns/28177ms；H3 8 turns/31260ms。均result success、end_turn、is_error=false、exit0。五项及view守卫/H3全部由真实Claude直接改原提案与未来夹具；Codex只补本终态摘要并执行检查/提交推送。

调用者重跑6JSON/1JSONL解析、future-only标签、真实目录33项集合核对、snapshot顶层extracted2/current override3/result30一致性、旧checker、diff检查均PASS；Dart/Widget/原子发布/导航/恢复运行时测试仍NOT IMPLEMENTED/NOT RUN。PR18文件未改，需其owner同步非法payload vs领域invalid、extracted/adopt与H3最终admission。生产文件及旧契约/测试未动。
