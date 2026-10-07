# REG-2b 最终 leader 审查与集成结论

日期：2026-10-07。被审实现：`fix/reg-2b-integration-safety`，
`2beab6c6cae7af2c07c32b854b396a99cf3eb3b0`（PR #5）。
本文件由执行者记录云端父任务 leader B 角明确提供的独立复审结论，
不是执行者自授合入批准，也不冒称 Sonnet 或真机审查。
按 [REVIEW.md](REVIEW.md) 记录；根据本次明确指示在 fix 分支提交。

## 范围与交付核对

最新 `origin/develop` 为 `8e84c46`，已是被审实现的祖先，没有新的
未集成 develop 代码。整体 diff 同时含已验收 REG-2a（迁移 9）和
REG-2b（迁移 10），不能把前者误计为本轮越界。原始验证日志、
Flutter 生成的 Podfile/xcconfig 均未纳入本集成候选。
本轮追加修复仅三个实现文件、两个新增回归测试、三个历史夹具说明/SQL。

| 交付 | 结论与依据 |
|---|---|
| v2 类型与 v1 公共面 | 满足；`packages/muyon_module_api/lib/src/module_v2.dart:12`，契约全量 29 项通过。签名偏离见提交 `26a6526`：typed registrar、`ModuleSection.showInModuleMenu`、来源驱动解析；无业务模块迁移。 |
| 统一激活、失败隔离、目录、版本 `{1,2}` | 满足；`app/module_host.dart`、`module_catalog.dart`、`module_registry.dart`；API3、失败隔离、撤销/关闭时序回归。 |
| 注册器不暴露审批/写账、拒绝能力 | 满足；`app/host_tool_registrar.dart`、`platform/module_grants.dart`；公开 approve 变异被杀死，v2 tools 拒绝，knowledge/models 因 scoped facade 未就绪保持拒绝。 |
| 单一范围解析及先行差分 | 满足；`platform/scope_resolver.dart`、`test/scope_resolver_differential_test.dart` 与冻结旧实现；含空/有序/错误差分及 v2 身份防替换。 |
| 迁移与历史完整性 | 满足；真实 outbound 9 + grants 10，`platform/host_schema_compatibility.dart:77`；严格历史结构识别、事实记录防 UPDATE/DELETE/REPLACE、原子回滚和 reopen。 |
| 声明式首页/菜单/对象页与 v1 桥 | 满足；`app/legacy_module_bridge.dart`、`test/module_declared_ui_test.dart`；进入 v2 section 必须先激活，闭库前排空实际副作用。 |
| 既有测试与兼容范围 | §10.3 指定既有测试未修改；既有 `task_events_test.dart` 版本断言的任务系列偏离已在 `26a6526` 记录并纳入 leader 审查。没有改旧 golden 换取通过。 |

表内宿主路径相对 `apps/muyon/lib` / `apps/muyon`。未新增外部服务调用；
审批、范围、撤销由宿主控制，回环/夹具测试不冒充真实模型或真机结果。

## 三项追加复核与测试质量

1. **REPLACE**：默认 `recursive_triggers=0` 的独立探针确实能覆写旧修复事实。
   新 BEFORE INSERT 对已有事实的任何插入先拒绝，不依赖全局 pragma。
   仅精确匹配旧 repaired v10/v11 物理指纹时追加守卫，保留完整事实与
   migration 历史；后续失败会把 DDL/元数据一同回滚。
2. **v1 持久撤销**：真实 research 撤销 models 后，立即再激活和重启再激活
   均保留 denied/revoked 决策，不恢复 runtime。
3. **重叠撤销**：确定性 DB 队列屏障先复现第二条 durable withdrawal 被覆盖；
   按模块计数待完成撤销，旧调用不能提前解除激活门禁。失败能力保持关闭，
   其他能力成功不能清除它，只有其自身成功重试才解除。原 epoch 检查保留。

测试断言真实行为；屏障用 Completable/DB 队列而非 sleep。故障注入使用
SQLite trigger，变异以行为 assertion 失败而非编译失败计数；最终源码已恢复。
独立只读最终核实子代理也未发现具体代码阻塞。

## 实际重跑与门禁

Mac 最终 `scripts/ci.sh`：7 项 analyze 全通过（info 也失败）；
module_api 29、muyon_ui 6、prototype 40、research 211、supplier 482/3 skip，
宿主 `+890 ~3: All other tests passed!`。
最终恢复 focused 回归：`00:04 +38: All tests passed!`，exit 0。

Mac 询价：`+281 ~1 -46: Some tests failed.`；完整脚本 exit 1，
`CI SUMMARY: FAILED (test:inquiry)`。46 个 golden 失败路径及像素指标
与同机原 `e61a1db` 基线相同，184 张输出 PNG SHA-256 全部相同；
如实保留失败，未更新基准。原始日志仅 `/tmp/muyon-reg-2b-replace-fix/`。

14/14 变异行为杀死（各 exit 1）：API3、legacy-global、公开 approve、
revoke-epoch、close-authority、optional-cycle、migration-repair、
canonical-provenance、home-activation、shutdown-admission、REPLACE guard、
legacy-revoked、overlapping-gate、failed-revocation-gate。

Linux [CI 37677898172](https://github.com/mightyoung/Muyon/actions/runs/37677898172)
对应 exact head `2beab6c6cae7af2c07c32b854b396a99cf3eb3b0`：**success**，
analyze 7/7、suite 7/7；host 890/3 skip，inquiry 281/47 skip，Laya 29。
Linux 跳过需要 Mac 字体的 golden，不等于这些 Mac golden 已通过。
真机、真实模型验证延期，没有相应新增证据。

## 结论与非阻断后续

leader B 角云端独立复审：三项追加问题已修复，无新具体阻断，**有条件允许
普通合入 develop**。条件：本审查文档提交也须通过自身新 SHA CI，确认
最新 develop 没有新集成差异；有新冲突/失败需修复复审。不得合 main、发布或强推。

**非阻断，登记给 REG-3：v1 工具可用性同步。**
`apps/muyon/lib/platform/business_tools.dart:157` 的 `research.objects`
尚不属于 v2 inventory；models 被撤销后，runtime/grant 已拒绝，但该工具
可能仍 advertised 为可用并返回空成功。这不是已证明的外传或恢复授权绕过，
不扩大本 PR。REG-3 迁移时同步 inventory/availability：撤销 models 后
立即/重启重新查询工具均应拒绝或标 unavailable；执行不得空成功；
恢复合法授予后按实际可用性重新展示，并新增这三个场景的回归验收。
