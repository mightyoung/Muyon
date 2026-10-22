# Muyon v1.3.2 迁移入口小补丁

日期：2026-10-13 17:20 UTC（北京时间2026-10-14）  
对应用户复审：8d55113e8a4081919cd30f159c59f84f。仅补I02/S01/S02，不增加产品决定，不改仓库或原两册。本轮路径从固定产品提交01e56cc2d729dab70e1b1def05c3aa93b28f421a的完整树核出，并经GitHub只读API读取所列21份文件；F08已实际查看原PNG。

## I02：可加入MIGRATION-TRACE的旧任务登记

以下18项准确前缀均为 `docs/tasks/`，不要写成通配符就算完成登记。统一页首标注：“适用旧Dart/Flutter实现与表内固定SHA；业务、身份、回执、真实来源不变量继续继承；旧授权模式/人工频率仅按新版明确条款部分替代；新入口为当前两册相应章节及MIGRATION-TRACE；原审查与CI只证明其原范围，不当新版通过。”审查记录保留正文、历史失败及后续修补，不重新写成已通过。owner由M01/A00现有责任表确定，不重新派发。

| 精确文件名（前缀docs/tasks/） | 适用旧版/证据性质 | 继承与部分替代登记 | 新版入口 |
| --- | --- | --- | --- |
| AUTH-1a.md | 旧库层任务（未接线） | 授权库、解析、撤销/审计和复核接口继承；旧新端点/持久授权限制按新模式部分替代 | D01b/D04；单元11 |
| AUTH-1a-review.md | 固定旧库层审查证据 | 保留原SHA、范围和当时结论；不推导新模式或生产接线通过 | D01b旧机制fixture/证据索引 |
| AUTH-1b.md | 旧A/B/C接线总任务 | 可信宿主、scope/目标/版本/回执继承；新端点逐问与旧taint频率部分替代 | D01a/D01b/D04；单元11/13/14 |
| AUTH-1b-review.md | 旧A阶段独立审查 | 保留迁移、原子授权消费/审计/审批证据；不扩大为B/C或新架构通过 | D01b/P3；证据索引 |
| AUTH-1b-summary.md | 旧接线阶段性总结 | 按记录的SHA解释旧standard/readOnly/custom及model_auto；不等同新版Auto | D01b差异表；S04 |
| AUTH-1b-B1-facts-review.md | 旧来源事实审查 | 保留taint继承、durable marker、取消边界证据；taint风险后的新模式动作部分替代 | D01b/D04；单元11 |
| AUTH-1b-B1-review.md | 旧B1 checkpoint审查 | 可信事实/范围证明保留；不得推导B2/B3/C完整通过 | D01b；证据索引 |
| AUTH-1b-B2-foundation-review.md | 旧B2基础审查 | 实际wire、私有proof、排队重验、原子账本/审批、真实通道约束继承；旧risk block/confirm映射部分替代 | D01b/D04；单元11/13/14 |
| AUTH-1b-TLS-review.md | 旧TLS审查与修补 | 保留实际peer证书身份绑定和真实传输边界；身份校验不是风险询问，不被FullAllow取消 | W5/W7；单元17/18 |
| AUTH-1b-B12-boundary-repair.md | 旧B1/B2边界修补 | 保留chunk前重验、真实sent计数、受管路径/namespace证明与祖先换链反例 | D01b/W5；单元11/17 |
| AUTH-1b-B12-review.md | 旧固定修补复审 | 保留原失败与修后结论的各自SHA；不追溯改旧失败、不声称B3/C通过 | D01b；证据索引 |
| AUTH-1b-B12-leader-review.md | 旧精确集成门禁证据 | 保留精确审查/CI及接纳边界；旧负责人安排按最新唯一集成人更新入口而不改历史 | M01/A00；证据索引 |
| AUTH-1b-B3-cancellation-checkpoint.md | 旧optional/manual阶段 | 保留取消、实际review绑定及当时尚未生产接线边界；旧人工频率部分替代 | D01b/D03/D04；W4 |
| AUTH-1b-B3-review.md | 旧固定B3审查 | 保留BLOCK及后续修补所对应版本；无产品新模式放行证明 | D01b/D03；证据索引 |
| AUTH-1b-production-inputs.md | 旧真实输入事实接线 | 保留同次加载的memory/history及不可伪造HostLoadedInputProof；clean不能模型自报 | D01b/D04/D05；单元11/14/21 |
| AUTH-1b-production-automatic.md | 旧automatic local-write子片 | 保留真实owner/不可变request/nullable grant来源；旧自动授权不是新版Auto，taint旧门禁部分替代 | D01b；W4 |
| AUTH-1b-model-policy.md | 旧类别策略及model wire任务 | 保留四效果轴、真实profile/endpoint/字节/凭据/账本、生命周期重验；旧三档与review故障confirm按新版部分替代 | D01b/D04；单元11/13/14 |
| AUTH-1b-model-policy-review.md | 旧C1/C2精确审查集成 | 保留精确实施SHA、原失败/修复与现有模式自动来源证据；不升级新架构验收 | D01b/D04；证据索引 |

