# GB-5 写卡所需的模块契约扩展设计（grokbot，Opus 5.5）

分支 `review/gb-5-write-card-contract` · 基线 develop（取最新）· 执行：grokbot（只读代码与写文档；不运行 Flutter）· 审查：leader A

## 背景
[CR-2 本体写卡设计](../design/ontology-write-cards-2026-10-11.md) 第 1、4、5 节指出现有契约缺几样东西，写卡才能「插件不更新也能随本体演进」：
1. 插件按「对象类型 × 操作」声明可写字段、创建是否可用、校验入口、关系写入约束（现 `BusinessModuleV2` 没有通用表单校验；`inquiry_record_tools.dart` 的参数模式是跨类型字段并集）；
2. 提交前可调用的完整校验，返回规范化候选、稳定错误码 + 字段路径、表单级错误（现 `validatePayload` 是 fail-fast 的 `FormatException`）；
3. 结构化冲突（工具层仍 `failed`，受信错误数据带错误码、字段路径、当前版本），不靠解析中文摘要；
4. 宿主受控的只读业务回执查核（恢复时判断 `operation_id` 是否已执行）。
CR-2 的 D1～D11 用户尚未定，本设计按 CR-2 的推荐假设，假设处标明。

## 只做这些
产出 `docs/reviews/2026-10-11-write-card-contract.md`：
1. 对上面 4 项，各给一个最小的 `packages/muyon_module_api` 接口草案（Dart 类型签名伪代码即可）：放在哪个文件、哪些是可选能力、旧模块不实现时宿主怎么退路。
2. 询价模块实现这些接口需要改哪些文件、大致多少改动，复用现有 `ontology`、`_allowedFields`、`validatePayload`、`reg4c` 回执的哪些部分；`validatePayload` 改成可收集多条错误的最小办法（或说明为什么首版不改）。
3. 科研模块的对应关系：哪些操作能套用、哪些不适用（科研没有统一 save/版本，见 GB-2）。
4. 与 ADR-0004 的关系：是否需要新 ADR 或在 ADR-0004 加修订；列出需要用户拍板的点。
5. 拆成可以独立实现与审查的任务片（每片：范围、依赖、验收的拒绝路径测试）。

## 不做
不改代码；不运行 Flutter；推测标「推测」；不确定写「未能静态确认」。

## 回报
提交哈希；任务片清单；需要用户拍板的点。
