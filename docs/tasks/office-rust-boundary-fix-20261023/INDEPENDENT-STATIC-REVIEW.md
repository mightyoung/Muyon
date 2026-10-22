# Rust Office 边界独立静态核验

2026-10-23。工作树 `/workspace/office-rust-boundary-fix`；核验时 HEAD 为 `796cdfe7cb3d79d630056239724af78128094fee`，生产源码未改。本报告仅基于静态源码，**不是已运行的 RED/GREEN，也不证明修复完成**。

## 确认的问题

1. **P2：inline XLSX phonetic hints 混入预览正文。** `crates/muyon-office/src/text.rs:115–136` 的 `sheet_text` 遍历整个 cell 后代，遇到 Spreadsheet namespace 的任意 `t` 就追加文字（130–132）；未跟踪 `S:rPh` 祖先。因此 `inlineStr/is` 中普通 `t` 为 `東京`、`rPh/t` 为 `とうきょう`、后续 rich-run `t` 为 `駅` 时，按当前控制流会产生 `東京とうきょう駅`，而应只保留 `東京駅`。相对地，`shared_strings` 在 67、80–84 行已有 phonetic depth 过滤；只覆盖 shared-string 用例不会发现 inline 路径缺口。此结论未由实际 Rust 执行验证。

2. **P2：编辑/直接 rewrite 输出未遵守解压尺寸边界。** `edit.rs:52–53` 在无长度检查下创建 escaped replacement 和 patched part，再进入公开 `Package::rewrite_part`；后者 `package.rs:163–198` 写入任意 `new_content`、完成 ZIP 后只检查压缩后 `candidate.len() <= max_archive`，未检查新 part 的 `max_part`，也未核对替换后总解压量 `max_expanded`。高度重复的超长正文可保持压缩输出很小，却使 receipt 内候选超出同一 Limits 的读取/重开边界。`read_part` 在 `package.rs:152` 才执行 `max_part`；`Package::open` 在 112–117 行执行总 `max_expanded`。因此候选可能返回成功后不能按同一限制读取目标 part 或重新打开。当前写入、escape、splice、ZIP 缓冲分配还先于最终 archive-size 检查；不能把事后拒绝说成分配前内存上限。

同源路径：`set_xlsx_numeric_cell` 也在 `edit.rs:125–126` 无尺寸检查地 splice/rewrite。其 plain-number 检查（186–201）没有字符串长度上限；大量前导零后接 `1` 或 `1.` 后大量零是建议的有限数长字符串候选，但具体 Rust `parse::<f64>()` 行为必须在实际回归中确认。公开 `rewrite_part` 本身可绕过两个高层编辑入口的任何局部检查，故共用输出边界不能仅由 DOCX 调用点承担。

## 建议作者原样执行的 Rust 回归边界

- inlineStr：基础文字 + `S:rPh/S:t` + 后续富文本 run；断言完整预览值，无读音，后续正文和下一 cell 不丢失。补 sharedStrings 的同结构对照、空 `rPh`、不同 namespace 同 local-name 的对照；若覆盖嵌套防御，明确是 tokenizer 接受的非 schema 校验输入。
- 用较小自定义 Limits 构造合法 source，分别测 **新 part 恰好 max_part 与 +1**；测试 ASCII、多字节 UTF-8，以及 `&`/`<` XML escaping 后字节膨胀。不要只按 replacement 字符数计算 part 尺寸；需包含原 part 未改部分。
- 用高度可压缩 replacement 验证不能靠小 ZIP 绕过解压上限。单独设置 **所有 part 合计恰好 max_expanded 与 +1**，并把其他 part 纳入总量；保持 max_part 足够大以隔离总量分支。
- DOCX、XLSX 数值编辑及 **直接 `rewrite_part`** 都应有上述拒绝用例。XLSX 先用 `max_part` 略高于合法原 worksheet、较短但足以越界的有限数 replacement，避免不必要的大内存输入。
- 成功对照：同一 Limits 下重开候选、读取修改 part，并核验原 source hash 不变、仅声明范围变化、其他成员原始压缩字节和解压字节均不变、未知 part 不丢失、公式/缓存不被宣称已重算。
- `max_archive` 也保留边界用例。若需要证明分配前上限，必须结合实现检查与适当测试；仅断言返回 Err 不足以证明过程中没有超额分配。
- `max_text` 当前用于提取（text.rs:51、75），并非现有明确的统一编辑输入上限。请先保持当前公开 API/语义，勿仅为让测试通过新增限制接口或把提取失败等同于已规定的编辑拒绝。

## 执行状态与限制

只读命令：`git status --short`、`git rev-parse HEAD`、`rg`、`nl`、`sed`、读取 Cargo.toml，以及 `command -v cargo rustc gradle sdkmanager`。最后一条 exit 1、无输出，当前 PATH 中四项均未找到；未执行 cargo、rustc、Gradle 或 Android 测试，未安装工具、未变更权限、未寻找替代执行环境、未实现 Python 引擎。Android SDK 缺失按父任务已知环境约束记录，本次未另行扫描机器确认。

已完成：两项问题和同源 XLSX/直接 rewrite 调用链静态核验、建议回归边界。阻塞：真实 Rust 回归执行因当前环境缺少工具链而 **NOT_RUN**，不是测试断言失败，也不是自动审批拒绝。生产代码修改、提交、推送均未发生。建议保留准备中的回归原样，待授权且工具链可用的环境实际执行后，再据真实 RED 进行修复。