另补以下3个准确路径：

| 路径 | 适用旧版/部分替代 | 新版入口与继续继承 |
| --- | --- | --- |
| docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md | 2026-10-10旧Flutter默认开启条件计划，不是已经执行；旧时间窗口/负责人状态保留为历史。新端默认开启与授权Auto是两件事；外部内容旧逐次询问、旧“全部允许”按钮措辞按当前模式部分替代 | 单元09/10/11/20、D02/D03/D04、W4/W7及S01.1；继承生产编译器/目录先行、真实呈现三档与持久化、同候选审查、失败不冒通过、显式默认开放门禁 |
| docs/design/aiui-smoke-test-spec-2026-10-11.md | CR-3旧Flutter/Android验收规格；第6节已由ADR0001:108采纳，文件“未实现”是当时状态，不当当前实现事实。Dart测试文件/设备操作形式按新端替换，旧人工确认步骤只在相应模式保留 | 单元09/10/20、D10、M22–M28、W4/W8；继承同SHA真实生产链、自动1–4/7与重启5/6证据分开、真实上游与fixture分开、至少5原始样本/中位数、隐私白名单、恢复不重新播种/不自动执行。保留全部原用例映射，不重跑 |
| docs/design/aiui-stream-contract.md | 已采纳AIUI流合同的旧技术编码/版本依据；宿主身份与动作路由、严格坏行、候选/预览/final区分继续有效。Dart类型映射到M03同源schema；必须明确stream/2与library-2适配，不把历史标题v1当最终生产编码事实 | 单元09/10、M03/D02/D03、W4及公共卡片合同；继承完整end+全树验证、坏行不可丢弃后宣布成功、预览不带执行、迟到/取消不能复活、after_end与真实transport_error分开、旧版本拒绝/显式迁移；当前已登记确定性业务命令仍直Rust，不恢复模型绕路 |

补充依据：AUTH任务引用的 `docs/superpowers/plans/2026-10-08-auth-1b-b-minimal.md` 确实存在；若本轮只补任务入口，可作为AUTH-1b来源链接而非新增独立实施任务。不拓展本次盘点范围。

来源固定前缀：[产品基线目录](https://github.com/mightyoung/Muyon/tree/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs)。添加旧文件页首状态是后续实际文档切换动作，本补丁仅登记，未改变远端旧文件。

## S01：可直接加入两册的术语框

> 本文区分三套相互独立的名称：  
> 1. 旧授权三档：standard/readOnly/custom，即标准、只读、自定义；是固定Dart基线的权限策略，不能直接改名为新版Auto  
> 2. 呈现三档：自动、少用、只用文字；只控制可选卡片/可视化呈现，不授予业务、模型或外发权限。固定源码枚举实际为UiPresentationMode.automatic/few/textOnly，持久值automatic/few/text_only；auto/sparse/textOnly只能作为非代码简称，不能冒称旧schema枚举  
> 3. 新授权四档：只读、每次询问、Auto、全部允许；低风险并入Auto，新装默认Auto。该默认不改变呈现三档的默认或旧配置迁移行为，旧库仍按不升权规则迁移  
> 文中单写“三档”必须加“旧授权”或“呈现”；单写“自动”必须说明是呈现自动还是授权Auto

证据：[旧授权enum](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_authorization_policy.dart#L9-L11)；[呈现enum与存储值](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/ui_presentation_preference.dart#L6-L12)。评审的auto/sparse简称应据源码纠正，不必另造兼容枚举。

## S02：可直接加入第二册图示总则及F08

总则：
> 当前版本Markdown正文、页面合同与文字线框是本版规范；沿用的PNG是保留原字节的旧视觉参考。二者标题、文案或行为有差异时，以当前Markdown规范为准，PNG不新增权限、功能或默认值，不覆盖Auto/FullAllow、未知结果与恢复合同。图号只建立对应关系，不说明旧图已经同步更新；以后重绘须另记图版本，本次不改PNG

F08图注：
> F08原PNG标题为“F08 T03 可信审批与失效计划”，本版正文标题为“F08 T03 手机保存审批”，二者是同一图号的旧视觉参考与现行页面说明。PNG右侧“计划已变化，需重新审阅”只示意需要人工决定的模式；当前FullAllow仍按正文在合法读写集/业务条件下重建并校验，不因旧PNG恢复额外风险询问。原计划失效、版本检查和真实回执要求继续保留

F08已实际查看，原图未变；无需修图即可消除规范优先级歧义。本补丁不声称像素一致性或新实现验收通过。

