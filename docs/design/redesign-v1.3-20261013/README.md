# Muyon v1.3 Markdown 设计与 Claude 评审包

本包按用户最新决定直接发布冻结 Markdown，供 Claude 从仓库只读评审，不等待 Word。两册 Markdown 是本轮规范正文，交接说明也是冻结原件；没有发布 Word、HTML 浏览副本或其他重排版本。

- [第一册：架构与详细改造方案](Muyon-Redesign-Plan-v1.3-2026-10-13.md)
- [第二册：逐页设计手册](Muyon-Page-Design-Handbook-v1.3-2026-10-13.md)
- [给 Claude 的评审交接](Muyon-v1.3-Claude-Review-Handoff.md)
- [交付校验与验证边界](VERIFICATION.md) · [SHA-256 清单](SHA256SUMS)
- [原始插图 ZIP](Muyon-v1.3-Figures.zip) · [15 幅图目录](figures/)
- [保留的 v1.1](../redesign-v1.1-20261013/README.md) · [保留的 v1.2](../redesign-v1.2-20261013/README.md)

## 固定版本与评审范围

产品代码基线仍为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`，本次发布准备远端 develop 读取值同为该 SHA。发布分支仍为 `task/redesign-v11-claude-review-20261013`，追加前完整 SHA 为 `843bc7911a37f847a0545192b5994af47c3c53ad`。v1.1/v1.2 原文件和原历史提交保留，未改产品、main/develop，未合并或部署。

本次文档提交完整 SHA 由发布回执和固定 Git 链接记录，不在提交内写入自身 SHA。评审必须按同一固定文档提交读取三 MD，另记实际读取的产品代码 SHA；最新 develop 若变化另列影响，不替换既定设计基线。

v1.3 中研究资料的固定引用为 `190ddd88359a4f1a8f21f8d62d9186eb474137e9`，仍是研究证据角色，不是产品代码基线。旧版本中的其他固定引用保留各自历史含义。PR69 历史清理或合并不属于本任务，不是此次评审的前置。

本轮设计、原 11 条记忆验收和 14 条恢复验收、新增 15 条组合反例，以及跨册静态一致性已作**文档层复核**。本发布核对用例编号、页面/子页/图号及相关交接边界；这不是 40 项产品测试通过。未运行产品测试、真实模型或真机实验，未产生 Claude 本轮独立结论；Word 终版排版不作为本次交接前置。

交接要求 Claude 分别判断目标文档采纳、旧任务/ADR 切换、可开始工作及其前置、真正阻断与局部待决。FullAllow/Auto、业务直 Rust 和未定产品选项遵守冻结正文，不从旧竞品摘要冒认用户授权。

## 输入原件身份

四个指定 Library 文件已由本执行环境自行 materialize，确认实际文件存在、可读，核对全部预期字节数和 SHA-256 后按原字节保存。三 MD 未更名或修改正文；第二册保留自包含 diagram 文本，没有改写插图链接。

| 文件 | 字节数 | SHA-256 | Library ID |
| --- | ---: | --- | --- |
| [Muyon-Redesign-Plan-v1.3-2026-10-13.md](Muyon-Redesign-Plan-v1.3-2026-10-13.md) | 273312 | `60b4d43ac0fe0ba022ca4e2fd605d75a6437471edf03eb11b5fbfc30db8b284f` | `libfile_5041d2b1edd8819184b820afa26a60cb` |
| [Muyon-Page-Design-Handbook-v1.3-2026-10-13.md](Muyon-Page-Design-Handbook-v1.3-2026-10-13.md) | 203865 | `1966818e75ac15e38cfcd1845fb740a2f2735b015e3ee52d9334c4f5c62eaf06` | `libfile_90d1936ac5488191acb604f995a31fa7` |
| [Muyon-v1.3-Claude-Review-Handoff.md](Muyon-v1.3-Claude-Review-Handoff.md) | 15702 | `46d492ba1c2d062be93b246407f95698727437c1a09d723fb72e80cb6d5ae1e7` | `libfile_3b2ee82b87b481919e3ac80a17fc824f` |
| [Muyon-v1.3-Figures.zip](Muyon-v1.3-Figures.zip) | 2813145 | `b7f2f468294cc149eda37ed418c489e5347e969409ae1a783ee57753e6bfcf7f` | `libfile_e5a919cb9f5c81919518ab5f07bc2151` |

ZIP 原件也保留。检查压缩包只有 `figures/F01.png` 至 `figures/F15.png`，无多余条目、目录穿越或符号链接后解包；解出的 PNG 与 ZIP 条目逐字节一致，每幅均列入 SHA256SUMS。

## 15 幅图浏览区

图示为设计示意，不代表产品已实现；以第二册对应 F01–F15 章节为行为说明。点击图名或缩略图打开原尺寸 PNG。第二册正文可独立阅读，以下只是补充图示入口。

| 图示 | 图示 | 图示 |
| --- | --- | --- |
| [F01 A01 手机助手对话](figures/F01.png)<br>![F01 缩略图](figures/F01.png) | [F02 W01 桌面工作台总览](figures/F02.png)<br>![F02 缩略图](figures/F02.png) | [F03 R02 桌面 PDF 阅读与可编辑成果](figures/F03.png)<br>![F03 缩略图](figures/F03.png) |
| [F04 R02 R04 手机阅读与批注转证据](figures/F04.png)<br>![F04 缩略图](figures/F04.png) | [F05 Q05 桌面候选比较与证据](figures/F05.png)<br>![F05 缩略图](figures/F05.png) | [F06 Q06 手机价格试算](figures/F06.png)<br>![F06 缩略图](figures/F06.png) |
| [F07 T01 T02 任务活动与分轴结果](figures/F07.png)<br>![F07 缩略图](figures/F07.png) | [F08 T03 手机保存审批](figures/F08.png)<br>![F08 缩略图](figures/F08.png) | [F09 S06 记忆经验与整理](figures/F09.png)<br>![F09 缩略图](figures/F09.png) |
| [F10 S07 身份编辑与权限分离](figures/F10.png)<br>![F10 缩略图](figures/F10.png) | [F11 A01 执行摘要双端呈现](figures/F11.png)<br>![F11 缩略图](figures/F11.png) | [F12 取消请求与效果核对流程](figures/F12.png)<br>![F12 缩略图](figures/F12.png) |
| [F13 D01.1 首片供应商名称编辑](figures/F13.png)<br>![F13 缩略图](figures/F13.png) | [F14 既有入口与新子页面](figures/F14.png)<br>![F14 缩略图](figures/F14.png) | [F15 遗忘后恢复旧备份](figures/F15.png)<br>![F15 缩略图](figures/F15.png) |
