# Muyon：Muse 对话可操作组件研究与改进规格 v1.0

核查日期：2026-10-22，北京时间。执行位置：云端。性质：截图核读、代码只读与设计规格；未修改仓库、未安装/运行 Muse、未调用真实模型/工具、未进行付费操作。

## 1. 结论

应借鉴的是“对话中的对象能操作，并把状态与结果留在原上下文”，不是复制 Muse 外观或把任意 HTML 接到业务工具。优先做原生、类型化的列表/选项/本地表单与回执卡，复用 Muyon 现有权限、请求身份、业务预览、费用门控和查询原回执机制。富 HTML 沙箱与地图不是首批必需项。

三种动作必须分开：①仅编辑本地组件状态；②发送一条明确可见的对话消息；③打开来源或请求宿主执行业务动作。不能把普通“选项”“👍”隐式升级成外发、付款、删除或修改授权。一次性聊天组件与可长期维护的 Artifact 是不同对象。

## 2. 证据分层与逐图观察

来源为用户此次提供的 10 张截图，按附件顺序编号 S01–S10。图片无可核实版本号，截图所显示时钟不作为发布日期。截图中助手对能力的描述只是产品内文本，不等于实测。未复刻私人学习内容，以下仅描述结构。

- S01（libfile_ceabc022aa1c819193861ed6dd8cb2c6）：多题 A–E 按钮、主操作“提交判分”、次操作“重做”；文案称选择自动保存、可重开读回。看到了入口，没有看到提交后的分数、持久化或回读记录。
- S02（libfile_8ee59e1bac8c8191aa56a2e48acfa80f）：题组标题、规则说明、题干和分组等宽按钮；同一题组在会话中纵向延展。
- S03（libfile_5b10b451b8f08191a61a0164ec3e8e63）：普通回答后紧接独立练习块，说明与可操作对象分离。不能据此确认由模型实时生成何种代码。
- S04（libfile_c0c781aa78fc81918501725efc122713）：两条带虚线边框的预设回复；后续有一条用户消息和勾选反应，提供“快捷回复进入消息流”的截图证据，但不是独立点击录像。
- S05（libfile_16a9acc9aae08191b3436bf9960fd443）：仅文字介绍 Letter、商品/购物车、文件、语音和 Artifact；明确说未现场演示。这些不能列成已看见的组件或已验证能力。
- S06（libfile_78315d675ea0819199fc1ec58d762e76）：地图、聚合标记、缩放按钮、地点选择 chip、选中地点摘要、OpenStreetMap attribution。两处相近地点却显示世界尺度，当前视口并非合适的可用性范例。可见版权标注不证明具体地图 SDK。
- S07（libfile_c8cf7c7fb68c819198d78cf8414280bb）：同一列表中有普通行、带箭头链接行、带勾选的 Send Message 行、日程示例行和邮件示例行。日程/邮件只是展示，不证明连接真实账户。
- S08（libfile_fb404ba025208191b0563f5774d96289）：单题四个纵向选项；标题称 HTML 交互组件，文案称自动保存、可读回。不能仅凭这些文字断定 WebView、JS 桥或存储实现。
- S09（libfile_cfa6aab3734881919ecb950cdfc384d0）：用户气泡有表情反应；正文介绍交互组件；固定顶部吉祥物与菜单、底部输入框和导航一致。
- S10（libfile_34dc734b55408191a74acd83343bb3ad）：吉祥物换成工作姿态，显示“正在回复”；输入区有停止按钮。截图不能证明停止能取消服务端工作或回滚已完成动作。

可见共性：左侧大圆角灰色回复、右侧淡蓝用户气泡，组件嵌在消息流中。不可照搬的问题：大吉祥物/透明顶栏遮盖正文，向下浮钮压到正文和选项，长题组缺少可见的答题进度与未完成提示。Muyon 继续采用已确认的柔黑/柔白背景、少量耳棕和低饱和强调色；角色顶部有安全留白，不能覆盖操作目标。

## 3. Muyon 复用核查

本次只读核了固定提交 f4781e16ddf4e542b983fbd77f266a0071148255 的 MainActivity.kt 和 ChatScreen.kt。并非对整个仓库重新审计。固定源码：

