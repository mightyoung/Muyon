# Muyon v1.2 两册设计复审包

本包新增发布 v1.2 原件和给 Claude 的定向复审交接，针对正式评审 B1–B3、I1–I10、S1–S7，以及执行摘要和 AUTH-TRACE-02 增量。设计处理表不等于实现修复或测试关闭。只新增本目录文档，保留 v1.1 目录和原提交。

- [Claude 定向复审交接](CLAUDE-REREVIEW-HANDOFF.md)
- [校验和发布边界](VERIFICATION.md) · [SHA-256 清单](SHA256SUMS)
- 第一册：[原始 MD](Muyon-Redesign-Plan-v1.2-2026-10-13.md) · [原始 DOCX](Muyon-Redesign-Plan-v1.2-2026-10-13.docx) · [DOCX 浏览副本](Muyon-Redesign-Plan-v1.2-2026-10-13.preview.html)
- 第二册：[原始 MD](Muyon-Page-Design-Handbook-v1.2-2026-10-13.md) · [原始 DOCX](Muyon-Page-Design-Handbook-v1.2-2026-10-13.docx) · [DOCX 浏览副本](Muyon-Page-Design-Handbook-v1.2-2026-10-13.preview.html)
- [保留的 v1.1 索引](../redesign-v1.1-20261013/README.md) · [原 v1.1 固定提交](https://github.com/mightyoung/Muyon/tree/91dea2e66c340fe55c06421abdc9e3549fea1554/docs/design/redesign-v1.1-20261013)

## 三个版本角色

设计代码基线仍为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`。发布准备远端 develop 读取值也为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`（2026-10-13T14:39:10Z 前后准备阶段），不把这次读取称为全量重新审计。

[PR69](https://github.com/mightyoung/Muyon/pull/69) 的固定证据 head 为 `3c9ac395ac8424e9e43b58381fb5001bd1f30821`，本次读到 OPEN、mergedAt=null。它是未合并的静态研究参考，**不是设计代码基线**，不得用其源码改写基线事实。正式评审的意见由两册处理表引述，本包不额外上传未指定的原报告或竞品 APK。

v1.2 用户最新决定优先于 PR69 旧 SUMMARY 的“已决定”表：全部允许含首次新网站/API，无额外询问；Auto 独立；确定性业务 UI 直 Rust；屏幕读取、临时会话、记忆容量、个人账号限制和其他模式默认仍待决。旧表不能冒认当前授权。

## 原件身份

四份指定 Library 文件本地 materialize 成功后按完整字节复制，未修改正文、文件名或 DOCX 内容。第一册 MD/DOCX SHA-256 与委托给定值一致。

| 原件 | 字节数 | SHA-256 | Library ID |
| --- | ---: | --- | --- |
| [Muyon-Redesign-Plan-v1.2-2026-10-13.docx](Muyon-Redesign-Plan-v1.2-2026-10-13.docx) | 341177 | `e71386564524352f57ce5fdc972d5c2b4665ee33a876ff86b888098df4bdde2b` | `libfile_5e8813b776fc819189fb16495b2bd559` |
| [Muyon-Redesign-Plan-v1.2-2026-10-13.md](Muyon-Redesign-Plan-v1.2-2026-10-13.md) | 240505 | `cef499d4d3b98e087ce8c50a0e3cee02e638815138ca390036a4b6f1ffb91308` | `libfile_dbab674285b48191b1f652ad3ba551ca` |
| [Muyon-Page-Design-Handbook-v1.2-2026-10-13.docx](Muyon-Page-Design-Handbook-v1.2-2026-10-13.docx) | 2927619 | `93aa68f30725757792a795d88e7cd2914f3d4f8f0ff0ed1e4883c4c9a1d1cb11` | `libfile_51864e6e58ac81918d5e3d25839d8edf` |
| [Muyon-Page-Design-Handbook-v1.2-2026-10-13.md](Muyon-Page-Design-Handbook-v1.2-2026-10-13.md) | 175489 | `0c0fa0be8c609f083175c29c15c5f8e9466a6fd0b948539c9e80647bf53a2ce4` | `libfile_257addabe5f48191b126626611cb09d4` |

委托页数为第一册 79、第二册 71；本次不重排 Word 分页，页数只作输入说明。第二册 29 主页面、9 子页面标题和 15 图/内嵌媒体已静态核对。HTML 是有声明的 DOCX 补充浏览副本，嵌入全部媒体，不保留分页；GitHub 通常显示 HTML 源码，下载后在浏览器阅读，完整图与排版以原 DOCX 为权威。
