# Muyon v1.3.1：合同复审与 Android Design 双入口

本包按北京时间 2026-10-14 命名，追加在原文档分支，只发布冻结 Markdown、迁移追踪和必要图示。两种任务分别从以下入口开始，不把视觉设计任务当作代码/合同复审结论。

## Claude：代码、合同与目标文档采纳复审

- [Claude v1.3.1 定向复审交接](Muyon-v1.3.1-Claude-Review-Handoff.md)
- [第一册：架构与详细改造方案](Muyon-Redesign-Plan-v1.3.1-2026-10-14.md)
- [第二册：逐页设计手册](Muyon-Page-Design-Handbook-v1.3.1-2026-10-14.md)
- [旧决定与迁移追踪](MIGRATION-TRACE-v1.3.1-2026-10-14.md)

目标是定向核对 V13-B01/B02、I01–I06、S01–S05 的修订，区分 DOCS-G0、实施门禁与已有风险；并判断旧任务/ADR如何切换。本次不修改生效ADR或任务根入口，MIGRATION-TRACE只是供审查的追踪文档。

## Claude Design：Android 设计需求

- [Android 手机/平板设计需求与交付简报](Muyon-Android-Claude-Design-Brief-2026-10-14.md)
- [Android 设计参考矩阵](Muyon-Android-Design-Reference-Matrix-2026-10-14.md)
- [15幅参考图](figures/)，对应第二册 F01–F15。图示从旧 v1.3 固定提交原字节复制，仅作为参考；行为与新增决定以 v1.3.1 正文为准，不宣称这些图已经按新增决定重画。

本任务只发布需求，不直接调用 Claude 或 Claude Design，不开始新界面实现、模型实验或部署。后续设计应遵守冻结需求书的已有/新增/待决标识与数据边界。

## 版本与证据边界

