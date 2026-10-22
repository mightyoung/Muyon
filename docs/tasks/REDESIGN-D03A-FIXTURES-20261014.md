# REDESIGN D03a — 最小恢复 machine fixture 输入

状态：**可固定SHA审查，72场景全部not_run；仅静态结构核验，非runtime门禁**。日期：2026-10-14。Leader B委派 `/root/redesign_d03a_contract` 单writer；唯一集成人仍B。

## 隔离与固定输入

独立worktree `/workspace/Muyon-leader-b-redesign-d03a-fixtures-20261014`，branch `task/leader-b-redesign-d03a-fixtures-20261014`，从 `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a` 创建。独占预留仅 `fixtures/redesign/recovery-minimal-v1/` JSON/README/SHA256SUMS及本文；未改合同、root入口、原两册、产品、schema、Rust或平台。旧M05/合同worktrees与所有旧dirty状态保留；此前适用AGENTS/.agents检查无文本要求。

固定P `01e56cc2d729dab70e1b1def05c3aa93b28f421a`、D `58fe9c62612d74a973614c41677e62a54332e6d6`；已审D03a合同输入 `40f3cddb6e62baa2374bde288120d2385cb14c3f` §8，19组原标签逐组映射。此次没有重定义M03 DTO/编码/状态enum或实现第二套恢复状态机。

## 四文件交付与范围

[目录说明](../../fixtures/redesign/recovery-minimal-v1/README.md)、[机器输入/期望](../../fixtures/redesign/recovery-minimal-v1/recovery-scenarios.json)、[SHA256SUMS](../../fixtures/redesign/recovery-minimal-v1/SHA256SUMS)及本文。JSON共19group/72局部正负或故障分支；每case拥有input/expected/refs（group引用）、not_run、actual=null、golden=null。

覆盖完整store/scope/stream/seq域、许可投影跳跃证据与隐私、snapshot/durablecursor一致提交/崩溃边界、有界buffer/resync、旧epoch显示栅栏与真实receipt独立核对、PendingInput身份/送达/留存、unknown零自动重发及可信用户新intent保留oldunknown。FullAllow合法纯风险零额外问，真实scope/用途/能力/业务/CAS硬前提保留；取消/导航关闭不视为businessrollback。没有范围歧义需要新增合同决定；D03A-19明确保持D03/D06/P3后续边界，不变首片实现范围。

所有内容为synthetic metadata placeholder，未物化正文、凭据或用户记录。输入trusted标志只是未来可信fixture注入要求，不是实际能力/签名证明。小buffer预算不当产品默认，隐私过滤seq差值不解释为隐藏审计数。

## 验证与出口

实际仅静态：JSON解析、19组/72唯一case、逐组映射及源引用、正负分支、递归完整cursor域/字符串seq、actual/golden空、全部not_run、README/任务相对链接、SHA256SUMS核验、预留文件范围及`git diff --check`。这些不能计恢复pass，也未写任何runtime结果或冒称gate通过。

52主case不增，29分类子case仍not_run，新72子场景均not_run。非作者固定SHA审查与真实合成恢复runner待B组织；M03单源冻结、M12实现与真实协议/平台证明仍未由此次交付满足。没有tests/model/device/network执行，不运行未授权Native LE04实验，不安装/pub/Android/真实模型、不设置MUYON_EVAL_REAL；仅本地正常commit，不push/merge/main/force/delete/deploy。
