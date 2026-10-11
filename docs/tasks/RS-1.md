# RS-1：科研工作台对齐 research-skill v6.8

执行：Codex。派发：leader A，2026-10-11。集成：Leader B。基线：最新 develop；分支 `task/rs-1-research-skill-v68`。

## 依据
用户决定以 [research-skill](https://github.com/mightyoung/research-skill) 最新版 v6.8（2026-10-03，`UPSTREAM.json` `local_schema_version: 2`）为准（ADR-0001 2026-10-11 晚 CR-17 第 3 条，在 `task/decisions-20261011d`）。Muyon 现按 v6.5 识别 skill 布局：`packages/research_module/lib/src/core/research_skill.dart:7-19` 的 `skillKinds` 不含 v6.8 新增的 `assertions`，`exchange.dart:395` 导入、`research_skill.dart:223,262,269` 的 `[kind/id@rev]` 引用解析、`workbench_app.dart:765` 都用这张表。
v6.6–v6.8 变化（evidence schema 仍为 2）：v6.6 searches 可选 `intent`、opportunities 可选 `decisive_neighbors`；v6.7 `critical_unknown` 条目可为 `{paper:{id,rev},gap}`；v6.8 新增 `assertions` 日志（研究者自己的主张，不挂论文；`assertion_state` untested/supported/refuted/inconclusive/withdrawn；`evidence:[{kind,id,rev,role}]`；可选 `opportunity_id`），交付物可引用 `[assertions/id@rev]`；旧项目缺该日志不报错，新初始化建空文件。

## 要做（只读识别与展示层面；不新增写回、不导出 assertions）
1. `skillKinds` 加入 `assertions`；导入 v6.8 项目时 `research/assertions.jsonl` 按其它可选日志一样读入，旧项目缺该文件不报错。
2. `[assertions/id@rev]` 引用能解析、能在工作台按现有引用方式展示；无效 / 陈旧引用的处理与其它 kind 一致。
3. 新可选字段（`intent`、`decisive_neighbors`、结构化 `critical_unknown`）读入时不报错、不丢失原始行（只需保留原始 JSON，不要求新 UI）。
4. 文件头注释与 `docs/research-skill-integration.md`（若存在）把 v6.5 改为 v6.8，并说明 assertions 只读。
5. 不改 claim 草稿格式（v6.8 claims V2 契约未变）；不改 V1 / V2 判定逻辑（仍以 `schema_version == 2` 判 `research-skill-v2`）。

## 测试先行
用手写合成夹具（结构对照 v6.8 `examples/v2-case`，不复制上游文件）：含 assertions 的 v6.8 项目可导入、assertions 行数正确；`[assertions/a1@1]` 引用解析成功；缺 assertions.jsonl 的 v6.5 项目照旧导入；含 `intent` / `decisive_neighbors` / 结构化 `critical_unknown` 的行不报错且原始 JSON 保留。

## 变异（必须做）
从 `skillKinds` 去掉 `assertions`；导入时丢弃未知字段。测试必须失败。

## 约束
strict analyze 零 info；research_module 与 `apps/muyon` 全量；不提交平台文件；不合 develop。

## 回报（固定 6 行）
1. RED 提交哈希与失败第一行　2. 实现提交哈希（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与两包全量（pass/skip/fail）　6. 未做或有疑问