产品代码基线仍为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`；发布准备远端 develop 同为该 SHA。追加前文档提交为 `e014b097be94b48a6744c5d5df41a764918b0afa`。新文档完整 SHA 由发布回执固定，两个入口和六份MD都须从同一固定提交读取。最新 develop 的变化影响另列，不能静默换基线。

**旧 CI 失败未修复：** [v1.3 的 CI 38424976446](https://github.com/mightyoung/Muyon/actions/runs/38424976446) 为 completed/failure，失败在 supplier_core 的 deadline 测试；本任务没有改该代码、重跑旧CI或验证根因。新提交CI另按精确 SHA 只读跟踪。文档采纳判断不能代替仓库可合并状态。

**52项设计验收均未执行：** 原11记忆＋14恢复＋15组合例与本版新增12例是验收设计，不是52项产品测试通过。已有静态定向B01/B02及I修订核证只代表其覆盖的文档检查，不能冒称Claude完整独立结论或工程验证。未运行产品、真实模型、真机或故障实验。

## 历史：c7bb 首次发布时两份引用报告未随包提供

冻结交接第29行引用下列相对文件，但本次授权 Library 包只有六份MD，未含这两报告：

- `Muyon-v1.3.1-Disclosure-Targeted-Recheck-2026-10-14.md`
- `Muyon-v1.3.1-Review-Verification-Migration.md`

因此这两个原链接在 c7bb 首次发布时不可用（本次已补齐，见下文）。保留六MD原字节，不伪造报告或替换证据；其“静态定向核证”的完整细节不能从本包直接复读。Claude 可继续检查两册、trace和代码，但报告必须注明缺失，不能声称已读取两报告。补入原报告需后续单独提供真实原件。

## 原件与校验

来源 Library 包：`libfile_9e8d5e94aecc8191bee876c63cc0d590`，`Muyon-v1.3.1-MD-Review-Package-2026-10-14.zip`，276532字节，SHA-256 `dadbb4ab0e58359749e89dc305938f767ac74cd3cd9a2b1e6d8f4e13213d7cd1`。该包由本executor自行物化并校验；ZIP严格只有六个MD根文件，未将父工作区路径当传输证明。

| 冻结原件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| [MIGRATION-TRACE-v1.3.1-2026-10-14.md](MIGRATION-TRACE-v1.3.1-2026-10-14.md) | 14015 | `46601ad98c5a8c86f94041257cb01568476dc18e3767e012070a8467ca20656b` |
| [Muyon-Android-Claude-Design-Brief-2026-10-14.md](Muyon-Android-Claude-Design-Brief-2026-10-14.md) | 96806 | `c932f9c0da0eb4425413a012e0c4476be426cc5bd5db3919f4d46a7eaea3a18e` |
| [Muyon-Android-Design-Reference-Matrix-2026-10-14.md](Muyon-Android-Design-Reference-Matrix-2026-10-14.md) | 27644 | `9d2cb32968b94ba1fe3dcddd9da1b7346af9d66839780b58d6efef9b5a45c451` |
| [Muyon-Page-Design-Handbook-v1.3.1-2026-10-14.md](Muyon-Page-Design-Handbook-v1.3.1-2026-10-14.md) | 236793 | `35af88e25388fe934d860744cad83b041dee8afb6ca9e47c7c2af2c0f3b48cc9` |
| [Muyon-Redesign-Plan-v1.3.1-2026-10-14.md](Muyon-Redesign-Plan-v1.3.1-2026-10-14.md) | 305321 | `0e192e44959b0e6b32cc0518d2411dd7a3a3500d5753ef0a1bb0d6b1cb11c073` |
| [Muyon-v1.3.1-Claude-Review-Handoff.md](Muyon-v1.3.1-Claude-Review-Handoff.md) | 6562 | `9eff751a956c0876f4c87462cbe294c82b18fa5de56f5dd45feef5473b972dde` |

六MD逐字节不变，解包图示与原 `e014b097…` Git blob相同；输入 ZIP 保留在本执行环境，本目录只发布其中六MD，不额外复制ZIP。没有Word或HTML重排副本。

[SHA256SUMS](SHA256SUMS) 覆盖六原件、15图与两份发布说明；[VERIFICATION](VERIFICATION.md) 记录实际检查、上述缺失链接及限制。旧 [v1.1](../redesign-v1.1-20261013/README.md)、[v1.2](../redesign-v1.2-20261013/README.md)、[v1.3](../redesign-v1.3-20261013/README.md) 保留原字节与原提交。未修改产品、生效ADR、任务根入口、main/develop，未合并、强推、清理PR69或部署。

## 本次补件：两份真实定向报告已发布

- [数据披露、记忆与未知效果定向复核](Muyon-v1.3.1-Disclosure-Targeted-Recheck-2026-10-14.md)：4667字节，SHA-256 `d851e7529d1c628d2ad417d4185b8cab1194cbe894e42d5fb63d95e156cb5ee1`
- [迁移与预算定向复核](Muyon-v1.3.1-Review-Verification-Migration.md)：5441字节，SHA-256 `d3ec4f0da0503a2b74d1ee609b0341a2241aaa37dc03e346d4fa0ea7339b9540`

来源为 Library `libfile_612ca7e2d6788191a9b5f95436cc6546` 的 `Muyon-v1.3.1-Targeted-Reviews.zip`（6680字节，SHA-256 `d61918d617ea0d33fbfa41dd2ed4e7228bc23bea4b8e4bb5fed63a6b7b43f4b7`），经本executor物化及安全检查后原字节补入。冻结交接第29行的两个链接现在均有真实目标；原缺件记录保留为首次发布历史。

两报告受检身份与六MD冻结版本一致，结论仅限其定向静态范围，不代表Claude完整采纳决定或工程/CI/产品/真实模型/真机验收。报告中引用的先前旧核查标题只作历史说明，不冒称那些旧附件也已随包发布。

本次补件只新增两报告，并更新README、VERIFICATION和SHA256SUMS；六MD、15图及所有旧版本不改。首次 c7bb 提交CI与本次补件提交CI分别读取精确SHA状态，不把任一旧绿灯当新提交的成功证明；实际终态由交付回执报告。
