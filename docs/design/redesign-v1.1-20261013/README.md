# Muyon v1.1 两册设计审查包

本包供 Claude 只读审查架构改造方案和逐页设计手册，产出独立中文审查报告及待决定短清单。只发布文档；不代表改造已实施或最新代码已经审计。不直接联系 Claude。

- [Claude 审查交接与输出要求](CLAUDE-REVIEW-HANDOFF.md)
- [文件校验与发布边界](VERIFICATION.md)
- [SHA-256 清单](SHA256SUMS)
- 第一册：[原始 Markdown](Muyon-Redesign-Plan-v1.1-2026-10-13.md) · [原始 DOCX](Muyon-Redesign-Plan-v1.1-2026-10-13.docx) · [DOCX 浏览副本 HTML](Muyon-Redesign-Plan-v1.1-2026-10-13.preview.html)
- 第二册：[原始 Markdown](Muyon-Page-Design-Handbook-v1.1-2026-10-13.md) · [原始 DOCX](Muyon-Page-Design-Handbook-v1.1-2026-10-13.docx) · [DOCX 浏览副本 HTML](Muyon-Page-Design-Handbook-v1.1-2026-10-13.preview.html)

## 固定版本

设计代码基线：`01e56cc2d729dab70e1b1def05c3aa93b28f421a`。发布前于 2026-10-13T12:27:26Z 通过 `git ls-remote` 读到的 develop 完整 SHA 也是 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`，本次观察二者相同。它们仍是两个独立证据角色；将来的 develop 不得替换设计基线。审查本版本设计后，另列基线至审查时新快照的变化及影响。

[固定代码树](https://github.com/mightyoung/Muyon/tree/01e56cc2d729dab70e1b1def05c3aa93b28f421a)。文档发布分支为 `task/redesign-v11-claude-review-20261013`，由该基线独立建立；固定文档提交链接以发布回执提供的完整 SHA 为准。

## 原件与阅读方式

四份原件从指定 Library ID materialize 至本执行环境，确认存在、可读后按字节复制，未改正文、文件名或 DOCX 内容。下面的 hash 同时写入交接文档，避免换版后沿用旧审查结论。

| 原件 | 字节数 | SHA-256 | Library ID |
| --- | ---: | --- | --- |
| [Muyon-Redesign-Plan-v1.1-2026-10-13.docx](Muyon-Redesign-Plan-v1.1-2026-10-13.docx) | 305860 | `dc24f4e976b56cbd2e8439d2537f2b095700209caf5536f2773644e924239535` | `libfile_827e9f3423708191b74aa6898ae20478` |
| [Muyon-Redesign-Plan-v1.1-2026-10-13.md](Muyon-Redesign-Plan-v1.1-2026-10-13.md) | 183432 | `e1686147b91943bec5600c52017f81556073b2675db9c89ab17041bf929d9ef1` | `libfile_39e26060d5948191a6163a3937fc6b67` |
| [Muyon-Page-Design-Handbook-v1.1-2026-10-13.docx](Muyon-Page-Design-Handbook-v1.1-2026-10-13.docx) | 1945698 | `726bab89eac030ded1ac90985649df47183c5561e2d5dec34c65f93da4d718e6` | `libfile_3aae070590b88191bfcf18622888510d` |
| [Muyon-Page-Design-Handbook-v1.1-2026-10-13.md](Muyon-Page-Design-Handbook-v1.1-2026-10-13.md) | 125629 | `6e8ec428cdd9ad4d0893593b843d699bf7cf4f00cde7ee0dfda88fb94e4c9a01` | `libfile_0a37dbba29588191b14f0552cb386ab2` |

委托输入标注第一册 63 页、第二册 49 页，第二册 29 个页面规格、10 图。本次核对到 29 个规格标题和第二册 DOCX 的 10 个内嵌媒体文件；没有用 Word/LibreOffice 重新分页，63/49 页只作为输入页数，不能称本次渲染确认。DOCX 自带 Pages 元数据为 1，不能用于证实实际页数。引用请优先使用章节、页面编号及 Markdown 行号，再补实际阅读器中的页码。

两份 `.preview.html` 是由 DOCX 用 Pandoc 生成的补充浏览副本，嵌入全部媒体，可下载后在浏览器打开。它们不替代原件，不保留 Word 分页，转换可能改变版式。GitHub 原始 HTML 页面通常显示源码，需下载本地打开。图像和完整排版以原 DOCX 为权威；Markdown 的 ASCII 线框也保留原样。没有上传任何竞品原 APK 或外部附件。

原件中的官方和代码链接是原作者证据入口，本次仅验证格式、相对文件引用和固定基线源码目标，不重新确认全部外部网页内容。