https://github.com/mightyoung/Muyon/blob/f4781e16ddf4e542b983fbd77f266a0071148255/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/ChatScreen.kt

- L40–45、L82–106：已存原请求身份并有会话作用域回调保护。新卡片不可跨会话复用失效确认。
- L117–151：chat_lookup 查询原结果；未知保留费用并不重发；cancelled 文案明确已外发请求仍可能保留费用上界。应统一投影到 ReceiptCard，不能新建第二套“成功”状态。
- L153–172：chat_prepare 与 chat_tool 分开；工具失败/作用域改变时不自动重试。可复用 ActionDispatcher 边界，但需提取类型化 UI 适配器，而不是把 model-supplied action 直接当 IPC 方法名。
- L174–211：业务回执核 intent、协议版本、scope 和 committed；原回执只代表历史事实，不等于当前记录状态。
- L292–299：已有搜索结果 Card，展示 title/url/snippet/summary。建议扩展其呈现，不重复造数据来源。
- L307–313：已有 AgentWorkflowSurface。进度与停止由其权威任务事件驱动，不由吉祥物动画推断。
- L396–424：已具请求预览、保留上界、完整外发内容、send_allowed 门控；保存原请求身份成功后才能确认。
- L425–467：业务修改与结果披露独立确认；参数含 scope、digest、expected_revision 和 intent_id。新卡片必须复用两道独立审核，不能合并成“继续”按钮。

这些是已有代码路径，不是本轮已通过端到端实测。生产费用证明仍不能被 UI 绕过。固定提交和当前分支是否一致，应在实施前再核。旧 PX 规格及既有任务不据此宣布完成。

## 4. 统一组件契约（独立设计，不是 Muse 逆向结论）

每个块最小字段：schema_version、component_id、message_id、conversation_id、project_id、kind、revision、source_ref、payload、actions。状态另存 state_revision、values、status、last_intent_id、receipt_ref；模型只能提出内容，宿主验证和持久化。

Action 分为 local_edit、open_source、compose_message、submit_local、request_host_action。每个 action 有稳定 action_id、参数类型、目标范围和无障碍标签。默认快捷回复先填入输入框；明确标为“发送…”的低风险按钮可经用户点击走现有发送预览。发送自然语言不等于授权它所描述的外部动作。

状态机：draft → validating → prepared → awaiting_confirmation（需要时）→ running → succeeded/failed/cancel_requested/cancelled/unknown。unknown 不是 failed；先用原 intent_id 查回执。取消请求不等于取消成功，更不等于回滚。控件重新打开从持久状态恢复，不从显示文案猜测。

幂等：提交前固定 intent_id，绑定组件修订、会话/项目和参数摘要；重复点击返回同一回执。参数或作用域变更使旧确认失效。自动保存须有“保存中/已保存/保存失败”，用 compare-and-swap revision 防止后台回调覆盖新答案。重做创建新 attempt，不抹除已提交历史。

通用失败：无效 schema、超长内容、未知 action、来源失效、缺权限、版本冲突、存储失败、超时未知分别展示；保留用户草稿。扩展未知版本降级成不可操作说明，不能执行任意脚本。

## 5. 稳定改进任务 MU-01–MU-10

### MU-01｜类型化消息块与安全动作分发（P0）
把已有文字、来源列表、任务与回执映射到有限 kind；禁止 payload 任意指定 IPC 方法、URL scheme 或权限。复用 ChatScreen 的 prepare/tool/lookup，先建适配器再渐进迁移。验收：未知类型安全降级，伪造动作不触发工具，跨会话 action 拒绝，超长块不阻塞。关联 PX-04、PX-09；既有任务 7/9 的展示接线，不替代真实工具闭环。

### MU-02｜列表、来源链接与快捷回复明确分型（P0）
schema：row_id、title、subtitle、row_kind、source_ref 或 visible_message。普通行只读，链接行展示目的地并保留返回锚点，发送行明确“发送”。状态含 idle/pending/sent/unknown，不以本地勾选冒充发送成功。重复发送按 action intent 去重；取消草稿不删历史；失败保留文本与原请求查询。验收：点击不同类型不会串行为；来源失效有可见错误。关联 PX-02/04/09，任务 7。

