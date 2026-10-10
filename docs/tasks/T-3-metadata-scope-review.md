# T-3 metadata scope / PR14 最终独立复审

日期：2026-10-10。develop基线 `3b0adb9e5242dc4a598bf3be71a8252204a9a053`；
冻结源提交 `2f7cdee41a428bd02257de990e2e54242a01ddc1`。
审查分支 `review/T-3-metadata-final-integration-20261010` 从此源提交建立，
工作区 `/workspace/Muyon-T3-final-integration-20261010`。按HANDOVER A–D、REVIEW、
ADR-0001现行用户决定、产品总览、AIUI流式契约及任务说明核实；无AGENTS.md或.agents技能。
本机缺Flutter/Dart，独立动态核实使用原有Linux Actions，未安装SDK或新增workflow。

## 范围与交付

相对基线8文件，1564新增/9删除：platform_tools/tool_registry机制、metadata专项测试、
research_task_flow_test及四份设计/任务/证据文档。生产bootstrap、LAN/supplier_core、
模块恢复源码、CI脚本/workflow、UI契约及授权定义均无变化。
非作者只读核实者沿用前轮逐项机制复审，并对最终B1增量复审，无修改/提交/推送。
父任务转交真实Claude七个完整闭合小包结论及最终B1单包通过；不冒称本线程运行Claude。

| 交付 | 结论与边界 |
| --- | --- |
| P1 隔离/审计 | 满足任务受测notes DB/SQLite及prepare/invoke阶段审计；普通附件/目录及所有生产模块文件未全面覆盖，不冒称全模块文件证明 |
| P2 拒绝 | 类别/schema/global/预取消/宿主不可用受控行为测试；解析前拒绝、零handler |
| P3 binding | 成功封存私有绑定、registry/descriptor identical；四ID/provider/module/read/global/空refs另由registry核验；跨registry/伪造lane反例 |
| P4 固定lane/撤权 | lane丢失在fallback前拒绝；await后核generation/identity/policy/关闭/availability；handler在生命周期await后再核撤权 |
| P5 回放 | 只有认领路径追加lane identity；同进程/并发/重开及新invocation行为测试；不声称任意策略变化仍可回放 |
| B1 正常恢复 | test:357–389同host先读四metadata，pending/绑定/通知/receipt不变、来源与激活/commit为零；然后business/global正常完成，首次激活1、已有receipt不变、commit0，重复解析不重复效果 |
| B2 冲突/科研协调 | 持久冲突通知规则、真实ResearchModule三DB重开与afterActivate协调恰一次；不是重新导入ZIP证明 |
| B3 旧路径 | 未认领global/workspace/selected差分，旧identity兼容与原授权回归保留 |

B1前轮缺口明确关闭：最终源相对2cb只新增17行上述测试及证据文档，未改生产机制。
研究race测试同步有独立失败证据；不改生产状态顺序，不降低校验或删失败断言。
隔离夹具通过相同host基础设施第二registry，不是生产host.tools装配E2E。
模块receipt在B1为允许的fixture内存桩；B2另有持久科研receipt证据，不混称。
未发现当前提交确定生产阻断。生产登记仍OFF、完整T-3未完成；生产接线/正文/记忆提议/
扫描预算/项目查询另片，Mac golden、设备、真实模型仍未验证。

## 动态验证与完整SHA

原有ci.yml review/** push触发，ubuntu-latest/Flutter3.47.5。
本线程主动推精确源提交独立分支，触发[独立CI38018663166](https://github.com/mightyoung/Muyon/actions/runs/38018663166)。
实际入口 `bash scripts/ci.sh`：pub get，8包`flutter analyze --no-pub`（info失败），
gate退出码回归、doctor23场景及8套`flutter test --no-pub --reporter compact --timeout 120s`。
host目标为完整`test`，无name/tag/文件排除，覆盖metadata/platform_tools/tool_registry/
import_recovery/accepted_research_import/scope_resolver_differential/module_lifecycle七专项，
也包含research_task_flow。不是七专项命令分别运行；全文日志不入仓库。
既有Laya四组在主门禁通过后运行，无真实模型/新增网络夹具。
源push[38017057408](https://github.com/mightyoung/Muyon/actions/runs/38017057408)及PR
[38017060942](https://github.com/mightyoung/Muyon/actions/runs/38017060942)在完整最终源head success，已亲自读API复核；
不把它们代替本次独立运行。独立终态与摘要将在此补记。

最终源独立CI38018663166/job114114568617，attempt1，completed/success，实际checkout
精确2f7cdee完整SHA。analyze8/8、test8/8；module_api68、UI323/152skip、prototype39/1skip、
research220、supplier490/4skip、host1404/3skip、preview15、inquiry289/47skip。
gate通过、doctor23场景、Laya四组8/4/8/9 tests全部通过。全套无删减、无重试挑绿。
原始日志仅`/tmp/muyon-ci38018663166-job114114568617.log`或Actions，不进仓库。
结论：建议合入精确机制源；不会把成功写作历史LAN已修复。合后精确发布CI另行跟踪。

## 历史LAN风险与后续待办

旧源2cb的独立run[38016276386](https://github.com/mightyoung/Muyon/actions/runs/38016276386)
analyze8/8、test7/8，host1404/3skip成功，但supplier489/4skip/1fail；
lan_security_test:302第二合法上传Expected200/Actual400，Laya因此skipped。
helper丢弃正文、服务器catch未记录原因，历史异常不可从现有日志恢复；未据差异0直接判无关。
supplier_core整tree与基线同为`57d47924c8ee952138f9b096eef53f81cc7c3a78`。

用户后续授权单次隔离诊断，固定`55d0f10996be9fb3e77fc0b02d23330fafb51c6c`，
保留150ms/300ms和200断言、无生产修改、无重试挑绿。
[38017703913](https://github.com/mightyoung/Muyon/actions/runs/38017703913) success，
analyze/test8/8、supplier490/4skip、host1404/3skip、doctor23和Laya全通过。
trickle关闭→inbox观测清空→合法请求200/正文0字节/客户端35.245ms。
结论仅为**未重现、原因未明**，不是服务器timer证据，也不是已验证LAN修复。
诊断代码与其ci.sh标签输出绝未混入本审查分支。

后续待办保留此未决：再次出现时保留完整日志并停合入，优先受控采集服务器请求序号/
单调耗时/阶段/deadline/stopped/固定异常分类与清理结束，禁止输出凭证、payload、真实路径。
不简单放宽150ms、不删测试、不用反复运行挑绿。原始日志仅Actions或/tmp，未入库。
最终源验证通过、当前确定阻断为空后，可依最新用户授权合机制片，历史LAN风险继续保留。

父任务转交真实Claude LAN交叉研判完整result/exit0：合法请求自身150ms deadline优先，
文件/签名异常次之，HTTP解析400未排除；容量503、nonce409、授权401，不支持仅凭400
归因这些拒绝。35.245ms只证明该次成功。另有先持久化消息ID再交付文件的失败重试窗口，
是基线静态风险、未证明为历史原因且非PR14新增，后续独立任务处理，不顺手改LAN。

合入门槛解释：REVIEW“验证失败必须修复后才能合并”针对当前待合提交的门禁；
本轮不跳过测试、不豁免失败。如果固定最终源全套成功、独立复审无当前确定阻断，则门槛
满足；历史失败作为显式保留风险，不伪称已修复。HANDOVER允许经过两三轮审查后将剩余
低概率问题另开小任务，父任务本轮又明确授权此条件下合入。无需新增权限或测试例外。
