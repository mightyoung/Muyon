# Leader B 入口补丁独立只读复审

固定补丁 `9430668090396343f0e4138d392e7de1b7843298`，比较基线 `0ec2159f413b5b90e674b48865cbcb217d6dc0f7`；worktree `/workspace/Muyon-leader-b-redesign-m01-20261014`。复审者为非作者 `/root/redesign_m02_contract`，本任务不修改其M02分支或任何仓库文件，证据只写本目录。实际只做git/文本/哈希/链接静态检查，无产品运行、fixture执行、模型、设备、真实数据、新凭据、费用、push或merge。

## 结论及 C/I/M

**入口补丁可接纳；C0、I1、M0。** C为阻断本次入口补丁接纳的缺陷；I为唯一develop集成前仍需完成的工程步骤；M为非阻断表达/事实补充。没有需要作者修订的C/M项。

- **C：0。** 精确四文件、51新增行、零删改历史正文；限定为两个已存在文件的入口提示，没有扩大到其他21旧headers、ADR0006/7或产品分支。最新B全职责和正式开工授权已有，不要求重复询问已授权routine。
- **I-01：准确组合提交的独立CI及唯一集成。** source CI38439338859属于固定设计`58fe9c62612d74a973614c41677e62a54332e6d6`，不能登记为943或后续组合提交CI。由Leader B按既有授权取得最终组合准确SHA的独立检查/CI终态，再唯一正常合入develop，读回实际提交；main、force、分支删除、部署和旧产品分支仍在范围外。本review不执行这些步骤，不证明943 CI或52新验收通过。
- **M：0。** 新发现的A00适用澄清以新文件补充，未改输入字节或将原报告追溯标错；未知spike、Unicode等价及模式工程出口清楚保留。

## 已独立核实的证据

1. `0ec→943`只涉及：`docs/adr/0001-leadership-and-scope-freeze.md`（+13）、`docs/tasks/HANDOVER-LEADER.md`（+4）、`docs/tasks/redesign-kickoff-20261014/A00-APPLICABILITY-CLARIFICATION.md`（新增9行）、`ENTRY-INTEGRATION-SCOPE.json`（同目录新增25行）。`git diff --check`返回0，worktree无脏改动。
2. ADR旧正文26237字节完整为943前缀，SHA256=`6d8d60f5be4b7015a2db87310e7f928f849e0596ad4e421bcb1f00a0cc0df7b8`；HANDOVER旧正文26935字节完整为943后缀，SHA256=`a9c8452debb3be2aace2489cfb0318202554d51a6e0ef0d7d8a6b5f04b5f0aeb`。均与manifest、0ec、固定58设计及固定01产品的旧文件逐字节相同。旧Oct12职责和“丢失”记录仍原样保留，新追加说明仅记录后续职责/恢复，不追改旧失败。
3. 相对固定设计58，整个`docs/design`无差异；源六提交相对产品01新增95设计文件、五个目录，95文件逐字节与943一致。相对固定产品01，`apps/packages/scripts/.github`无差异。本次没有引入旧产品任务分支代码或改源码/CI。原A00分类目录、kickoff交接、Claude复审及其SHA256SUMS相对0ec逐字节未变。
4. 新增本地链接目标均存在；HANDOVER的`#2026-10-14leader-b-全职责接任与-v132-改造开工`与ADR新增标题规范slug一致。新增固定GitHub链接均指向58下真实存在文件，L798/L39均在文件范围内，实际读取相应段落；未调用网络或宣称远端渲染实测。入口README/M01引用可定位。ADR0006/0007在943树没有被分配；manifest仍要求冻结前另核所有在途预留，未以本树不存在冒称全局占号保证。
5. ADR追加明确B派发/说明/审查/登记/独立验证/唯一develop合入，A暂停；历史writer/在途所有权保留。HANDOVER前缀将旧正文标为按日期/SHA的历史，并固定58设计和01产品。没有将文档采纳当产品完成；保留旧Flutter/生产库，52新架构验收未执行，M03未冻结；真实数据/模型/设备成本/发布不自动扩大。
6. ADR引用source CI38439338859时明确“固定文档58、准确SHA”，前后明确只为DOCS-G0采纳；HANDOVER说明文档CI/派发/合同草案不是产品完成。原Claude报告“当时读不到该CI”未改写。source CI与M01既有证据的适用域一致，本review仅静态检查作用域，没有重新拉远端日志或重跑8CI，也不把它归到943。
7. A00澄清准确指向原目录L51：原“业务载荷”对unreviewed限定为业务**外发**载荷。固定第一册L798–801及第二册L39明确unreviewed禁模型/外发，credential原文禁模型/业务工具或分享正文/日志；这两者不能混作全部本机写入禁令。补丁仍要求本机name实际新值credential检查、可信声明、来源/继承限制、业务、模式/风险、scope、能力及CAS；缺最小必要检查局部拒绝或blocked_contract，field none不授写权、不洗来源、不认证全用途已覆盖。未要求等待14广域规则全实现，也没有绕过最小当前用途检查。
8. FullAllow免额外风险询问与真实硬前提分开：scope/能力/身份/业务/CAS仍必要，旧三档不因入口升权；该追加没有制造taint/新目的地强制确认、Auto永久confirm或legacy_standard=Auto。完整外发分类规则归D01b/单元14，A00仍14拟定、29分类子case和52主验收not_run；M03前仍须D01a/D03a/SPIKE-01及真实Android库加载/Unicode等价证据，文档和现有CI不能替代。

## 接纳条件与适用边界

据已有授权，本四文件入口patch可以进入Leader B的独立组合CI与唯一develop集成，不需再请求用户确认。其他21旧headers仍排除本次，须按准确预留与writer协调，不凭本review自动获得修改许可。ADR0006/0007不在本次创建或占号，真实模型/外发/设备/数据和产品实施须遵守后续对应工程出口。

ADR最后一段关于C6原分支推送属于Leader B与M01既有恢复证据陈述；本次核对其前后一致、恢复不等于review/merge、未引入产品代码，没有独立重新核远端push。该范围界限已明确，不是入口patch执行或CI通过证据。

完整静态证据见`evidence.json`，包括fullSHA、numstat、旧正文哈希/字节保留、95设计源文件哈希、链接目标、manifest与检查状态。没有运行fixture/程序，未把静态结果包装为跨端加载或新52验收通过。