### MU-03｜本地可编辑表单/练习卡（P0）
schema：fields、允许选项、校验、attempt_id、state_revision、提交规则版本。先支持 single_choice、text、checkbox，而非任意网页。自动保存只写本地状态；提交和判分为不同动作。客观规则明确时可本地确定性评分；模型判分必须标 AI 评估，不能冒充标准答案。重做保留旧 attempt。验收：杀进程重开、乱序保存、双击提交、缺选项、存储失败均正确；本地提交不会产生模型请求。关联 PX-07/08/09；不自动增加正式科研真值。

### MU-04｜卡片内持久回执与恢复（P0）
schema：intent_id、operation、scope、status、receipt_ref、occurred_at、known_cost/held_cost。复用已有查询原结果/业务回执；未知时显示查询，而不是“再来一次”。取消入口显示是否尚未开始、请求取消中或实际取消完成。验收：网络断连、确认后进程退出、重复回调不重复写；历史回执和当前记录状态分开。关联 PX-03/09/10，任务 6/7/8。

### MU-05｜安全业务确认卡（P0）
完整展现目标、字段变化、expected_revision、外发目的/接收方、费用范围；批准修改和批准披露分开。普通快捷回复、reaction、表单选择不能充当危险动作授权。版本改变重新 prepare，取消不提交，unknown 查原意图。验收：摘要与实际字节不一致拒绝；换会话/项目/参数旧批准失效。关联 PX-10，任务 6/7/9。

### MU-06｜任务状态、吉祥物与停止联动（P1）
角色姿态只投影真实 queued/running/waiting/failed；停止按钮绑定具体 task_id/attempt，显示取消确认与回执，不把整个会话当可回滚事务。并发时停止目标清楚，离线或失联显示未知。顶栏预留高度、输入框与浮钮避让；大字体和 TalkBack 可操作。关联 PX-03、任务 8 与 UI 重置。

### MU-07｜表情与轻量反馈（P1）
schema：message_id、reaction、actor、revision。幂等设置/撤回，失败回滚本地乐观显示并提示；不触发模型费用。明确“反馈”不是新的授权。验收：跨消息/跨用户不能错位，重启保持，多次点击不生成多个业务动作。与既有任务无直接业务能力绑定，属 UI 质量改进。

### MU-08｜聊天组件与长期成果分层（P1）
组件属于 message+attempt；Artifact 属 project+artifact_id+revision，保留来源和更正。先复用项目/PDF/快照，不引入第二套资料库。转为成果是显式操作，重复点击同 intent 不重复存；失败保留原组件；删除/修改遵循既有权限。验收：聊天删改不悄悄改成果版本，同名附件不串源。关联 PX-01/02/08，任务 9。

### MU-09｜地图/专门领域卡按需增量（P2）
地点 schema 含稳定 place_id、坐标、来源、精度/时间；地图选择只是本地 view state，打开导航另有明确目的地确认。先适配边界和无地图列表降级；保留 attribution，核瓦片/SDK许可及费用，不凭截图选择依赖。默认 fitBounds 到所有有效地点，拒绝无效坐标。不要求定位权限即可浏览已提供地点。日程/邮件/商品卡先作为只读展示，不因此获得账户读写或购买权限。关联 PX-05/06/10。

### MU-10｜受限 HTML 扩展实验（P2，须单独评审）
只有原生 schema 无法覆盖的低风险交互才考虑沙箱。独立 origin、禁止任意网络/文件/导航/反射接口、CSP、资源和执行时限，桥接仅传类型化 state patch/action proposal；宿主再校验并确认。JS 不持有密钥、不直连 Service。序列化状态与渲染内容分离；失效降级只读。验收包括脚本注入、恶意 URL、跨组件读写、桥接伪造、无限循环、断电恢复。不能依据 Muse 文案假定它已实现这些防护。关联任务 9，非首批阻塞项。

## 6. 最小落地批次与验收门槛

批次 A：MU-01/02/04/05，并复用 PX-02/03/04/09/10。先在当前代码真实数据和本地固定样例上，完成“来源列表 → 预览动作 → 取消/确认 → 原回执”链路。不依赖新的模型费用证明，不打开付费请求。

批次 B：MU-03 + MU-06/07/08。增加本地表单状态与稳定视觉反馈，检验重启、多会话、无障碍、长文本和后台恢复。用脱敏教学样例，不把测试答案当研究人工真值。

