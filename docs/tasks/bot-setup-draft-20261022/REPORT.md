# GB-01–04 最小离线配置草稿批次

执行位置：Muyon 云端保存环境；日期：2026-10-22 UTC。
状态：独立、可测的内存草稿状态组件；没有产品接线、正式 Agent 创建或启动。

## 来源与范围

- 开工只读核远端：`codex/muyon-android-refactor` = `f4781e16ddf4e542b983fbd77f266a0071148255`；main = `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`；develop = `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`。任务分支开工时远端不存在。
- 原 `/workspace/Muyon` 的 work 分支干净，未检出/改写其分支；新增 worktree `/workspace/bot-setup-draft`，分支 `task/bot-setup-draft-20261022` 从已核候选派生。
- `find /workspace -name AGENTS.md`、候选内再次查找均未发现该文件；核读任务索引、REVIEW、HANDOVER-LEADER、leaderb-next HANDOFF、Android PROGRESS/任务卡和 live CURRENT。旧任务卡中历史未开工状态由 PROGRESS 的精确证据补充，不当作最新事实。
- 完整读取 Grok 规格 `libfile_de7d567abee8819187963fcb5f2dae68`（136行）与总纲 `libfile_d1ffab06dfa4819180f0affb933237bf`（182行），均 `has_more=false`。Grok 名称动态推荐控制流未证，本实现为 Muyon 独立设计，未复制竞品代码/资产。
- 写入范围仅新增 `product/agents/setup/`、对应 `src/test/.../agents/setup/` 和本报告目录。没有改 MainActivity、导航、聊天、构建、Manifest、权限、依赖或既有测试。
- 唯一 develop 合入者仍为 Leader B；本任务不自行合入。

## 已实现

| 需求 | 实现与可核边界 |
| --- | --- |
| GB-01 | `BotSetupDraft` 从名称到用途、配置、复核逐步推进。稳定 draft_id 与名称分离；名称长度与已有目录保持 UTF-16 ≤60，角色 ≤160，用途 ≤8000；拒绝空白、控制/格式字符和畸形 UTF-16，支持中文/合法 emoji。重名草稿可有独立 ID，无目录写入依赖。 |
| GB-02 | 仅根据用途匹配确定性本地模板，明确 `本地模板建议`，记录 template id/version。建议与选值分离，接收只展示；显式采纳才改变角色。每个字段有 origin、revision、userLocked；手工角色锁定后拒绝建议覆盖。任何配置编辑使旧请求失效；同revision也用 request_id 区分。无网络建议失败依赖，始终可手填。 |
| GB-03 | 宿主提供 `CapabilityOption`/`MaterialOption`，含版本、可用性、原因和输入输出。仅显式选择可用 ID，资料必须属于原 account/project opaque scope；变更技能元数据/版本会取消旧选择，资料失权后移出选择；保留逐项失效原因，显式重新选择前禁止配置页进入复核或取得 preview。改名不清除已选技能。这里只是草稿选择，绝非读取资料、启用技能或授权。 |
| GB-04 | `SetupPreview` 展示名称/用途/角色、已选能力/资料和模板来源。权限固定显示“未配置；未授予新权限”；费用固定“费用未知；未配置执行预算”；费用字段为 null，不以0假定。`canCreate=false`、`canStart=false`。 |
| 回退/取消 | 导航保留用户输入；取消保留内存草稿、丢弃晚到建议；resume只恢复此对象。跨账户/项目恢复校验拒绝。无进程重启持久恢复证明。 |
| unknown 防线 | 被动观察 seam `observePendingCreation` 绑定当前 review revision 与原 intent；不执行创建。PENDING/UNKNOWN 时编辑、取消、新 pending 被拒，结果只接受原 intent；UNKNOWN 保持冻结或接受原意图确定结果。CREATED 为终态；明确拒绝保留输入，修改产生新 revision 后才能开始另一观察。 |

`observe*` 只是未来宿主回执适配的局部状态合同，调用它不产生外部请求、正式 Agent、确认授权或真正幂等事务。仅字段/步骤变化不触发保存；无自动 Agent 启动。

## 复用与接线计划（未执行）

