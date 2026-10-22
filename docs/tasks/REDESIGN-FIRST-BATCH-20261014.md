# REDESIGN 首批合同、合成输入与 Dart 函数参考

日期：2026-10-14。本文记录最终组合提交前的接收快照，集成人为唯一 Leader B；Leader A 暂停。原任务、审查、输入哈希、失败与未执行记录保留。此批次交付合同草案和测试输入，并取得有限 Dart 函数参考结果；没有新 Rust/Android/Electron 产品功能。

## 来源、作者与固定交付

产品基线 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`，设计 `58fe9c62612d74a973614c41677e62a54332e6d6`；原95设计文件及v1.3.2的26项校验不变。原M01/A00提交 `421e7332807d0f8a2f7a6a36819601dcad442130` 与后续审查记录保留；已审入口候选为 `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a`。

| 交付 | 固定提交 | 作者及独占目录 |
| --- | --- | --- |
| M02 Draft | `2fd91b03a7b5f0888c1e11ab0ba559a580e970d0`，保留原642a939 | redesign_m02_contract；supplier-name-contract.md及M02任务书 |
| D01a Draft | `99c4d779bb5b94e3388637228f42869d6e81152d` | redesign_d01a_contract；authorization-minimal-contract.md及D01a任务书 |
| D03a Draft | `40f3cddb6e62baa2374bde288120d2385cb14c3f` | redesign_d03a_contract；recovery-minimal-contract.md及D03a任务书 |
| M04 名称输入 | `8c5995515fa14ca3592a1c33c71afb4e4c1e5def` | redesign_m02_contract；fixtures/redesign/supplier-name-v1/及M04任务书 |
| M05 Dart函数参考 | `962daee22c2ee2108440d9b30f2fcf7a88948f40` | redesign_d03a_contract；scripts/redesign/supplier-name-reference/及M05任务书 |
| A00 分类输入 | `7a8128ca86c583b0bbf1191c4baa4f3e732ca547`，保留原fe5896f | redesign_d01a_contract；fixtures/redesign/classification-v1/及分类任务书 |
| D03a 恢复输入 | `55480f06490983a54e38908b043b06b4b02df451` | redesign_d03a_contract；fixtures/redesign/recovery-minimal-v1/及恢复fixture任务书 |

各作者原合同工作均已完成，并未仍在修改原合同。后续fixture另有独立分支；不占旧产品writer或共享文件。23迁移单元清点已接收，不重复盘点；旧null实现writer不等于共享文件可用。Rust和平台产品writer尚未放行。首批当前入口仍只追加ADR0001、前置HANDOVER提示；另外21个旧页首不在本候选。

## 实际验证与未执行状态

M04是54个输入记录：32名称、16入口、6状态计划，原golden仍null。M05实际调用固定产品Dart的normalizeText和Supplier.fromJson，非Python镜像：作者与非作者复跑均47次实际调用、39项独立预期对照、零差异。分层结果32 pass、14 partial、8 not_run；partial不是完整入口通过。独立负对照实际拒绝源码漂移，错误NFC预期实际检出一项差异。根组合工作区亦再次真实运行，得到相同摘要。

未运行private raw guard、旧controller、schema/dispatch、scope、CAS、授权或回执链。unorm_dart 0.3.1自声明Unicode8.0，32函数样本不证明Rust跨端Unicode等价。实际观测保留在[函数参考](../../scripts/redesign/supplier-name-reference/reference-observations.json)，[非作者报告](redesign-kickoff-20261014/independent-reviews/m04-m05-review.md)明确其范围。

A00保留原29子case，展开77局部变体；14规则仍proposed_unfrozen，29均not_run。恢复输入19组展开72场景，全部not_run、actual/golden=null。JSON、唯一ID、完整cursor、固定来源、哈希与链接核验只证明输入材料完整，不是分类或恢复状态机执行。52主验收仍not_run，不把局部数量累加为新主case。

## 分类与载荷适用澄清

模型生成字段取可信字段声明为基础类别，并对规范化后的实际新值完成当前输出覆盖及credential检查，两条件缺一不可。来源/个人或商业限制继续继承，复制进none字段不能降类；参数或版本改变使旧证据失效。合法且已覆盖的新名称有确定通过路径，缺规则结束该版本本次分类尝试，保持unreviewed并返回明确原因，不能无限等待或由确认补覆盖。

unreviewed在可信分类前不进模型/业务外发，不泛化成所有本机业务正文；credential原文不进模型、业务工具/分享正文或日志。完整用户名称的确定性本机命令不为分类增加模型回合，当前用途最小ValueCheck、可信字段、来源、权限/模式、scope、CAS和业务条件完整即可，不等待14条广域规则全部实现。FullAllow缺Auto风险规则不误阻断；缺实际新值检查仍停止。沿用[根适用澄清](redesign-kickoff-20261014/A00-APPLICABILITY-CLARIFICATION.md)，不改原A00输入字节。

分类fixture的body标记只表示当前purpose对应候选材料资格，与action_result分轴；非当前用途的flag不构成任何许可。实际runner/M03前须改为单current-purpose资格或非当前not_applicable，不能泛用几个body=true来授外发权。它是离线输入格式待细化项，不是新产品限制或wire DTO。

初版分类输入发现并保留两项应改：F10 Auto高风险的确认标记与预期矛盾；A01第2页credential/用途覆盖缺映射。7a8128窄修对齐F10、绑定A01 page.2，并在A02逐页记1–7覆盖、8–10无覆盖且仍拒全篇；其它27原case未改。原提交、初版发现及增量复审均保留。

## CI、集成边界及 M03 门槛

入口候选[CI38488260486](https://github.com/mightyoung/Muyon/actions/runs/38488260486) completed/success，完整checkout为bc5b2c37，8/8 analyze、8/8 suite、Doctor23、Laya、coverage成功，4199 pass/207 skip/0 fail。该CI只覆盖当时入口/合同候选，不冒称包含后续fixture/scripts。此批次在独立branch `task/leader-b-redesign-first-batch-20261014` 完成精确候选CI后，B才正常合入develop，并核验合入后CI终态；本文是提交前快照，实际结果必须绑定CI完整SHA，不把CI绿当新架构产品验收。

M03仍blocked_contract：D01a实际值分类/模式fixture和D03a恢复runner未执行；M05完整入口/状态及跨端Unicode等价未证；SPIKE-01真实Android库加载、回调/释放、错误与双传输语义/摘要证据缺失；单源schema/编码选型未冻结。本环境未找到cargo/rustc/rustup/adb/sdkmanager，没有真实Android加载结果，不用文档、fixture或旧Flutter CI替代。未实现新Rust领域、平台UI或后台。

旧C6恢复两提交的CI38485490388/38485489896均completed/failure，保持旧证据并排除本候选；不改产品掩盖失败。原始日志留仓库外。未改main、强推、删除分支、部署、真实模型或真实用户库，不设置MUYON_EVAL_REAL，不购买或新增凭据。
