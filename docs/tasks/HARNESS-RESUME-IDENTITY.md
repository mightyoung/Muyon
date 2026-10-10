# Harness 恢复身份最小补强

基线：远端 develop `3b0adb9e5242dc4a598bf3be71a8252204a9a053`。
分支：`task/harness-resume-identity`；草稿 PR #16；仅供指定合入者审查，不自行合并。

## 短方案

1. 先以手动 / 模型任务的同工具、同 invocationId、不同参数或解析 scope 的真实 prepare 摘要造历史回执，确认恢复错误采纳成功结果；同时覆盖缺失、空白及非字符串摘要。
2. `ToolRegistry.receiptFor` 读取已有 `identity_digest`；恢复只比较历史提案（手动任务 `toolIdentityDigest`，模型步骤 `identityDigest`）与持久回执，不重新 prepare，不查询当前可变注册表身份。
3. 身份无法核对时停在 `waitingConfirmation / resume`，说明原因，不采纳结果、不发审批、不重发副作用。未知写入 / 外传沿用现有暂停及重新授权流程。无回执沿用既有新请求 / 审批语义。
4. 连续性覆盖：成功回执不重跑，回执先落盘而任务状态未落盘，合法历史回执不受当前 scope / 注册表变化影响，步数 / 注入宿主时钟计量的活动时间 / reported token 在重复恢复间持续累计。

## 范围与风险边界

仅改 `agent_resume.dart`、`tool_registry.dart` 和对应恢复测试及本任务证据。无数据库迁移，无消息模型 / 权限体系重写，无 Dream / foundation 记忆变更。

此处摘要是调用在 prepare 时由宿主生成并保存的历史绑定，不是对任意本地数据库篡改的签名或认证。若攻击者同时改写历史提案摘要及回执，两者比较不能证明原参数真实性。不得把内部坏数据夹具写成已证明外部攻击路径。

旧提案缺摘要时：已有回执不能作为成功结果被采纳；安全暂停供人核实，之后仍需新请求和正常授权。没有回执时保留原有行为。

## 验证记录（持续更新）

- 云端未安装 Flutter / Dart；下载项目固定 Flutter 3.47.5 被 HTTP 403 拒绝，未占用 Mac 构建。
- GitHub CLI 当前 GH_TOKEN 无效；已连接 GitHub 工具成功读写，本任务未配置新凭证。
- tests-only red 提交：`8060d815121adae0fbf8252b467e304549b9dfc4`；[Linux CI 38017735820](https://github.com/mightyoung/Muyon/actions/runs/38017735820) 终态 failure。8/8 analyze 通过；host `+1366 ~3 -10`，10 例新增身份测试全部按预期失败（manual 错误 completed，model 错误 model），其余套件通过，`CI SUMMARY: FAILED (test:host)`。
- 独立会话静态复核确认了另一个本范围连续性缺口：已 prepared 模型调用但无回执/仅匹配失败回执时回退 fresh，预算归零。补两例失败测试；后续三个局部守卫保证这类步骤也 carry + completeStep，调用折叠为未执行，不审批、不重跑。
- 原始日志不入库；仅记录命令、终态、失败 / 成功摘要与固定 SHA。
- 用户要求的重要核心改动独立会话与真实 Claude 窄包交叉审查：独立会话已安排；云端无真实 Claude 可调用入口，真实 Claude 结论需另会话补齐，禁止冒充。

## 窄包审查材料

基线到最终提交 diff；`agent_resume.dart`、`tool_registry.dart` 的 ToolReceipt / receiptFor、`agent_dispatch.dart` 的 _planned / _stage / toolProposed、`agent_resume_test.dart`；ADR-0005 §6.5、§8.3；固定提交的 Linux CI。核对身份来源、旧数据、暂停后新授权、成功去重、scope 变更与预算连续性。
