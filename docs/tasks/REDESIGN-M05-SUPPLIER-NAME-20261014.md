# REDESIGN M05 — 固定 Dart 供应商名称参考 oracle

状态：**真实函数级参考运行完成，可固定SHA审查；入口/状态覆盖未完成，M03仍blocked_contract**。日期：2026-10-14。writer：Leader B委派 `/root/redesign_d03a_contract`，唯一集成人仍Leader B。

## 隔离、输入与文件范围

独立worktree `/workspace/Muyon-leader-b-redesign-m05-20261014`，branch `task/leader-b-redesign-m05-supplier-name-20261014`，从 `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a` 创建。仅写 `scripts/redesign/supplier-name-reference/` 与本文，不占M04 fixture writer、产品/原两册/schema/Rust/platform/其它docs。旧dirty worktrees保留；适用AGENTS/.agents文本未发现。

产品固定 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`，设计 `58fe9c62612d74a973614c41677e62a54332e6d6`；领域delta来源 `2fd91b03a7b5f0888c1e11ab0ba559a580e970d0`。M04固定 `8c5995515fa14ca3592a1c33c71afb4e4c1e5def`，从git对象只读三个JSON。M04原32 domain/16 entry仍not_run、6state仍planned、goldens仍null；本文不修改或注册它们。

## 实际交付与命令

[README与复现说明](../../scripts/redesign/supplier-name-reference/README.md)、[实际Dart adapter](../../scripts/redesign/supplier-name-reference/oracle.dart)、[固定源/fixture runner](../../scripts/redesign/supplier-name-reference/run_reference.py)、[每case machine观测](../../scripts/redesign/supplier-name-reference/reference-observations.json)。Python不重实现规范化；直接调用固定原Dart源。无需pub/install；用临时package_config映射已装unorm缓存。

实际命令在README逐字列出。运行exit **0**；Dart **3.13.4 stable linux_x64**，unorm_dart **0.3.1**包自声明Unicode **8.0**，lib/source/fixture/adapter哈希全部在machine报告。values/entities/inquiry与产品P逐字相同；未复制或修改规范化实现。

| 层级 | 实际结果 | 不覆盖项 |
| --- | --- | --- |
| 32名称normalizer向量 | 32 pass；同独立M04预期零差异 | raw guard、完整命令、分类/授权/CAS/回执 |
| 16入口比较 | 14 partial、2 not_run | private host guard、旧UI/controller、schema/Rust入口未invoke |
| Supplier.fromJson | 6完整payload负例＋1普通中文补充正例，7真实调用 | validatePayload dispatcher与完整工具接口未invoke |
| 入口raw normalizer追加观测 | 8 observed_only，不计完整入口pass | pretrim、2000护栏与业务写入未证明 |
| 6state向量 | 6 not_run，planned合同保留 | 新intent/重复零写/scope/CAS/receipt/unknown无运行证明 |

共47真实调用，39固定预期对照、零差异；54case报告汇总32pass/14partial/8not_run。32pass仅该函数层级，不是M04整入口、52新架构主case、A00 29分类子case或runtime门禁通过。反例实际覆盖201码点、VT/FF/NUL、孤立surrogate等，正例含NFC、中文、合法补充字符；anti-vacuity确认实际正负分支与完整结果集合，非自写normalize自证。

原始evidence仅 `/workspace/reports/redesign-m05-reference-20261014/`；repo machine报告仅普通合成规范值/非secret原因。未使用真实DB、secret、canary、模型、设备、外部服务或付费资源。未设置MUYON_EVAL_REAL。

## 核查、故障与未满足项

已执行Dart format、Python编译检查、真实参考命令、独立预期集合/正负分支检查、文档相对链接/预留范围/`git diff --check`。第一次无CI环境的Dart format因尝试写只读`/home/agent/.dart-tool`失败exit255；按既有CI=true与XDG_CONFIG_HOME环境重跑成功，无权限升级/依赖安装。初次运行遗漏fixed M04已更名Supplier entry，仅32对照/40调用；修正固定键后完整执行47调用/39对照，最终报告为后者，不将初次未覆盖冒称通过。

非作者固定SHA审查待Leader B组织。Rust目标全部not_run，跨端Unicode等价未证；unorm Unicode8.0事实须给M03处理，不能只因另一库名NFC就宣布等价。D01a、SPIKE-01真实Android加载/双传输与单源schema冻结等M03前置仍未满足。M05明确遗漏完整UI/private guard/dispatch/CAS/receipt/state，后续真实可信入口runner另行实现，不能fake计pass。

本地正常commit；不push/merge/main/force/delete/deploy/install/credentials/payment，不运行未授权Native LE04攻击实验。无业务运行验收通过声明。