1. 已核 `product/agents/AgentCatalog.kt`：已有 `AgentProfile(id,name,role,instructions,...)`、`AgentCatalog.saveAgent`，后者立即写正式目录。新组件不另造正式配置持久化模型，且不调用目录。
2. 未来经公共 owner 接 Compose/ViewModel；单线程持有该状态对象。现有 stable Agent ID 必须由创建 owner 分配，不能拿名称或 draft_id 当已创建 agent_id。
3. 明确本地创建审查通过后，映射预览 `name → AgentProfile.name`、`role → role`、`purpose → instructions`；图标/颜色沿已有默认。当前只提供预览字段，不提供可保存 AgentProfile 或创建按钮。现有模型没有 skills/scope/permission/budget 字段，禁止塞进 instructions 冒充权限；正式宿主合同待单独接线。
4. 从现有 `crates/muyon-core/src/agent/workflow.rs` 的 `supplier-overview`/`paper-overview` 描述投影当前可用能力，不新增第二套执行目录；本批未将任一技能假定为已可用。候选 ID、version、实际资料 scope 必须由可信宿主提供并在执行时再次核权，UI 元数据从不充当权限。
5. 草稿持久化需另立独立 namespace、account/project/draft_id 归属和 CAS；不能复用 catalog key。当前内存保留不等于进程重启恢复。恢复、旋转/进程退出、可访问性与设备验收仍待后续组件/存储任务。
6. 真正创建必须先补 durable intent、expected revision/config摘要和原回执查询，unknown 查询原请求。此组件没有持久幂等、Service/JNI 或 catalog 原子事务的保证。外部写入、模型调用、预算和外发授权仍只能沿既有可信确认链。
7. GB-05–07 完整创建/持久恢复/主Agent及置顶归属未实现。无 Compose 页面、APK、导航入口、设备截图或产品可用声明。

## 测试先行与验证

初始 RED 测试提交：`8f814baeeb14c4dc2be5d95952ab32af9b2f7a3d`；只添加8组行为检查。实现前运行 Kotlin 编译，因 `BotSetupDraft` 等尚未定义而失败；这属于 API 缺失 RED，不冒称运行时红灯。
实现/扩展检查提交：`94023ba709808fe3c6c3b379427a4e3b136c475e`。候选选择投影补测先因 `choices` 缺失编译失败，再补API。

环境原本没有 Kotlin 编译器/Android SDK。仅将公开 Kotlin 2.2.10 编译器下载并解压到 `/tmp/bot-setup-tools`，无仓库依赖变动、凭据或付费。独立 JVM 复验入口：

```sh
KOTLINC=/tmp/bot-setup-tools/kotlinc/bin/kotlinc \
  apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh
```

初版实际执行结果：PASS 10 offline checks；独立复审R1补修后，最终源码提交 `f9920c75b05904ab54250c2c65cc6dca3db27390`，PASS 11 offline checks。R1新增测试先因 invalidations 缺失编译 RED，再补修状态投影和重新确认门槛。覆盖名称不保存、旧/乱序建议、用户锁、回退/取消、复核无授权/费用、revision绑定、unknown/错误原意图/终态、明确拒绝、技能白名单/跨scope/版本撤销、UTF16和超长输入。测试为独立 Kotlin main，不是 Gradle 自动发现的 JUnit/Android 测试；按上述入口单独运行。没有运行完整 Android 构建/设备验收，也没有拿旧候选的通过替代本批。

负向变异在 `/tmp` 副本中执行，不改仓库源：去掉迟到请求隔离、去掉手工锁、放开UNKNOWN编辑、去掉资料跨scope校验、去掉失效选择重新确认门槛；每个变异均须由行为断言击中。最终结果与独立复审见 REVIEW.md。原始编译/测试日志不入仓库。

## 剩余阻断与历史事实

- 整体产品验收保持原 PARTIAL/HOLD；无新CI或同候选真机结果。
- 旧两次真实请求仍 unknown，累计预占 ¥0.002620、实际费用未知；未读取/重置旧台账、未重发、未结清预占。
- 本批未发真实模型/搜索请求、未配置凭据、未扩权限、未部署/付费/强推/删除分支；不处理历史拒绝的 I04 操作。
- 正式创建持久合同、进程恢复与宿主接线均未完成；这份独立组件不能作为 Agent 已可创建或运行的证据。
