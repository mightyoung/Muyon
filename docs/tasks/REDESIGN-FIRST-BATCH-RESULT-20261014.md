# Muyon v1.3.2 首批接入终态（2026-10-14）

**首批已由唯一集成人Leader B正常合入develop，合入后CI完成且成功。**
develop完整SHA：`1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`。
main保持 `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`。

本文在独立review结果分支记录终态，不改已受测develop。此前M01-STATE及首批任务书是提交前接收快照，原记录保留；此文补充实际CI和合入结果，不追溯改写审查、失败或未执行事实。

## 固定作者交付与在途所有权

| 交付 | 固定SHA | 作者状态与独占写范围 |
| --- | --- | --- |
| M01/A00初始登记 | `421e7332807d0f8a2f7a6a36819601dcad442130` | B登记；原输入及历史保留，后续入口候选bc5b已完成 |
| M02审查后Draft | `2fd91b03a7b5f0888c1e11ab0ba559a580e970d0` | redesign_m02_contract原合同已完成；supplier-name-contract.md及M02任务书；保留642a939初稿 |
| D01a审查后Draft | `99c4d779bb5b94e3388637228f42869d6e81152d` | redesign_d01a_contract原合同已完成；authorization-minimal-contract.md及D01a任务书 |
| D03a Draft | `40f3cddb6e62baa2374bde288120d2385cb14c3f` | redesign_d03a_contract原合同已完成；recovery-minimal-contract.md及D03a任务书 |
| M04名称输入 | `8c5995515fa14ca3592a1c33c71afb4e4c1e5def` | M02作者后续工作已完成；fixtures/redesign/supplier-name-v1/及M04任务书 |
| M05真实Dart函数参考 | `962daee22c2ee2108440d9b30f2fcf7a88948f40` | D03a作者后续工作已完成；scripts/redesign/supplier-name-reference/及M05任务书 |
| A00分类输入及窄修 | `7a8128ca86c583b0bbf1191c4baa4f3e732ca547` | D01a作者后续工作已完成；fixtures/redesign/classification-v1/及分类任务书；保留fe5896f初版 |
| D03a恢复输入 | `55480f06490983a54e38908b043b06b4b02df451` | D03a作者后续工作已完成；fixtures/redesign/recovery-minimal-v1/及恢复fixture任务书 |

以上作者固定分支均正常推送、完整SHA读回，并在首批合入历史中保留。全部旧工作区、脏改动与其它writer保留；未重复A00清点或OC13/OC14/CR10F3独立复验。Rust/Android/Electron产品writer未由此批次放行。

## 精确CI与合入证明

| 阶段 | 完整受测SHA | CI终态 |
| --- | --- | --- |
| 入口及合同候选 | `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a` | [38488260486](https://github.com/mightyoung/Muyon/actions/runs/38488260486) completed/success |
| 完整首批候选 | `a592996ac5050b027911ecd717c3c34e5abcffd4` | [38491305570](https://github.com/mightyoung/Muyon/actions/runs/38491305570) completed/success，00:59:14 UTC |
| 合入后develop | `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d` | [38493563519](https://github.com/mightyoung/Muyon/actions/runs/38493563519) completed/success，01:22:33 UTC |

候选job115616877172及合入后job115624111497均重新读取完整解码日志，核对git-log checkout全SHA；各自coverage gzip snapshot.actions_run_id、8套件exit与逐pass/skip/fail均同日志一致，旧proof与新proof分别保留。两次均8/8 analyze、8/8套件、Doctor23、Laya四脚本29测试、coverage通过。

| 套件 | pass | skip | fail |
| --- | ---: | ---: | ---: |
| module_api | 276 | 0 | 0 |
| muyon_ui | 392 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 365 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 2312 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |
| 合计 | 4199 | 207 | 0 |

合入为正常no-ff merge和正常push；parents为原develop `01e56cc2d729dab70e1b1def05c3aa93b28f421a` 与候选a592。合入tree与已通过候选同为 `e4bf5bd79d0e67f63592e67d1fe1bcbfb4673f98`。产品与配置相对原基线diff为空。

原设计95文件、26项v1.3.2校验、两ZIP输入及内部哈希保留；原ADR正文只append，HANDOVER正文只prefix。首次集成脚本误对全历史diff做whitespace检查，原设计Markdown硬换行空白令其exit2并在push前停止；改核严格作者文件范围与合入增量均exit0，受保护原文件另以字节/哈希核对，未修改原文或CI门禁。另21历史页首未混入本候选。

## 实际实现证据范围与分类澄清

已取得M05真实固定Dart函数参考：47实际调用、39独立预期对照、零差异；32 pass/14 partial/8 not_run。非作者复跑匹配逐case/entry与来源哈希，源码漂移及错误NFC预期负对照均实际拒绝；B组合工作区亦真实复跑同摘要。仅normalizeText和Supplier.fromJson层；private guard、controller、dispatch、scope/CAS/授权/回执链与Rust目标未运行。

A00保持原29 case、77局部变体及14 proposed_unfrozen规则；D03a保持19组72场景。分类各场景execution_status仍not_run，恢复actual/golden均为null；结构和引用检查不是分类或恢复runtime通过，52主验收仍not_run。此批次接入Draft合同、合成输入与函数参考，没有新Rust/Android/Electron产品功能。

模型字段基础类别来自可信声明，但规范化后的实际新值仍须当前输出覆盖和credential检查；商业/个人来源限制不得因none目的字段降类。缺规则终止本版本分类尝试，保持unreviewed；参数改变使旧证据失效。unreviewed禁止模型/业务外发，不泛禁全部本机正文；credential禁止正文和日志。确定性完整用户名称不新增模型回合；当前用途最小检查完整时不等14全域规则，FullAllow缺Auto风险规则不误阻断，缺actual ValueCheck仍停止。

F10 Auto高风险确认标记矛盾及A01 page2覆盖缺映射已窄修并按7a8128增量复审C0；初稿发现保留。I03仍为M03/runner前条件：body标记只解释当前purpose候选材料资格，非当前flag不是许可；须改为单current-purpose资格或非当前not_applicable，不能据body=true授外发权。

## 尚缺门槛

M03仍blocked_contract：D01a实际值分类/模式runner与D03a恢复runner未执行；完整名称入口/状态及Rust跨端Unicode等价未证；unorm_dart0.3.1自声明Unicode8.0不代表新实现等价；SPIKE-01真实Android库加载、回调/释放、错误、JSON字节与同源类型化UniFFI语义/摘要选型证据缺失；单源schema未冻结。Flutter CI、文档和fixture都不能代替真实Android加载证据。

旧C6恢复CI38485490388/38485489896均failure，保留并排除首批，不改产品掩盖失败。未改main、forcepush、delete、deploy、真实模型/Android、真实用户库或MUYON_EVAL_REAL；未新建凭据或购买额度。监控gh两次HTTP401为只读请求通道错误，以现有MCP/公开元数据完成核验，不算CI失败。

原始日志只在仓库外 `/workspace/reports/redesign-first-batch-20261014/`；proof.json为候选、proof-postmerge.json为合入后，integration-proof.json、RESULT.json与M03-GATES.json分别记录集成与缺证据。本文为纯结果报告，[skip ci]不重复门禁；本文提交不冒称为受测产品SHA，也不再次合入develop。
