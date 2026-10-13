# v1.2 文件校验与发布边界

校验日期：2026-10-13 UTC。本清单验证文档交付，不是产品测试、模型实验、动态 APK 分析或最新代码审计。

## 原件与保留范围

四个指定 Library ID 已按当前 Library materialize 流程成功下载到本执行环境，确认存在、非空、可读，按完整字节复制到本目录。正文、文件名和 DOCX 内容保持原字节。身份、字节数和 SHA-256 见 [README](README.md) 和 [复审交接](CLAUDE-REREVIEW-HANDOFF.md)。第一册 MD 的 `cef499d4d3b98e087ce8c50a0e3cee02e638815138ca390036a4b6f1ffb91308`、DOCX 的 `e71386564524352f57ce5fdc972d5c2b4665ee33a876ff86b888098df4bdde2b` 与委托预期一致。

本次只新增 `docs/design/redesign-v1.2-20261013/`。v1.1 目录逐文件核对原 `91dea2e66c340fe55c06421abdc9e3549fea1554` 的 Git blob，不修改文件、不改写原提交。原有分支远端 head 发布前仍为该提交。

## 交付检查

- 四原件本地下载和发布副本按完整字节/hash 比较一致；两 MD UTF-8 可读。
- 两 DOCX ZIP CRC 完整、文档 XML 可解析、内嵌媒体逐张解码有效：第一册 1 个，第二册 15 个。
- 第二册静态核对 29 个主页面、9 个子页面标题与 F01–F15 十五组线框。委托输入页数 79/71 未用 Word/LibreOffice 重新分页认证，不以 DOCX 的 Pages 缓存元数据证明实际页数。
- 原件文本（MD 与 DOCX 段落/表格）检查私钥、GitHub token、AWS key、模型密钥和带引号的凭据赋值模式，未命中。有限检查不保证绝对无秘密；未增加其他私人附件或竞品 APK。
- 两 DOCX 经 Pandoc 转为声明过的自包含 HTML 浏览副本，媒体以内嵌形式保存；在本地 HTTP 服务下用 Chromium 实际打开，所有图片解码完成、正文和标题存在、无页面脚本错误，首屏截图已查看。截图仅内部检查，未发布。
- 新目录 Markdown 相对链接核对实际目标；原件固定 Git SHA 源码/研究链接核对所指 Git 对象文件存在与引用行号有效。该检查不是全量重新审计代码或重新核实全部官网内容。
- README、复审交接、校验说明和两原 MD 经 Pandoc 渲染检查；原 MD 无本地图片引用需要改写，ASCII 线框保留原样。
- `SHA256SUMS` 覆盖四原件、两浏览副本、三份说明文档，不包含清单自身；提交前执行 `sha256sum -c SHA256SUMS`。
- 检查 Git diff 仅新增新目录、v1.1 无差异；普通非强制 push 发布后用 `git ls-remote` 读回完整文档提交 SHA。最终发布及 exact-SHA CI 状态由交付回执提供，不在该提交中循环写入其自身 SHA。

## 三个版本与研究边界

设计基线仍为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`。发布准备 develop 也是该 SHA，不构成最新版全量审计。

PR69 固定证据 SHA 为 `3c9ac395ac8424e9e43b58381fb5001bd1f30821`，准备阶段 API 返回 OPEN、mergedAt=null，未合并。它不能替代设计代码基线。PR69 旧 SUMMARY 中过时“已决定”不覆盖本次 v1.2 最新决定。

正式评审原报告未作为本任务额外文件 materialize；交接要求 Claude 使用其原报告复核，无法取得时说明只能依据第一册 §12 转述审阅。竞品研究仍是静态线索，无动态验证；本地认领/去重、事件重放和幂等不是外部 exactly-once 证明。

未运行 Dart/Flutter/Rust/Electron/Android 产品测试、模型或真机实验，未部署、合并或修改 main/develop。若 GitHub 自动触发 CI，只读记录该文档提交的实际状态，不手动重跑或将未运行报为通过。

## 阅读限制与复核

HTML 为 DOCX 转换副本，不保留 Word 分页或完整版式，GitHub 通常显示源码，需下载后在浏览器阅读；完整图像和排版以原 DOCX 为权威。引用优先用原 MD 行号、章节和页面编号。

在本目录执行：

```sh
sha256sum -c SHA256SUMS
```
