# C6-REDO：模型披露不透明引用（重做）

执行：Codex（路线 2）。派发：leader A，2026-10-12。集成：leader A。基线：develop `ab5506c3`；分支 `task/c6-opaque-reference-redo-20261012`。
背景：Leader B 交接（2026-10-12）。C6 最新两枚补修 `5436f68c`、`7df93d72` 只在已停的云端工作区，用户决定**当作丢失、重做**。远端旧候选 `task/model-disclosure-opaque-reference-20261012` @ `e6579861`（CI 38208251598 失败：apps/muyon analyze、host 70 失败、coverage 分母漂移）只作**参考**，不得整枝合入。相关 PR #65（`82c2c20d`，披露 canary：20 例 9 通过 11 RED）的 RED 测试是验收依据。

## 必须达成（交接第 7 节「模型披露与 C6 引用」）
1. 整行业务 `contentDigest` 不发给模型，改用宿主映射的不透明引用；引用绑定 task、scope、snapshot，拒绝伪造、跨任务、过期引用；内部摘要完整性保留。固定盐 / 公开盐不算脱敏；不得改全局持久对象身份来凑测试。
2. 自由文本 `notes`、`award_note`、`requirement` 默认不出站；本机显示偏好不等于披露许可；未知字段默认遮盖。契约层 `notDisclosed` 残值、`sources.originalText`、`currentView`、`initialState` 走统一门禁。
3. 覆盖每条生产出站路径的正例与反例：真实 prompt 组装、manual / raw tool body、history / tool、global bridge、`agent_resume`、撤权、授权卡；走不到的路径标「未测」。

## 做法
先把 PR #65 的 canary 测试带进本分支（cherry-pick `82c2c20d` 的测试部分），确认 RED；再参考 `e6579861` 的实现逐项实现，每项先 RED 后 GREEN。e6579861 的 70 个 host 失败要逐类说明是否由本实现引起，本分支不得带入。覆盖率分母变化写进回报，由 leader A 复核基线，不自行改 baseline。

## 变异（必须做）
引用不绑定 task；过期引用不拒绝；`notes` 漏出 prompt；`agent_resume` 路径绕过门禁。都必须被测试抓到。

## 回报（固定 6 行）
1. RED 提交与失败第一行（含 PR #65 canary 的 RED 数）　2. 实现提交（远端与本地一致）　3. 改动文件与行数；每条出站路径「已测 / 未测」清单　4. 变异结果　5. analyze 与 `apps/muyon`、`muyon_module_api` 全量（pass/skip/fail 及分类）与精确 SHA CI　6. 未做或有疑问
