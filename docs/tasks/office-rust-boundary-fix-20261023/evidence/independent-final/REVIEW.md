# Rust Office 边界修复独立审查

结论：**固定待提交源码快照在本次范围内未发现未解决的 Important 问题，可以接受这批 Rust 边界修复。** 这是 Rust 主机源码和回归审查，不是 Android/设备、视觉保真、公式重算或完整 OOXML 安全认证。

## 对象与固定身份

- 基线：`796cdfe7cb3d79d630056239724af78128094fee`。
- 审查工作树：`/workspace/office-rust-boundary-review`。待提交差异为 `src/package.rs`、`src/text.rs`、`src/edit.rs` 和新增 `tests/boundaries.rs`，均在 `crates/muyon-office/` 下。
- 四文件 SHA-256 与作者 `review-source.sha256` 完全一致，独立保存于本目录 `source.sha256`；运行结束再次校验四项全部 OK，见 `source-after.log`。本报告通过这些哈希识别待提交版本，不将基线 SHA 误称为修复提交 SHA。
- 复用已授权恢复的 rustc/cargo 1.93.1、Clippy 0.1.93；独立设置 `CARGO_TARGET_DIR=/workspace/office-rust-boundary-fix-tools/target-review`。现有 host SQLite 链接设置由任务 env.sh 提供。未安装任何软件或变更系统配置。

## 独立真实执行

准确命令及环境见 `commands.txt`，全部使用 `--offline --locked` 和显式 `--manifest-path crates/Cargo.toml`：

| 检查 | 结果 | 原始日志 |
|---|---|---|
| muyon-office boundaries + fidelity | 12 + 12 PASS，0 failed/ignored，exit 0 | office-tests.log |
| workspace/all-targets Clippy，`-D warnings` | PASS，exit 0 | clippy.log |
| workspace 全量 cargo test | 601 PASS，0 failed/ignored，36 个结果组（含空 doc-test 组），exit 0 | workspace-tests.log |
| 运行后四文件 hash | 全部 OK | source-after.log |

首次从仓库根调用 cargo 未指定 manifest，因根目录没有 Cargo.toml 在编译前失败；原日志保留在 `office-tests-wrong-root.log`。随后指定正确 manifest 成功。该调用错误**不是行为 RED**。本审查未独立重跑作者的基线 RED；上述通过结果来自固定修复快照的实际 Rust 执行。

## 源码核验

1. **inline rPh 修复符合 cell 作用域与 namespace 边界。** `text.rs:137` 的 `sheet_text` 在每个 Spreadsheet cell 内初始化 phonetic depth，仅在 Spreadsheet namespace 的非空 rPh 起止标签增减，过滤其 t/v 子节点；empty rPh 不泄漏状态。后续富文本和下一 cell 保留，foreign namespace 同名 rPh 不误触过滤。回归覆盖 default/prefixed namespace、inline/shared 对照、后续富文本、empty rPh、foreign t/rPh 及下一 cell。

2. **高层编辑在逃逸/splice 前进行预算检查。** `edit.rs` 的 DOCX/XLSX 入口先核对调用输入字节预算；DOCX 精确统计 &/< /> 的 XML 逃逸后长度，再通过 checked `splice_size` 和 `check_rewrite_size` 检查新 part 与 expanded delta，之后才分配逃逸/拼接缓冲。XLSX 同样在拼接前经过共用预算。`package.rs:244` 校验 splice range/算术，`package.rs:252` 用 fallible reserve 创建缓冲。没有新增公开 limits/API。

3. **直接 rewrite 不能绕过输出预算。** `package.rs:164` 先检查目标新内容 max_part 和实际 expanded delta；原始实际解压尺寸在 open 时记录，包含带 slash 的 directory-named payload，不再因 is_dir 跳过。`package.rs:167` 在压缩前使用替换 view 执行同一 reader 的 XML/text/sections 预算，包含其他 sections、共享字符串及每次 cell 引用、空正文 placeholder。`text.rs:115` 的 append helper 在追加前检查输出字节余量。

4. **archive 输出在写入前受限。** `package.rs:269` 的 BoundedArchive 在 reserve/write 前用 checked position+length 检查 max_archive，覆盖 headers、替换内容压缩输出、raw-copy 和最终 central directory；错误映射为 LimitExceeded，不返回 receipt。已知 ZipWriter drop 在拒绝后打印 `failed to finalize archive ... FileTooLarge`，独立测试中确实出现；测试仍通过，且拒绝路径未返回 candidate。不能把该 stderr 单独当作回归成功或 RED 的证据。

5. **原件与未知 part 保留。** `package.rs:193` 沿用 untouched member raw_copy；fidelity 用例核对成员顺序、原始压缩字节、解压字节和单一 splice 范围，覆盖 opaque part、评论/书签/header、日期系统/隐藏表/公式缓存。边界拒绝用例检查 source bytes/hash/part 不变，并在失败后再次进行合法编辑、重开和读取，确认没有残留部分状态。

## 剩余限制

- Limits 是逻辑字节/结构预算；本次没有分配器或 RSS profiling，不声称总进程内存严格等于某个单一 limit。XML tokens、源缓冲及压缩器仍有各自开销。
- `Package::open` 不对所有既有 opaque part 强制 max_part；read_part 保持其既有 max_part 规则，所有目标新 part 必须符合 max_part。本次不将这一明确范围选择误报为修复缺失。
- rewrite 的 reader view 检查使编辑在其他已有 reader 预算不满足时保守拒绝；不是语义、schema 或可视化保真验证。直接 rewrite 仍是低层 API，changed_range 是调用方提供的声明，不能代替高层授权/语义 oracle。
- 未运行 Android/Gradle/SDK/设备和 bindings 生成检查，也未接受 Android SDK 协议。作者另报的 bindings 检查不计入本独立执行结果。

审查期间未改生产源码/测试、未提交或推送、未安装软件、未接受协议、未调用网络/模型/设备。只生成独立 target-review 编译产物和本 `/tmp/office-rust-final-review-independent/` 下证据。
