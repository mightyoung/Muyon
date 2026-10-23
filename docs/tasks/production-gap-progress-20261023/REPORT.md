# 生产缺口推进与验证结果

日期：2026-10-23（Asia/Shanghai）。基线：`e16af808620488a7be0b3b4a10b91190d18f1177`。实时 GitHub develop 分支查询与该基线一致；主工作区原有改动未动。本轮为独立候选，未合入 develop。

## 本轮实际实现

1. **草稿持久化**：`services/draft_store.rs` 新增独立 SQLite namespace，原子保存完整 DraftEnvelope 与 SaveAck，CAS、原保存 intent 幂等查询、插件命名空间、scope/account/generation 分区、严格 schema/版本检查。Bot 与原业务 intent 账本均未借用或修改。历史保存回执不回滚新草稿，也不再次产生派发机会。
2. **开发管理宿主服务**：`development_drafts.rs` 接入实际保存/恢复及持久 dispatch marker；`development_session.rs` 将其与真实 ProductCore 连接。固定 development owner、保存前版本检查、确认前完整原命令核对、重复/重启只查询原意图；Requirement/Bug 仍是草稿。
3. **已有业务操作适配**：`command_port.rs` 实现 HostCommandPort 到现有 ProductCore 的严格适配。复用原 prepare、可见用户确认、lookup、cancel、授权与回执，不建第二命令账本，不新增 Operation。Rust capability 仅供可信宿主，不注册给模型/插件或通用 wire dispatcher。
4. **GitHub 响应适配**：`github_repository.rs` 解析真实 REST PR/Actions 响应，核对仓库、PR、前后 SHA、完整分页和 workflow/run/attempt；缺预期 workflow 或实际 tested-subject 证明时保留 Unknown。测试合并提交与 head 独立投影。

## 新鲜验证

实际使用已安装的 Rust **1.93.1**，所有 Cargo 验证均 `--offline --locked`，未新增依赖。

| 验证 | 结果与范围 |
| --- | --- |
| 全 workspace / all-targets Rust 测试 | **754 passed / 0 failed / 0 ignored，48 项 test summaries**。包含既有执行次数与新增 34 次执行，不宣称是 754 个互不重叠业务场景。最终 schema 修正后重跑 exit 0。 |
| 草稿新增测试 | 11 项；真实磁盘重开、CAS 冲突、intent 冲突、历史回执、scope/plugin 分区、额外 schema 对象、超限、保存失败无派发、旧编辑器 marker 重放，以及子进程 commit 后直接 exit 的恢复。子进程辅助用例计入执行次数，不另称独立验收场景。 |
| 宿主适配与 session | 新增 5 + 5 项；真实 ProjectCreate 确认、原回执重开、丢 prepare 回包、确认前退出显示 NotSubmitted、重复点击与错绑定零业务效果。 |
| GitHub adapter | 新增 13 项，与既有 reducer 13 项联测通过；覆盖缺页、身份/SHA、非成功结论、缺 workflow、缺 tested-subject、TestMerge 和旧 attempt。 |
| 全 workspace / all-targets 严格 Clippy | `-D warnings`，exit 0。 |
| Android Rust 两架构检查 | `muyon-android-ffi` 的 aarch64-linux-android 与 x86_64-linux-android，exit 0；这是 Rust 编译检查，不是 APK/设备执行。 |
| 变更 Rust 文件格式与 diff 空白 | 均 exit 0。 |
| 真实 GitHub 只读响应探测 | 实际读取 PR108、完整 Actions 分页并再次读取 PR；新 adapter 成功解析 head `cb982e642496bae855c4bb10b71f8758a2843d60`。未提供 checkout 证明，结果正确为 **Unknown / checks=0**。该探测使用现有 gh 只读访问，不是产品 OAuth/WebHook 接通。 |

本地原始输出位于 `/private/tmp/muyon-production-gaps-tests-final.log`、`/private/tmp/muyon-production-gaps-clippy.log`、`/private/tmp/muyon-production-gaps-android-check.log`。它们是本机工作证据，不保证跨机器持久保存。候选 CI 状态需另查，不能用本地结果冒充 hosted CI。

独立 core 代码复核、宿主组合复核及架构审查见 [REVIEW.md](REVIEW.md)。发现并修复了历史 marker 回执重复放行和先执行后校验绑定两个问题；最终架构结论为 WATCH，本切片无剩余必修阻断，整体产品门槛仍保留。

## 仍不能关闭的交付门槛

| 事项 | 本轮后状态 / 下一项依赖 |
| --- | --- |
| PR108 / 整套 UI | PR108 仍为 Draft。两项既有 PR workflow success、无 GitHub review submission，均不构成视觉认可。完整生产页面、TalkBack、200% 字体、滚动与键盘返回验收仍未完成；本轮未修改该 PR。 |
| 开发管理生产链路 | 本轮完成的是 **Rust 宿主服务与真实 owner 的集成**。DevelopmentSession 尚未导出 UniFFI、接入 Android Service/UI 或模型聊天。真实宿主仍须从可信状态提供 account/scope generation、切换时销毁 session、仅在可见审核回调确认。不得报“插件端到端已接通”。 |
| 仓库连接器 | 新增 provider 格式适配且真实只读探测成功；产品 OAuth token 生命周期、WebHook 验签/重放、持久同步与实际 checkout 证明生产者仍未实现/验收。实际网络/授权/刷新 owner 仍是前置依赖。 |
| Skill / Connector 执行 | 仍需具名 Operation、可信连接/授权代次、原执行 owner 与取消排空。不能把任意 Skill/Connector JSON 塞进 ProjectCreate；本轮 adapter 没有放开这些门槛。 |
| Reader / FD | 仍缺受控文档身份/epoch/session、只读可 seek FD 桥与实际 Reader 入口。已有附件 Base64 分块读取不替代 FD 租约；本轮未改该链路。 |
| Android 真机 | 已在可用权限环境实际执行 adb 设备枚举，列表为空。本轮无法取得真机/instrumentation/PDF renderer 运行结果；两架构编译不代替它们。 |
| 真实模型 | 本轮未发真实模型请求，也未重启此前停止的 canary。模型聊天端到端仍未验收。 |

下一依赖顺序：可信宿主 account/scope 生命周期与 Service/API 接线 → 开发管理页面/模型到 DraftPatch 的来源绑定 → 原审核动作实际入口 → 产品 OAuth/WebHook 与来源证明 → Skill/Connector 具名执行契约、Reader/FD → 真机与完整视觉验收。后续工作应复用本轮候选，不能重新实现这些已验证的底层切片。

## 官方响应语义依据

- [GitHub PR REST](https://docs.github.com/en/rest/pulls/pulls?apiVersion=2026-03-10#get-a-pull-request)：closed 与 merged、测试 merge SHA 与实际 merge SHA 的区分。
- [Actions workflow runs](https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2026-03-10)：workflow/run/attempt 与 head metadata；这些 metadata 不单独证明实际 checkout 对象。
- [GitHub REST 分页](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api)：保留 Link 并跟随 next，不能用短数组推断完整。