批次 C：有具体需求再评审 MU-09/10；不为复刻 Muse 一次加入地图、邮箱、支付、WebView 和插件平台。

共同验收清单：
1. 相同 intent 双击/重放只有一次提交；参数修订有新批准。
2. 断网/进程退出后 unknown 保留，查询原结果不重试写。
3. 切换会话、项目、Agent 后旧回调不更新新页面或开放确认。
4. 组件保存失败明确提示，用户输入不丢；已提交 attempt 不静默覆写。
5. 停止不宣称已回滚；外发后费用与预占未知不显示为零。
6. 200% 字体、TalkBack、长列表、旋转、软键盘下均不遮挡按钮。
7. 嵌入文本/脚本/链接无法获得工具权限；未经批准外发保持为零。
8. 每项“通过”须有实际测试命令、结果和固定 SHA；此报告本身不代表这些测试已执行。

## 7. 复用边界

优先顺序：Muyon 现有 Compose 与宿主协议 → 已确认许可证的现有依赖 → 独立实现交互机制。Muse 包可用于静态理解结构与验证截图归属；即使可反编译也不把专有实现、资源或标识复制进生产。未知许可标“未核”，不得用“能看到代码”替代可复用许可。依赖新增必须查仓库许可证与具体版本，不能凭产品名推荐。


# 附录 A：包内静态实现证据

日期：2026-10-22。仅下载和离线解析；未安装、未执行 APK，未调用其接口、未使用账号凭据。以下是包内实现证据，不是运行验收或服务端安全审计。

## 文件与身份

- 来源：用户 Drive apk 文件夹中的 base(1).apk，https://drive.google.com/file/d/1U8RgVCVXvavevoCEeNKs9H2Tf6k1Vjc6/view
- 文件大小：42,279,886 bytes。
- SHA-256：c7e788b5df855912dffbefc4c017f2e621b54aaeef954424f56339bd994fcefa
- Manifest/resources：app label Muse；package com.facebook.aura；versionName 11.0.0.8.164；versionCode 1061601403；minSdk 29 / targetSdk 36。
- 这是这个用户提供文件的身份与指纹，不等同于已向厂商核实签名或证明最新版本。
- Library 中 Muyon-Muse-UI-d3572ea5-offline.apk 是 Muyon 产物，不是本研究的 Muse 标记包。

## 关键实现证据与可借鉴设计

所有类以下均以 com.facebook.aura 为前缀。本次解析记录了 DEX 类定义、字段、方法签名、方法内部 const-string 与 invoke 引用；只列类名但没有定义的字符串未用于确认实现。下面给出 DEX 文件与类/方法定位，可对同一 SHA 的安装包复核。

1. 插件式展示，而非把所有交互都塞进 Markdown。
   - classes.dex：conversation.widget.api.ConversationWidgetRenderer 有 canRender；ConversationWidgetRenderers.rendererFor 调用 canRender。
   - conversation.widget.api.ConversationCardControls 字段 onAccept/onDecline/isEnabled/containerShape/backgroundColor。
   - classes2.dex：gateway.parser.HatchWidgetTokenParser 将正文拆成 TextPart 与 WidgetTokenPart，存在 dropIncompleteTrailingToken，处理流式文本尾部不完整占位符。
   - 建议 Muyon 用自己的结构化消息 parts + renderer registry；不要把模型正文当授权凭证，且无需照搬对方占位符格式。

2. 选择组件有真实状态和锁定检查。
   - classes2.dex：model.OptionWidgetData 字段 options/buttonStyle/composerHint/customInputPlaceholder。
   - classes.dex：conversation.view.HatchOptionWidgetKt.HatchOptionWidget 调用 HatchOptionButton；后者调用自有 AuraButton 和可访问性/触觉相关组件。
   - classes2.dex：conversation.viewmodel.GenericListSelectionDelegate.select 先调用 repository.captureWidgetState，再调用 model.GenericListPresentationKt.genericListSelectionLocked，创建 HatchSendMessage 与 GenericListSelection。
   - 建议为选项卡使用稳定 id、选择状态、提交中、已锁定、失败重试；输入兜底与按钮外观分开。

3. Widget 更新是独立版本化状态，不只是发送一句聊天文本。
   - classes2.dex：conversation.repo.WidgetStateSetRequestJson 字段 widget_id/base_version/mutation_id/state；Response 字段 applied/state。
   - WidgetStateSyncSlot 字段 committedState/optimisticStateData/pendingStateData/isSyncing。
   - HatchConversationRepository 定义 captureWidgetState、applyWidgetStateIfCurrent、applyConfirmedWidgetState、persistWidgetState、reconcileWidgetStateEvent、syncNextWidgetState 等；persistWidgetState 调用 setWidgetStateDocument，包含未收敛/rebase 诊断信息。
   - 建议采用版本检查、幂等 mutation id、乐观与已确认状态分离、冲突合并与回滚。仅凭字段不能证明服务端严格幂等或全部竞态已解决。

4. 审批是独立专用链，不与普通选项混同。
   - classes2.dex：agentpermission.AgentPermissionPendingCardKt 含普通、BrowserTaskConfirmation、Checkout、FlightCheckout 多种审批卡函数。
   - AgentPermissionApprovalsViewModel 字段 approvalsRepository/historyRepository/historyState/submittingApprovalIds/uiState；submit 创建 submit 协程，该协程调用 HatchAgentPermissionsRepository.decideApproval。
   - gateway.ApprovalPresentation = BLOCKING/NONBLOCKING；AgentPermissionRequestPresentation = DETAILS/INLINE。
   - 建议审批卡由可信业务对象驱动，明确对象、后果、允许/拒绝、提交中与历史回执。存在独立链不代表已证明其服务端授权安全性。

5. 表单用字段 schema 与统一校验，而非每张卡自写输入框。
   - classes3.dex：checkout.ui.HatchFormField 字段 id/kind/isRequired/initialValue/options/placeholder/format/validate/trailingIcon 等。
   - HatchFormState 持有 sections、trailingSections、values、collectedValues；isSubmittable 调用 allFields；seed 调用 formattedInput；reformatDependents 处理依赖字段。
   - HatchFormFieldKind 覆盖 TEXT/NUMBER/EMAIL/PHONE/姓名/地址/银行卡字段。
   - classes2.dex：HatchSelectableOption 独立 id/isEnabled/isLoading/title/subtitle/trailingText/leadingIcon。
   - 限制：此证据证明 checkout 的 schema 表单基础设施，不证明截图中每种问卷均由该类实现。Muyon 应先实现普通非敏感字段，不因为存在支付字段就移植支付流程。

6. 原生之外另有 HTML widget 桥。
   - classes3.dex：conversation.view.richcontent.WidgetJsBridge.onWidgetState 调用 parseWidgetState，识别 chat-widget-state / set_state；onWidgetHeight 调用 clampWidgetHeightPx。
   - WidgetStateJson 字段 type/action/state；HatchWidgetWebViewKt 有 createWidgetContainer、buildWidgetHtml、fetchWidgetDocument、widgetDocumentUrl；离线代码显示主题、尺寸与状态同步处理。
   - 建议首期优先白名单原生组件。若后续做 HTML widget，应独立设计隔离、导航白名单、消息 schema 校验和有限权限桥，不能把反编译得到的 WebView 片段直接拿来当安全实现。

## 复用边界

可复用架构思想、交互状态机和测试设计；不把专有反编译代码或 Muse 资产直接复制进 Muyon 生产。可独立实现自己的 schema、registry、状态同步和审批组件。未发现/核实 Muse 项目开源许可证；不能把 APK 可读等同于代码可复用授权。



补充身份限制：com.facebook.aura 这一包名本身不能证明厂商或产品身份。本报告只确认用户 Drive 文件内部标签为 Muse，未进行官方签名/发行渠道对照，不称其为已认证官方包。截图未提供版本号，因此不能确认截图由这一版本产生；包内存在实现亦不代表对该账号启用。服务器保存、判分、授权及费用逻辑未验证。

证据到任务映射：Renderer/TokenParser → MU-01；Option/ListSelection → MU-02；版本化 WidgetState/SyncSlot → MU-03/04；独立 Approvals → MU-05；WidgetJsBridge/WebView → MU-10。MU-06–09主要源于截图观察及 Muyon 自身需求，不冒称全部由包内调用链确认。
