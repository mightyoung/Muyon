# Muyon 架构与详细改造方案

桌面 Electron　Android Kotlin Compose　共享 Rust 本机内核

第一册　设计版本 1.3.1　｜　2026年10月14日 北京时间

本文面向 Muyon 的产品决策、架构拆分和后续实施评审。目标是把助手、科研与 PDF、询价业务组织成可持续使用的双端产品，并明确从现有 Flutter 与 Dart 代码迁移的顺序、验证标准和风险边界。

核心结论：保留一份 Rust 业务与执行语义，分别建立桌面和 Android 原生交互；先完成“只读业务切片 → 受控单项写入”的闭环，再逐模块扩展。真实历史数据切换与新增跨设备同步继续后置；已有记忆、经验、整理、业务交换和设备功能仍逐项迁移，首阶段使用隔离测试数据。本次交付为MD设计修订。用户已明确在设计确定后开始改造；实现任务须先关闭文档阻断并按第8章门禁推进，本文不把授权开工写成产品代码已实现。

阅读导航：第1至3章看决策、参考与当前源码；第4至6章看架构、合同与安全；第7章连接页面手册；第8至10章覆盖首片、全业务波次与验证回退；第11章列风险和待定决策，第12章逐项记录评审处理。逐页布局、字段和交互规范见第二册《Muyon 逐页设计手册》。

## 1 决策摘要与范围

### 1.3.1变更摘要

1. 修复Claude v1.3采纳评审指出的两项文档阻断：继承Sensitivity分类与禁外发规则来源；将D01.3纠正为远端公司资料中心Hub
2. 记录最新产品决定：正式只读/每次询问/Auto/全部允许四档，新装默认Auto且旧配置不升权；全部允许模式下，personal/commercial默认可在当前任务与既有权限用途内进入模型或业务外发；unreviewed在可信分类前不外发；credential不进入模型或业务正文，受控认证通道另行绑定
3. 将设备消息与既有跨设备研究任务登记为必须显式交代的迁移功能；区分任务提议、接受、本人授权导入研究说明、人工研究及结果回传，不扩大为远端自动执行
4. 纠正新增能力状态：既有聊天已持久化并可取近期上下文；自动记忆提取器、跨会话助手历史检索、可选聊天留存控制尚无对应生产链路，自动提取与跨会话检索已决定纳入、首次默认关闭且分别开关；未实现时未提供，可选留存控制仍待决
5. 统一未知效果规则：先核对且绝不自动重发；用户明确再做一次时可建立可信关联的新意图，内联提示可能重复，旧unknown保留且FullAllow不额外确认；保留本机导出新副本额外约束，不能由本机例外自动推导远端原调用重放；用户明确新意图按本轮可信关联合同
6. 新增D03a最小恢复合同作为M03前置，从既有恢复估算中前移2–4人日，消重后首片52–79、后续D36–64、W300–575，重分配本身不改变388–718总额；新增D11自动记忆/跨会话检索净增18–34，整体改为406–752人日，均为低置信规划
7. 用MIGRATION-TRACE补齐8份遗漏决定与专项合同，登记ADR-AUTH-01/02的唯一建议落点；只修设计，不声称已改变生效ADR或完成文档切换
8. 保留v1.3全部原25例及新增15例，增加本轮针对分类、Hub、设备、恢复前置与本机副本例外的验收门槛，均未运行

### 1.3变更摘要

1. 保留1.2全部迁移单元、既定技术路线和已定模式；在主合同、迁移、开发任务和验收中融合 MEMORY-LIFECYCLE-04 与 RECOVERY-TRACE-03，不以附录替代正文
2. 记忆继续使用 MemoryRecord、MemoryCurationRun、CurationProposal；补齐对象版本谱系、同版异内容冲突、四控制、会话内部不自动写入及在途策略变化
3. 恢复前先保全当前旧墓碑和域外遗忘凭据，再合并候选备份；按 identity、来源和 lineage 判定禁止集合，不把条目 revision 与遗忘 generation 比大小
4. 明确恢复的展示、模型请求和工具效果三层；同一持久 scope 的事件流增加存储身份与日志身份校验，快照水位与投影内容一致提交，保全未送达输入
5. Stop、执行进度、每项效果和历史完整性分轴；旧代际只限制展示接纳，真实迟到回执仍核对入账；未知非幂等效果不盲重放，也不变成全部允许的额外确认
6. 保持最近完成整理运行及完整 fingerprint 未变的整次回滚门槛，补偿写新版本；保持摘要版本、工具调用与结果配对、当前权限和遗忘过滤
7. 逐项处理记忆11例、恢复14例，另列15条新增故障反例；全部是待实现验收，不是通过率或现成功能
8. 将竞品客户端静态观察、作者推断、公开API说明与Muyon工程设计分开，保留固定源码、报告哈希及取证限制；更新D系列净增预算及入口门禁

本版保留1.2中B1至B3、I1至I10、S1至S7、执行摘要及AUTH TRACE的逐项处理。代码事实仍以固定产品SHA为准；本轮没有产品代码、产品测试、APK动态复现、模型实验或发布。新合同均为后续实施目标。

### 明确决定与待决边界

| 事项 | 当前结论 | 对本版的约束 |
| --- | --- | --- |
| 技术路线 | 已确认 | Electron桌面、Kotlin Compose Android、Rust本地离线内核 |
| 生成卡交互 | 已确认 | 已有卡片本地交互直接响应；确定性业务动作进Rust；理解或重规划才另调模型 |
| 全部允许 | 已确认 | 已选工作区和现有访问权限内免额外询问；高风险和此前未用的新网站/API均不追加确认 |
| 独立Auto | 已确认 | 与其他档位并列；规则判低风险自动、高风险确认、禁止类拒绝 |
| 正式模式与默认档 | 已确认 | 只读、每次询问、Auto、全部允许四档；低风险并入Auto，新装默认Auto；旧配置不自动扩大权限，迁移细则与期限仍需冻结 |
| 来源和新端点边界 | 全部允许含新目的地已确认 | 此前未使用的网站/API不追加首次询问；ADR-AUTH-01记录旧规则替代，保留数据用途与权限边界 |
| 外发数据类别 | 已确认 | FullAllow下personal/commercial在当前任务范围默认允许；unreviewed可信分类前不外发；credential不进入模型/业务正文，认证通道分离 |
| 内容复核映射 | ADR-AUTH-02待决 | 分开风险意见、确定性硬限制和复核不可用，禁止隐形确认 |
| Android屏幕读取 | 待决 | 不默认实施、申请权限或承诺持续后台读取 |
| 临时会话与记忆容量 | 待决 | 先分开能力合同，是否启用、配额和清理策略另定 |
| 个人账号限定 | 待决 | 基线有Hub与只读MCP服务共享能力；不预设仅个人账号，也不承诺完整组织多租户支持 |
| 自动记忆提取与跨会话历史检索 | 已确认纳入整体改造 | 首次默认关闭、分别开关，独立D11排期不阻塞Rust首片；未实现时未提供；可选聊天留存控制仍待决 |
| 既有设备消息与研究任务 | 迁移排期待决 | 已登记S05.1/W5，不无声取消；迁入或暂留旧端须明确决定 |
| 未知效果下用户新意图 | 已确认有条件提供 | 先查核不自动重发；用户明确再做一次可形成宿主绑定的新操作，内联可能重复、旧unknown不变、FullAllow零额外确认；其他模式照常 |

“全部允许”是产品内的免确认模式，不是模型获得自行扩权的能力。系统和第三方不可绕过的限制、现有访问权限、用户撤销、版本和回执校验依然有效。此产品语义不改变后续工程在真实设备、账号和数据上的独立执行授权。

### 已确认的技术路线

| 层级 | 本次路线 | 边界 |
| --- | --- | --- |
| 桌面应用 | Electron | Windows 和 macOS 为待验证平台；React 与 TypeScript 是本方案推荐界面实现 |
| Android 应用 | Kotlin 与 Jetpack Compose | 采用平台原生导航、输入、文件和生命周期能力 |
| 共享内核 | Rust 本机 core | 领域规则、任务、存储、权限、执行账本及契约语义共用 |
| 未来 iOS | Swift 与 SwiftUI／UIKit 接入位置 | 仅预留接口，不列入本批实施和工期 |
| 数据与同步 | 每台设备独立本地存储 | 正式旧数据切换和新增全局同步后置；既有设备消息/研究任务逐项保留迁移归属 |

桌面和手机运行同一 Rust 内核的不同平台构建，各自持有本地数据库与账本。“共享内核”指共享代码和合同，不意味着两台设备自动共享数据、审批或运行状态。桌面 Rust 采用受控侧进程；Android 将 Rust 库嵌入应用，不增加一个常驻 HTTP 后台。

### 本方案要解决的问题

- 助手说清正在做什么、需要用户决定什么，并把最终产物放回有身份、有版本的业务对象
- 科研能够从问题走到证据和可编辑结论，PDF 能从选区走到可核对字段，询价能从条件走到比较、草稿和台账
- 两端共享业务真值、错误和恢复语义，避免在 TypeScript 与 Kotlin 各建一套规则
- 权限、幂等、商敏投影和回执在可信内核闭合，不能靠 UI 按钮状态或模型自述保证安全

### 范围与阶段边界

同步后置特指新增的全局任务、权限、审批与统一数据协调。现有询价交换、文件夹/LAN传输、设备消息及跨设备研究说明/结果交换均为独立迁移对象，登记S05.1/W5；具体新端开放排期可待决，但不能把“仅保留旧Flutter”或退役写成已决定，不能借同步后置删除原业务。

本批方案覆盖产品结构、页面行为、跨语言合同、单设备本机执行、分阶段迁移、测试和回退设计。现有 Flutter 体验版保留为参考与回退入口；已有任务不因选型变化自动取消。真实生产数据切换、云服务部署、数据同步、完整 iOS 客户端和所有功能的全面迁移不进入首阶段承诺。

28项任务估算只用于首个可验证闭环的拆分。尚未完成全模块成本盘点、设备矩阵和实际工程速度测量，因此不能据此承诺“一月全量迁完”。

## 2 参考证据与当前代码事实

### 参考产品如何用于 Muyon

| 参考 | 有证据支持的观察 | Muyon 采用方式 |
| --- | --- | --- |
| Muse | 官方展示图呈现目标、活动记录与明确审批 | 用任务面板、活动时间线和可信审批呈现后台行为 |
| Claude | 官方帮助文档把可持续编辑的产物与对话关联；移动招聘明确原生技术要求 | 把产物做成稳定业务对象；Android 采用 Kotlin Compose |
| ChatGPT | 官方 Projects 文档组织相关对话、文件和项目上下文；Canvas 承载持续编辑 | 项目成为上下文范围，结果能打开工作台继续编辑 |

Muse 官方视觉素材已经查看；Claude 与 ChatGPT 的本轮参考主要来自官方文档，未做 Android 实机交互验证。竞品截图能支持信息组织和视觉判断，不能证明其内部权限、任务恢复和技术栈实现。本文所有页面与架构图均为 Muyon 原创方案，不是竞品截图复刻。

[Muse 设计说明](https://introducing.muse.ai/)　[Claude Artifacts](https://support.claude.com/en/articles/17153992-what-are-artifacts-and-how-do-i-use-them)　[ChatGPT Projects](https://help.openai.com/en/articles/10169521-projects-in-chatgpt)　[ChatGPT Canvas](https://openai.com/index/introducing-canvas/)

### Claude 移动端框架的证据强度

Anthropic 的 Android 官方招聘列出 Kotlin、Jetpack Compose 与 Android SDK；iOS 招聘列出 Swift、UIKit 与 SwiftUI。结合 Mike Lewis 早期关于原生 Swift／Kotlin 的公开说明，可支持“以原生移动栈为参考”的选择。招聘要求和公开说明不构成当前客户端全部模块的源码审计，不能推断所有屏幕都只使用某一个 UI 框架。

[Android 官方招聘](https://job-boards.greenhouse.io/anthropic/jobs/4899511008)　[iOS 官方招聘](https://job-boards.greenhouse.io/anthropic/jobs/4572744008)　[Mike Lewis 公开说明](https://www.linkedin.com/posts/mikerlewis_careers-activity-7173804945295466497-JDNw)

Muse 移动端内部框架目前没有足够可靠证据，因此只作为交互参考，不写成 React Native、Flutter 或原生框架的已知实例。

### 竞品证据的更正与采用边界

Claude当前记忆帮助页区分新版与legacy体验：新版按主题管理记忆，旧版摘要每24小时更新的描述仅适用于legacy，不能作为全部用户的现行机制。Muyon据此把“结构化记录、用户可读编辑、历史检索”分开设计，不照搬更新周期。[Claude聊天搜索与记忆](https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context)

Claude可分享包含MCP使用的聊天快照；官方说明隐藏原始MCP工具数据，但保留最终回答与对话。隐藏raw结果并不能证明回答不含敏感信息。Muyon的分享或导出必须再次按目标受众投影，并检查正文、引用和附件；不能依据“原工具结果未显示”就开放分享。[Claude分享说明](https://support.claude.com/en/articles/10593882-share-and-unshare-chats)

ChatGPT静态材料中的DIL8动作只是一份观察到的动作清单，不是ChatGPT全部交互能力的上限。官方Apps参考明确提供组件调用工具的callTool能力，工具的标准可见性默认包含model与app；组件可发起工具调用，不要求每次都重新让模型理解。“回模型”不是授权安全边界，schema验证和沙箱也不等于业务授权。[OpenAI Apps参考](https://developers.openai.com/plugins/reference)

Meta官方Muse安全说明已经描述宿主侧Sentinel作为连接器动作与网络出口权限权威，并按目的、连接器或目标及许可范围检查后续调用。Muyon采用Rust可信授权与目的限定投影，是针对本地双端产品的具体取舍，不声称这一原则由Muyon首创。[Muse安全架构](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)

静态竞品代码或研究报告中的INSERT OR IGNORE至多提示某张表有去重登记，不能证明外部效果至多一次。必须进一步验证登记、派发、回执与崩溃恢复的完整链，才能描述相应保证。本文第5章的账本方案是Muyon待实施合同，不由竞品截图、方法名或单条SQL证明已经有效。

### AUTH TRACE 02 增量证据

[PR69固定研究材料](https://github.com/mightyoung/Muyon/tree/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference)补充了Claude认领先于执行、Orbit参数摘要与比较、Code/Muse审批决定的smali摘录，已超出单条SQL或字段名线索。1.2历史核验时PR为open、未合并，当时head为3c9ac395ac8424e9e43b58381fb5001bd1f30821；它是当时研究证据；1.3当前研究head见后节，均不替换Muyon的01e56cc2产品代码基线。片段仍省略关键分支，未取得完整APK/反编译物或动态结果，不能称独立复现。第12章列逐项证据上限与采纳方式，PR内旧SUMMARY中的四档、仅个人、新端点先问等过期主张不覆盖本轮产品决定。

### 记忆生命周期与恢复报告的证据边界

新增输入为用户提供的《MEMORY-LIFECYCLE-04》和《RECOVERY-TRACE-03》。两报告分别提出11条记忆用例和14条恢复故障用例，本版在第10章逐项修订后纳入验收。报告涉及 Muse 11.0.0.8.164、Claude Android 1.261009.20、ChatGPT Android 1.2026.272；均是作者静态分析。部分反编译方法缺失、部分样本仅base APK、ChatGPT的jadx约66%中止。本轮读取报告及表格，没有取得其全部新证据片段或运行APK；“包内直接证据”仍是作者分级，不升级为本轮独立复现。

Muse所见整文件覆盖、Claude所见指令式记忆编辑可用作CAS设计的反例，但缺客户端版本字段不证明服务端无锁；StateFlow内存CAS也不等于远端写入CAS。删除聊天或断开连接后“可能仍记得”，应理解为不保证清除全部派生记忆，而非证明所有对象都完全不传播删除。工具活动行与模型“已记住”的回复均不足以证明持久提交。

恢复证据必须按普通聊天、远程Code会话、设备命令和审批集合区分。Claude的complete_blocks/fingerprint不证明所有正文永不回退；消息已完成分支、同计数异正文、合法撤回都需另核。ChatGPT所见offset先持久化后分发只提示条件性窗口，不是实测丢失；Muse审批HTTP/WS门控不等于聊天流共用持久游标。Claude已有本机client tools证据，不能说只有Muse执行手机工具；流服务未显示工具执行也不能概括整个ChatGPT App。

公开API或开源app-server说明不能证明Android App私有协议。JSON事件未含id字段，也不足以证明传输解析层不处理SSE id。关于NOT_STICKY、快照头指针和去重的绝对结论在第12章逐项收窄；Muyon的合同由自身故障测试证明，不借竞品观察宣称正确。

来源定位采用报告M、R及Word文档顺序段落号（包含表格，不是页码）；原附件SHA-256：M为7a0e774206273632f59f5e128be108ce478595bf3a94f69a23492f4b97ee8a55，R为bcc82371f419ec75fa60c9af87b7df210277630872238dab7f9a6ba6145adbeb。研究材料PR69另固定当前研究head 190ddd88359a4f1a8f21f8d62d9186eb474137e9，仍未合入产品基线；新报告原文定位不冒充仓内已核源码入口。

### v1.3采纳评审及本轮核验范围

本轮输入为用户转交《Muyon v1.3 文档采纳评审》（Claude，2026年10月13日）。评审针对文档提交e014b097be94b48a6744c5d5df41a764918b0afa和固定产品基线01e56cc2，提出2项阻断、6项重要问题及5项建议。其“本次新增32文件”与固定提交比较不符，核验为22文件（7份正文/交接及包元文件＋15图），不沿用32。1.3.1对照同一产品源码和旧决定文件只读核验，按正文修订及第12章逐项回应处理；没有运行产品测试、真实模型、Hub服务、设备通信或故障实验。“有生产接线”不升级为“已部署上线”。研究与产品源码事实以各自固定版本为准，用户最新决定优先于评审建议。

### 固定代码基线

本版继续锁定 Muyon develop 历史快照：

01e56cc2d729dab70e1b1def05c3aa93b28f421a

该快照核验时间为2026年10月13日北京时间00:48；1.3不把历史盘点当作实时进度；正式评审报告另记2026年10月13日13:28:22 UTC读取develop同SHA，该外部报告的读取不替代本轮实时仓库核验。前次研究基线为 9836bb87e9f86a866ad05e83cee8beb9fe1eec8e，两者之间有19个提交。当前盘点与差异证据见第3章；历史链接仍按其原SHA引用，不把旧证据改名为新基线。分支名称和任务状态会变化，实施前须再次固定提交与在途所有权。

本次现状对路线的直接影响：supplier_core 的81个lib Dart文件没有直接Flutter或flutter_*导入，但仍依赖Dart运行时与平台库，因此优先复用规则与fixture；inquiry_module 的92个文件有84个直接UI或插件耦合，页面必须实质重建；LocalExportLedger虽有实现，当前未发现生产实例化，不能把本机导出当成已完成接线。第3章逐项给出文件、符号、测试和判据，第9章据此分8个业务波次。

## 3 当前源码盘点与迁移映射

### 证据范围与结论

本章保留原只读盘点及证据范围，并补充本版对授权、记忆和遗漏入口的固定源码核对。下文“当前”“在途”均指所列快照与时点，不是1.3实时仓库状态；实施前由M01重新核对差异。

本文件是迁移设计输入，不是实施报告。固定源码：`mightyoung/Muyon@01e56cc2d729dab70e1b1def05c3aa93b28f421a`，2026-10-12 16:48 UTC实时读取时为develop HEAD；与review/leader-a-batch-20261012c同SHA。旧基线9836bb87e9f86a866ad05e83cee8beb9fe1eec8e到此为ahead 19 / behind 0。所有源码定位都使用完整SHA，不链接浮动develop。

读取范围：GitHub递归tree共2127项，truncated=false；462份lib Dart/pubspec文件及29份选定测试已读取，并将491份内容与Git blob SHA逐份核对一致。分析为静态源码/调用关系/测试用例阅读，没有在本任务运行Dart、Flutter、Rust、Electron或Android测试，也没有变更仓库。未完整读过的测试明确只作为已存在的待迁移测试定位，不宣称通过。源码行号来自该固定SHA。

关键结论：要搬的是业务真值、授权和事务状态机，不是把Flutter Widget逐段翻译成React/Compose。最可复用的是supplier商业规则与ui_contract语义；最需拆开的是真实宿主生命周期、Flutter observable repository、UI controller内部publication原子操作、PDF/OCR和文件/secret平台能力。

### 静态耦合计数（直接import/export，非传递依赖图）

|包|lib Dart文件|直接Flutter或flutter_* import/export文件|迁移含义|
|---|---:|---:|---|
|apps/muyon|166|44|host虽有大量纯逻辑，但启动/数据通知/平台服务仍耦合UI|
|supplier_core|81|0|优先抽商业语义，仍需替换Dart运行时与第三方库|
|muyon_module_api|38|3|将ModuleSession/Widget页面合同与纯DTO/语义合同拆开|
|muyon_ui|27|21|两个原生实现重建视觉，权限/原子controller下沉|
|research_module|38|17|特别注意core中的Rect/pdfrx，不按目录名判纯净|
|inquiry_module|92|84|保业务能力与调用语义，页面重新设计实现|
|prototype_module|11|4|sandbox/webview另设平台适配与内容隔离|

计数正则针对import/export package:flutter/或package:flutter_，不包含dart:ui、part文件传递依赖和pdfrx等非flutter前缀插件；所以数值是可重现的直接耦合下界，不是“余下全纯净”。

### 23个可分派的迁移单元

每个“建议目标”都是本次设计判断，表示终局职责归属，不代表首片或本期全部实现；不是当前仓库已经拥有Rust crates或跨端IDL。首片使用隔离新测试库；物理旧库、旧收据与历史fixture转换/兼容验证统一受后置P3数据迁移门禁约束，未经授权不写真实生产目录。新增跨设备自动执行/审批同步另立方案；基线已有研究任务交换仍由单元17登记迁移。

#### 01. 宿主启动、模块注册与关闭

- 源码定位：[MuyonHost.open / close](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/bootstrap.dart#L227)；[ModuleHost.activate / revokeCapability / close](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/module_host.dart#L308)；[main](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/main.dart)
- 当前职责：宿主打开muyon数据库，挂接schema目录与中断恢复；构造模型、工具、授权、模块、知识和传输服务；依赖延迟闭包解决host与module互引；关闭时先撤销准入，再排空agent、传输、平台操作和模块，最后关闭存储。bootstrap传入uiPlanningEnabled:false，但PersonalAgent在presentationPreference非空时将harness enabled设为true，并由presentation模式、请求冻结、模型能力及授权另行gate；不能由这一个参数推断产品AIUI关闭。
- Flutter/运行时耦合：bootstrap本体没有直接Flutter import，但构造MethodChannelSecretStore并连接到Flutter host、FoundationRepository和模块页面；不能因此称它已经是跨语言可嵌入内核。
- 建议目标边界：Rust RuntimeOwner负责启动状态机、唯一服务/数据库寿命、ShutdownBarrier；Electron主进程与Android宿主只提供PlatformPorts与宿主生命周期事件。UI订阅RuntimeReady/ModuleStateChanged，不持有模块runtime对象。
- 现有测试：[module_host_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/module_host_test.dart)（已读取源码，未执行）；[model_capabilities_migration_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/model_capabilities_migration_test.dart)（已读取源码，未执行）；[module_lifecycle_regression_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/module_lifecycle_regression_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：先定义ports、错误与事件合同，再搬启动。恢复/导入/撤销期间的late callback与双重close是优先回归点；不要把close退化为简单kill进程。
- 迁移交付判据：相同数据目录只产生一个writer owner；两次close等待同一drain；启动失败不留下半打开模块；默认AIUI策略显式可配置且与当前开关语义一致。

#### 02. 存储所有权、事务队列与schema迁移

- 源码定位：[ManagedConnection.write / exclusiveAsync / StorageManager.open](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/storage_manager.dart#L13)；[ManagedDatabase / ModuleSchema](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/storage.dart#L1)；[host schema compatibility](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/host_schema_compatibility.dart)
- 当前职责：ManagedConnection使用BEGIN IMMEDIATE同步事务体、_tail串行队列、COMMIT后通知；exclusiveAsync允许整段异步排他操作但不自动在异步文件IO外再包事务；结构digest、连续迁移、ahead version拒绝、quiesce和close属于宿主。
- Flutter/运行时耦合：直接依赖Dart sqlite3 Database并通过ManagedDatabase.raw外泄连接；这不是适合跨IPC保留的接口。onCommit观察者失败已被隔离为commit_observer_failed，不会把已提交业务误报失败。
- 建议目标边界：Rust storage crate拥有连接池/单writer、短事务与migration registry；跨端只暴露typed queries/commands与revision，禁止renderer/Kotlin传SQL或raw database handle。先保持schema版本/digest校验与拒绝超前等兼容语义；首期在隔离测试库工作，物理schema与历史库转换作为后置迁移单独验证，不预设必须保留原物理表。
- 现有测试：[storage_manager_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/storage_manager_test.dart)（已读取源码，未执行）；[managed_connection_commit_observer_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/managed_connection_commit_observer_test.dart)（已读取源码，未执行）；[storage_recovery_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/storage_recovery_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：现有模块有自己管理的短SQL事务；不能一律套第二层事务。新旧进程同时写同目录会破坏唯一owner。旧库转换进入后置P3门禁时，需要真实旧库fixture与备份回退演练，而不只是空库建表。
- 迁移交付判据：保留事务体异常回滚、队列不毒化、postcommit观察者异常不改业务成功、close drain、schema超前拒绝；逐库比对表结构/数据/收据而非只比行数。

#### 03. module_api合同与插件边界

- 源码定位：[BusinessModuleV2 / ModuleSection](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/module_v2.dart#L10)；[ModuleRuntime / ModuleSession](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/module.dart)；[optional capabilities](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/optional_capabilities.dart)；[ToolRegistrar](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/tool_registrar.dart)
- 当前职责：统一manifest、ontology、capability coverage、辅助库、工具注册、会话、ObjectRef及导入等可选能力。v2扩展v1；inquiry adapter仍需HostToolRegistrar与ManagedConnection具体类型。
- Flutter/运行时耦合：module.dart/module_v2.dart/optional_capabilities.dart直接导入Flutter，ModuleSection.builder是Widget Function(BuildContext,host)，WorkspaceSectionHost直接返回Widget，存储合同带sqlite3类型。
- 建议目标边界：拆为Rust domain contracts、版本化wire DTO/IDL、端侧screen registry三层。SectionId/ObjectPageRoute替代Widget builder；Query/Command能力替代runtime泛型和raw DB；业务模块仍需声明能力与操作覆盖，不能把manifest当授权。
- 现有测试：[contract_v2_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/contract_v2_test.dart)（已核文件存在，未逐项读取/执行）；[write_contract_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/write_contract_test.dart)（已核文件存在，未逐项读取/执行）；[module_host_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/module_host_test.dart)（已读取源码，未执行）
- 风险与先后依赖：不能按package原封不动编译到Rust，也不能用同名TS/Kotlin接口假装已互通。需显式定义unknown field、enum扩展、nullable、64位整数、decimal string和版本协商。
- 迁移交付判据：Electron与Compose分别注册同一业务route ID；拒绝未声明能力；core不含Flutter/Widget/BuildContext/JS引擎/Kotlin UI依赖。保留Sensitivity字段声明及ADR-0004 Q7分类，缺分类为unreviewed；模型/插件不能靠改枚举自授披露权。

#### 04. supplier_core商业域：记录、价格、预算、比价

- 源码定位：[Store.save / delete / restore](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/store.dart#L378)；[micros / roundedDivide / priceInTaxMode](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/pricing.dart#L1)；[compareQuotes / priceHistory](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/compare.dart#L75)；[预算与BudgetLine](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/budget.dart)；[规格匹配](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/spec_match.dart)
- 当前职责：记录版本、字段变更、软删除/恢复、引用检查、报价有效性、单位/含税转换、阶梯价、成交价、预算与规格匹配。目前价格使用BigInt百万分定点，roundedDivide为半值远离零；不同币种不做FX；未知单位/税基保守返回不可比较。
- Flutter/运行时耦合：完整supplier_core/lib的81个Dart文件无直接Flutter或Flutter插件import/export；但仍依赖Dart IO、isolate、sqlite3、archive、crypto、pdf、xml等，属于“业务可分离”，不属于“零成本搬迁”。
- 建议目标边界：Rust supplier-domain + storage repositories。价格/数量使用Decimal6或等价定点类型，wire用规范十进制字符串；运算、有效性与比较排序为唯一核心实现，两端只格式化和输入。
- 现有测试：[pricing_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/pricing_test.dart)（已读取源码，未执行）；[store_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/store_test.dart)（已读取源码，未执行）；[spec_match_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/spec_match_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：最危险的回归不是UI像不像，而是舍入、阶梯边界、已成交快照、报价币种不可混合、暂停供应商、税率缺失的语义。先纯函数差分，再读写与exchange。
- 迁移交付判据：Dart旧实现与Rust对同fixture逐字段输出一致；覆盖负数半值、6位小数、税率缺失、数量跨档、同币种/跨币种、历史快照不被新报价污染。

#### 05. Folio询价应用状态、导入与业务页面

- 源码定位：[AppState](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/app/app_state.dart#L25)；[Section / build page switch](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/app/shell.dart#L24)；[InquiryImportPipeline](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/ai/import_pipeline.dart)；[InquiryBusinessModule / InquiryModuleRuntime](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/adapters/inquiry_module.dart#L32)
- 当前职责：AppState同时承接Store、AI jobs、sync、LAN、settings、hub/模型凭据及ChangeNotifier；inquiry adapter复用既有owner而不复制数据库；导入有prepare/commit/receipt，页面有项目、报价、供应商、产品、交换、数据中心与Hub。[Hub](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/hub.dart#L13-L16)是公司部署的可选远端共享服务，同事发布选定供应商/报价并搜索他人发布；不是本机公司主体资料表。迁移status、search、publication、history、preview、publish、reconcile及端点/凭据配置。
- Flutter/运行时耦合：92个lib Dart文件中84个直接Flutter/plugin import/export；AppState既是业务服务容器又是UI可观察对象。大部分页面不能机械翻译为Compose或React。
- 建议目标边界：把Store读写、导入流程、job协调和settings domain移到Rust；两端分别重建SupplierViewModel/ProjectViewModel/QuoteEditorState。输入焦点和临时编辑缓冲留在UI；需要恢复或跨页共用的草稿由内核持久化并版本化，正式业务验证与写入在core。
- 现有测试：[ai_import_resume_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/test/ai_import_resume_test.dart)（已核文件存在，未逐项读取/执行）；[host_attachment_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/test/host_attachment_test.dart)（已核文件存在，未逐项读取/执行）；[module_host_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/module_host_test.dart)（已读取源码，未执行）
- 风险与先后依赖：保留hosted/standalone的差异：当前hosted Ask入口会回Home，不要不经业务决策就恢复另一套独立agent。UI并非权限边界，需从core限制导入项目/工作区变化。
- 迁移交付判据：导入重新打开、撤销/丢弃、来源文件改变、工作区切换、重复commit和回执恢复有相同结果；页面改版独立于数据迁移。D01.3保留Hub未连接空态、远端搜索及来源/时间、发布预览/历史和结果核对；结果未知先查原发布，不自动重发；远端搜索记录不能自动成为本机供应商记录。

#### 06. 科研对象、卡片、大纲、人工运行

- 源码定位：[WorkbenchStore / scoped / manual runs](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/store.dart#L16)；[OutlineStore extension / deleteSection / cite](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/outline_store.dart#L29)；[CardStore](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/cards/card_store.dart)；[registerResearchTools](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/module_tools.dart)
- 当前职责：研究项目、文档、entry、批注、卡片修订、引用、大纲及task/run由真实本机存储维护；manual run只建/更新本机记录，不能当作远端执行能力。scoped/checkedProject/checkedObject承担项目边界。
- Flutter/运行时耦合：core/store.dart仍直接导入Flutter visibleForTesting；ResearchRuntime/ResearchSession既解析对象又返回Widget页面。目录名core并不保证框架无关。
- 建议目标边界：Rust research-domain统一版本、关系、删除影响与保存；两端NativeResearchViews消费route与snapshot。保留人工运行记录与未来执行器能力的独立状态，不把“已记录”显示成“已运行”。
- 现有测试：[research_runtime_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/research_runtime_test.dart)（已读取源码，未执行）；[reg3d_research_writes_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/reg3d_research_writes_test.dart)（已读取源码，未执行）；[section_delete_preview_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/section_delete_preview_test.dart)（已读取源码，未执行）
- 风险与先后依赖：大纲顺序、级联删除、evidence kind与digest必须兼容；迁移不可通过简化对象表删除现有批注/卡片/关系功能。需在域命令内检查scope，不能只依赖页面筛选。
- 迁移交付判据：同数据库fixture迁移后对象可逐个解析；删除影响预览与实际操作一致；manual task/run revision与外来来源边界保留。

#### 07. PDF阅读、来源锚点与引用定位

- 源码定位：[QuoteLocation / ExactMatch](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/source_locator.dart#L1)；[CitationResolver / PdfrxCitationPageProvider](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/citation_resolver.dart#L40)；[ReaderPage](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/reader_page.dart)；[SourceRef](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/source_ref.dart)
- 当前职责：引用定位区分PageOnly、ExactMatch、AmbiguousMatch、SourceUnavailable。ExactMatch保存左上原点0..1页面比例Rect；页跳转和精确高亮是不同承诺，重复文本不能猜定位。
- Flutter/运行时耦合：source_locator.dart以Flutter Rect作为跨层数据；citation_resolver.dart同时负责证据解析与pdfrx提取，直接导入flutter/painting和pdfrx；reader是Flutter Widget。
- 建议目标边界：Rust保留SourceRef、digest/revision检查、消歧和归一化几何DTO；DocumentTextPort提供页文本与字形rect。Electron PDF viewer与Android PDF原生view各自实现视口、选择、缩放/旋转坐标映射。
- 现有测试：[citation_resolver_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/citation_resolver_test.dart)（已核文件存在，未逐项读取/执行）；[citation_resolution_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/citation_resolution_test.dart)（已核文件存在，未逐项读取/执行）；[reader_evidence_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/reader_evidence_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：单纯重写阅读器会丢字符offset和旧锚点兼容。PDF后端选型是独立验证项，本清单不宣称已选定跨端库；不同文本抽取需固定parserVersion和fallback语义。
- 迁移交付判据：同一来源在两端命中同page/quote或同一保守降级状态；旋转/缩放高亮测试、重复文本、扫描件、替换文件、源删除全部覆盖。

#### 08. PersonalAgent执行、模型回合与工具调度

- 源码定位：[PersonalAgent.start / confirm / cancel / resume](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/personal_agent.dart#L59)；[AgentModelTurn.drain](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_model_turn.dart#L586)；[AgentDispatch.executeCard](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_dispatch.dart#L645)；[ExecutionStore](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/execution_store.dart)
- 当前职责：任务状态、预算、草稿、模型审批、流收集、工具卡片确认、取消/暂停/恢复和事件分散成协作组件。drain把ToolCallDelta仅作为展示，完整ToolCallComplete收集到结束后才由后续路径执行。
- Flutter/运行时耦合：agent多为Dart逻辑，但经FoundationRepository与host UI规划源间接依赖Flutter；Future/Stream/cancellation与renderer UI状态共享寿命。
- 建议目标边界：Rust AgentRuntime + durable task/event store拥有执行和恢复；UI直接处理纯本地展示交互；需要业务执行时发送明确Command，渲染TaskSnapshot/TaskEvent，理解或重规划才新建模型轮次。模型流、工具流、UI规划流分类型，不把所有流塞到无类型JSON日志。
- 现有测试：[personal_agent_streaming_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/personal_agent_streaming_test.dart)（已读取源码，未执行）；[personal_agent_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/personal_agent_test.dart)（已核文件存在，未逐项读取/执行）；[cf2_independent_production_paths_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/cf2_independent_production_paths_test.dart)（已读取源码，未执行）
- 风险与先后依赖：移进Electron renderer会把刷新、关闭页面变成执行生命周期；Android页面重建不能使任务重新执行。resume不得回放已完成副作用；需定义cancel请求/收到/终止/未知结果区别。
- 迁移交付判据：两端断订阅不会恢复授权或重复动作；流中断不执行半个tool call；恢复使用checkpoint/receipt，重新连接只replay事件。

#### 09. 语义UI合同、流编译、session与publication

- 源码定位：[pure ui_contract export surface](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/ui_contract.dart#L1)；[validateUiPlan](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/ui/validation.dart)；[UiSessionState.prepareRebase / dispatch](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/ui/state.dart#L41)；[UiPublicationCoordinator](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/ui/publication.dart#L38)；[UiStreamCompiler.addLine](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/ui/stream_compiler.dart#L63)
- 当前职责：已有DataSnapshot/InteractionIntent/UIPlan、typed edit spec、collection、validated plan、draft/view分离、revision/refs、stream compiler、publication fencing和recompute freshness。01e56cc2已含旧计算结果previous标签状态。
- Flutter/运行时耦合：ui_contract独立导出层本身不导出host/storage/IO/tool；这套语义可保留为跨语言合同。问题在合同依赖Dart对象身份、同步probe、内部不可伪造类型，而不是所有字段都含Flutter。
- 建议目标边界：Rust ui-semantics/plan-validator/session-owner统一验证、dispatch准入、publication与draft revision。IDL生成只读DTO；ValidatedUiPlan等权限句柄不由UI构造；需业务语义的事件提交event与opaque lease，纯本地展示交互由前端直接处理，不一律送模型。
- 现有测试：[ui_contract_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/ui_contract_test.dart)（已读取源码，未执行）；[ui_publication_coordinator_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/ui_publication_coordinator_test.dart)（已读取源码，未执行）；[cf_fix_t5_freshness_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/cf_fix_t5_freshness_test.dart)（已读取源码，未执行）
- 风险与先后依赖：不能把Dart identical/object identity简单序列化为字符串并信任客户端。保持final probe与session rebase同一个核心原子提交点；异步桥接后旧capture/旧callback必须被epoch拒绝。
- 迁移交付判据：非法binding/action/catalog、stale revision、reentrant cancellation、recompute失败恢复编辑、previous/current freshness及publication原子性在Rust及两端合同测试一致。

#### 10. 动态UI renderer、controller与公式重算接线

- 源码定位：[UiSurfaceController / DynamicUiSurface](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/lib/src/dynamic/surface.dart#L81)；[UiAdapterContext / render adapters](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/lib/src/dynamic/component_adapter.dart#L24)；[UiLiveFormulaRecomputePort / UiFormulaRecomputeAdapter](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/ui_recompute_adapter.dart#L28)；[UiFormulaRegistry](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/ui_formula_registry.dart)
- 当前职责：Flutter controller不只是绘图：它持有session/publication、prepareRebase/commit、pending action/receipts、render capture、dispatch、撤销探测和recompute。公式adapter还从muyon_ui导入library2UiCatalog。
- Flutter/运行时耦合：27个muyon_ui lib文件有21个直接Flutter import/export；host侧公式adapter反向依赖UI package说明catalog合同与视觉实现尚未彻底分离。
- 建议目标边界：React renderer与Compose renderer各自实现组件、布局、焦点、可访问性与本地输入；controller内的权限/原子状态搬到Rust；catalog schema抽成无视觉依赖的版本化共享数据，公式仅由Rust执行。
- 现有测试：[cf_fix_t5_stale_result_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/test/cf_fix_t5_stale_result_test.dart)（已读取源码，未执行）；[ui_library2_recompute_adapter_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/ui_library2_recompute_adapter_test.dart)（已读取源码，未执行）；[aiui5_stateful_capture_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/test/aiui5_stateful_capture_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：只移validator留下两份端侧controller会重新制造不同步事实源。先拆controller职责再重写视图；视觉库扩展不应自动增业务action权限。
- 迁移交付判据：同事件序列两端显示同事实/失败原因/旧结果标签；键盘焦点、scroll、text scale、screen reader状态分别验收，golden并不能替代真实交互。

#### 11. 权限、scope、taint与实时撤销

- 源码定位：[HostScopeAuthority](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_scope_authority.dart)；[HostAuthorizationFacts](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_authorization_facts.dart#L55)；[HostModelAuthorization / HostModelPermission](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_model_authorization.dart#L32)；[prepare / approveWithGrant / invoke](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/tool_registry.dart#L348)
- 当前职责：作用域解析、实时模块authority revision、来源污点、模型请求body/endpoint绑定、tool grant、policy revision与实时撤销各自有状态。HostAuthorizationFacts用共享latched事实通知阻断已在途通道。
- Flutter/运行时耦合：facts用Flutter ChangeNotifier做安全相关的及时通知；raw数据库和Dart对象身份参与proof。UI侧“确认”文本不是授权事实本身。
- 建议目标边界：Rust AuthorityService形成唯一policy/grant owner；事件总线代替ChangeNotifier但保留先锁存后持久化的保守顺序；UI持有短寿命approval presentation ID，不接收可重建的内部permission对象。
- 现有测试：[host_authorization_notifications_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/host_authorization_notifications_test.dart)（已读取源码，未执行）；[tool_registry_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/tool_registry_test.dart)（已核文件存在，未逐项读取/执行）；[scope_resolver_differential_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/scope_resolver_differential_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：撤权以内核受理并锁存为线性化点；其后不得开始新的受限动作，UI/IPC通知延迟不得恢复旧权限；已发出的动作按账本核对，不能承诺撤回。来源访问权不明、模块失活、scope变更、数据库写失败须拒绝。平台permission如文件选择/系统权限需与业务grant分开。
- 迁移交付判据：重放approval、换endpoint/body/scope、撤销后晚回调、事实写入失败等反例零越权；不以“本机应用可信”省掉renderer边界。

该单元补充迁移证据：旧三档、四维准入、五时长与taint门禁见第6章，不能只迁scope/CAS而忽略授权策略。既有策略只收紧、不授grant；新版ModeGrant是明确新增语义。旧standard/readOnly/custom、缺失/损坏auth1b:policy、outbound不允许always及会话上界都必须有合成迁移fixture。全部允许含新目的地的最新决定由ADR-AUTH-01明确替代范围，不篡改旧兼容配置。内容复核同时覆盖模型与工具，由ADR-AUTH-02固定理由类型和映射。

#### 12. 业务写入、CAS、幂等与回执完整性

- 源码定位：[inquiry write tool commands](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/inquiry_write_tools.dart)；[GenericWriteIdentity](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/inquiry_write_receipts.dart#L23)；[lookupInquiryReceipt](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/inquiry_receipt_lookup.dart)；[business receipt contracts](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/business_receipts.dart)；[atomic batch contracts](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/atomic_batch_write.dart)
- 当前职责：写入identity绑定operation/invocation/scope/arguments；业务对象版本、change log、receipt和历史只读lookup保留；研究写操作也由host registrar及receipt路径连接。
- Flutter/运行时耦合：合同部分可分离，但receipt与CAS依赖当前数据库事务与source ref语义；页面或model不能从历史receipt推导新授权。
- 建议目标边界：Rust CommandExecutor以expected revision+idempotency key为入口，在同事务完成业务、change log与receipt；结果区分applied/alreadyApplied/conflict/unknown。NativeReceiptProjection与ModelReceiptProjection分别定义。
- 现有测试：[reg3d_research_writes_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/reg3d_research_writes_test.dart)（已读取源码，未执行）；[inquiry_write_conflicts_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/inquiry_write_conflicts_test.dart)（已核文件存在，未逐项读取/执行）；[wc_d_inquiry_receipt_lookup_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/wc_d_inquiry_receipt_lookup_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：不能重写成“UI POST成功就成功”；超时可能已commit。Receipt schema/digest顺序与json canonicalization是持久合同；迁移需要从旧receipt读回且不能放宽校验。
- 迁移交付判据：重复提交只写一次；payload/scope同ID冲突拒绝；进程在commit前后故障可解释；historical lookup只读且无恢复授权副作用。

#### 13. 模型gateway、SSE、超时与外发账本

- 源码定位：[OpenAiModelGateway / _GatewayChannel](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/model_gateway.dart#L156)；[OpenAI-compatible provider](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/openai_compat_provider.dart)；[ModelEvent typed events](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/model_provider.dart)；[OutboundLedger](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/outbound_ledger.dart)
- 当前职责：chat/embed/request/chatStream统一出口；凭据解析、policy/grant watch、beforeSend、外发先记账、超时、取消、最终outcome、安全错误。不同model capability影响native-tools/compat与流式，不能自动换端点逃过拒绝。
- Flutter/运行时耦合：核心HTTP使用dart:io；凭据从平台SecretStore读；Dart Stream订阅取消语义需要重新设计到IPC/FFI而不是直接照搬。
- 建议目标边界：Rust model-runtime负责HTTP、SSE parser、payload-finalization、ledger和取消；UI只获允许的draft与typed event。一个request ID贯穿authorization、wire payload hash、ledger、tool-call assembly和telemetry。
- 现有测试：[model_stream_ledger_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/model_stream_ledger_test.dart)（已读取源码，未执行）；[personal_agent_streaming_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/personal_agent_streaming_test.dart)（已读取源码，未执行）；[openai_compat_provider_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/openai_compat_provider_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：网络断连、静默timeout、慢流总时限、HTTP400重试规则和key回显脱敏都有真实现测试；不得因新HTTP库默认retry而重发带副作用上下文。
- 迁移交付判据：保留先落账再wire发送、账本不可写则零网络、midstream cancel与listener失联终态、首字节/idle/总时限、错误不带key；平台网络差异单独验收。

#### 14. 模型披露与本机展示分层

- 源码定位：[InquiryUiPlanningSource.read](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/inquiry_ui_planning_source.dart#L19)；[SectionDeletePreview.toModel](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/section_delete_preview.dart#L32)；[history replay / request view](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/request_view.dart)；[redactCredentials / maskSecret](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/credential_redaction.dart#L27)
- 当前职责：当前有多处局部防线：询价read-only UI源将格式化值标为unverified/notDisclosed并不给checkpoint草稿披露权；N2模型投影不携带本机ID/digest；错误credential redaction与history replay各自存在。不能把“可在本机看”当作“可送模型”。
- Flutter/运行时耦合：数据分层主要是Dart对象/Map与入口约定，不应从单个redactor存在推断全出站链统一覆盖。C6/opaque-reference分支仍在途，不能视作当前已完整接线。
- 建议目标边界：Rust强类型NativeView、ModelView、AuditView与DisclosureContext；每次最终payload封包前检查allowlist及source proof。UI只提交披露选择，不自行把raw对象serialize到模型。secret redaction与数据披露规则分别处理。
- 现有测试：[n2_projection_boundary_regression_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/n2_projection_boundary_regression_test.dart)（已读取源码，未执行）；[cf2_independent_production_paths_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/cf2_independent_production_paths_test.dart)（已读取源码，未执行）；[model_stream_ledger_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/model_stream_ledger_test.dart)（已读取源码，未执行）
- 风险与先后依赖：统一deserializer/serializer若默认包含所有字段，会重新泄露路径、native ID、hidden digest、商业值和旧history内容。必须逐入口记录模型可见字段，不可只靠正则删除。
- 迁移交付判据：同canary覆盖live request、历史重放、compaction、UI planning、错误、receipt和日志；模型不可见字段在最终wire bytes中不存在；继承Sensitivity与ADR-0004 Q7，模型请求和工具外发均按第6章最终载荷投影；C6未合内容独立评审后再移植。

#### 15. 文档解析、知识索引、OCR与搜索

- 源码定位：[DocumentParser.parse](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/documents/document_parser.dart#L14)；[KnowledgeService.index / search / isCurrent](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/knowledge/knowledge_service.dart#L49)；[PaddleOcrService.recognizePdf](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/ocr/paddle_ocr_service.dart#L56)；[SearchService](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/search/search_service.dart)
- 当前职责：解析前后digest复核、文件/页数/文本上限；知识库导入与索引、projection变更使索引失效、当前来源校验；OCR管理模型、图像归一化、推理与PDF渲染，search另有scope过滤。
- Flutter/运行时耦合：DocumentParser调用pdfrxFlutterInitialize；PaddleOcrService直接依赖flutter_onnxruntime/pdfrx，属于深平台/引擎耦合，不是普通纯Dart服务。KnowledgeService还导入research对象。
- 建议目标边界：Rust knowledge-domain负责索引身份、chunk/metadata、digest、query/ranking与失效；DocumentText/OcrInference ports承担引擎调用。可用Rust原生后端或平台native adapter，需先验证分发包、线程、内存与模型许可。
- 现有测试：[public_services_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/public_services_test.dart)（已读取源码，未执行）；[search_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/search_test.dart)（已核文件存在，未逐项读取/执行）；[ocr_real_model_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/ocr_real_model_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：OCR真实模型测试文件存在不等于本次模型可用或真机通过。PDF engine变化可能改变文本/offset，须标parserVersion并触发可控重索引；不得为索引而隐式外发文档。
- 迁移交付判据：相同文档边界/页码/来源保持；文件改动立即使旧索引不可当current；离线OCR取消/恢复、模型缺失、空文本与超大输入给稳定状态。

#### 16. 导入冻结、工作区激活与备份恢复

1.3恢复目标：候选root替换前必须先保全当前旧墓碑，不能只先导入备份里的墓碑；恢复日志分离保全、合并、过滤验证和激活。新库身份、版本谱系、事件日志身份与遗忘证据缺失均有显式隔离出口。具体合同见第5章，不能以import成功回执替代所有入口过滤验证。

- 源码定位：[FileGateway.freeze](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/file_gateway.dart#L26)；[ImportCoordinator.commit / recover](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/workspace/import_coordinator.dart#L8)；[BackupService](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/backup_service.dart)；[_restore / checkpoint lifecycle](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/app_shell.dart#L137)
- 当前职责：文件选择后冻结快照，拒绝symlink、限制512MiB/10000文件；导入intent与业务receipt分离，recover按已提交事实激活工作区；恢复前checkpoint、退出旧页面/引用lease、close host、restore、reopen。
- Flutter/运行时耦合：FileGateway把file_picker和文件冻结揉在一起；app_shell用Navigator/WidgetsBinding/mounted保证旧树先退出后关数据库。端侧生命周期细节不能搬成通用Rust函数。
- 建议目标边界：平台PickerPort返回短寿命FileGrant；Rust snapshot/verify/import/backup协调；UI负责unsaved input提示、视图detach与rebind，但核心restore barrier和导入幂等统一。
- 现有测试：[restore_flow_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/restore_flow_test.dart)（已核文件存在，未逐项读取/执行）；[workspace_binding_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/workspace_binding_test.dart)（已核文件存在，未逐项读取/执行）；[research_runtime_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/research_runtime_test.dart)（已读取源码，未执行）
- 风险与先后依赖：Android内容URI不等于路径；Electron renderer传路径不能自动获访问权。恢复期间旧snapshot/subscription不可继续写新库；备份必须保留来源版本和可回退的旧目录。
- 迁移交付判据：旧库到新库迁移与备份restore分开验收；中断导入只恢复已提交结果；权限失效/源变化/超限/目录逃逸/引用lease未释放均有反例。

#### 17. LAN传输、任务信封、聊天与文件夹同步

- 源码定位：[TransferService / send / receive](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/transfer/transfer_service.dart#L65)；[TaskCoordinator](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/transfer/task_coordinator.dart#L8)；[LanNode / transport](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/lan.dart)；[syncWithFolder](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/folder_sync.dart#L44)
- 当前职责：paired peer、待核验收件、包/消息去重、用户接纳、task offer/accept/start/complete/applyResult、聊天已读/重试；supplier_core还提供folder exchange/sync。收到加密且配对的task信封不等于获准执行。
- Flutter/运行时耦合：host TransferService直接用flutter_secure_storage；LAN/同步核心是dart:io网络、文件与加密；任务队列和UI接收通知相互回调。
- 建议目标边界：Rust transport/sync/runtime + PlatformSecretPort、NetworkAvailabilityPort；端侧权限提示和前后台联网政策由平台adapter处理。Envelope schema、device identity、replay protection与acceptance state统一。本条是终局能力盘点，不等于本期全量开放。[devices_page](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/screens/devices_page.dart#L74-L123)及[ResearchTaskBridge](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/research_task_bridge.dart#L145-L205)有生产接线，不构成上线或运行通过证据。S05.1/W5显式承接设备消息和既有研究任务交换：offer/accept与真正本人授权导入研究说明分开，ResearchTaskBridge不自动完成研究，结果由用户形成并提交/导入科研。迁入新端或明确暂留旧端的排期待决，未实现显示未提供且保留旧入口；新增自动执行、审批同步和全局一致性另立方案。
- 现有测试：[task_coordinator_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/task_coordinator_test.dart)（已读取源码，未执行）；[transfer_states_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/transfer_states_test.dart)（已读取源码，未执行）；[folder_sync_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/folder_sync_test.dart)（已读取源码，未执行）；[lan_security_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/lan_security_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：不能把文件夹同步等同实时多设备一致性协议，也不能承诺Android后台常驻与桌面相同。pending收到与业务import完成必须分别显示。
- 迁移交付判据：paired TLS到达不触发执行；accept本身不等于执行，研究说明导入须本机用户明确发起，消息可标已读/附件待接受；restart running不重复导入说明或执行已有阶段；提交结果与导入科研分开，重复包/消息不重复导入；设备撤销、网络切换、进程重启和幂等恢复逐平台测。迁移改造不能把接收远端指令视为本机用户授权。

#### 18. 凭据与平台安全存储

- 源码定位：[MethodChannelSecretStore](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/secret_store.dart#L9)；[Folio secret adapter](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/app/secret_store.dart)；[FlutterLanSecretStore](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/transfer/transfer_service.dart#L22)
- 当前职责：模型secret store在Windows用flutter_secure_storage，其它平台调用com.mightyoung.muyon/secrets MethodChannel；LAN另有muyon-lan- key namespace；model profile保存引用而非把key当普通配置。
- Flutter/运行时耦合：存在不止一个secret adapter与命名空间。不能只移模型页输入框就认为所有凭据已迁移；各平台native实现本次未逐行审计。
- 建议目标边界：Rust只持有SecretRef并在受控IO发送阶段调用SecretPort；Electron主进程/受信helper与Android Keystore adapter完成安全存储；renderer与Compose screen state不接收读回的明文key。
- 现有测试：[secret_store_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/secret_store_test.dart)（已读取源码，未执行）；[model_stream_ledger_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/model_stream_ledger_test.dart)（已读取源码，未执行）
- 风险与先后依赖：旧Flutter存储项不会自动出现在新adapter里；需设计用户介入的重新认证或明确迁移路径，不能把密钥导入SQLite/JSON备份。MethodChannel mock测试不能证明OS keychain行为。
- 迁移交付判据：验证三类namespace、升级/重装/锁屏/权限拒绝/secret不存在/撤销；错误、日志、crash附件与导出均不含secret。

#### 19. 本机导出：冻结准备、分阶段授权、账本与保存适配

- 源码定位：[LocalExportPreparation / stages](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/local_export.dart)；[ResearchExchange.prepareReport](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/exchange.dart#L1132)；[ResearchClaimDraftPreparer](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/claim_draft_preparation.dart#L71)；[LocalExportLedger.execute / check](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/local_export_ledger.dart#L235)；[LocalExportTargetIssuer](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/local_export_target.dart#L52)
- 当前职责：已有冻结bytes/manifest/source refs、generate与save两阶段、一次性目标capability、pending先持久化再callback、终态未知不自动重试和只读check。当前完整lib检索未找到LocalExportLedger生产import/构造调用；research模块工具未接prepareReport/prepareClaimDrafts，coverage仍标导出deferred。
- Flutter/运行时耦合：账本为纯Dart/SQLite逻辑，可移核心；最终安全保存需要本机文件grant/handle、原子写/rename及cleanup adapter，不能把displayName当真实目标身份。E01的stager文件不在当前develop。
- 建议目标边界：Rust ExportCoordinator拥有frozen preparation、identity、审批revision、ledger；DesktopFilePort/AndroidDocumentPort持有系统授予handle；生成成功、保存成功、用户取消、cleanup residue与unknown分别投影。
- 现有测试：[local_export_contract_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/local_export_contract_test.dart)（已读取源码，未执行）；[local_export_ledger_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/local_export_ledger_test.dart)（已读取源码，未执行）；[le05_local_export_intent_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/le05_local_export_intent_test.dart)（已读取源码，未执行）；[report_preparation_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/report_preparation_test.dart)（已读取源码，未执行）
- 风险与先后依赖：不得把“LE06文件已合”写成端到端导出已上线。E02 preparation/presentation digest与A/B identity尚在分支且CI失败，需单独验证后决定沿用；锁冲突与数据损坏错误不能合并为一类。
- 迁移交付判据：先持久pending后产生外部文件；completion记录失败不再次执行；save取消不抹掉已生成事实；恢复不重建目标权；两个进程竞争最多一个callback。

#### 20. 持久通知、任务事件与后台作业

1.3恢复目标：通知、摘要和任务列表仅消费当前权限投影；接收游标、已应用游标、持久应用游标分开，Stop多轴、迟到效果核对和历史缺口均保留。通知重发或投影重放不重新执行业务；审批恢复采用当前权威集合，不以旧UI清空推断远端已经拒绝。

- 源码定位：[FoundationRepository.notify / updateTask](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/foundation_repository.dart#L997)；[TaskEvent / task records](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/task_records.dart)；[AiJobStore / AiJobSession](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/ai_jobs.dart#L32)；[Store.inBackground](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/background.dart#L13)
- 当前职责：FoundationRepository将站内通知写入notifications表、维护read状态并ChangeNotifier刷新；任务和事件持久化。AiJobStore保存步骤、请求摘要与checkpoint；supplier background通过isolate或host executor执行。不能从notify方法推断已实现OS推送。
- Flutter/运行时耦合：持久状态与Flutter通知绑在一个repository；Dart isolate/finally与Android process death、Electron helper退出不是等价语义。
- 建议目标边界：Rust JobScheduler/EventLog/NotificationInbox统一持久化；OSNotificationPort是可选adapter，只接收已脱敏通知摘要；React/Compose订阅序号化delta并支持snapshot重同步。
- 现有测试：[ai_jobs_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/ai_jobs_test.dart)（已读取源码，未执行）；[task_coordinator_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/task_coordinator_test.dart)（已读取源码，未执行）；[task_events_test.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/task_events_test.dart)（已核文件存在，未逐项读取/执行）
- 风险与先后依赖：移动系统可随时停进程，不能承诺Dart式常驻后台；恢复必须区分安全纯计算retry与不可知外部效果。通知投递失败不得把已成功任务改为失败。
- 迁移交付判据：保留SIGKILL后的已完成WAL步骤、变更请求使旧suffix失效、重复事件去重、同设备多视图read状态同步；OS通知点击只导航，不自动执行旧确认。

#### 21. 记忆 经验与整理

1.3迁移增量：保持五类旧记录与字段盘点，新增MemoryControlPolicy策略版本、同identity/version异摘要分叉隔离、来源删除读点封锁、可审计新版本回滚及旧root墓碑域外保全。旧revision++不当成CAS，旧页面与表存在不当成新恢复合同已实施。对应D05/D06及第10章MEM与N-M用例。

- 源码定位：[PersonalMemory](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/foundation_repository.dart#L35-L81)、[上下文筛选和记忆生命周期](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/foundation_repository.dart#L403-L674)、[经验 墓碑 整理表](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/workspace/workspace_repository.dart#L100-L142)、[整理运行 提案与回滚](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/dream/dream_service.dart#L38-L246)、[现有记忆页](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/screens/memory_page.dart)、[重复和冲突建议](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/memory_review.dart)
- 当前职责：memories有来源、范围、核实/推断、revision、停用和到期；experiences有candidate/verified/retired；dream_runs存整理前snapshot_json，dream_proposals存提案payload_json。上下文排除停用、到期、未核实和退役内容；用户可离线整理，也可选择模型辅助，后者记录外发。提案不自动成为事实，回滚只允许最近完成且状态指纹未变的运行。
- 耦合与真实缺口：FoundationRepository兼有SQLite、ChangeNotifier与管理动作；memory_page单条保存只使revision递增，尚无expectedRevision CAS。墓碑与业务数据同恢复域；整理快照和提案可含正文，旧墓碑不能独自证明全副本遗忘。
- 建议目标：Rust memory-domain/memory-application负责记录、核实、范围收窄、lineage、提案、回滚及用途投影；S06重设计为记忆/经验/整理三子区。新增CAS、自动记忆独立开关和恢复域外遗忘凭据，具体字段见第5章。
- 现有测试：[memory_page_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/memory_page_test.dart)、[memory_review_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/memory_review_test.dart)、[dream_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/dream_test.dart)（本版从固定tree核存在，未逐项执行；不以存在当通过）。
- 依赖与交付：M03/M07之后先做合成旧schema fixture与五类记录逐字段差异，D05/D06完成业务语义，W4接上下文、W7接管理、W6接索引。真实历史库转换留P3；停用/过期/候选不进上下文、回滚不覆盖人工、遗忘后恢复不复活均有独立反例。

#### 22. 受限原型 页面版本与反馈

- 源码定位：[PrototypeModule生产注册](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/module_catalog.dart#L8-L10)、[原型对象 版本 反馈和导入](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/lib/src/prototype_module.dart#L14-L117)、[导航和桥接限制](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/lib/src/web_guard.dart#L14-L39)、[资源策略](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/lib/src/resource_policy.dart)、[scheme边界](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/lib/src/scheme_loader.dart)
- 当前职责：已有原型对象、版本、反馈和受限WebView，限制顶层导航及桥接channel；不是任意网页都有本机能力。原1.1耦合表已提prototype_module，缺的是独立迁移归属，不能称完全没有盘点。
- 建议目标：Rust拥有原型身份/版本/资源manifest/反馈；平台提供隔离沙箱与受限资源scheme。Electron独立sandboxed WebContents，Android受控WebView；文档中的脚本产物不进入可信主renderer。只允许注册桥接进入同一Rust授权路径，默认无任意网络、文件、secret或IPC能力。
- 现有测试：[web_guard_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/test/web_guard_test.dart)、[scheme_loader_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/test/scheme_loader_test.dart)、[resource_policy_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/prototype_module/test/resource_policy_test.dart)、[prototype_wiring_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/prototype_wiring_test.dart)（固定tree存在，未运行）。
- 归属与交付：W1资源身份＋W4受限桥接＋W7能力注册，页面W01.1。版本切换、外链、编码路径穿越、伪造channel、导航后残留句柄、撤权、离线缺资源有fixture。平台未达门禁时明确不可用并保留旧独立体验；本版不退役原型，也不把静态产物都升级为可脚本执行。

#### 23. MCP客户端与本机只读服务

- 源码定位：[Streamable HTTP配置](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/mcp_adapter.dart#L15-L45)、[客户端工具接线](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/mcp_adapter.dart#L137-L226)、[MCP按需连接](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/screens/mcp_servers_page.dart#L113-L126)、[只读stdio服务](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/mcp_server.dart#L14-L165)、[siq_mcp入口](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/bin/siq_mcp.dart)、[外部AI客户端配置](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/data_center/ai_tab.dart#L216-L245)
- 当前事实：客户端消费远程Streamable HTTP服务，已有配置入口；不是stdio子进程客户端。独立supplier_core只读服务才用stdin/stdout JSON-RPC及SQLite readOnly/query_only/schema检查。bin入口已在固定tree核存在，本地选择性快照未全文读取；不以本地缺文件推断删除。
- 建议目标：HTTP客户端归Rust agent/platform的受控网络适配，工具映射进入统一registry、目的地/凭据引用、content_review与outbound账本；UI只配置和显示支持状态。桌面只读MCP服务迁为单独CLI或受控bridge，schema转换后通过有版本查询合同读取，不能偷开旧schema假兼容。若使用子进程由可信Electron main按固定清单启动并监督，Rust负责协议/数据投影；Android不默认承诺桌面CLI托管。
- 现有测试：[mcp_adapter_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/mcp_adapter_test.dart)、[mcp_token_redaction_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/mcp_token_redaction_test.dart)、[mcp_servers_page_test](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/mcp_servers_page_test.dart)、[只读MCP测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/mcp_test.dart)（固定tree存在，未执行）。
- 归属与交付：W4客户端协议/工具、W7 S03.1配置与能力、W3只读商业查询；记录端点/credential identity、分页上限、schema拒绝与撤权。客户端HTTP与本机只读服务分别列平台矩阵，服务发布商业数据仍需用途/受众授权；“只读”不等于可以向任意外部客户端披露。任何暂停/后置有明确可替代入口，不能默默删除旧能力。

### 六条已核实的真实调用链，以及迁移时不能切断的位置

这里写的是当前代码中的调用段，不是假设的新架构。调用间的箭头用于解释现有控制流；新Rust/IPC API名称不能倒灌成现有符号。

#### C1. 模型流是先受控收集，再决定执行

[AgentModelTurn._collect](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_model_turn.dart#L549) → 同文件drain（586行） → [OpenAiModelGateway.chatStream](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/model_gateway.dart#L377) → gateway channel受控打开/记账/发送 → TextDelta/ToolCallDelta/ToolCallComplete/Done归集 → 后续native或compat判定路径。

- drain里的ToolCallDelta只触发“准备工具调用”的展示，不能开始执行；TextDelta进入内存draft，任务事件只记长度/digest而非草稿全文
- gateway在每次尝试里执行beforeSend与policy/grant checks，订阅消失、取消、HTTP错误和timeout都有明确ledger outcome
- 迁移时将网络事件放到IPC后，必须把“已显示一段参数”与“完整、已校验、获授权的调用”继续区分。客户端不得从partial JSON直接dispatch
- 证据：[先写账本/不可写则零网络/取消及超时用例](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/model_stream_ledger_test.dart#L133)；[agent流测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/personal_agent_streaming_test.dart)

#### C2. 已确认工具卡片仍会在真正invoke前重新验证

[AgentDispatch.executeCard](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_dispatch.dart#L645) → ctx.tools.prepare → prepared.identityDigest与卡片绑定digest比较 → authorization.review/sign或confirm（或显式tools.approve） → [_invokeOne](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_dispatch.dart#L497) → [ToolRegistry.invoke / _dispatch](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/tool_registry.dart#L858) → 真实registered handler。

- 每个调用有独立invocation；scope可能被本卡片前一个写操作改变，因此确认后不能跳过reprepare
- _invokeOne在外部来源调用前先标taint，返回objectRefs后继续锁存来源；取消/closing/当前task state在多处复核
- 迁移时approve ID必须绑定core里准备好的调用身份、scope revision与effect，UI不能传一个boolean绕过这些检查
- 证据：[registry测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/tool_registry_test.dart); [研究写操作集成测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/test/reg3d_research_writes_test.dart)

#### C3. 动态界面的原子发布不全在纯合同包里

[UiSurfaceController.recompute](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/lib/src/dynamic/surface.dart#L164) → UiRecomputePort → _publishPrepared → validateUiPlan → UiSessionState.prepareRebase → UiPublicationCoordinator.completeRecompute（final token probe + fence） → commitPreparedRebase → notifyListeners。

另一条接线：[HostDynamicWorkspace.load](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/screens/dynamic_workspace.dart#L170) → [UiWorkspaceController](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/lib/src/dynamic/workspace.dart#L12) → 内含UiSurfaceController；持久化checkpoint先完成，host event回调再检查task/presentation/pending identity/taint，最后router.dispatch。

- 当前不可只把validateUiPlan搬Rust，留两端各自acceptPlan/session/publication；那会把本来同线程无await的原子状态切分成多个IPC往返
- 建议把核心session/publication/dispatch owner一起下沉，UI仅持render revision与编辑缓冲；一个publish命令返回整个已接受bundle。UI中焦点/布局状态留本地
- 证据：[final probe / stale token / reentrant dispose测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/test/ui_publication_coordinator_test.dart#L178)；[旧结果标签及semantics测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_ui/test/cf_fix_t5_stale_result_test.dart#L142)

#### C4. 引用定位的“core”仍依赖PDF/Flutter几何

[ReaderPage locator.locate调用](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/reader_page.dart#L100) → QuoteLocator（可由[ResearchServices.quoteLocator](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/research_services.dart#L43)提供） → [CitationQuoteLocator](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/citation_resolver.dart#L265) → CitationResolver.resolve → CitationPageProvider.loadPage → PdfrxCitationPageProvider。

- 当前Rect已经明确为页面0..1比例、左上原点；页跳转、精确高亮、歧义、来源不可用有不同类型
- 迁移应在PageText/NormalizedRect DTO处切开，保留判定在Rust，渲染及PDF引擎在明确adapter；不能让Electron和Compose各自猜同一quote的位置
- 证据：[四类定位状态与坐标注释](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/source_locator.dart#L3)；[引用定位测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/citation_resolution_test.dart)

#### C5. 导入业务提交与工作区激活是两段可恢复动作

[FileGateway.freeze](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/file_gateway.dart#L26)冻结选择输入 → 模块prepare → [ImportCoordinator.record](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/workspace/import_coordinator.dart#L22)记录intent → [ImportCoordinator.commit](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/workspace/import_coordinator.dart#L174)核对prepared.matches、markSourceExternal → runtime.commitImport → activate(receipt)。中断后的recover读取模块receipt决定后续激活，不重新猜有没有写入。

- 核心知道prepared identity，平台只负责取得可读句柄；Android URI必须先按授权冻结，不能假设它是普通磁盘路径
- 不可将这一整链简化成前端上传后切换页面；import成功与workspace activated需要分别可审计
- 证据：[ResearchRuntime.commitImport](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/research_module.dart#L342)；[runtime导入/对象寿命测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/test/research_runtime_test.dart)

#### C6. 比价、预算和UI试算必须共享同一价格语义

[compareQuotes](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/compare.dart#L75) → priceInTaxMode/priceInUnit；[预算选价及阶梯价格链](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/budget.dart#L202) → atQuantity → priceInUnit → _convertedPrice → roundedDivide/micros。[UiFormulaRegistry商业公式](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/ui_formula_registry.dart)的tax计算调用supplier pricing，而不是让UI自行使用浮点运算。

- 当前价格是十进制文本+BigInt百万分；中间状态中的unknown税基/单位/币种不能被新UI默认成0
- Rust迁移应一份domain价格实现供预算、比价和“试算”使用；JS number与Kotlin Double不能作为金额真值
- 证据：[税转换/单位归一/历史及阶梯价测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/pricing_test.dart#L37)；[合计/合同阈值/不同币种拒绝测试](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/test/store_test.dart#L174)

### 已存在的边界断裂与改造位置

1. module API有Widget builder。[ModuleSection.builder](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/module_v2.dart#L95)把业务可用页面与Flutter构造函数绑住。新合同应声明route/section ID和数据能力，再由两端映射页面；不能在Rust反射一个BuildContext
2. 存储合同公开Database raw。[ManagedDatabase.raw](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/storage.dart#L7)使调用者能绕过事务/actor边界。新API是typed command/query；旧库迁移工具单独受控访问SQL
3. host计算依赖UI catalog。[UI catalog import](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/ui_recompute_adapter.dart#L1)直接import muyon_ui/dynamic_ui。抽catalog contract/schema与纯语义，不把整个renderer当core dependency
4. core引用返回Flutter Rect。[Flutter/pdfrx imports](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/citation_resolver.dart#L1)与source_locator需要归一化几何DTO和DocumentTextPort，不能仅删import
5. 安全事实通知使用ChangeNotifier。[_HostFactNotifications](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_authorization_facts.dart#L10)不仅为了刷新UI，还参与及时撤销；替换为Rust广播时必须保留锁存/内存拒绝优先于可能失败的持久化
6. 导出存在构件但生产链未闭合。对当前完整apps/muyon/lib及packages/*/lib做“local_export_ledger / LocalExportLedger(”检索，仅见定义本身，无生产import或实例化；research module_tools不含prepareReport/prepareClaimDrafts接线。[researchCoverage](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/module_declarations.dart)仍将report/claim_drafts导出标deferred。故迁移清单不能从账本单测推断已有完整导出UI流程
7. 凭据有三类入口。model MethodChannel/Windows adapter、Folio adapter与LAN secure storage均要做namespace和平台恢复清单；迁移不会自动合并OS已存密钥
8. 通知名称容易误导。[notify](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/foundation_repository.dart#L997)写站内表并notifyListeners，不能据此说已实现Android系统通知或跨设备通知同步

### 当前开发状态只保留对迁移有影响的差异

#### 当前固定HEAD与旧9836基线

17:04 UTC再次读取develop，仍为`01e56cc2d729dab70e1b1def05c3aa93b28f421a`。该SHA的develop push [CI 38279219941](https://github.com/mightyoung/Muyon/actions/runs/38279219941) 在17:01:19 UTC completed/success；同SHA组合分支的[CI 38265618988](https://github.com/mightyoung/Muyon/actions/runs/38265618988) 在15:11:51 UTC success。本次只读取workflow元数据，未重新跑或逐job审计该次CI，因此它不能扩展为本次测试/真机/系统打包通过声明。

[9836bb87...01e56cc2对比](https://github.com/mightyoung/Muyon/compare/9836bb87e9f86a866ad05e83cee8beb9fe1eec8e...01e56cc2d729dab70e1b1def05c3aa93b28f421a)新增19提交，生产代码差异主要是：
- CF-FIX-T5：publication计算freshness与renderer旧结果标签；已有值在重算pending/失败时不能假装current
- CF-FIX-B：空end-only stream归model_no_card、用户切textOnly归user_text_only、撤销不把完整流伪装未完成；涉及personal_agent/ui_planning/stream_ui_planning/reason及ui_stream_task_view
- LE06-NARROW实现135074064cb9c2625292cfba06bba5eb85bc2ce8已在当前祖先链；仅SQLite busy/locked结果码映射ledger_pending_failed，损坏或其他read失败保留ledger_read_failed
- B17脱敏盘点、C6评审、export-N2设计/ADR等文档变化不等于对应功能已经上线

若主册其他章节引用9836作为旧研究时间切片，必须明确它是旧证据。涉及上述行为的新设计基线应使用本清单01e56cc2，不能把新功能的测试结论倒写到9836。

#### 仍在途的精确tip及处理建议

分支列表与open PR为2026年10月12日16:48–16:49 UTC快照；下列CI查询为当日16:53–16:54 UTC快照（该HEAD的CI另于当日17:04复核）。compare数字是“task-tip...固定develop”，ahead为develop独有，behind为task独有。它证明提交祖先关系，不自动证明代码从未cherry-pick；已逐项说明已合核心实现与未合尾部区别。

|对象|固定tip / ancestry|最近读取CI|对迁移的实际影响|
|---|---|---|---|
|组合batch-20261012c|01e56cc2d729dab70e1b1def05c3aa93b28f421a，与develop相同|develop<br>38279219941<br>success|当前源码基线，不能继续列为在途组合|
|LE06-NARROW|3a8df824eeb2c722a66d9c5e4119b8a3cfb31285，diverged 25/2，merge-base是已合实现13507406|[38264347152 success](https://github.com/mightyoung/Muyon/actions/runs/38264347152)|只剩task文档与child Flutter build-dir隔离测试修补未在develop；不能称锁分类实现未合，也不能称整个tip全合|
|C6 fix1 / fix2|43632fe02834dc1e6711a60e1657a4f134b23d74 diverged 51/14；另一后续分支fix2=5aae763e98a215b1cfc79d41d478cdeb5f94c3c5 diverged 51/11|fix2 [38260024613 cancelled](https://github.com/mightyoung/Muyon/actions/runs/38260024613)|opaque-reference与model disclosure改造仍需独立评审，不能当当前统一披露合同完成；本次未穷尽所有C6相关分支的内容关系|
|E01 bounded staging|923e556d78a98dfe8ce696a9c1244cbb3011e6df diverged27/2|[38264730838 success](https://github.com/mightyoung/Muyon/actions/runs/38264730838)|新增export_file_system/local_export_staging和测试不在当前HEAD；Rust保存port可参考候选，先评审边界和平台适配，不标已集成|
|E02 frozen facts|285c107e3973e84d911719e6de1356fcdd9e09b4 diverged27/2|[38264782856 failure](https://github.com/mightyoung/Muyon/actions/runs/38264782856)|preparationDigest/presentationDigest与A/B call identity是候选变化；定义wire合同前消除旧新身份规则分叉，本次没有诊断其失败原因|
|OC21 redaction去重|ab9e9faa2a163ab5a469dbe0fec78195f7b0afb4 diverged19/2|[38270487843 failure](https://github.com/mightyoung/Muyon/actions/runs/38270487843)|只是部分credential masking helper去重候选，不替代模型披露系统；不能把失败原因猜成安全回归|

GitHub当时有15个open PR，其中包括旧/独立证据PR。示例：[PR59](https://github.com/mightyoung/Muyon/pull/59)仍open，不代表LocalExportLedger不在develop；[PR30](https://github.com/mightyoung/Muyon/pull/30)仍open，也不能据此否认当前publication代码。导出恢复测试[PR63](https://github.com/mightyoung/Muyon/pull/63)、模型披露canary[PR65](https://github.com/mightyoung/Muyon/pull/65)和打包[PR67](https://github.com/mightyoung/Muyon/pull/67)为各自证据/范围，不能一键算成当前端到端发布验收。迁移应冻结选定代码/合同，依据当前行为与用例迁移，避免把旧PR进度表直接抄成模块完成率。

### 本次明确未证明的事项

- 未运行当前Flutter app、Rust内核原型、Electron或Compose，也未执行选定29测试
- 未逐行审计所有库代码；全量lib读取/grep及hash证明只用于覆盖文件与可复核定位，不能替代代码审查或安全审计
- 未验证C6/E01/E02/OC21候选相互组合后的行为；未将它们混入当前develop源码事实
- 未验证OS keychain、Android文件授权、OCR真模型、PDF后端性能、通知/后台策略、Windows/macOS/Linux安装与签名
- 未选择并实现Rust/Android/Electron具体FFI、进程协议与PDF/OCR发行依赖；这需要独立spike与许可/分发验证
- 未承诺旧数据库物理结构永久不变，未迁移生产数据；旧库转换、备份/回滚与历史收据兼容须过P3门禁
- 未执行merge、push、删除分支或任何源仓库写操作

## 4 分层架构与双端职责

```diagram architecture
桌面 React TypeScript → preload → Electron main → stdio → 桌面 Rust CoreHost
Android Compose → ViewModel Repository → UniFFI → Android Rust CoreHost
共享 Rust 代码：application / domain / policy / agent / contract / store
每台设备：SQLite / 附件 / 任务检查点 / 执行账本
平台端口：密钥 / 文件 / PDF OCR / 通知 / 网络
两台设备独立存储；本期不新增任务与权限同步；既有业务交换按W5迁移
```

架构图表达同一代码在两台设备的独立实例。桌面运行受控侧进程，Android 将库嵌入应用；无需常驻HTTP后台。联网模型或外部工具失败时，只让依赖它们的步骤等待，不影响已支持的本地浏览、编辑与恢复。

### Rust 内核的分层

Rust workspace 建议分为以下 crates，依赖方向始终指向领域层：

- `muyon-domain`：对象标识、供应商等业务实体、规则与领域错误，不依赖 UI、数据库或平台 SDK
- `muyon-contract`：命令、查询、事件、投影、版本协商及校验；作为 TypeScript、Kotlin 契约生成与一致性测试的依据
- `muyon-application`：用例、任务状态机、取消、重试分类、权限检查与事务边界
- `muyon-store`：SQLite 仓储、事件日志、执行账本、任务检查点、附件索引及 schema 升级
- `muyon-policy`：能力授权、外发数据选择、操作计划绑定与脱敏投影
- `muyon-agent`：模型适配、工具调度和结果归一化；模型输出只能提出操作，不能赋予执行权限
- `muyon-platform`：密钥、文件句柄、网络凭据、时钟、通知、PDF/OCR 等端口；平台实现不能反向改变领域规则
- `muyon-desktop-host` 与 `muyon-android-ffi`：分别承载进程协议与 UniFFI 导出，保持薄层

界面端负责导航、交互、布局和本地展示状态。业务事实、权限结论、实际执行结果必须来自内核，禁止两端各写一套规则。当前设计对齐基线为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`。历史 `9836bb87` 的盘点曾发现 `module_api` 混有 Widget／BuildContext，并把 `supplier_core` 等纯 Dart 逻辑列为规则提取候选；这部分是历史证据，须以新基线盘点逐项确认，不冒充已核验的新代码结论。移植时复用测试用例、数据语义和算法规范，再逐项转写并做差异测试；不以把全部 Dart 嵌进 Kotlin 作为默认路线。

移植时先把模块 API 拆为纯数据的模块清单、能力声明及业务用例，与两端各自的展示注册表。Widget 构建器、BuildContext、主题和导航全部留在界面层。每个领域先冻结当前有效样例与安全不变量，再移植 Rust，最后以正常、边界、拒绝和损坏数据样例对照结果；发现旧行为缺陷应单独记录，不能将“结果一致”当作安全保证。UIPlan 只使用版本化组件词汇和数据引用，不成为任意 JavaScript、HTML 或 Kotlin 的执行入口。schema限定可表达结构，沙箱限定运行边界；最终业务授权仍由Rust决定。

### 桌面进程与可信桥

调用链为 React renderer → 受限 preload → Electron main → Rust 侧进程。main 从安装包固定位置启动签名配套的可执行文件，不执行用户提供路径、不拼接 shell 命令。第一版采用专用 stdin／stdout 管道，无本机监听端口；stdout 仅传协议帧，stderr 仅输出脱敏诊断。帧建议采用四字节大端长度加 UTF-8 JSON，初始上限 1 MiB，附件走受控 blob 句柄。分片读取、粘包、超长帧、非法编码均须测试。

管道仅由 main 创建并交给指定子进程，不把控制凭据放入命令行、可读文件或 renderer；子进程不请求提升权限。协议解码拒绝重复 JSON 键、过深嵌套、未知方法和越界字段，对在途请求数与总缓冲量另设预算。一次请求超时只表示等待结束，不证明底层已取消，必须继续查任务终态。

renderer 显式启用 sandbox、contextIsolation，关闭 nodeIntegration；使用严格 CSP，禁止任意导航、新窗口和远程脚本。preload 只暴露具名业务方法，不暴露原始 ipcRenderer、任意频道、文件系统或命令执行接口；main 校验 senderFrame、来源、参数和窗口会话。以上对应 [Electron 安全建议](https://www.electronjs.org/docs/latest/tutorial/security/) 与 [contextBridge 使用边界](https://www.electronjs.org/docs/latest/tutorial/context-isolation)。Rust 侧进程的崩溃隔离不等同于操作系统权限沙箱，main 或同一用户账户被攻陷仍是剩余风险。

### Android 原生生命周期

Kotlin/Compose 经 Repository 进入生成的 UniFFI Kotlin 接口，Rust 编译为随应用分发的原生库。官方当前 Kotlin 路径通过 JNA 调用原生代码，不能笼统描述为“UniFFI 自动生成 JNI”；若包体、启动或回调性能无法达标，再以实机证据决定是否采用窄 JNI 桥，并单独承担绑定维护成本。参见 [UniFFI Gradle 与 JNA 集成](https://mozilla.github.io/uniffi-rs/latest/kotlin/gradle.html)。

FFI 明确定义对象、缓冲区和回调的所有权，不跨边界传原始指针或界面对象。Rust panic 不允许跨 FFI 展开，可恢复失败转为类型化错误；同进程原生崩溃仍可能终止 Android 应用，不能照搬桌面侧进程的故障隔离承诺。

每个进程只创建一个受控 CoreHost，由应用级组件管理；ViewModel 持有订阅与 UI 状态，不随 Compose 重组反复创建内核。数据库和阻塞 FFI 不运行在主线程，事件以有界批次转为 Flow。句柄明确关闭，订阅解绑后禁止继续回调；关闭应等待在途调用安全收束。不能依赖 onDestroy 或析构落盘，因为 Android 杀进程时它们可能不执行，见 [UniFFI 对象生命周期](https://mozilla.github.io/application-services/book/howtos/uniffi-object-destruction-on-kotlin.html)。需要持久后台执行的步骤经 [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent) 调度，但任务状态归内核，调度器不构成无限后台常驻保证。Worker 与前台共享同一宿主入口；若以后引入独立进程，必须额外解决唯一写者和 IPC，不能各开内核抢写。

### 平台适配与能力声明

Android屏幕读取尚未确认，不纳入默认平台能力。不以文件读取、分享或普通应用权限推导屏幕捕获、无障碍服务或持续后台读取许可；若以后决定支持，需单列系统机制、可见提示、敏感窗口、会话寿命和撤销验收。

文件 picker、分享、通知和权限提示留在宿主；Android 使用 [Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider) 授予的 URI，经平台适配读流或复制到应用受控目录，不伪造普通文件路径。PDF文本抽取与字形坐标优先评估Rust侧单一引擎候选，平台负责渲染和选择；也可由受控适配器承接，但抽取版本、文本规范化、rotation/crop与坐标输出必须通过同一跨端fixture。引擎选型以许可证、包体、性能和锚点一致性实测决定，尚未定版。不能默许两平台各自抽取再猜锚点。OCR仍由能力适配器承接，返回带页码、坐标、置信度及来源摘要的结果；大型或不可信解析应考虑独立工作进程，不能默认在 Electron main 解析。内核负责流程和结果校验，具体引擎、许可证、离线模型体积另行验证。受控blob读取使用带scope、用途、内容digest、有效期和读取范围的短寿命BlobLease；renderer经受限读取接口取分块字节，不得拿原路径或任意file URL。每次读取复核lease，撤权后拒绝后续分块并清空相关缓存。

统一错误包含 code、脱敏 message、request_id／task_id、可选 field_path 与明确 recovery_action。至少区分 INVALID_ARGUMENT、SCOPE_DENIED、REVISION_CONFLICT、CAPABILITY_REQUIRED、CAPABILITY_STALE、PROTOCOL_UNSUPPORTED、CURSOR_EXPIRED、STORE_BUSY、STORE_FULL、CORE_UNAVAILABLE、EXTERNAL_OUTCOME_UNKNOWN。不要只返回可重试布尔值；恢复动作应区分稍后查询、刷新计划、重新授权、用户核实及禁止重试。

## 5 统一合同与可恢复执行

### 一份语义合同

合同必须只有一个版本化schema事实源。首选技术候选为规范JSON信封schema，桌面stdio传UTF-8字节、Android经UniFFI传同样字节，UniFFI类型仅承载句柄、批次与回调寿命；另一候选是由同一schema生成JSON编码与UniFFI类型化绑定。SPIKE-01比较两者的包体、延迟、维护成本和安全字段覆盖后固定选型，尚未完成实测选择。Rust统一解析、校验与规范化；TypeScript/Kotlin DTO从同一schema生成，不各自维护第二份业务字段定义。M03锁定生成器、规范化算法、枚举、未知字段、null/缺省和数字规则；相同输入经两传输得到语义及摘要一致的规范化业务响应；若采用统一JSON字节候选，再要求规范化业务字节一致，传输request_id和进程epoch等明确非业务字段按fixture规则固定。该技术方案须先通过SPIKE-01，失败时形成有证据的ADR替代，不让两端私自分叉。启动握手返回协议主次版本、内核构建号、支持能力、数据库版本和随机进程 epoch。主版本不兼容拒绝工作；次版本按能力协商，未知安全字段不能忽略后继续执行。协议版本、业务 schema、数据库 schema、界面投影版本独立演进。

下面仅示意可信宿主内部的执行契约形态，不是已经实现的 API，也不授予模型或 renderer 直接写入的权限。模型和普通界面先提交类型化意图，内核确定计划并按当前模式判定是否需要确认，再由可信宿主附加能力引用；已有完整动作参数可以直接进入此路径，不要求先开模型新一轮。执行入口仍须校验计划、能力、scope 和 revision。示例中的能力引用是占位值，不能由普通界面自行填入来取得执行权：

```json
{
  "protocol": {"major": 1, "minor": 0},
  "request_id": "req-01",
  "scope_id": "workspace-01",
  "method": "supplier.update",
  "idempotency_key": "op-01",
  "expected_revision": "7",
  "plan_ref": {"id": "plan-01", "revision": "3"},
  "capability_ref": "cap-opaque-placeholder",
  "params": {"supplier_id": "sup-01", "name": "示例供应商"}
}
```

`request_id` 只关联一次传输；`task_id` 标识持久任务；`scope_id` 限定工作区与授权边界，不能代替权限检查；`idempotency_key` 标识一次业务意图，由Rust在形成稳定actionId与plan_ref时铸造并持久化，绑定scope、动作类型、cardRevision、目标与canonical_params_digest；UI只能回传plan_ref，不能按每次点击新建业务键。重复plan请求须携带原intent_ref并返回既有计划，不能在键铸造之前漏出双击窗口；确属新意图才分配新actionId。相同 scope／操作／幂等键只能对应同一规范化参数摘要，不同摘要返回冲突；返回 accepted 前必须持久化任务。 认领成功后、实际派发前崩溃可能零次执行；重复请求尚无回执时只返回已有阶段/待核对状态，不能因“已认领”编造原成功回执。重连先按任务或幂等键查询，再决定后续动作。金额采用币种加十进制定点值，跨 JSON 的 64 位计数用十进制字符串；时间同时保留 UTC 时刻和必要的业务时区，空值与字段缺省分别定义。

查询返回 `result＋revision`；异步命令返回 `accepted＋task_id`，终态由 `task.get` 或事件取得。业务修改采用 expected_revision 比较交换，过期页面不能覆盖新状态；批量操作明确全成全败或逐项回执。公共接口只接收数据，可信宿主另附会话身份与能力引用，不能从模型或普通页面参数中读取身份。规范化摘要算法、字段顺序、缺省值和 schema 版本要纳入共享契约样例。

任务运行状态、等待原因、取消请求与外部效果分开建模。建议运行状态为 queued／running／waiting／succeeded／failed／cancelled，waiting_reason 区分补充信息、模式要求的确认、离线、执行器不可用、外部依赖、结果核实、user_paused和capability_hold；单动作content_review的pending/reviewing状态另记录为复核子状态，不能假扮用户确认；取消请求另记时间与阶段。仅执行器支持安全检查点暂停时才显示暂停入口，暂停不撤回已发出的外部动作。只有确实等待必需的执行检查才进入waiting；建议型content_review不可用不得使全部允许等待，复核子状态不自动成为waiting_reason。界面的“暂停”“取消中”“结果待核对”是这些字段的投影，不另造相互矛盾的事实。生成内容完成不代表外部操作成功，任务完成必须满足其承诺的回执条件。

authority_revision是Rust持久的scope内权限版本标识，授权、用途、撤权等有效权限事实变化时更新，业务备份恢复不得使其回退或复活旧能力。UI若使用permissionEpoch名称，它只是该值的显示/绑定别名，不由前端自增；与每次启动随机产生的process_epoch严格分开。process_epoch只隔离旧进程回调，不表示权限版本，更不重置持久scope事件序号。MemoryRecord、content_review和摘要缓存共用authority_revision语义，不另造第三套权限代次。

### 事件 流控与重连

恢复分为展示投影、模型请求、工具效果三层。展示可重建，模型生成是否继续取决于对应执行器，外部效果只由账本与可核证据判定。每台设备的Rust/CoreHost各自权威；共享的是代码与合同，没有新增云端中心Rust。生成卡折叠、排序、筛选、分页和草稿仍可本地响应；恢复订阅不新建模型轮次或重发业务命令。

持久事件继续使用scope内seq，最小字段为scope_id、task_id、seq、kind、payload_version、payload。为避免独立设备或恢复旧库时身份相撞，EventCursor增加store_id与stream_id；完整域为store_id＋scope_id＋stream_id，seq以字符串编码，只在同域比较。store_id由可信宿主持有，标识本机存储安装实例，新设备恢复不能直接继承备份store_id；stream_id为该持久事件日志身份，正常进程重启均不改变、seq不归零。若旧备份恢复无法维持原日志与水位，显式创建新stream_id并走全量快照接入，不把旧序号伪装成新进度；切换stream不重铸原intent/action或幂等账本身份；这是事件接入隔离，不是设备同步或跨域时钟。

process_epoch为当前进程连接栅栏，只核验相等，不按大小判断新旧。authority_revision为现有scope权限版本；对象revision、MemoryControlPolicy.policy_generation、遗忘generation与context_generation另有各自作用域，不可数值互比。它们不是替代seq的时间线。事件/快照必须通过存储、scope、日志身份、schema与当前权限校验，才接入对应投影。

| 合同 | 必需字段或行为 | 不可混同 |
| --- | --- | --- |
| EventCursor | store_id、scope_id、stream_id、seq | 不能用设备A的seq推进设备B；不能比较不同stream的大小 |
| ProjectionSnapshot | cursor域、covered_through_seq、projection_revision、schema_version、authority_revision、state、history_completeness | projection_revision为不透明相等标识，不等于水位；快照不证明执行器活跃 |
| ClientApplyState | received_cursor、applied_cursor、durably_applied_cursor、buffer_limit | 收到不等于应用，更不等于持久提交；ACK不代表业务成功 |
| HistoryCompleteness | complete、partial、unavailable及可安全披露的缺口范围 | 历史缺口不撤销已有真实成功回执，也不允许补造历史 |
| PendingInput | client_message_ref、submission_intent_ref、delivery_state、draft_revision | 未送达输入独立于压缩/流块；网络重试复用同发送意图 |

内核原子取得状态与covered_through_seq；客户端持久投影与durably_applied_cursor同事务提交，或采用经故障验证的等价恢复日志，不能先写游标再写它代表的数据。快照若采用“内容后头指针”布局，必须是不可变内容版本加已提交manifest，或同一事务一致快照；两次事务中原地更新消息再换头不能被宣称天然一致。残缺、环、schema不兼容或摘要不符的候选不激活。

正常恢复先展示仍获准的本地缓存并标记截至水位；运行中/等待审批等活动态必须再取当前Rust/执行器事实。人工草稿与未送达输入在独立层保全，不由服务端或旧快照覆盖。先尝试从已应用游标有界补拉；缺口暂停增量应用并有界缓冲，补不齐或CURSOR_EXPIRED就取原子快照；安装快照和水位后，仅接纳水位之后的合格事件。失败时标partial/unavailable，不跳过缺口后假称连续，也不把已有回执改成未知。

对UI的EventCursor及covered_through_seq只属于已授权投影流，其序号由投影流顺序器持久维护；原事实/审计日志的序号仅内核使用，不直接透传。不同许可投影不能混用同一stream_id；合法权限变动后须由内核重投影/作废旧视图，必要时提供新stream快照。HistoryCompleteness.complete只表示该许可投影覆盖范围完整，不代表全审计历史。去重与相邻检查仅对同一已授权订阅流有效。协议若因合并或过滤产生合法跳跃，必须携带可验证的推进水位/next_cursor并与快照覆盖一致；客户端不能对原始账本跳号机械执行seq+1，也不能从隐私过滤后的缺项推断隐藏事件数量。不得向无权UI暴露原审计序号、受限类型或计数。没有合法推进证据的跳跃才进入缺口修复；授权收窄时先清受影响投影，再取得当前许可的快照。

建议初始窗口128条或1 MiB未确认事件，最终由测量确定。任务终态、授权结果和外发回执先落盘，不被背压丢弃；瞬时进度可合并并说明不属事实。慢订阅暂停或断开后按游标恢复，禁止无限缓存。重连只恢复查询/订阅，不重提turn或执行命令；发送超时依原submission_intent_ref查询受理结果，无法确认就保持送达未知，不新造第二条已确认用户消息。

main遇EOF、超时或进程退出，冻结写入口；取得旧writer退出及目录锁证据后有界退避重启、握手与恢复，不批量重放无响应写入。连续崩溃进入只读诊断。页面/会话切换通常只改订阅；显式任务绑定策略例外另列。账号退出使本机旧能力失效，远端取消/拒绝是否完成须有实际回执，离线清UI不等于远端完成。审批TTL来自自身合同，不照抄竞品240秒。

### 本地事务与文件一致性

每台设备各自持有 SQLite 与附件库，同一数据目录只有一个 CoreHost 写入口；多窗口共享它。Electron先取得应用单实例锁，再由Rust持有按数据目录标识的OS文件锁，二者缺一不可；旧Flutter包、独立CLI与新包同机运行时也不能共写该目录。应用单实例锁不替代跨程序文件锁，旧程序不支持同一锁协议时继续使用独立目录，禁止凭新包自检宣称旧writer已停。应用用有界单写者队列串行修改，短读事务使用快照。WAL 支持读写并行，但每个数据库仍只有一个写者，参见 [SQLite WAL](https://www.sqlite.org/wal.html)。写事务内同时提交对象变更、revision、幂等记录、任务检查点和领域事件；不跨网络调用持有事务。存储繁忙可有限退避，磁盘满、损坏和校验失败必须显式阻断，不能回退为空库。

文件与数据库不是同一事务：导入先写临时文件、校验摘要，再登记附件与提交状态，通过恢复日志完成重命名和孤立文件回收。禁止把外部任意路径直接授予内核；附件返回带 scope、用途和有效期的受控引用。

外发采用执行账本：prepared → authorized → dispatching → succeeded／failed／outcome_unknown。发送前先持久化目标、规范化负载摘要、能力引用和外部幂等键，再执行调用，再保存回执。数据库事务无法使第三方请求获得 exactly-once。崩溃发生在“已发送、未记回执”窗口时，先查询提供方回执；仅在提供方明确支持幂等且契约允许时使用原键恢复。没有可靠核实路径就保留 outcome_unknown并展示核实入口；仅在确需补充核对事实时请用户处理；合法新业务意图的范围按下段限制，不把它变成全部允许档的常规确认弹窗，也绝不把超时当失败自动重发。纯计算、只读请求和外发任务采用不同恢复策略。

提供方适配器必须声明幂等支持、键作用域、有效期、查询原效果的方法及不支持时的出口。外部键从稳定业务intent/action映射，不因新attempt、tool_call_id或显示generation而重铸，也不一律等于tool_call_id。记录仅“已认领且无结果”不足以断言unknown：若持久派发边界及唯一执行入口能证明尚未派发，保留未派发事实并按当前模式/能力续办；可能已派发才进入核对。人工点确认不能把unknown变已知；全部允许下仅核对无果、没有新的可信用户指令时仍零新派发、无额外风险确认。本轮用户已决定：先查核、绝不自动重发；用户明确提出“再做一次”时，可以建立与原unknown关联的新业务操作，页面内联持续显示“原结果未知，本次可能重复”，原效果仍为unknown。新操作用新intent_ref和新Attempt、按当前权限/用途/版本重新形成确定计划；FullAllow不追加确认弹窗，其他模式仍按各自授权规则。网络重连、重复投递、模型自行重试、切换模式或超时都不构成用户的新指令。

acknowledged_unknown_ref是可信宿主/Rust创建的不透明关联凭据，不是授权token，也不是原结果已查明的证明。其绑定必须覆盖可审计user_instruction_ref、原unknown action与记录版本、展示版本display_revision、scope_ref、动作类型、规范化目标/参数摘要以及新intent_ref/plan摘要；具体字段由M03/D03单一schema冻结。自然语言指令须能回指真实用户消息，页面动作须回指可信宿主显示过当前未知事实的显式发起事件；模型、外部文本或renderer自填一个ref不足以签发。不能仅按“同目标＋同动作”永久封锁所有无关业务，也不能用目标别名/微改payload逃过同一效果的关联；D03以稳定业务意图/效果身份和规范化目标定义冲突集合。派发前原事实或范围变化时重新核对并更新计划/展示，不沿旧凭据盲发；是否额外询问仍按模式，不能把此重验变成FullAllow风险确认。两个操作各有回执，新操作成功也不把旧unknown改成成功或失败。

既有本机导出例外继续继承：[ADR-0001于10月12日采纳DESIGN-EXPORT-N2的D1–D5](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0001-leadership-and-scope-freeze.md#L124)，其中D2允许在历史导出结果未知时，用户显式从同一冻结内容新建本机副本操作。新操作必须使用新exportId、新A/B阶段调用及目标能力身份，并选择新的副本目标；保留原unknown及其核对入口，不覆盖原目标、不将查不到当未执行、不自动新建或重放。A/B身份与本次目标绑定继续继承，是否有Muyon额外确认统一服从当前模式；FullAllow不因纯风险再问，但系统目标选择和真实访问能力不能伪造。该有限例外本身不授予Hub、邮件或任意远端原调用重放；用户明确的新远端意图按本轮独立关联规则处理，也不表明旧导出链已完成生产接线。

备份恢复不能把外部世界一并回滚。恢复前还须保全当前可用执行/幂等账本、已派发记录和回执；候选备份中的任务与账本先标为历史导入且未核对（historical/unreconciled），不得仅因旧行是prepared就证明“尚未派发”。例如备份后已外发、旧备份无回执，即使切换stream_id仍须查询当前保全记录或原提供方；无法核对保持outcome_unknown，禁止自动续发。新设备丢失当前账本时尤其不能由旧备份推断零派发。保全布局由D03/D06联合冻结，不以换日志身份重新获得一次执行机会。历史回执与当前恢复后的业务对象版本可能不同，必须分别呈现；没有一致性证据不伪称当前对象已应用，相关执行入口保持隔离。

### 原子组与独立操作集的提交边界

内核返回并锁定batchMode及原子组成员，UI不得用逐行呈现改变原子性。atomic组整组提交或回滚，使用组级回执、原operationId与幂等键核对，不能报告组内部分成功或提供单行续办。independent操作集才可逐项结算和汇总；仅续办确定未执行且允许重试的项，未知项先核对回执。计划摘要与revision绑定模式、成员、目标和数据范围，预览后任何变化都使旧计划及其授权绑定失效；刷新后是否需要确认仍按当前模式决定。

此约束继承当前[AtomicBatchForm合同](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/atomic_batch_write.dart)，适用于科研R07、询价批量写入与导入。验收必须同时覆盖“第N项失败导致atomic全组无写入”和“independent部分成功后按真实回执续办”，不能以同一套逐行重试逻辑替代两者。

### 任务状态的产品含义

| 状态 | 确定含义 | 用户可做什么 |
| --- | --- | --- |
| queued／running | 任务已落盘，等待或正在执行 | 查看步骤、补充指定任务、请求取消 |
| waiting + 确认原因 | 当前模式要求对具体计划作出决定 | 查看目标和差异，确认或拒绝 |
| waiting + 离线原因 | 某一步确实依赖网络 | 稍后恢复，仍可阅读本地结果 |
| 取消请求字段 | 已接收取消，尚未收束 | 显示取消中，不显示假终态 |
| succeeded／failed／cancelled | 内核确认的终态 | 查看结果、原因或已发生的副作用 |
| 账本 outcome_unknown | 外部效果尚无法确认，任务等待核实 | 先核实回执，不能无条件重试写入 |

状态名称是建议合同，实施前须固定状态转移表。UI不能从模型文案推断成功；瞬时进度不是事实账本。退出页面、停止生成、取消任务和撤销权限是四类动作。

动作卡的四个基础文案字段是“动作名、进行中、已完成、失败”，它们是呈现模板，不是完整状态机，也不是只能出现四种结果。需要确认、已阻止、结果未知、取消中、已取消及安全审查暂停各有独立状态与原因，不强塞进四个字段。尤其不能把未知结果归为失败后重试；“已完成”只能由满足合同的确定结果或回执驱动。文案来自结构化状态，不参与授权判定。

建议ActionRecord至少包含action_id、task_id、object_ref、expected_revision、canonical_params_digest、mode_revision、policy_revision、grant_ref、execution_phase、waiting_reason、effect_outcome、receipt_ref及cancel_requested_at。允许转移表与不可达组合在合同测试中固定；用户关页或模型生成停止不得把派发中标成取消。全部允许影响是否等待确认，不改变派发、回执和未知结果的状态机。

1.3将取消、阶段、效果与历史完整性显式分轴，避免一个“已停止”吞掉效果：cancel_state为none/requested/executor_stopped/stop_unconfirmed；仅收到请求或传输送达仍是requested，executor_stopped须有目标执行器停止后续工作的证据。execution_phase为queued/prepared/authorized/dispatching/running/stopped/completed；每项effect_outcome为none/succeeded/failed/outcome_unknown，failed须有确定失败证据。已有执行账本的prepared→authorized→dispatching→结果状态按此投影，未更换权威事实源。 execution_phase=completed只表示该执行阶段结束，不等于Task.succeeded或effect_outcome=succeeded；UI成功标签仍要求相应真实结果。

executor_stopped可与已成功效果或未知效果并存；Task的cancelled表示本次取消目标的剩余工作已经停止且没有待定承诺效果，仍保留取消前已完成步骤及真实回执；不能解读为整个任务从未产生效果。若目标范围仍有unknown，只显示停止未来工作并继续核对。Stop丢包或确认缺失保留stop_unconfirmed/reconciling，不承诺必然收敛。迟到成功回执可以收敛原效果，摘要或UI清理不能改写它。历史partial独立于这些轴，不能使已有权威终态倒退，也不能把没有新鲜完成证据的任务推成成功。

### 执行摘要与可恢复展示投影

静态Claude Android材料显示工具行、连续折叠组、计划进度、Research来源、远程Code轮次摘要、summary_pending及压缩回执等线索。采用的是可扫读和可展开的表达方式；客户端字段不能证明其后台如何生成摘要、外部效果exactly-once、所有会话均有子代理或已完成小部件。普通聊天与远程Code会话不混作同一个能力承诺。

Muyon继续以Task、Attempt、ModelTurn、ToolInvocation、EffectReceipt为权威执行对象；不新建另一套“执行成功”事实。ExecRun/ExecStep作为版本化读模型，引用权威ID、事件游标和当前投影权限，可以重建计数和状态，不能反向写账本。一次任务可有多attempt与model turn，重试不是新成功；跨设备数据与账本本期独立，不声明全局至多一次。

| 投影对象 | 最小字段与来源 | 不可推导的事实 |
| --- | --- | --- |
| ExecRun | task_id、attempt_ids、kind、projection_revision、counts、timing、summary_ref、summary_pending | 组头“完成”不能替代各效果回执，也不能掩盖unknown |
| ExecStep | invocation/turn引用、parent_ref、scope_seq、title、location、object_ref/revision、effect_state、receipt_refs | UI布尔isComplete不能创造成功，步骤计数不等于写入次数 |
| SummaryVersion | summary_id/version、producer_kind、source_event_range/digest、生成时间、模型/模板版本、authority_revision | 自由模型摘要不可称确定性重算；保留版本，修订不覆盖旧证据 |
| CompactionReceipt | context_generation、输入/输出token计数及计数方法、source_digest、状态 | “压缩完成”不是删历史、遗忘记录或撤回已外发内容 |

状态和计数由Rust投影确定性计算。摘要正文可为固定模板或模型/外部文本：模板允许按相同版本重算，模型自由摘要须版本留存并标来源，不承诺字句可复现。生成摘要也属于模型请求，按当前模式与用途授权；即使摘要生成失败或迟到，真实任务终态与可查回执仍即时显示。summary_pending只表示说明文字待到，不能把已完成效果改回运行中。

折叠组可合并连续同任务/attempt的可折叠展示片段；正在等待用户、失败、unknown、capability_hold及关键回执必须在组头保留明确计数/状态。展开可看步骤、允许的输入摘要、真实位置、耗时及产物/对象版本；展示量很大时虚拟列表和分页，不能把敏感全文塞进组头、搜索或通知。权限变化时摘要、source标题、计数、引用与产物跳转都重新投影，缓存键包含authority_revision，旧摘要不是披露通行证。

事件仍复用第5章scope内seq、epoch、cursor和原子snapshot协议，1.3补齐store/stream身份后，摘要事件为ProjectionUpdated、SummaryVersionAdded、CompactionRecorded、DisplayFragmentRetracted等投影更新。状态变更可能早于响应，也可能重复或乱序到达；客户端按store_id＋scope_id＋stream_id域内seq去重和重排，先按process_epoch相等性拒绝旧展示回调，游标过期取快照再续流。scope序号不构成跨设备全局序，不宣称全局exactly-once。

DisplayFragmentRetracted只撤回指定展示片段或过期旁白，保留原事件身份与撤回原因；不删除ToolInvocation、EffectReceipt、已发生副作用或审计事实。正文被撤回后如有已执行动作，任务详情仍可在当前权限内核对效果。上下文压缩同样不使账本或对象消失。

旧process_epoch或context_generation的展示片段不得覆盖当前页面；真实迟到tool_result/EffectReceipt仍按原action、attempt、参数摘要、执行来源和权限核验。旧连接回调不可信时通过当前连接查询原账本，不能连真实效果一起丢弃。DisplayFragmentRetracted绑定scope、片段ID与片段版本，只改展示并留原因；任何ToolInvocation.state变更也不是删除历史回执的入口。

压缩候选补齐conversation_ref、turn_refs、source_cursor_range、input_digest、context_generation、authority_revision、memory_policy_refs[]与forgetting_set_digest；每个策略引用都含policy_scope_ref＋policy_generation，覆盖工作区和会话的全部相关策略；提交时重新验证所有来源、记忆控制与遗忘凭据。CompactionReceipt保留工具调用/结果配对及receipt引用，未配对且效果未知的调用不能被压成成功文本。PendingInput将发送身份/送达状态与草稿正文分开。正文能否持久化服从chat_retention_policy_ref及单独草稿策略；关闭聊天保存不能被恢复机制无条件改成保存全文，限期崩溃缓冲如需提供须明确授权与清理边界，不在本版写死默认期限。最小非正文提交身份、payload_digest及效果回执的获准字段按各自审计合同保留；未获准持久的未发正文崩溃后不承诺可恢复，须如实提示。压缩本身仍不能静默丢弃当前内存中的未发送输入；压缩失败/失效保留仍获准原历史及未送达输入，失权内容按现权隐藏。模型自由摘要保留版本，不自动提升成verified记忆；需要转存时另走提案与CAS。

执行关键边界：同action/幂等键同payload返回原状态或回执，同ID异payload明确IDEMPOTENCY_CONFLICT；只有prepared/authorized/dispatching登记不等于成功，dispatching结果不明就返回unknown。取消请求先持久化为cancel_requested；单动作cancelled仅用于执行器证明该动作取消范围未产生承诺外部效果，Task取消则按剩余工作范围判定；已执行部分保留回执。核对unknown若仍无证据，继续unknown并说明可用核对路径，不靠StepVerified名称、摘要文本或超时自动改成功/失败。

报告原第9页的具体模式映射、“只限个人账号”和“卡片只能新建请求不能直接执行业务”不能直接采纳；本轮用户另明确四档为只读/每次询问/Auto/全部允许、低风险并入Auto且新装默认Auto，不能因数量同为四就把旧报告当决定来源。个人限定仍待决，完整参数的业务UI直接经Rust校验执行。生成内容无权自发越权，但已注册并有有效授权的按钮可以产生确定性业务命令；执行摘要的按钮也服从同一路径。

验收基于账本fixture：正常/空、失败、离线、取消竞态、撤权、旧版本、重复点击、重启、摘要迟到/失败、压缩、展示撤回、同ID异payload和unknown核不出。离线不一律显示后台继续：只有内核能证明仍在运行才显示“本机继续”，网络依赖显示“等待联网”，执行器失联显示“状态待核对”。

### 记忆 经验与整理的继承合同

MemoryRecord是现有PersonalMemory的跨语言目标合同，已有功能包括带scope/sourceRef/verified/revision/disabled/inference/lineage/expiresAt的记忆、candidate/verified/retired经验、用户发起的离线或模型辅助整理、整理提案、重复检测、遗忘墓碑和整理回滚。本版继承这些功能，不能把S06写成从零新建；物理旧库转换后置不意味着删掉新产品中的等价业务能力。

旧saveMemory会递增revision，但现有页面不提交expectedRevision，不能称其已有CAS。新版CAS是增强。现有删除是永久删除；新版回收区/可恢复删除和彻底遗忘分级属于新增生命周期合同，不能按旧数据缺省自动升级。

首版编辑粒度固定为单条自然语言内容，在本机确定性保存。UI提交memory_id、expected_revision和显式changed_fields；Rust校验类型、scope、来源和CAS。主题只负责分组浏览，主题整段文本转新增/修改/删除补丁暂不实施；不调用模型解析保存、不因文本省略删除隐藏字段或其他记录。并发冲突保留两方版本，自动整理不得覆盖较新人工修改。

expected_revision仅针对同一memory_id与版本谱系。导入/恢复发现同ID、同revision但statement或lineage摘要不同，按分叉冲突隔离，不因整数相等而去重或覆盖。lineage增删、source_revision、用途、核实与停用状态进入CAS读写集；时间戳只表示时间，不能替代版本。保存成功必须返回操作身份、实际新revision及持久回执，模型回复或工具状态行不是保存凭据。本机离线编辑可直接提交本机CAS，不虚构等待网络。

| 旧字段或记录 | 新合同对应 | 继承和变化规则 |
| --- | --- | --- |
| PersonalMemory.id / content / source / kind | memory_id / statement / source_kind / memory_kind | 保留稳定身份、正文与来源类别，不能把推断改为人工事实 |
| createdAt / updatedAt | created_at / updated_at | 保留原UTC时间，迁移时间另记，不冒充创建时间 |
| scope / sourceRef | scope_ref / source_ref | 保留原范围与可定位来源；新加source_revision及source_set_digest，缺来源不伪造可信 |
| verified / inference | verification_state / inference_flag | 保留独立语义；推断不得因迁移自动变为人工核实 |
| revision / disabled / expiresAt | revision / disabled / expires_at | 逐字段保留，失效和过期仍不进入上下文 |
| lineage | lineage_refs | 保留推导与整理来源链，关联修订与撤销传播 |
| experiences候选及状态 | ExperienceRecord及candidate/verified/retired | 未核实候选不进入MemoryProjection，退役不隐含删除审计 |
| dream_runs / dream_proposals及快照/变更记录 | MemoryCurationRun / CurationProposal及可逆变更集 | 保留运行来源、输出、状态、外发记账和回滚边界；迁移后“整理”为产品名 |
| memory_tombstones | ForgettingReceipt与墓碑投影 | 不只迁表；恢复前由不随业务备份回退的遗忘凭据重建屏蔽 |
| 新版新增字段 | allowed_uses / source_revision / authority_revision | 旧记录不能凭缺省值自动获得模型/外发用途；缺项先隔离待核，不静默扩大 |

MemoryRecord在新版增加由Rust写入的deletion_state：none/deleted_recoverable/forgetting/forgotten，保留旧disabled与expires_at。lifecycle_state只是只读确定性展示投影，优先序为forgotten、forgetting、deleted_recoverable、disabled、expired、active；verification_state和inference_flag仍独立，不能被这六态覆盖。forgetting/forgotten必须由ForgettingReceipt及受控清理范围的PurgeProgress事实支持，前端不可提交状态值冒充完成；遗忘后的记录如需保留，仅为获准最小无正文标识/审计，不因此保留原statement。UI的kind只是memory_kind别名，lineage只是lineage_refs别名。

能力现状先分清：基线有记忆读取注入、用户手工saveMemory及用户发起的整理；聊天消息已经持久化，模型可读取[当前会话最近16条user/assistant上下文](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_task_factory.dart#L92-L145)，[消息持久化](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/foundation_repository.dart#L374-L397)并非新增。未找到自动记忆提取器、跨会话助手历史检索或可选聊天留存控制的完整生产链路；这些均不是现成开关。用户本轮已决定把自动对话记忆提取和跨会话助手检索纳入整体改造，首次默认关闭、分别开关；D11实现和验收前显示“未提供”，提供后才显示有效开关。可选聊天留存控制及临时会话语义仍待决，不能把现有保存行为显示成未提供。现有知识库检索、当前会话上下文和用户整理不能冒充这三项新增能力。记忆使用、未来自动记忆、未来历史检索和用户手动管理分别建模。“自动记忆”实现提供后，只控制自动/模型提取写入，不阻止手工编辑、删除或用户明确发起且获准的整理；“使用记忆”关闭后不读入助手上下文，管理页仍可显示当前获准记录；历史检索实现提供后另按来源权限执行。关闭其中一项不隐含改变另外两项，聊天留存是单独设置。旧库用途不明时保留管理可见性与明确不可用原因，不把所有旧内容直接塞进模型。

MemoryControlPolicy是新增的同源策略合同，字段为policy_scope_ref、policy_generation、memory_read、automatic_memory_write、history_search、conversation_memory_write、chat_retention_policy_ref；对应“使用记忆、自动记忆、检索历史、保存聊天”四控制的目标合同，记忆读取行为和聊天保存行为已有，但四个独立控制都是新增目标接口；automatic_memory_write与history_search首次默认false，依据本轮已定范围由D11实现后开放；memory_read新开关和chat_retention_policy_ref须分别继承有效基线行为/获准策略，不能凭新增字段静默改旧行为。可选聊天留存控制具体语义仍待决，不因schema有字段就启用。用户手动管理仍独立。策略引用固定为policy_scope_ref＋policy_generation；工作区和会话策略分别保存对应引用，generation在各自本机策略域内持久更新，绑定时只核同域相等性，不比较不同scope/会话的数字。有效自动提交必须同时满足automatic_memory_write AND conversation_memory_write以及当前权限、来源和用途条件，会话true不能覆盖工作区false；它不是authority_revision，也不是MemoryRecord.revision。报告中的entry_version仅映射现有revision，不另建memory_item模型。

conversation_memory_write=false（UI别名memoryWrite=false）只禁止该会话的自动/模型记忆提取、新增与修订提交，不改变读记忆、聊天保存、历史检索或合法手工CAS管理。它不代表临时会话、无痕、任务产物与必要回执零留存；临时会话与容量仍待决。创建时可保存策略快照，但读取、模型发送、提案应用和最终提交还要核验当前策略及authority_revision；变更后先重新计划/投影，不能凭入队快照忽略关闭或撤权。重新开启只允许新的有效意图，不自动复活被拒绝的旧提案，也不靠“转待确认”绕过关闭开关。

整理只由明确的用户操作或以后单独批准的策略启动，不从既有Dream名称推导自主后台授权。每次运行冻结输入范围、source/authority_revision、输出变更集与before/after revision；无模型profile的离线整理继续保留；只有明确选择模型辅助时才产生模型请求并走授权和出站账本。应用变更时复核当前记录。首版保持旧回滚边界：仅最近完成的整理运行，且整个受影响组织状态fingerprint与该运行完成时一致，才能整次回滚；任何后续人工改动或其他变化均拒绝回滚并保留当前状态，不能逐项跳过后声称完整撤销。局部补偿/选择性回滚仅列未来候选，另定冲突合同后再实现。candidate经验需人工核实后才可进入上下文，整理成功不自动核实其结论。

回滚实现为可审计的新补偿版本，不降低对象revision或回退权限/遗忘代次。其fingerprint覆盖完整相关对象、lineage、用途、核实状态与应用结果，而非仅某一条正文；任一冲突拒绝整次回滚。幂等身份绑定原run、完整应用状态及稳定回滚intent，双击只返回一次补偿结果；不能仅用run_id＋单条applied_version替代。部分应用提案、选择性回滚和自主后台整理均未因补证开放。

MemoryProjection由当前来源权限与用途投影。来源撤销先锁存拒绝，再使检索缓存、向量命中、主题摘要和未发送上下文失效；归纳任务在开始、读取、外发前和提交前重查。晚结果不得复活撤销来源，已发给第三方的内容不能承诺本地撤回。独立人工录入且获准保留的事实可以保持自身来源，复制/推导内容不能靠改名逃过撤销。

删源、撤读取权、停用、可恢复删除和彻底遗忘分别处理。删源先使该来源依赖不可用；依赖它且无其他有效来源的事实、经验、摘要、索引、通知草稿、导出候选清单和排队上下文不得继续使用，不能只挂“来源已删”标签后照常注入。多来源对象移除失效依赖并重验；有独立获准来源的条目可按其自身来源保留，不无差别删除。针对记忆的彻底遗忘按精确目标及lineage阻断派生重生，不顺带抹掉无关聊天。

ForgettingReceipt的读用封锁与purge清理进度分开；PurgeProgress使用pending/done/partial、可核范围和未完成原因。剩余计数只涵盖受控已枚举集合，不声称第三方或用户已导出副本全部物理删除。必要时读取点先阻断再异步清理；任务可确定性裁剪且重验仍完整时按当前模式继续，缺必要事实则等待补充或重规划，不一概转成重新授权确认。

### 遗忘凭据与备份恢复顺序

1. 删除/遗忘先在整root恢复替换域外持久化ForgettingReceipt；独立小库为优先候选，也可采用验证过的单调证据合并，D06经崩溃试验后定布局。凭据只含稳定目标、来源指纹、lineage关联、forgetting_domain_id及该域内generation、时间与范围，不留正文；业务墓碑为可重建投影。最小元数据、加密与清理规则在D06冻结
2. 跨库不能声称原子事务。先落遗忘凭据，再封锁相关读取和生成，随后应用业务墓碑、索引删除与缓存失效，并枚举dream_runs.snapshot_json、dream_proposals.payload_json及关联摘要/队列中的正文副本，按已批准留存策略清除或不可逆去正文，审计只留最小身份与结果元数据；崩溃重启先对账，完成前不激活相应上下文。凭据落盘失败不能报告遗忘完成
3. 恢复旧业务备份时先冻结writer和来源投影；对仍在当前业务root内的旧memory_tombstones，在任何root替换前与域外凭据一起持久保全并核验保全回执。先保全当前禁止集合和当前MemoryControlPolicy中关闭/收窄的有效状态，再合并来源可信且identity可解析的备份凭据；候选备份不能重新开启当前已关闭的记忆读取、自动写入、历史检索或聊天保存，按当前有效策略重投影，无法判断时隔离并保留原策略；不以旧备份覆盖当前证据，也不凭陌生备份任意扩大删除。对候选库按同identity、source和递归lineage重放，验证摘要、索引、经验、run/proposal正文及全部上下文入口，验证完成后原子激活。任一步失败保留旧可用库及域外证据，候选不能半激活。恢复时间更旧不降低当前遗忘代次，也不恢复旧grant
4. 对象revision、authority_revision、MemoryControlPolicy.policy_generation和遗忘generation分属不同域，禁止item.version≤tombstone.epoch这类比较；不同forgetting_domain也不直接取max。屏蔽按身份/来源/lineage和有效凭据合并，同ID新revision不能自行绕过遗忘。无法判定谱系的记录隔离待核，不能猜为新独立来源
5. 找不到凭据库、设备全量丢失或换机恢复时不声称具备防复活保证；进入待核/不可用于上下文状态并说明缺少哪些记录。凭据本身备份与跨设备同步另立政策，不借本文开放同步
6. 用户主动重新录入/恢复某条内容是独立意图，须保留新来源和revision；不得把恢复向导的笼统继续当作取消全部遗忘

验收必须覆盖“备份→遗忘X→恢复该备份→X不可检索/不入上下文”，以及遗忘后晚整理回写、回滚后再次整理、凭据库失败、部分重放崩溃和人工编辑冲突。1.1已提出恢复不得复活已删除内容，1.2补了域外凭据机制，1.3补旧root墓碑先保全、谱系冲突、跨版本域禁比较和分阶段崩溃门禁。

记忆容量、主题配额、新归档/清理与临时会话仍待决。旧expiresAt照常继承，不据此新增清理规则或按固定容量删旧记录。

### 助手身份只影响表达与偏好

IdentityPreference仅保存名称、称呼、语气和语言；不含凭据，不创建grant、不切模式、不恢复来源。新增styleText若进入模型，须经ModelView和最终wire投影校验。账号、成员和设备身份由可信宿主管理；个人账号限定待决。

## 6 权限 商敏与发布安全

### 可信授权与目的限定投影

有副作用的业务操作先在Rust形成可校验的确定性计划，列明对象、目标、参数、数据范围及影响；这不等于每次都弹窗，也不等于每次调用模型。模式、已选工作区、现有访问权限与用户配置决定授权来源和是否需要当次确认。不能接受renderer或模型传来的approved布尔值，也不能把缺失计划、未知参数或丢失来源访问证明当作已有授权；仅因外部内容不可信不等于无访问权。

全部允许档在用户选定工作区及其现有访问权限内提供免确认授权，不要求再逐对象询问。Rust由这份有效模式授权派生本次受约束能力，并在执行点检查对象、用途、参数、版本、有效期和撤销状态。若全部条件有效，即使风险规则标记为高风险也不再加Muyon确认；风险结果用于记录、展示和选择恢复策略。配置全部允许不是默认开放未知工作区、已撤销来源或系统未授予的能力。

权限有效与当次确认分别记录：受信宿主产生不透明能力引用，可来自有效模式授权，也可来自模式要求的一次性确认。真正执行前核验scope、动作、目标、数据类别、计划摘要、有效期、使用次数和撤销状态；能力消费与dispatching登记按既定事务规则提交。修改对象或参数后旧计划失效，需要重新确定性校验，但是否重新询问仍由当前模式决定，不把刷新计划偷换为强制人审。

内核持有完整业务对象，界面、模型、导出和日志分别取得目的限定投影。供应商底价、联系人信息、凭据等字段在查询阶段按允许列表裁剪；UIPlan只引用已授权投影，不携带完整对象再靠前端隐藏。读取本地文件、传给模型与传给第三方分别判定用途与范围，第三方文档或模型中的指令不构成授权。切换scope时撤销订阅并清理相关缓存；事件回放、搜索摘要、错误详情、埋点和崩溃报告同样重新检查权限。

密钥由平台保管：Android Keystore 保存不可导出的加密密钥，用其保护凭据密文；它不是任意字符串保险箱。macOS 使用 Keychain，Windows 使用系统凭据保护或 DPAPI，内核只持引用或短时必要明文，不把密钥送入 renderer、事件或诊断。DPAPI 不保证隔离同一用户下的恶意应用；Linux 若无合格秘密存储应拒绝持久保存，不静默降级。参见 [Android Keystore](https://developer.android.com/privacy-and-security/keystore) 与 [Electron safeStorage 的平台差异](https://www.electronjs.org/docs/latest/api/safe-storage)。

### Sensitivity与外发数据类别合同

继承[ontology.dart中的Sensitivity五值及unreviewed缺省](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/muyon_module_api/lib/src/ontology.dart#L6-L47)：unreviewed、none、personal、commercial、credential。分类由可信模块声明、宿主规则及经授权的配置提供；模型、外部文档、插件提交的标签均不能自降分类或增加用途许可。迁移采用[ADR-0004 Q7最终注记](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0004-module-contract-v2.md#L690-L702)和[询价字段声明](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/adapters/inquiry_module.dart#L273-L300)：联系人姓名/电话/微信/邮箱、负责人/询价人为personal；客户名、合同号/合同额、成本和报价价格等为commercial；供应商单位地址依已定声明为none，不能全部地址一律改为personal；研究字段按其已确认声明继承，不能一律重标commercial。未知新枚举或缺少分类不能按none处理。

| 类别 | FullAllow模型与业务外发目标规则 | 不能据此推导 |
| --- | --- | --- |
| none | 当前任务、工作区、读取权与用途均有效时允许 | 不豁免scope、撤权、来源和系统限制 |
| personal / commercial | 本轮用户已选B：在当前任务与既有权限用途内默认允许，含新业务目的地，不追加风险确认 | 不允许发送与任务无关的数据；不撤销明确禁外发限制 |
| unreviewed | 用户已采纳：可信分类完成前不得进入模型或业务外发载荷 | 不按commercial默认放行；不能由模型自行改成none |
| credential | 原始凭据值不得进入模型上下文、业务工具/分享正文或日志 | 不等于禁止正常服务认证；认证使用另走下述专用通道 |

unreviewed在可信分类前禁模型/业务披露、credential原始值禁模型/业务正文是所有模式的共同边界，不因Auto或每次询问中的人工确认而解除；认证专用通道仍按下述合同。

“明确禁外发”必须来自可追溯的可信用途限制：经授权配置的对象/字段用途、有效来源限制、不可绕过的平台或服务限制、或专门硬合同。每条规则绑定适用scope、数据/用途、可信来源、policy_revision或相应版本及撤销状态；缺证明不可伪称有效许可。规则优先级为现有访问权/撤权及可信禁用限制约束当前用途，再在允许范围应用模式默认；单纯高风险、taint、新业务目的地、reviewer建议或超时不得临时升级为硬禁令。原[CR-2默认遮盖且不自动外发的决定](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0001-leadership-and-scope-freeze.md#L107)保留为旧合同事实；FullAllow下自动外发默认由本轮上述决定部分替代，其他模式与本机显示遮盖并未因此自动改写。

模型上下文、历史重放、摘要/检索、工具外发、导出与日志分别作目的限定投影；D01b/单元14在最后封包处验证字段类别、允许用途和规则版本，并记录最终业务payload摘要。删去字段后若业务语义不完整，应明确拒绝或重新形成有效计划，不能静默删必填字段后声称完成。此次继承枚举不证明全链过滤已实现，现有本体卡遮盖也不是全出站安全证明。

认证通道独立：可信适配器从已配置且身份绑定的服务连接解析credentialRef，只向对应认证端点注入所需header或专用认证参数；业务payload、模型上下文、事件和诊断不含明文秘密，凭据不能随重定向流往其他服务。现有[model_gateway认证与正文分离](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/model_gateway.dart#L642-L712)和[MCP认证路径](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/mcp_adapter.dart#L420-L471)提供继承证据，不证明所有新适配器已验证。credentialRef不是秘密明文，也不是模型可自行选择的授权。FullAllow允许新业务目的地，不产生跨服务复用凭据的许可。

提示注入在已允许数据/任务范围内诱导错误写入或外发仍是需明示的残余风险；本次只有静态分析与条件威胁推断，没有复现泄漏。实施前以合成canary验证最终业务wire bytes、认证通道、规则版本和模式记录，不留真实秘密。

### 既有授权模型与新版模式映射

固定基线已实现standard/readOnly/custom三档策略和read/model/write/outbound四类开关；HostPolicySnapshot只能收紧准入，不自己提供grant。缺失配置才选旧standard，配置损坏或未完成写入锁存时fail-closed。模型、本地写和外传另有grant与可信事实校验。枚举、存储和执行门禁存在，不等于完整配置UI上线：现有assistant_control_page是只读查看已保存授权，没有grant issuer或policy writer接线。

固定证据：[HostAuthorizationPolicy](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_authorization_policy.dart#L9-L105)、[旧授权控制页](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/screens/assistant_control/assistant_control_page.dart#L81-L95)、[ADR-0002](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0002-graded-assistant-authorization.md)。

| 旧模式 | 旧语义 | 新版迁移处理 |
| --- | --- | --- |
| standard | 四维准入，仍需grant和实时事实；部分已绑定本机/本人设备模型自动分支 | 先保持legacy_standard兼容语义，不直接等同每次询问或Auto；最终显示名与映射待ADR-AUTH-01 |
| readOnly | 读取与模型维度仍各有开关；写和外传受模式禁止 | 保留明确禁写/禁外传和独立model维度；新只读不能误称完全不联网 |
| custom | 按四维配置收紧，不能凭开关自行赋grant | 保留四维值、revision和规则绑定；规则编辑与模式迁移入口需新增接线 |
| 缺失/损坏值 | 缺失默认旧standard，损坏fail-closed | 合成迁移fixture分别处理，不把损坏配置当缺省，不静默升为全允许 |

新版ModeGrant可由用户明确选择的模式与范围派生单动作能力，属于新的授权语义，不能只改旧enum名字。兼容层先保留旧策略和grant的行为，新档由用户主动选择。本轮用户已定正式四档为只读、每次询问、Auto、全部允许，低风险并入Auto，新装默认Auto。旧standard最终映射、custom编辑UX及ModeGrant期限细则仍需D01b冻结；旧配置缺失走旧兼容语义，不能把新装默认Auto套在迁移库上静默升权。未冻结的映射只做隔离fixture，不在真实旧配置上猜。

| grant时长 | 继承含义 | 不得放宽的迁移细节 |
| --- | --- | --- |
| once | 单次且可有使用次数限制 | 成功消费与失效可审计；重试先查回执，不能重新铸授权 |
| task | 指定task内 | task身份与scope/destination绑定保留，不能因任务重建扩大 |
| conversation | 指定会话内 | 关闭/变更会话后不得跨会话复用 |
| timed | 明确到期时刻 | 保留UTC过期、使用次数与撤销；外传仍受旧会话上界 |
| always | 原类别允许时的持久grant | 旧outbound不允许always；不得迁移成永久外传许可 |

五时长用于model/write/outbound，read本来不使用grant。所有旧grant保留tool、scope_digest、destination、task/conversation、expires_at、max_uses/uses及revoked_at。外传必须有目的地，非once外传同时绑定会话。新ModeGrant时效和外传范围另以明确版本表示，不把旧outbound grant暗中延长。证据：[grant匹配](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/grant.dart#L1-L121)。

### 授权ADR的唯一建议落点

本设计包中ADR-AUTH-01统一指建议文件`docs/adr/0006-fullallow-supersedes-endpoint-and-taint-asks.md`；ADR-AUTH-02统一指`docs/adr/0007-content-review-contract.md`。在本次核验的产品01e56cc2与文档e014b097中，0006/0007尚未占用；未遍历所有在途分支的预留，唯一集成人落地前仍须复核。上述只是文档建议路径，未创建、预留或改为生效ADR，不提供假装已存在的链接。

AUTH-01正文首先固定已定Auto/FullAllow、新目的地与taint不额外问、已定数据类别默认及旧规则精确替代；旧standard/custom等映射与期限细则仍按D01b出口；正式四档和新装默认Auto已定。AUTH-02固定风险意见/可信硬限制/不可用理由的输出与旧reviewer映射，不改变上述决定。原ADR-0002/0004/0005及专项合同只在明确条款和模式内部分替代，未替代的事务、身份、回执、用途、目标能力和业务规则继续继承，详见[MIGRATION-TRACE](MIGRATION-TRACE-v1.3.1-2026-10-14.md)。

### 执行模式的四维合同

下表列用户已定四档，低风险行为并入Auto而不独立成第五档，新装默认Auto。每行均以有效scope、数据用途与当前系统能力为前提；全部允许的目的地类别包括此前未使用的网站/API，不要求预选逐端点白名单；“免询问”不替代这些授权范围。这些为目标产品档位，不能与旧standard/readOnly/custom枚举直接换名等同；升级迁移不扩大旧权限。read/model/write/outbound是效果维度；远程model可同时涉及数据外发，用途投影不能省略。

| 模式 | read读取 | model请求 | write业务写 | outbound外传 |
| --- | --- | --- | --- | --- |
| 每次询问 | 当前获准投影；普通read不凭本档扩大范围 | 对需授权请求确认，旧grant如何复用待映射 | 当前意图确认 | 当前目的地与数据范围确认 |
| 只读 | 当前获准投影 | 独立model设置，不因只读自动授权外发 | 不提交，只预览试算 | 不执行业务外传 |
| Auto 默认 | 当前获准投影 | 确定性规则低风险自动、高风险确认 | 低风险自动、高风险确认 | 范围内低风险自动、高风险确认 |
| 全部允许 | 当前获准投影 | 范围内免额外询问 | 范围内免额外询问，高风险亦如此 | 包括此前未使用的新网站/API，不追加首次询问 |

禁止类须分来源：无权访问、已撤销、系统/第三方不可绕过限制和业务合同非法动作始终拒绝；仅由风险规则提出的高风险、建议确认或风险性block，不在全部允许档额外变为询问或拒绝。Auto依版本化风险规则分流；所需规则不可用时不假装低风险，返回明确规则不可用状态。全部允许不依赖纯风险评分成功才执行，评分缺失不构成隐形暂停。

RiskDecision由Rust版本化规则计算，含risk_class、reason_codes、matched_rule_ids、policy_revision、decision_digest；动作、数据类别、影响范围、可逆性、接收者、来源可信度均是输入。模型不能自报低风险或把自己的意见升级为硬限制。ModeGrant与RiskDecision分开存储，最终允许来自前者和可信执行校验。

### ADR AUTH 01 旧底线与免询问语义的替代范围

旧CR-2把外部内容任务贯穿恢复/子任务标为tainted，保留核对后的单次确认；unknown/tainted会失去自动write/outbound grant资格；旧批量按钮“全部允许”被隐藏。旧ADR-0002规定从未授权远程端点逐次询问。这些是真实既有门禁，不能漏盘，也不能永远凌驾于用户最新选择的全部允许模式。

固定证据：[taint事实](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_authorization_facts.dart#L14-L109)、[CR-2外部内容](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/ontology-write-cards-2026-10-11.md#L65-L68)、[旧端点底线](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0002-graded-assistant-authorization.md#L51-L80)。

本版明确的替代原则：在新版全部允许的有效范围内，不能只因读取过外部内容、历史端点尚未逐个确认或风险评估建议确认，再追加Muyon询问。旧CR-2/ADR-0002中这些“必须逐次问”条款若与该语义冲突，应由正式ADR明确仅对新模式的适用例外；旧兼容模式的门禁不被顺带删除。taint追踪、来源、scope、投影、撤权、CAS、账本和审计继续继承，旧批量按钮更名“允许本批”，不与新全允许模式混用。

2026年10月13日最新产品决定已明确：全部允许也允许向此前未使用的新网站/API发送数据，不追加首次目的地询问。因此本版ModeGrant在该模式包含新目的地类别，不要求预选端点，不因缺旧manual端点记录转确认。它不授予读取无权数据、不解除明确禁止外发的数据限制、不恢复撤权或绕过系统限制；发送前仍固定实际目标、允许用途与payload摘要并落账。其他模式继续保留相应旧门禁直至明确映射。ADR-AUTH-01要记录被替代的旧新端点manual/逐次询问条款与生效版本，这是实施前合同工作，已不再是产品待决。正式四档与新装默认Auto已定；旧standard/custom映射与ModeGrant期限细则仍需冻结。

| 差异项 | 本版处理 | 适用范围 |
| --- | --- | --- |
| 外部内容taint导致强制单次确认 | 全部允许内保留追踪与风险展示，移除仅因taint的重复询问 | 新全允许模式；旧兼容模式不顺带放宽 |
| 从未授权端点须manual记录/逐次询问 | 最新决定明确替代；新网站/API同样免首次询问 | 新全允许模式，数据权限/用途和系统限制仍有效 |
| 旧外传grant不能always及会话上界 | 保留旧grant原语义，不能迁成长期许可 | 新ModeGrant独立类型、期限待定，不能混用旧grant |
| 用户另选更窄目的地范围 | 可作为以后自定义配置，当前不默认限制 | 不能暗加预选端点条件来缩小已定全部允许 |
| 保留taint/新端点一律询问建议 | 不采纳作为全允许实现 | 若未来采用，须明确修改产品决定或归其他模式 |

unknown须分原因：来源内容可信度不确定属于风险事实；授权记录损坏、scope证明丢失、参数或执行账本无法验证属于真实执行前提失败，可拒绝或隔离并明确原因。把所有unknown一律要求确认会重建被否定的隐形人审。

残余风险是条件判断，不是已复现漏洞：若用户给ModeGrant足够宽的合法范围，外部PDF/网页/报价单可能通过提示注入诱导范围内、却不符合用户真实意图的修改或发送。schema、合法能力、有效版本和来源追踪不能单独证明用户本意；取消逐次核对会保留这一风险。本版没有进行注入实验或复现外泄；“新目的地免首次询问”是产品设计决定，不是对现有Dart已经如此执行的事实描述。目的限定投影、范围可见、可撤销与效果审计用于降低和定位风险，不能包装成绝对防护。

模式变化更新mode_revision。未派发动作在执行点重查最新事实，已派发动作继续核对回执；撤权先锁存再清队列和缓存。切为全部允许不重发unknown、不解除capability_hold，也不恢复旧grant。

### 生成卡的本地交互与确定性动作

生成卡可直接处理折叠、分页、筛选、选择、输入和其他纯本地展示交互；无需为了每次点击打开新模型轮次。业务计算和写入使用登记的类型化查询或命令，经可信桥进入Rust，进行当前授权、对象存在与版本、参数约束和模式检查后执行；写入或外部副作用另须幂等与账本校验，纯只读查询不强制幂等键。完整确定性参数已存在时，从点击到结果可以完全不调用模型。

已有卡片的交互只有需要理解新自然语言意图、补足语义或重新规划时才另调模型。用户要求创作新内容时仍可启动正常生成任务，这不意味着确定性按钮必须绕经模型。模型调用本身也要通过对应来源披露与网络权限检查。自动重建只允许目标相同、用户意图值不变，并能由字段级revision/diff证明中间修改不与本动作读集/写集及业务关联条件冲突；不能证明不重叠则返回REVISION_CONFLICT并保留两方差异。全部允许也不得覆盖另一端对同字段的新值。刷新得到新plan_ref和新的版本绑定，关联原意图并核对既有回执；并非所有旧卡都可自动重建执行。符合这些条件的刷新不以“安全”为由强迫模型重规划；若更换对象或目标确需重新理解，才进入新轮次，并保留原动作未执行或已发生效果的事实。

UIPlan只描述白名单组件、授权数据引用、局部交互和已登记动作意图，不携带任意JavaScript、任意IPC频道、文件路径或凭据。保存转为类型化命令；历史卡片引用稳定对象及revision，失效卡先刷新并按当前模式处理。普通renderer、模型或可生成页面不能凭JSON布尔值发放能力。schema校验、沙箱隔离、模型是否参与，均不能替代Rust授权。

需要确认时，由可信宿主固定组件显示确定计划，直接把结果交回Rust；不通过模型转述获得批准。客户端维护版本化组件注册表、schema和能力列表，未知组件降级只读，未知动作拒绝；未完整JSON和流式预览不能触发业务写入。渲染失败不改变业务状态，普通UI卡只展示投影，既不能冒充可信确认组件，也不能伪造回执。

### 工程能力暂停 capability hold

capability_hold取代1.1含混的review_hold/security_review工程用法，作用对象为“能力路径＋构建/合同版本”，不是每一个高风险动作。触发条件是授权或scope证明失真、撤权传播异常、投影越界、账本损坏、回执不一致、原子性无法验证或对应未关闭工程阻断。单纯taint、高风险标签、建议型内容审查不可用不能成为全允许暂停理由。

状态为active→remediation_ready→verified→cleared；记录hold_id、capability_set、reason/evidence、build/contract_revision、受影响任务及恢复条件。Rust持久锁存，尽量只关受影响路径，保留获准浏览、草稿和已完成产物。进入hold后停止未派发准入，已派发继续核对效果。重启、换档、普通批准、清缓存或一次content_review通过都不能清除。

清除必须具备准确修复/隔离构建、对应反例与撤权/故障恢复测试、非作者审查确定的开放范围、对遗留unknown的核实或隔离，以及当前对象/权限事实重查。清除仅释放指定能力，不补发全部历史请求、不复用过期授权；风险接受不能把缺失回执变成成功。

### 单动作内容复核 content review

content_review的对象是某次模型请求载荷或工具效果及其plan/payload摘要。它继承OutboundContentReviewer职责，并补旧枚举缺少的理由类型；不授grant，不清工程hold，不证明外部效果成功。旧实现有allow/confirm/block，Noop返回allow且reviewed=false；链取较严结果，异常/超时转confirm且reviewed=false。模型请求与工具都有接线，不能只迁工具分支。证据：[reviewer合同与异常](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/outbound_content_reviewer.dart#L3-L88)、[模型复核](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_model_authorization.dart#L95-L123)、[工具复核](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/host_tool_authorization.dart#L166-L279)。

新状态为pending→reviewing→completed/unavailable/expired，completed另存decision及policy_resolution；unavailable附稳定reason_code，区分error、timeout与unsupported。状态和策略结果分离，不能把completed叫“动作完成”或把reviewer block等同确定性拒绝。动作摘要、来源集、证据/规则版本变化使复核失效；恢复只对当前动作重新评估，不能清除其他hold。复核不可用用有限超时与明确错误收束，不无限转圈。

ADR-AUTH-02需在真实模型/外传开放前固定输出schema与解释权：reviewed、recommendation、reason_class、reason_codes、evidence_ref、policy_revision、plan_digest。reason_class区分advisory_risk、trusted_hard_constraint、unavailable；必须由可信事实适配器判定，模型/插件自报“硬限制”不足以成立。下表是遵守已定模式的合同上限，具体规则和旧配置映射待该ADR冻结，不以待决为理由重新询问高风险。

| reviewer结果 | 旧兼容行为 | Auto及每次询问 | 全部允许 |
| --- | --- | --- | --- |
| allow | 仍需有效grant，Noop不代表已审 | 仍校验授权；按模式/风险规则执行 | 仍校验ModeGrant和执行前提，不新增确认 |
| confirm 风险建议 | 转逐次确认，模型取消automatic | Auto高风险确认；每次询问按其合同 | 记录并展示风险，不追加人审 |
| block 风险意见 | 旧链拒绝 | 按版本化规则拒绝或需范围调整 | 不因风险枚举名拒绝；不得升级成工程hold |
| block 可信硬限制 | 拒绝 | 拒绝 | 拒绝并列具体无权/系统/合同原因 |
| 异常或超时 | confirm且reviewed=false | Auto必需风险规则不可用时不假装低风险；给可恢复状态 | 建议型复核不可用记录告警，不转确认或无限hold；授权/账本等真前提不可验则停止 |

若最终希望任何confirm必问、任何block必拦或任何建议审查故障必停，须明确这是收紧全部允许的新决定，不能作为无感实现细节。本版不采用这种隐形修改。两册T02/T03分别展示“能力暂停原因”和“本次内容复核”，不能只换词而保留两套清除权。

### 构建升级与数据边界

桌面应用与 Rust 可执行文件作为同一签名发布单元，安装后校验版本清单及文件摘要；Android AAR／应用包纳入所支持 ABI 的库、JNA 与生成绑定，锁定 Rust、NDK、UniFFI 和依赖版本。候选首批 ABI 为 arm64-v8a 及测试用 x86_64，覆盖范围仍待产品设备矩阵确定。须实测 JNI/JNA 线程附着、取消、句柄释放、杀进程恢复与 [16 KB 页面兼容](https://developer.android.com/guide/practices/page-sizes)。签名更新、侧进程路径、旧版本回退和依赖供应链检查列入发布门禁。

后置的范围仅为历史用户数据迁移及跨设备同步的实施；OS／ABI 兼容属于本期必须验证的工程门禁，不能推迟到历史迁移阶段。现在即保留 schema 版本、只读旧快照和转换验证契约。升级前使用受支持的 [SQLite 备份方式](https://www.sqlite.org/backup.html) 制作一致快照；旧应用不得写入未知新 schema。以后用真实样本副本验证记录数、引用完整性、金额、附件摘要与任务状态，再决定切换和回退，不承诺现有数据已经可无损迁移。

跨端共享代码不会自动同步数据。两台设备的数据库、授权和任务账本默认独立；新增通用同步、跨端冲突合并、统一身份/密钥共享与离线多主协调需另立方案；单元17既有有限设备交接另按W5继承，不能直接同步正在使用的 SQLite 文件。进入实施前的最低门禁是：同一契约双传输一致、重复请求不重复写、越权投影不可读、慢订阅内存有界、外发关键窗口故障注入不重复发送、升级失败保留可验证快照。以上均为待实施和验证的要求。

未来 iOS 已规划 Swift 与 SwiftUI／UIKit；本轮只预留平台端口和不含 Android 类型的契约，不实现第三套客户端。Swift 绑定接入、后台策略及分发验证留到 iOS 实施阶段，也不据此扩大第一阶段抽象层。

## 7 产品结构与页面手册衔接

当前代码的顶层导航是“助手、任务、资料、设置”；目标方案调整为“助手、工作台、任务”三个主入口，并保留固定设置入口。这是信息架构改动。工作台聚合科研、PDF、询价及通用数据入口，不意味着现有资料功能消失或业务对象只留在聊天内。

| 用户路径 | 第二册页面ID | 与内核的关键合同 |
| --- | --- | --- |
| 表达意图与找历史 | A01–A03 | 消息、项目scope、附件引用、任务关联与草稿 |
| 找项目和最近产物 | W01 | 对象身份、版本、可用能力和授权摘要 |
| 科研与PDF | R01–R08 | 文献身份、页码锚点、选区、证据类型、笔记大纲与版本 |
| 询价与试算及目录 | Q01–Q06、D01.1–D01.3 | 条件版本、报价口径、税率规则、未知字段、比较快照 |
| 任务 活动与批准 | T01–T03 | 真实状态、持久事件、可信计划、回执和取消 |
| 数据 记忆与设置 | D01、S01–S07及子路由 | schema、模型路由、连接、权限、存储、记忆与身份偏好 |

三个主要闭环是“问题 → 文献证据 → 可编辑结论”，“PDF选区 → 字段草稿 → 按模式校验保存”，以及“询价条件 → 候选证据 → 比较试算 → 草稿或台账”。助手负责表达意图，工作台负责持续操作业务对象，任务页负责进度与控制。

第二册逐页给出手机与桌面布局、字段、关键交互、空态、失败、离线、权限失效和验收样例，并提供15组原创线框及本版修订的页面规格。本册不重复具体控件尺寸，页面与F01–F15相对图链见[第二册](Muyon-Page-Design-Handbook-v1.3.1-2026-10-14.md)。页面设计完成不是上线证明；各页是否可开放取决于对应业务波次和平台门禁。

### 既有入口与新增能力的完整归属

| 旧入口或对象 | 新页或子路由 | 迁移波次与边界 |
| --- | --- | --- |
| 询价工作台 项目 报价 | W01、Q01–Q06 | W3，保留预算/比较/报价身份与状态 |
| 供应商目录和详情 | D01.1 | 首片只get/name update/合成JSON导出；联系人、停用和价格史在W3扩展 |
| 物料目录 | D01.2 | W3，类型、单位、规格与关联报价；不把泛数据表视为完成 |
| 公司资料中心 Hub | D01.3 | W3/W5，搜索同事发布的供应商/历史报价，来源与时间、预览/发布/历史/reconcile；S03配置端点与credentialRef；非本机公司基础表 |
| 问数据与AI任务 | A01、T01 | 继承hosted统一助手，关联AiJob状态/续办，不新造重复聊天入口 |
| 同步交换 数据中心 设置 | S05、D01、S01 | W5/W7，既有交换与后置新同步分别标明 |
| 记忆 经验 整理 | S06 | D05/D06及W4/W6/W7，现有入口重设计 |
| 原型 版本 反馈 | W01.1 | W1/W4/W7，脚本沙箱与资源能力另验 |
| MCP客户端和只读服务配置 | S03.1 | W4/W7，HTTP消费与stdio对外服务分开 |
| 设备 配对 消息 收件 研究任务 | S05.1 | W5/W7，文字附件、已读、提议/接受/本人导入研究说明、提交结果/导入科研；迁移排期待决，不能无声删除，不等于新增同步 |
| 消息中心 | T01.1 | W7/W8，站内已读与有效对象跳转，失效目标可解释 |
| 专题/子对话 | A01.1 | W4，独立草稿/滚动/模型选项；关闭视图不取消任务、不继承父授权 |
| 自动 少用 只用文字 | S01.1和A01快捷项 | W4/W7，持久呈现策略；与授权Auto是不同维度 |
| 知识资料列表 检索 重建 删除副本 | W01、A02、D01资料子视图 | W1/W6/W7，源对象、索引和平台副本分离 |

呈现三档保留真实策略与持久化：自动可按已配置策略选可选UI，少用降低可选UI使用，只用文字抑制可选生成卡但不关闭普通业务页；均不切授权、不让模型扩权。具体策略与旧fixture对照，不能做三个标签同一行为。

Q04真实发送与Q06 FX仅为设计新增候选，不等于已有实现或已取得单项开放批准。Folio业务语义继续作为询价迁移依据，新增项须单独冻结范围与验收，不能借路线采纳自动开放。Q04发件账号/收件人/真实发送回执相对旧“复制询价消息/导出表格”是新增适配；未完成服务接线不展示可用发送。Q06跨币种汇率假设是新增试算规则，旧supplier_core不同币种不可比，Exchange/.siq不是FX。汇率来源、方向、时间和舍入须单列合同，试算不偷改原报价/预算。S07风格档案同样新增，不等于旧个人/设备名称改皮。

自动记忆提取与跨会话助手历史检索已明确纳入，首次默认关闭、分别开关；可选聊天留存控制仍待决。D05/W4/W6/W7原预算只覆盖继承和策略合同，不把新增提取器/历史检索服务完整实现无成本塞入。自动提取与跨会话检索现已获批，由新增D11另列实现、隐私验收和净增成本；留存控制仍待决。

### 产物按能力分类

产物应有稳定身份、版本、来源与用途，而不按“看起来是卡片还是网页”授予能力。下列是可组合的能力类别；固定界面和生成界面均使用同一授权路径，生成来源不能扩大权限。

| 产物能力 | 例子 | 允许交互与执行边界 |
| --- | --- | --- |
| 静态可阅读 | 回答、研究摘要、只读报告 | 查看和复制已获准内容；分享与导出另按目标投影 |
| 本地可交互 | 筛选表格、图表、演示、试算面板 | 本地状态直接响应；业务公式由确定性内核统一语义 |
| 受限脚本或原型 | WebView原型、版本化交互页面 | 独立沙箱、受限资源与桥接白名单；脚本身份不获得业务/网络权限 |
| 业务可编辑 | 科研大纲、报价草稿、记忆单条编辑 | 类型化补丁、对象revision、CAS、模式授权和持久回执 |
| 可调用外部动作 | 发送、导出到目标、受控工具面板 | 声明动作、目的地和数据用途，执行账本与系统能力检查 |

一个产物可以同时具备多类能力，但能力清单由可信注册表和Rust返回，不能由生成内容自报。新鲜度、只读/可编辑、已保存/未保存、来源失效和外部效果是不同字段；不能仅用“可交互”承诺可保存或可发送。历史产物仍可在许可范围内阅读，原有动作引用是否可执行必须重新核对当前事实。

助手页应能看见当前模式、来源及执行去向；工作台支持继续编辑持久对象；任务页显示真实账本、执行摘要、capability_hold和content_review的不同状态。记忆管理提供主题、来源、用途、版本及编辑冲突，不把身份偏好混进授权设置。临时会话、Android屏幕读取和个人账号限定只在决策清单出现，不先放一个默认启用入口暗示功能已定。

## 8 渐进迁移与首个可验证闭环

### 建议的迁移原则

1. 先提炼语言无关合同，再移植业务规则。金额精度、单位转换、null 与省略的区别、版本冲突、权限判断、回执语义必须在切换前有明确约定
2. 首片选择一个有明确输入、输出和错误路径的只读业务流程，随后才接入有幂等回执的单项写入。不要将完整 AIUI、导入、同步和所有模块作为首片
3. 现有 Dart 实现、已审查测试和业务样本共同作为对照。已知缺陷不能因为“旧实现也是这样”就进入新的正确性基线
4. Rust 负责业务规则与可信状态变更；两前端只作平台交互与视图状态映射。平台权限和安全存储通过最小能力接口提供，不能把路径、数据库连接或任意执行能力直接交给 UI
5. 每片拥有独立开关、独立测试数据和明确回退入口。功能开关只能切路由，不能保证已经发生的数据格式变化可逆

### 模块迁移分类与留用规则

| 范围 | 建议处理 | 保留条件 |
| --- | --- | --- |
| 领域规则、金额和单位语义 | 提炼合同后移植 Rust | 保留业务约束与反例，不机械保留语言细节；首片仅单供应商详情与名称更新 |
| supplier_core Dart 实现 | 保留为行为对照和旧体验版依赖 | 不与 Rust 同时写生产数据库 |
| supplier_core SQLite 存储 | 重写适配，不默认保留物理 schema | 事务、revision、变更日志与回执语义保留；旧库转换后置 |
| module_api 数据、动作、回执语义 | 保留语义，重新定义跨语言合同 | 与 Widget、BuildContext、宿主生命周期解耦 |
| Flutter Widget、ChangeNotifier、导航和呈现层 | 分别重写 Electron 与 Kotlin 平台绑定 | 复用交互验收目标，不承诺复用 UI 源码 |
| OCR/PDF、安全存储和文件选择 | 平台适配，逐项验证 | 授权、取消、失败和资源释放必须形成合同 |
| 宿主可信确认与权限 | Rust模式策略加必要的平台确认适配 | 保留实时事实重查、计划绑定、拒绝和撤权；全部允许不追加风险确认 |
| AI运行时、动态UI、工具执行 | 保留规则与反例，重写接线 | 模型无权自授权；首片不调用真实模型或真实外发工具 |
| 科研模块、批量写入与复杂导入 | 后续独立业务切片 | 证据类型、引用、原子性、持久回执不能因后置而删除 |
| 旧数据库迁移、同步 | 暂缓独立设计 | 在正式数据切换前完成备份、恢复与冲突策略 |
| 多设备审批与iOS | 仅预留 | 不承诺跨设备统一账本；不创建Swift项目或估iOS工期 |
| 未关闭审查项 C6、CF、LE06 等 | 继承待复核 | 不因技术栈迁移自动关闭或默认开放相关能力 |

本表是设计分类，第3章已提供固定基线清点，实施时由M01复核基线差异和在途所有权。复用须满足行为被理解、测试能检出相应错误、没有带入已知未解决缺陷；旧测试通过不能覆盖最新安全要求。

### 渐进替换阶段和依赖

#### P0 固定所有权和合同

保存旧体验包、固定提交、依赖锁、重要测试和开放风险。清点旧线在途任务，逐项区分继续完成、仅回移关键修复、另行决定；不直接停掉全部任务。首片建议选择单供应商只读详情、受控名称更新和合成JSON导出，不涉及联系人、报价、外部发送或真实模型。

出口G0：范围、合同、数据规则、差异和所有权明确；与在途工作无重复writer。未通过时停在设计，保留旧体验。

#### P1 双端最小纵向切片

先有Rust规则、独立测试库和Dart对照，再接桌面stdio与Android原生绑定。两前端调用同一应用层，显示同一语义结果；随后补受控写入、幂等回执、取消、事件恢复和导出。两端页面可在合同锁定后并行，不能分别设计业务规则。

出口G1：同一fixture经Dart、Rust及两端适配执行，差异均已解释或修复；权限、重复提交、取消和恢复反例可重放。下述28项涵盖P0/P1及其包级验证，不代表全量业务迁移完成。

#### P2 逐业务扩展

建议按基础对象与文件、一个完整科研/PDF闭环、一个完整询价闭环、多步骤工具与动态UI、批量与复杂恢复逐片规划。实际业务先后可调整，权限、存储和回执依赖不能跳过。每片独立列范围、对照集、风险、接线、设备验收与回退证据。未迁移功能明确不可用，或继续在独立旧体验中使用，不在新客户端做虚假入口。

出口G2：拟开放功能在目标平台有真实包证据；受影响历史风险已复核，无阻断的数据损失或商敏泄漏问题。

#### P3 历史数据和同步另立方案

功能切片稳定后，另行确认正式数据范围、迁移窗口、备份恢复和回滚代价。先转换副本、核对后再决定写入权转移。共享Rust不会自动同步数据；设备身份、冲突、密钥、审批和执行账本需单独设计。

出口G3：已批准数据的副本迁移与恢复演练通过，用户明确接受切换和回滚边界。此前生产库仍由旧客户端持有。

#### P4 正式切换和旧版退役

完成准确版本的签名包、升级、未知schema拒绝写、故障回退和支持说明，再逐功能开放。旧版退役需明确决定，不随首片完成自动发生。分支删除不属于本方案的实施范围。

### 首阶段28项可验收任务

下表0.5至1人日保留为1.1原任务时间盒，便于追踪原拆分，不再作为本版当前完整首片预算。它们没有包含新增合同、spike、接线返工与完整验收。当前范围区间见后面的预算表，不能将旧24.5人日当承诺。前提是开发机、Windows/macOS/Android runner与基本工具链可用；设备采购、账号申请、签名凭据配置、生产数据迁移、全量视觉打磨和反复架构探索不含在内。超出时间盒的问题应重新拆分估算，不能靠删验收压进一天。

建议角色：C1为Codex内核/合同，C2为Codex存储/恢复，A1为Claude桌面，A2为Claude Android，G1为grokbot合同/安全测试，G2为grokbot设备/集成测试。只是责任建议，未实际联系或派发；可由具备相应能力的人或工具替代。合同保持单一owner，每项由非作者复审，集成负责人另行指定。

新代码组织采用架构篇的Rust crates：muyon-domain、muyon-contract、muyon-application、muyon-store、muyon-policy、muyon-desktop-host、muyon-android-ffi。样例建议放contracts/fixtures/supplier-v1，证据按完整SHA归档。目录是设计建议，实际落点在M01确认，不为对齐目录而移动旧包。

公共接口子集沿用架构篇的CommandEnvelope、Response、Event语义。首片方法限定supplier.get、supplier.update、task.get、task.cancel、supplier.export；request_id关联传输，scope_id限定范围，idempotency_key绑定一次写意图，expected_revision采用十进制字符串。supplier.update初期只开放name，缺省/null/空值按M02从旧实现提取并审查后的规则处理，不自行放宽。读接口不要求幂等键；可信宿主根据模式授权或该模式要求的确认产生能力引用，不能接受普通UI的approved=true。首片以确定性fixture覆盖Auto与全部允许，不依赖模型为每次操作作判断。

每项实现都先记录预期失败的测试，再实现、重跑目标测试与受影响回归，交付准确提交、红绿日志和非作者审查。表内“通过”均为验收目标，本轮没有实际执行。

| ID | 独立交付物与验收 | 前置 | 建议责任 | 估计 |
| --- | --- | --- | --- | --- |
| M01 | 固定基线及首片文件/在途所有权清单；入口可定位，不触碰旧库和活跃writer | 无 | C1，G2复核 | 0.5人日 |
| M02 | 首片领域合同和差异表；锁定名称校验、错误、revision、权限与回执，并接收P0补充盘点 | M01、A00 | C1，G1复核 | 0.5人日 |
| M03 | 单一schema及生成/编码映射，正负fixture；在D03a草案验证后冻结恢复合同；未知版本、类型错、越界字段不静默通过 | M02、D01a、D03a、SPIKE-01 | C1，A1/A2复核 | 1人日 |
| M04 | 合成fixture和可解释golden；固定时钟/ID，正常、错误、拒绝、旧版本各有样本 | M02 | G1，C2复核 | 0.5人日 |
| M05 | 固定Dart对照runner；独立临时库执行首片并输出规范化结果，失败不改golden掩盖 | M04 | C2，G1复核 | 1人日 |
| M06 | Rust纯领域首片；相同fixture得到合同结果，含中文/Unicode边界及超范围字段拒绝 | M03、M05 | C1，G1复核 | 1人日 |
| M07 | 新测试库和单写入口；对象、revision、回执能原子提交，故障注入无半写 | M03 | C2，C1复核 | 1人日 |
| M08 | 只读详情scope/字段投影；跨scope对象和未授权字段不出现于响应或错误 | M06、M07 | C1，G1复核 | 0.5人日 |
| M09 | Rust受控单字段更新；提交前核验scope/能力/计划/revision，缺省/null按合同处理，失效授权或旧revision拒绝且库不变 | M06、M07 | C2，C1复核 | 1人日 |
| M10 | 幂等键和持久回执；同键同摘要不重复写，同键异摘要冲突，重启后可查原回执 | M09 | C1，G1复核 | 1人日 |
| M11 | 首片取消状态机；提交前取消无副作用，提交后返回已提交事实，不丢回执 | M10 | C2，G1复核 | 1人日 |
| M12 | 首片事件和恢复；完整store_id/scope_id/stream_id/seq同域去重与补拉；process_epoch仅展示回调栅栏；快照与durably_applied_cursor一致提交，慢订阅有界，真实迟到回执单独核对 | D03a、M03、M08、M11 | C1，G2复核 | 1人日 |
| M13 | 桌面stdio编解码/握手；分包、粘包、超长帧、版本错、EOF都有明确结果 | M03、M08 | A1，C1复核 | 1人日 |
| M14 | Electron可信桥接/模式路由；错误来源、频道、伪造批准被拒，renderer无法直接读库或执行命令 | D01a、M10、M13、SPIKE-03 | A1，G1复核 | 1人日 |
| M15 | Electron首片详情/编辑/任务页；加载、冲突、取消、双击和重启走真实桥接 | M11、M12、M14 | A1，G2复核 | 1人日 |
| M16 | Android最小Rust绑定；锁定UniFFI/依赖，成功/错误/非法参数通过真实原生调用 | M03、M08、SPIKE-01 | A2，C1复核 | 1人日 |
| M17 | Android CoreHost/Flow生命周期；旋转重组不重建内核，解绑无旧回调，阻塞不占主线程 | M11、M12、M16 | A2，G2复核 | 1人日 |
| M18 | Compose D01.1首片页面/模式所需确认；返回、进程重建、重复点击不丢草稿或重复提交 | D01a、M10、M17 | A2，G1复核 | 1人日 |
| M19 | 独立权限反例；scope/revision/权限变化拒绝，真前提异常不放行；全部允许高风险及新端点不额外问 | D01a、M14、M18 | G1，C1复核 | 0.5人日 |
| M20 | 确定性崩溃注入；提交前、提交后响应前、重启查账可验证，不重复写或伪造取消 | M10、M11 | G2，C2复核 | 1人日 |
| M21 | 合成供应商JSON导出/两端目的地适配；受限句柄、摘要、同意图重试、半文件恢复 | SPIKE-02、M08、M14、M18 | C2主责，A1/A2配合 | 1人日 |
| M22 | 同command双前端E2E；隔离副本产生相同规范化响应、回执和状态，页面无mock成功 | M15、M18、M19、M20、M21 | G1，G2复核 | 1人日 |
| M23 | Windows安装包冒烟/基础测量；配套Rust加载、离线读写、退出重开，记录包体/进程总量 | M22 | G2，A1复核 | 1人日 |
| M24 | macOS安装包冒烟/基础测量；目标架构、路径、权限与重开通过，不能继承Windows结果 | M22 | A1，G2复核 | 1人日 |
| M25 | Android arm64真包/x86_64测试包；设备/模拟器执行首片，原生库/16KB检查及资源记录 | SPIKE-03、M22 | A2，G2复核 | 1人日 |
| M26 | 权限、模式、revision、幂等、脱敏定向变异；规定变异有对应红灯，还原后准确版本为绿 | M19、M20、M22 | G1，C2复核 | 0.5人日 |
| M27 | 新旧隔离/回退演练；新包不误开旧库，未知schema拒写，停新体验后旧包及旧数据可用 | M23、M24、M25 | C2，G2复核 | 1人日 |
| M28 | 独立组合审查/G1证据包；列pass/fail/未跑/skip、SHA、包hash、设备和风险，只决定首片可否试用 | M23–M27 | G2整理，未参与相关实现者审查 | 0.5人日 |

旧时间盒合计24.5人日仅作1.1审计基线，本版首片以52至79人日的低置信规划区间作为资源讨论起点；不是经实测的排期承诺，也不能按六个角色简单除以六换算日历天。M03前以合同为关键路径；M13–M15与M16–M18可并行；M22以后的包验证依赖完整首片。角色切换、环境等待、返工和用户决定会增加实际耗时。M12/M21/M25若发现协议、平台或依赖问题应追加任务，不能承诺复杂问题一天解决。

### 合同前置 spike与当前预算

| ID | 工作范围和出口 | 前置 |
| --- | --- | --- |
| A00 | 23迁移单元及所有注册module/bin/旧Section逐项归属；授权/记忆合成fixture目录、已有与新增差异清单 | M01后完成，供M02输入 |
| D01a | 首片最小模式合同：Auto、全部允许、四维效果、稳定意图、风险/硬限制区别及taint/new-endpoint fixture；新装默认Auto、旧配置不升权 | M02；其结果是M03/M14/M18/M19前置 |
| D03a | EventCursor、ProjectionSnapshot、ClientApplyState、PendingInput最小恢复合同与正负fixture；完整游标域、持久应用水位、正文留存边界、迟到回执与展示代际分离；规划2–4人日 | M02；草案可与D01a/SPIKE-01并行，统一输出后作为M03前置 |
| SPIKE-01 | 比较统一JSON字节与同源类型化UniFFI，验证Android实际库加载、回调/释放、错误、规范化语义和摘要一致；记录包体/延迟与退出方案 | M02及D01a草案；M03冻结前完成 |
| SPIKE-02 | Windows/macOS句柄与Android SAF目标，权限撤销、半文件、原子rename/替代写法、取消与unknown核对 | M03受控文件合同；M21前完成 |
| SPIKE-03 | 最小Electron+Rust及Android原生包，ABI/API/16KB、单实例与目录锁、原生依赖定位、安装/重开 | SPIKE-01和M03；M14/包级验收前完成 |

依赖主链为M01→A00→M02→D01a、D03a与SPIKE-01→M03→领域/存储/两端桥接→M14/M18/M19→M22→包级门禁。D01a与D03a只依M02，草案可并行；D03a若与SPIKE-01编码出口冲突先协调再冻结。完整D01b后续映射不反向成为首片前置；SPIKE-01可以用合同草案试验，冻结输出必须先于M03，避免环依赖。外发模式由确定性假服务fixture验证，首片不实际联网模型、不发往新端点。

预算单位均为人日，表示建议规划区间，不是报价、实际投入或速度验证。与Claude评审提出的40–60/25–45/320–700区间独立处理：接受需要补全估算的意见，不直接把其低置信数字改名为事实。下表按新增工作包解释增量，首片G1后以实际吞吐和失败修复时间重估。

| 首片预算构成 | 范围 | 假设 |
| --- | --- | --- |
| 原28任务时间盒基线 | 24.5 | 保留原拆分，不含下列新增覆盖 |
| A00与D01a补充合同 | 5–8 | 固定源码可读，产品两档已定，非真实数据迁移 |
| D03a最小恢复合同前移 | 2–4 | 从1.3既有恢复5–9中拆出，不是净追加同一份工作 |
| 三项技术spike净增 | 6–12 | 在既有runner试验，不含采购/账号等待 |
| 首片页面 端侧接线及审查返工 | 8–16 | D01.1只名称编辑，不扩联系人/价格史 |
| 组合负例 设备及故障注入增量 | 6–14 | 不缩减M19/M20/M26/M28证据 |
| 规划合计 | 约52–79 | 四舍五入资源区间；若选型失败，重新拆分，不硬塞上限 |

若3至4个有效工程席位、工具链已就绪且合同决策及时，首片可用5至10周作初步日历情景；并行受合同、真机和集成关键路径限制，不是交付日期。1.2的D系列基线是首片之后净新增约30至52人日，W系列约300至575人日，1.2合计新双端业务试用版约380至702人日。1.3曾把恢复/Stop/游标覆盖5至9人日与记忆覆盖3至7人日全计后续D系列。1.3.1将前者明确拆为D03a最小合同2至4人日（前移首片）和后续恢复实现/故障覆盖3至5人日；记忆仍3至7。重分配后首片52至79、后续D01至D10为36至64、W300至575，小计仍388至718人日，未把前移工作重复相加。本轮用户另批准自动对话记忆提取与跨会话助手检索，D11新增18至34人日，因此当前后续D总额54至98，试用版总计406至752人日。该合计不代表正式生产切换全成本：历史数据/同步/iOS、签名公证商店、设备采购、账号、付费服务、组织多租户和主题整段记忆编辑均不含。全产品生产排期须P3数据盘点、首片实测与各波细分后另锁，不能用此区间宣称“一月全迁”。

### 本版新增的独立设计落实任务

以下D01至D11承接1.1设计落实任务并修正其依赖；D01a与D03a最小子合同已计入本版首片，D01b及其他D任务按后续净新增估算，不能重复相加。它们不是已派发或已实现清单。先冻结跨端合同，再按所有权分派；已有对象版本、旧卡失效和账本不是新增功能，相关任务重点是继承并补齐新模式反例。

#### D01 固定模式与风险合同

D01a在M03之前固定首片必须的最小合同，覆盖独立Auto和全部允许；后者含新网站/API、不重问高风险或taint。用明确fixture的ModeGrant期限和合成scope验证，不能把测试期限写成产品默认。D01b随后完成旧三档×四维×五时长的兼容表、旧policy/grant迁移、正式四档接线、新装Auto默认及旧配置不升权、ADR-AUTH-01正式替代条款。依赖M02，完整迁移以产品待决解决为出口；不把旧映射待细化当作重问已定四档/默认Auto的理由。

验收：相同事实和规则版本结果一致，旧损坏配置fail-closed、旧grant不升权、不延长外传；全允许对新端点零首次询问；Auto高风险确认；无权、撤权、系统限制与非法业务仍拒绝。D01a是M03/M14/M18/M19前置，D01b是W4真实业务权限开放前置。新增Sensitivity分类、可信禁用来源、FullAllow任务内personal/commercial允许与unreviewed禁外发、credential正文/认证分离fixture；对模型请求与工具两个路径抓取合成最终payload和规则版本，不把旧局部遮盖当全链实现。固定基线未找到持久grant的生产issuer或policy writer调用；真实迁移量可能主要为缺失配置→legacy_standard，须在获准P3副本上统计，不虚构已有大量grant。仍保留全部旧枚举合成fixture，缺生产记录不等于删合同。

#### D02 接通生成卡三类事件

交付local_interaction、domain_command、model_intent三类入口及两端适配。验收：折叠筛选不发模型请求；完整保存参数直接进入Rust；已有卡片仅在语义理解或重规划时另建ModelTurn，正常新内容生成任务不受此限制；伪造动作和越权对象拒绝；旧卡仍按既有revision失效规则处理。依赖M03、D01和M14/M18。

#### D03a 首片最小恢复合同

在M03之前交付第5章EventCursor、ProjectionSnapshot、ClientApplyState、PendingInput的schema草案及合成正负fixture。明确store/scope/stream/seq可比域、投影与持久应用水位的原子边界、snapshot覆盖水位、正文留存规则、展示旧epoch与真实迟到回执分流；此任务不建全量恢复实现、不开放新增留存策略。依赖M02，与D01a和SPIKE-01草案协调，M03冻结前完成；2–4人日为从既有恢复预算前移的低置信规划，不能视为一人日M03顺带完成。

#### D03 固定动作状态 回执与执行摘要

交付Task/Attempt/ModelTurn/ToolInvocation/EffectReceipt身份链、稳定intent/plan/key、状态转移、ExecRun/ExecStep投影和SummaryVersion/CompactionReceipt。验收：同意图双击/重投递/重启只复用原回执，同ID异payload冲突；dispatching不报成功；cancel_requested不报cancelled；unknown无证据仍unknown。summary_pending迟到不影响终态，模型自由摘要版本留存，撤回只影响展示。增加用户显式新意图＋acknowledged_unknown_ref绑定、模型/重连伪造拒绝、原/新效果独立以及本机导出新副本限定的验收，不把普通确认变为执行证据。依赖M10–M12、D01a；W4接线前冻结。

1.3出口增加EventCursor/ProjectionSnapshot/ClientApplyState、PendingInput、Stop多轴及提供方幂等能力声明；以REC-F1至F14及N-R用例验证同域恢复、游标不超前、旧代际不吞回执。基础恢复合同与fixture先由D03a完成草案和验证、在M03冻结；D03后续实现依M10–M12；不得另建Android HTTP后台来照搬报告伪接口。

#### D04 区分能力暂停与内容复核

交付capability_hold与content_review两套对象/状态机及ADR-AUTH-02。验收模型与工具两分支的allow/confirm/block/异常/超时；Noop reviewed=false不能显示已完成实质审查。全允许纯风险建议/故障不加问、不无限hold；可信硬限制明确阻断。hold跨重启/换档保留，只由修复/隔离、反例、非作者审查和事实重查解除。依赖D01a、D03及M19/M20；规则分类冻结是W4真实外发门禁。

#### D05 继承记忆 经验与整理

交付单元21的五类记录映射、单条本机编辑、经验核实/退役、离线整理/可选模型辅助、提案接受和防覆盖回滚。新增MemoryRecord CAS和用途字段与旧行为作差异表；S06不是从零新建。验收候选/停用/过期不进上下文、来源/lineage不丢、仅最近完成且完整fingerprint未变可回滚，不覆盖后续人工改动、无模型profile仍可整理。依赖M03/M07与领域身份合同；真实旧库仍P3。

1.3增加同版异摘要分叉、策略域、四控制目标合同与会话不自动写入、关闭/重开在途提案、lineage进入CAS及完整fingerprint补偿回滚。MEM-A1/A2/C1/C2/E3和N-M01/02/03/06为出口；输出从旧表到新对象及策略的迁移差异，不把新增字段缺省当旧数据授权。

#### D06 遗忘 恢复与撤权传播

交付恢复替换域外ForgettingReceipt候选、跨库阶段日志、恢复前重放、五类正文副本清理清单，以及记忆使用/未来自动记忆/未来历史检索的独立控制合同；未提供能力不能靠开关默认为已建成。验收遗忘→旧备份恢复、晚整理回写、snapshot_json/payload_json残留、凭据丢失、崩溃续办和排队/读取/发送/提交四时窗。没有可靠遗忘凭据不得承诺防复活；外发过的内容不能本地撤回。依赖D05及W4基础投影合同，完成后才做W4记忆组合，不依赖整个W4先完成。

1.3增加旧root墓碑、关闭策略和当前执行/幂等证据保全回执、当前与备份禁止集合可信合并、跨域版本不比较、读点封锁与物理清理分离、多来源删源策略、压缩待送输入保全。MEM-B1/B2/D1/D2/E1/E2及N-M04/05/07全部覆盖后才开放对应记忆上下文路径；无凭据换机只隔离，不用同步承诺填缺口。

#### D07 限定身份与账号边界

交付IdentityPreference与账号/工作区身份隔离合同。验收：修改名称、语气或身份文本不产生grant，不切模式，不重开来源；个人账号限定尚未决时不实现隐含组织限制，也不承诺未做的多租户隔离。依赖D01、D05及W7。

#### D08 登记产物能力清单

交付静态、本地交互、受限脚本、业务编辑和外部动作的能力声明与查询。验收：同一组件在不同能力下显示正确入口；生成内容不能自报可执行能力；可阅读不推导可分享或可送模型；静态产物无隐藏副作用。依赖D02及W1/W2/W3。

#### D09 处理局部产品待决

交付Android屏幕读取、临时会话、记忆容量、个人账号限定、可选聊天留存控制、既有设备功能迁移排期的选项、成本和验收边界。Hub和只读MCP服务是现有共享能力，须作为账号范围决策输入，但不能据此承诺完整多租户。FullAllow分类默认、自动提取/跨会话检索纳入且默认关闭、未知效果下用户可信新意图均已决定，不重新放入待决。验收：决策结果有明确范围与生效版本；未决定前不申请额外系统权限、不按未决临时会话或容量策略擅自启用留存/清理、不默认启用待决能力。该任务可先完成设计分析，不以等待决策阻塞无关离线切片；既有记忆读取、手工管理与用户发起整理不因此被冻结。

#### D10 进行跨端模式与记忆组合验收

交付双端同fixture的模式/记忆/生成卡/任务组合证据及非作者审查。验收：断网的纯本地交互及确定性已配置业务动作仍可用；同模式无端侧自行改判；撤权、CAS、旧卡、未知结果、安全暂停和恢复均可重放。依赖D01a/D01b已覆盖部分、D02–D08及M22，D09未定部分明确排除；旧映射待细化不使已定四档失去验收。

1.3组合验收必须覆盖原11＋14例逐项修订和新增15例，双端运行相同fixture各自独立验证，不将两设备自动收敛作为出口。依D03恢复合同与D05/D06继承合同，不因文档完成声称故障测试通过。

#### D11 新增自动对话记忆与跨会话助手检索

两项由本轮用户明确纳入整体改造，首次提供时默认关闭，分别可启用；不同于基线手工记忆、用户整理和当前会话16条上下文。排期独立于Rust首片，不成为M03/M14/M18的新前置。未实现或未过相应门禁时显示未提供，不能给用户一个没有作用的开关；升级不能把未设置自动当作开启。

- D11a 自动对话记忆提取器（规划8–14人日）：依D05/D06和W4对应模型/来源/记忆投影合同，建立可取消、有界、可恢复的提取任务和提案提交路径，来源固定到获准会话/turn版本与lineage；有效开关与conversation_memory_write、用途、authority_revision、全部memory_policy_refs、墓碑在读取/外发/提交点重新核验。模型提案不自动变verified，自动保存的候选必须保留推断标记并按既有核实门槛使用，不能覆盖较新人工修改；是否有无需模型的确定性提取应明列规则。开启不隐含批量回填所有历史，回填须有明确范围合同
- D11b 跨会话助手历史检索（规划6–12人日）：依W6受控索引能力和D06删源/遗忘，建立面向获准会话消息的独立查询及结果来源/时间/版本投影。开关history_search独立于记忆读写、消息保存及当前会话上下文；索引不替代原消息读取权，跨工作区、已删/撤权/不准保留的正文不得命中或进入模型，检索命中不自动写入记忆。默认使用受控本机查询，若选择外部embedding或模型检索必须另走对应外发用途及成本合同，不从“纳入”推导无预算联网
- D11c 新生产者的组合隐私/质量验收（规划4–8人日）：首次/升级默认off、两个开关互不代开、在途关闭、撤权/忘记后晚提案、同版异内容、人工新版本、历史索引失效、跨会话/工作区泄漏、网络失败/重复提取不多写、候选不自动核实。保留来源证据、合成样本、实际SHA、case结果和质量局限；不与D10已有40例重复记工

D11总净增18–34人日，是作者的低置信新估计；以合成离线合同先行、源消息已有可读取/版本身份为假设，不含可选留存控制、临时会话、历史真实库批量回填、外部付费embedding或多租户。规模/质量目标与实际吞吐测量后再估，不承诺模型提取准确率或完成日期。

| D系列首片后净新增 | 规划区间 | 去重说明 |
| --- | --- | --- |
| D01b及D04策略/复核 | 7–12 | D01a已计首片，旧配置UI实际接线归W7 |
| D02/D03/D08合同与投影 | 7–12 | 两端全业务呈现实现归W4，首片幂等不重复估 |
| D05/D06记忆与恢复合同及合成实现 | 10–18 | 完整S06平台视觉归W7，正式历史转换不含 |
| D07/D09/D10边界与独立组合证据 | 6–10 | 未决能力只做选项，不把其实现算已批准 |
| 1.2净新增小计 | 30–52 | 保留历史估算口径 |
| 1.3后续恢复与记忆覆盖重分配 | 6–12 | 后续恢复3–5、记忆3–7；D03a的2–4已前移首片；不重复W系列页面实现 |
| D01–D10首片后小计 | 36–64 | D03a已移入首片 |
| D11新增自动记忆与跨会话检索 | 18–34 | 提取8–14、检索6–12、新组合验证4–8；既有控制/40例不重复计入 |
| 当前D系列合计 | 54–98 | 低置信，按完成定义和实测再估 |

可并行：D05的记录合同、D08的能力分类与D09的选项分析可在各自输入明确后开展；D02两端接线可并行但共用一个合同owner。D04和D06不能在底层事实/账本合同未固定时以UI占位“完成”。

## 9 全业务改造波次

本章接续28项首片任务，说明科研、PDF、询价、Agent、导入导出、传输、OCR、检索与设置如何逐步迁移。28项只证明最小纵向切片，不覆盖下列全部业务，也不能作为全项目工期。以下增加低置信范围预算，仅用于资源讨论；每波启动前仍须以验收项、平台和实测速度拆分，范围变化同步重估。

代码定位固定于 [01e56cc2d729dab70e1b1def05c3aa93b28f421a](https://github.com/mightyoung/Muyon/tree/01e56cc2d729dab70e1b1def05c3aa93b28f421a)，依据本轮只读源码盘点与该提交的本地快照。较早9836bb87的材料只是历史基线，不能代替本章源码证据。本章描述目标方案，未实施、未运行实验或判定相关CI全部通过。

目标模块均为新Rust架构中的建议职责，不表示现仓库已经存在这些Rust实现。桌面采用Electron，Android采用Kotlin Compose；两端共享领域合同和业务规则，各自在自己的隔离测试数据库执行。未来iOS仅预留端口，同步与正式历史数据迁移另立方案。

### 双轨原则与总体依赖

旧Flutter线维持体验可用、必要安全修复和已确认继续的在途工作；新架构线按波次建设。两线不共写数据库，不安排第二个writer改同一任务文件，也不把“迁移”解释为撤销原任务。每个迁移合同有一位owner，每个旧线修复记录原提交、缺陷、反例与适用范围，再判断新Rust是否需同样修复。

旧Dart作为行为对照须有边界：正确语义与经审查的修复进入fixture；已知缺陷进入负例和风险列表，不能机械复制成golden。C6、CF、LE06及其他未关项保留原身份和证据链，迁移后仍需对应层复核，不能靠改文件名、改语言或重写UI自动关闭。

波次编号用于范围归属，不等于全部串行排队：

- 首片门禁通过后，W1文件/PDF、W3询价和W7基础设置可按文件所有权并行
- W2科研证据依赖W1；W6文档OCR与检索依赖W1及对应模块的源对象查询接口
- W4可先做离线协议与只读工具，但开放真实业务工具须等待W2/W3对应命令；开放模型/外发须等待W7授权配置和W5相关执行账本
- W5的本地文件导入导出先依赖首片与W1；业务接受依赖W2/W3；网络传输单列子阶段，不能与“已导入”混同
- W7是跨波次基础，不应拖到最后才补权限或秘密存储。完整设置体验可随能力落地，但能力开启的前置条件必须先通过
- 最后W8做组合验收，所有仍后置能力明确标记，不能以一个绿色总开关开放全部功能

### 全业务波次的资源区间

| 波次 | 规划人日 | 包含的主要增量 |
| --- | --- | --- |
| W1 文件与PDF | 35–65 | 受控字节、锚点/抽取候选、双端阅读和资源身份 |
| W2 科研 | 40–75 | 证据类型、大纲/引用、批量状态及双端编辑 |
| W3 询价与目录 | 50–95 | 金额/预算、目录/Hub搜索、比较与候选新FX试算 |
| W4 Agent与动态呈现 | 55–105 | 工具/模型、MCP客户端、受限原型、专题、摘要接线与三呈现档 |
| W5 交换与导出 | 35–70 | 文件导入导出、旧设备消息/研究任务交换、Hub发布/核对及候选新发送适配 |
| W6 OCR与检索 | 30–65 | 真实引擎、索引失效、资源测量及权限投影 |
| W7 设置与入口 | 25–45 | 双端记忆/经验/整理页面、设备/MCP、消息中心和能力状态 |
| W8 组合与试用切换 | 30–55 | 双端全路径、回归/变异、真实包、独立复核 |
| 合计 | 300–575 | 不含上文首片/D净增与P3正式数据迁移 |

假设既有规则与fixture可复用、团队能持续处理Rust/桌面/Android三个方向、无重大许可重选。区间不是按旧Dart行数机械换算；并行减少部分日历时间，不减少必要证据或总工作。新增规格、MCP服务兼容方案、PDF/OCR选型及正式发送渠道可能改变上限，须先列变更再承诺。G1后以每个验收切片实际周期重排W1–W8，未定旧映射/容量等只阻塞其依赖路径。

### W1 文件身份与PDF阅读基础

#### 目标边界

先实现本地文档登记、受控文件访问、PDF打开、翻页、缩放、选择和稳定来源跳转。PDF渲染留在各平台适配器，Rust统一文档身份、摘要、页序和锚点合同；文本/字形抽取优先评估单引擎，选择前以相同字节、rotation/crop、Unicode与字体fixture验证，不允许两端未经对照各猜位置。先支持已存在文本层的文件，扫描页通过明确的页级定位降级；OCR属于W6。文件导入后可作为隔离测试对象使用，不触碰用户旧资料库。

#### 前置依赖

首片的scope、存储、受控句柄、错误与任务取消合同；W7的文件访问能力和平台权限最小配置。大文件解析应离开UI线程，资源限制先成为合同再选解析器。

#### 现有文件与迁移落点

- [document_parser.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/documents/document_parser.dart)：当前PDF/文本解析与内容摘要入口
- [file_gateway.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/file_gateway.dart)：文件选择、冻结输入与受控文件边界
- [reader_page.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/reader_page.dart)、[source_locator.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/source_locator.dart)、[source_jump_banner.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/reader/source_jump_banner.dart)：现有阅读和定位体验
- 目标：muyon-domain文档/来源类型，muyon-application文档用例，muyon-store附件索引，muyon-platform PDF与文件端口；Electron/Compose分别实现阅读器和文件选择

#### 数据契约

DocumentRef至少区分scope、稳定文档ID、内容摘要、revision、显示名与受控blob引用。PDF Anchor记录内容摘要、零基物理页码、解析器版本、坐标空间、文本片段与可选精确范围；显示页码/印刷页码不得替代物理页身份。

现有source_locator明确区分页级定位、唯一精确匹配和歧义；新的合同保留这种区分。现有citation_resolver使用UTF-16字符偏移，而Rust字符串通常采用UTF-8字节访问，必须定义跨端偏移编码与转换，不把emoji、代理对或组合字符当作等长。精确高亮只能在摘要与定位证据吻合时提供。

#### 关键反例与完成门槛

- 同名不同内容、文件导入后被改写、失效URI、越scope引用、路径穿越/符号链接、密码PDF、损坏PDF、页码越界、大页数、大文件、取消后旧回调
- 双栏/旋转页、相同引文多次出现、emoji/组合字符、缺文本层：不猜高亮，显示页级或歧义状态
- 两端用相同字节和Anchor能到同一物理页；精确范围可独立核对，返回后保留位置，摘要变化立即失效；限额、取消与释放有真实设备证据
- 完成只代表文档阅读基础；不代表OCR、科研写入或历史库迁移完成

### W2 科研证据与大纲闭环

本波中的人工核对是用户编辑或质量核验路径，“接受”是业务状态，均不意味着每次持久化必弹额外授权框。参数完整、证据约束满足且当前模式允许时，Rust可以确定性保存；证据歧义需要补充事实时明确说明缺项。

#### 目标边界

把研究项目、文献、记录、阅读笔记、已接受运行结果、主张草稿与大纲连接起来。先完成“从PDF证据生成草稿 → 人工核对 → 保存引用 → 大纲编辑 → 打开原始来源”的闭环，再扩展多对象/批量操作。未接受运行结果不得自动当作可靠证据，阅读页的只读对象详情不得绕过编辑用例直接写库。

#### 前置依赖

W1文档/锚点；首片的写入版本、回执和授权；完整报告导出依赖W5。本波可先使用离线合成研究数据，不依赖联网模型生成。

#### 现有文件与迁移落点

- [models.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/models.dart)、[outline_store.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/outline_store.dart)：研究对象与有序大纲
- [citation_resolver.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/citation_resolver.dart)、[claim_draft_preparation.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/core/claim_draft_preparation.dart)：引用解析和主张准备
- [writing_page.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/app/writing_page.dart)、[object_pages.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/research_module/lib/src/app/object_pages.dart)：大纲编辑及只读详情
- 目标：muyon-domain研究对象/证据类型，muyon-application科研命令和草稿流程，muyon-store关系/大纲事务；两端科研工作台只渲染投影和发命令

#### 数据契约

EvidenceRef必须含module、对象类型、对象ID、项目、revision与来源摘要，不能只传一个可能在多个表同号的ID。Citation另外携带Anchor、引用文字与解析状态。OutlineNode含稳定ID、父节点、顺序、标题、论点、支持等级与显式类型引用；移动/删除以预览和expected_revision提交。

Draft区分提取值、人工编辑、证据与接受状态；刷新不能覆盖人工修改。ResearchRunRef携带运行身份、接受状态与结果摘要。事务内冻结变更和回执，不能提交后重新读取另一个对象形成“成功摘要”。

#### 关键反例与完成门槛

- entry、note、run同号；未接受run；来源删掉或换内容；跨项目引用；相同引文多匹配；人工改字段后重新生成
- 大纲循环、移动到自身后代、同位置无变化、父节删除的关联影响、旧revision提交、批次中一项失败
- Rust与已核业务规则对照一致；每条引用能定位批准的原始字节；类型歧义拒绝，事务回执对应真正变更；移动/删除预览与最终影响一致
- 两端完成项目/证据/大纲主路径、取消/恢复和只读降级；W5未完成前不把“报告导出按钮”标为可用

### W3 询价报价比较与试算

#### 目标边界

从首片供应商扩展到产品、联系人、报价、询价、项目预算、规格请求/响应和证据，补D01.1供应商、D01.2物料和D01.3公司资料中心Hub。Hub搜索同事发布的供应商和历史报价，标来源、时间、发布记录和历史；preview/publish/reconcile由W5共享账本，S03配置端点与credentialRef；与本机供应商编辑及接受导入分开。真实发送及FX为待单独冻结的新增子片。拆为“金额与口径 → 报价生命周期 → 同口径比较 → 项目试算 → 按模式授权保存”。比较、试算和采用报价是不同命令，试算不能偷偷改项目预算，读取比较结果也不等于授权对外询价。

#### 前置依赖

首片领域与事务基础；附件证据依赖W1，批量导入依赖W5。单条报价可先用合成输入独立迁移，与W2科研并行。AI提取只是后续输入来源，不能替代报价验证规则。

#### 现有文件与迁移落点

- [pricing.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/pricing.dart)、[compare.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/compare.dart)、[spec_compare.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/supplier_core/lib/src/spec_compare.dart)：定价、报价可比性和规格比较
- [quote_form.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/quotes/quote_form.dart)、[compare_view.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/quotes/compare_view.dart)、[budget_table.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/projects/budget_table.dart)：当前报价和预算交互
- [ui_formula_registry.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/ui_formula_registry.dart)、[ui_recompute_adapter.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/ui_recompute_adapter.dart)：宿主公式和重算接线
- 目标：muyon-domain询价/定点数/单位/报价规则，muyon-application比较与试算用例，muyon-store预算快照；两端分别实现密集表格与移动比较卡

#### 数据契约

Money使用币种和十进制定点值，禁止经JavaScript Number或浮点四舍五入改变账面意义。PriceBasis至少区分含税/未税/未知、税率是否已知、计价单位、数量、阶梯条件、附加费用、有效时间和来源。未知税率不等于0%，不同币种不能暗中换汇，不兼容单位不混入同一最低价排序。

QuoteComparison返回可比较分组、被排除/需核实原因和证据，不输出一个遮掉缺项的全局“最优”。ScenarioInput绑定输入revision和条件，ScenarioResult是只读试算；采用结果必须提交单独命令并重新校验版本。历史预算快照保留原口径，报价变更不静默重写旧成本。规格满足、未知、冲突要分开。

#### 关键反例与完成门槛

- 金额极值/精度、0与空、税率缺失、含税切换、单位转换不全、阶梯边界、币种不一致、附加费未知、报价过期/未来/未注明日期
- 供应商停用/删除，报价与产品不符，修改源报价后历史预算漂移，多次试算误落库，确认后条件变化，商敏底价进入普通摘要
- 对照样本覆盖金额、税率、单位和快照；关键舍入与口径由明确合同解释，没有未经批准的规则漂移
- 桌面表格与Android卡片展示相同分组/原因/数值；试算前后库不变，只有授权采用才产生一次回执和预算变更
- 本波完成不代表外发询价、LAN同步或全部AI导入已可用

### W4 Agent流式协议工具与scope投影

本波同时承接D01至D04的模式、三类生成卡事件、capability_hold/content_review及执行摘要合同，以及D06的记忆披露接线；这些是目标设计，不是对固定Dart基线已有能力的宣称。依赖顺序为W4基础投影合同、D06撤权链、W4组合接线与验收，避免把整个波次互设为完成前置。

#### 目标边界

迁移会话、任务、模型轮次、工具选择/执行、事件流、取消、恢复、权限卡和只读/可写UI投影。先用确定性模型回放和假外部服务测试协议，再逐个开放真实模型或工具。MCP HTTP客户端、受限原型W01.1、专题A01.1与呈现三档S01.1各有子片，不因重写主助手而被删。模型文本、结构化协议、工具参数和业务回执分开：预览不是执行结果，模型不能授予自己scope或批准写入。

#### 前置依赖

首片的事件/账本/权限；W2/W3提供相应领域命令；W7提供已授权模型配置与秘密端口；W5提供导出/传输的副作用核对。只读模型回放可先做，真正外发或业务写入不能先于依赖门禁。

#### 现有文件与迁移落点

- [personal_agent.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/personal_agent.dart)、[agent_model_turn.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_model_turn.dart)、[agent_dispatch.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_dispatch.dart)
- [protocol_stream_view.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/protocol_stream_view.dart)、[stream_ui_planning.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/stream_ui_planning.dart)、[agent_resume.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/assistant/agent_resume.dart)
- [tool_registry.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/tool_registry.dart)、[scope_resolver.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/scope_resolver.dart)、[projection_service.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/projection_service.dart)
- 目标：muyon-agent适配模型，muyon-application任务状态与工具调度，muyon-policy scope/能力/投影，muyon-store事件/回执；前端承载本地交互、可信任务投影与有限UI组件，业务动作统一进入Rust

#### 数据契约

Task、Attempt、ModelTurn、ToolInvocation、EffectReceipt分开标识。事件带scope/task/seq/epoch/版本；完成内容经严格验证后成为正式结果。UIPlan引用授权后的ObjectRef/投影，不带全量对象再让前端隐藏。ObjectCatalog是可重建的查找投影，实际打开、导出或喂模型仍向拥有模块重查对象存在、scope与revision。

授权绑定具体计划、对象、版本、目的地和数据范围。恢复只能复用已确认成功回执；结果不明的写/导出不能因resume自动重放。当前agent_resume已明确这些边界，新实现应保留并用反例验证，不因重写而简化成“一键重试全部”。

#### 关键反例与完成门槛

- JSON字符串/Unicode跨chunk，协议半截、工具参数混入正文、错误终态、提示注入、模型伪造批准或对象引用
- 用户取消而辅助UI异常、撤权后旧卡仍能执行、scope切换后旧缓存/事件外泄、老attempt回调覆盖新attempt、慢消费者无限缓存
- 已成功工具在恢复时重跑；网络超时却外部已执行；projection游标重放使已删除对象复活；同名跨项目对象被错选
- 确定性回放在两端产生相同任务/工具/回执状态；严格结果校验与展示预览分开；关键守卫有定向变异红灯
- 所有宣称可用工具经真实Rust应用层执行，权限与副作用账本可查；未核对结果停在待核实，C6/CF相关路径未复核时保持关闭

### W5 导入导出与受控传输

导入接受和导出目标选择是业务步骤；是否追加确认统一服从第6章模式。全部允许可以免Muyon询问，但不能捏造用户未选的保存目标、绕过系统文件授权、覆盖未经当前权限允许的对象，或跳过未知结果核对。

#### 目标边界

分成三个可单独验收的子阶段：本地文件冻结/预览/接受；本地导出及回执（含第5章已定显式新副本例外）；设备或服务传输。第三阶段显式登记设备文字/附件消息、已读、研究任务提议/接受/本人导入说明/人工结果回传，以及Hub发布历史和reconcile；开放排期受各自门禁约束，未决定是否暂留旧端前不得把这些功能删出迁移清单。导入接受、文件已到达、附件完整、已读和业务接受是不同状态。文件传输不等于多设备数据同步，不把收件自动变为业务采纳。

#### 前置依赖

首片的受控目标与幂等账本、W1文件身份；科研/询价接受分别依赖W2/W3；网络传输还需W7配对/证书/秘密与外发授权。可以先离线验收，不自动联系真实设备或外部接收者。

#### 现有文件与迁移落点

- [import_coordinator.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/workspace/import_coordinator.dart)、[import_review_projection.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/app/import_review_projection.dart)、[file_gateway.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/file_gateway.dart)
- [local_export_ledger.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/local_export_ledger.dart)、[local_export_target.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/platform/grants/local_export_target.dart)
- [transfer_service.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/transfer/transfer_service.dart)、[task_coordinator.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/transfer/task_coordinator.dart)
- 目标：muyon-application导入/导出/传输用例，muyon-store意图与回执/暂存记录，muyon-policy目标与外发数据，muyon-platform文件URI和传输端口；平台UI负责可信预览和当前模式所需确认

#### 数据契约

FrozenInput包含内容摘要、大小、文件类型、受控blob、目录清单和版本；预览与最终接受必须绑定同一冻结输入。ImportDraft独立于正式记录，保存时重新校验scope/revision及关联对象。ExportIntent绑定选中数据、投影版本、目标能力、覆盖策略与摘要；build intent不等于已授权执行。

Hub远端搜索的记录只形成带来源与时间的只读投影，不自动写本地库；发布锁定hub端点、业务集合、投影规则版本和payload摘要，先记账后派发，超时先核对原publication，不自动换ID重发；原端点/中心/publication/revision/digest均须匹配，notFound、取消或换地址不证明原请求未执行。若用户明确要求另做一次，才按第5章新意图合同与当前Hub服务约束处理，不能绕过服务真实硬限制。无配置显示未连接，本机业务照常；继承远程明文HTTP拒绝而非仅提示，发布联系人默认不带、纳入范围明确选择，包含项目时提示客户/合同金额，撤回须按中心实际权限处理。FullAllow不自行扩大发布清单，也不因已选personal/commercial内容追加确认；模型不可直接选择Hub发布工具的旧限制保留为迁移事实，新模型入口如需开放须单列合同，不因页面存在自动开放。

TransferReceipt包含传输身份、对端指纹、内容摘要和接收状态，业务接受另有回执。新合同应保留当前transfer_service区分的状态，不用一个success吞掉“已传输但未完整导入”。数据库提交不能使文件系统或网络操作天然exactly-once；恢复必须按阶段核对。

#### 关键反例与完成门槛

- ZIP穿越/膨胀、重复文件名、符号链接、扫描后文件变更、缺附件、摘要不符、文件名欺骗、部分解析、磁盘满和取消
- 预览后目标改变、覆盖超出模式许可或缺系统能力、导出成功但回执未落盘、已批准scope过期、同意图重试生成多份或多次外发
- 对端身份改变、证书/配对失效、重放包、收到文件但业务拒绝、断点中断后重复接受
- 两端合成样本可完成预览/接受/导出闭环；失败可恢复且原数据不被半写；回执能够分别证明传输和业务接受
- LE06及相关导出风险按原证据复核通过才开放对应入口。真实执行任务使用的接收者、正式文件、覆盖、配对和持续访问依然需要相应授权；这里指后续开发测试/上线活动，不给产品全部允许档恢复逐接收者询问

### W6 OCR与检索增强

既有记忆检索与D11b新增跨会话聊天历史搜索可复用索引基础，D11b单列预算与门禁，不合并为文档OCR权限。D05/D06的来源、用途和撤权合同优先于索引命中；相同文字来自不同来源时不能因去重而合并授权。记忆容量与自动清理策略仍待决。

#### 目标边界

先迁移本地文本检索，再补OCR文本和几何，最后根据明确需求加入向量检索/联网embedding。OCR输出是带来源和置信度的提取结果，不自动成为业务事实；索引是可重建派生数据，不能成为权限或源对象存在性的权威。

#### 前置依赖

W1文件/PDF/坐标；W2/W3提供类型明确的源对象与投影；W7控制模型下载、存储位置、资源预算和联网目的地。可先用合成图像/文本做离线检测，真实模型下载或付费embedding单独批准。

#### 现有文件与迁移落点

- [paddle_ocr_service.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/ocr/paddle_ocr_service.dart)、[ocr_geometry.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/ocr/ocr_geometry.dart)、[download_models.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/ocr/download_models.dart)
- [search_service.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/search/search_service.dart)、[knowledge_service.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/knowledge/knowledge_service.dart)、[index_invalidation.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/knowledge/index_invalidation.dart)
- 目标：muyon-platform OCR/解析端口，muyon-application索引任务，muyon-store索引/游标/模型元数据，muyon-policy检索投影；Rust统一结果语义，推理后端另经包体/性能/许可证验证

#### 数据契约

当前OCR结果已有sourceDigest、width/height、pageIndex、EXIF orientation、文本/检测置信度和点坐标。新结果合同保留这些信息，显式标注coordinateSpace、模型/算法版本、解析时间和是否人工修订，不能只传一个拼接字符串。

SearchHit绑定源ObjectRef、内容摘要、page/anchor、片段、匹配理由与当前性；Result同时报告partial和unavailable。索引版本区分解析器、tokenizer、embedding模型及维度。删除、撤权、文件换摘要后失效，展示/导出前仍向来源模块检查。

#### 关键反例与完成门槛

- EXIF旋转、PDF旋转页、透视/低清、混合中英文、数值单位误读、空结果、低置信度、OCR和原文本冲突
- 模型损坏/版本错/下载中断、内存峰值、Android后台中止、取消后的临时文件与句柄泄漏
- 索引含已删/已撤权对象、旧摘要、同号不同类型、中文分词边界、embedding维度变化、模型不可用被伪装成零命中
- 本地检索在网络不可用时仍准确报告其可用范围；OCR坐标在两端能回到正确页/图像，低置信度不自动当真值
- 增量重建/失效可证明，不泄漏无权源内容；实际包的CPU/内存/模型体积与取消回落有测量，不能继承首片小数据性能结论

### W7 设置安全存储与能力状态

设置加入模式范围/版本、自动记忆/记忆使用/历史检索分离控制、身份偏好、两类复核原因，以及S06经验/整理、S03.1 MCP、S05.1设备、T01.1消息中心和S01.1呈现三档的实际入口。默认模式按新装Auto/旧迁移不升权实施；临时会话、Android屏幕读取和个人账号限定仍待决，不擅自启用；设置必须区分尚未决定、平台不支持、未授权和暂时故障。

#### 目标边界

将模型与执行位置、文件/数据目录、设备身份、连接、权限、OCR资源、隐私与日志、外观/无障碍设置做成明确能力状态。初期先实现阻断未配置能力的基础设置，再随每波补配置页面；不因存在一个开关就表示底层能力可用。

#### 前置依赖

首片平台端口与能力枚举。安全存储/模型目的地配置是W4联网前置，文件能力是W1/W5前置，OCR下载设置是W6前置。普通偏好与安全权限分开，不让恢复外观设置恢复旧授权。

#### 现有文件与迁移落点

- [platform_shell_personal.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/screens/platform_shell_personal.dart)：宿主个人与设置相关界面，属于platform_shell的part
- [model_gateway.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/model_gateway.dart)、[secret_store.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/apps/muyon/lib/services/models/secret_store.dart)：模型端点与秘密引用
- [settings_page.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/settings/settings_page.dart)、[ai_settings.dart](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/packages/inquiry_module/lib/src/features/settings/ai_settings.dart)：询价子设置
- 目标：muyon-contract能力/配置视图，muyon-policy允许范围，muyon-platform系统秘密与权限，muyon-store非秘密偏好；两端分别采用平台合适的设置交互

#### 数据契约

CapabilityState区分可用、未配置、缺权限、不支持、临时故障，不合并为bool。ModelProfile区分本机/自己的设备/远程、用途、模型ID、规范化完整端点、身份和credentialRef。界面、执行计划预览及模式要求时的批准内容与实际请求目的地必须一致，凭据本体不进入renderer或普通合同。

配置改变带revision，对在途任务明确“继续有效配置/下次生效/刷新计划并按模式重新判定”的规则。敏感目的地、模型供应方或外发数据范围变化使旧计划授权失效；刷新后若仍在全部允许的有效范围内，不机械追加逐次确认。普通外观偏好不能产生安全授权；设备级身份与工作区级配置不混同。

#### 关键反例与完成门槛

- 秘密存储不可用、凭据丢失/撤销、端点补全后与预览不一致、切供应方沿用旧许可、未配置本地模型却显示离线可生成
- 恢复备份后错误恢复已撤销权限、调试日志带token、设备名称/路径异常输入、不可用开关仍可点击执行
- 两端能够看清实际执行位置与数据目的地；安全能力fail-closed，秘密不出日志/事件/页面；普通偏好不扩大授权
- 只有已通过相关业务波次的能力可标为可用；配置导出排除秘密与不可转移授权，iOS或同步相关项不冒充现有能力

### W8 全业务组合与切换评审

W8不再新增大功能，负责证明已经迁移的能力能组合工作。使用有版本的合成科研/询价案例，串联文件输入、阅读定位、提取草稿、人工修改、比较试算、模式授权或必要确认、落库、检索、导出与取消/恢复。至少包含同一command在两端隔离副本的语义对照，以及一端真实包连续操作的完整用户路径。

现有文件定位沿用W1–W7清单和仓库inventory，不把文档目录中的设计或任务书当作已实现能力。目标是准确版本的双前端包、同版Rust、合同/fixture锁文件和审查证据，不是一个“全部迁移完成”口号。

完成门槛：

1. 每波有范围、准确源码SHA、合同版本、正负fixture、红绿/变异、真实包/设备、未关风险及owner；失败、取消、跳过和未跑分别记录
2. 历史风险均有明确处理：已用对应反例关闭、受影响能力关闭，或经明确决定后置；不把缺测试写为低风险
3. Windows/macOS及所宣称Android ABI/API矩阵实际执行；PDF/OCR/模型载入的资源开销重新测，不使用首片结果背书
4. 接口、权限、取消、旧卡、索引、回执和升级组合没有新增数据丢失/商敏泄漏；独立审查者可从日志复核
5. 测试库与旧生产库仍隔离；正式迁移、同步、发布、签名访问、外部接收者、真实模型数据/费用按单独授权执行
6. 旧Flutter退役必须另行决定；若正式迁移尚未通过，完成状态应写“新架构业务试用版”，不能写“已无损替代旧系统”

到此为止仍不承诺iOS、云同步或跨设备审批统一结算。已有架构为它们预留稳定合同，只在相应方案、授权和验收完成后开放。

## 10 验证 平台测量与数据回退

### 验证框架

#### 行为和合同

- 统一 fixture 使用固定时钟、固定随机源、稳定标识、显式权限和初始数据；对比规范化业务结果、错误码、回执和最终状态
- 两个前端在各自独立副本上执行同一条 command，验证返回语义、业务状态变化、权限拒绝及重试结果一致。不能以共写同一数据库作为“一致性”证据
- 每个切片至少保留成功、输入错误、权限拒绝、过期版本、重复提交、取消、崩溃恢复和敏感数据不泄漏的用例
- 先得到预期失败的红灯，再实现绿灯；保存关键守卫的变异验证，证明移除权限检查、版本检查或幂等键会让测试失败
- golden 只用于稳定且可解释的输出，避免把整段含随机 UUID 的 JSON 当作业务正文安全断言
- 金额、单位换算、显式清空、历史快照、删除引用及批量原子性须单列。若新设计有意改变旧行为，应形成经确认的差异条目

#### 生命周期和权限

- 取消必须定义提交前、提交中和已提交后的不同结果；UI 取消不应把已落盘操作伪装成未执行
- 模拟进程在事务前、提交后但回执前、导出临时文件写入后等位置终止；重启后根据事务和回执恢复，不盲目重放
- 导出重试应验证幂等、目的地授权、文件完整性和临时文件处理；业务敏感内容不得进入遥测、无权限视图或通用错误文本
- Electron 测试覆盖 renderer 到主进程边界：来源校验、输入验证、上下文隔离、沙箱与受限桥接。具体实现应遵循官方安全指导：[Electron Security](https://www.electronjs.org/docs/latest/tutorial/security)

#### 真实包与平台

- CI 应分开记录 Rust 合同测试、前端测试、跨边界集成测试、打包与已安装应用测试，避免把“构建成功”写成“设备通过”
- Windows 和 macOS 需要实际安装包验证。Android 需按支持范围列出 ABI、最低与目标 API、模拟器和真实设备的证据；未跑平台明确标记未验证
- 原生库打包还需核查 16 KB 页支持及其依赖库。Android 官方分别说明了 ABI 和页大小要求：[Android ABIs](https://developer.android.com/ndk/guides/abis)、[16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)
- Kotlin 与 Rust 的 UniFFI 可作为桥接候选，但其官方说明明确区分绑定生成和完整平台分发；因此仍需实际包的加载、生命周期和错误传播验证：[UniFFI user guide](https://mozilla.github.io/uniffi-rs/latest/)

### 关键反例和证据格式

对照规范分为必须保持的语义、明确批准的改进、待判断差异。Dart与Rust不一致时先输出最小差异，不自动选旧结果或更新golden。fixture版本、源码SHA、seed、时钟和初始库摘要一起保存；只按约定规范化非业务随机值，不过滤权限、金额或状态差异。

测试顺序是纯领域、合同解析、存储事务、跨进程/FFI、两前端真实路径、安装包与设备。UI快照通过不是落库、权限或取消通过。

| 风险 | 必须注入的反例 | 合格结果 |
| --- | --- | --- |
| 合同漂移 | 未知主版本、缺字段、超长帧、64位越界、null/省略混淆 | 明确拒绝或按书面规则处理，两端一致 |
| 业务失真 | Unicode、零/负/极值、引用类型不明、历史快照被重算 | 当前切片规则一致；超范围能力不以默认值冒充支持 |
| 授权失效 | 模式授权或确认后切scope、revision改变、撤权、计划变、探针异常 | 提交前重查并拒绝，无部分写或旧授权复活 |
| 重复动作 | 双击、同键重试、同键异payload、重启 | 最多一次本地业务提交，返回真实回执 |
| 取消竞态 | 入队前、事务前、提交边界、提交后、退出页面 | 区分取消请求与已取消，保留已提交事实 |
| 崩溃恢复 | 写后未提交、提交后未响应、导出中途、磁盘满 | 原子回滚或可查回执，无静默空库和重复动作 |
| 商敏泄漏 | 越权字段、过期缓存、搜索摘要、错误、日志、崩溃报告 | 目的限定投影，未授权字段及秘密不出现 |
| 事件失序 | 重复/乱序、游标过期、旧epoch、慢订阅 | 去重或快照恢复，旧回调不串任务，内存有界 |
| 导出幂等 | 同意图重复、目标撤权、路径变、半文件、回执丢失 | 摘要可核对，无静默覆盖；结果不明先查账 |
| 平台生命周期 | Compose重组、旋转、进程死亡、桌面关闭/休眠 | 不重复任务，订阅释放，恢复显示真实状态 |

金额/税率/单位、批量原子性、科研证据类型、OCR置信度及真实外发在后续相应切片补齐，不能永久忽略。外部服务不保证exactly-once；第三方已执行而本地未记回执时保留“结果待核实”，仅在提供方幂等/查询合同允许时恢复，否则保持未知并说明事实缺口；人工判断不替代执行证据，也不自动开放一次可能重复的新派发。

每项关键守卫保存红灯、实现绿灯、反转守卫再次红灯、还原后最终绿灯。例如跳过权限、revision、幂等表或直接返回完整对象。变异存活需要解释并由独立审查判断，不以总覆盖率代替。安全断言针对具体字段和输出渠道，不对含随机UUID整段文本做模糊搜索。

证据包至少记录完整SHA、oracle SHA、fixture hash、工具链锁版本、命令、OS/设备/ABI/API、包hash、红绿/变异结果、审查者和剩余风险。区分pass、fail、skipped、not-run、cancelled；跳过不能计为平台通过。真实商敏样本、密钥和未授权崩溃转储不进入证据包。

### 本版补充的模式与记忆验收

| 场景 | 应观察的结果 | 失败判据 |
| --- | --- | --- |
| 生成卡折叠 筛选 输入 | 本地立即响应，无模型新轮次 | 所有点击被迫送模型，或出现隐含写入 |
| 已完整参数的业务保存 | 直达Rust校验与执行 | 以“安全”强制模型再理解一次 |
| Auto三种风险结果 | 低风险自动、高风险确认、禁止类拒绝 | 模型自报低风险可绕过规则 |
| 全部允许的高风险动作 | 有效工作区权限内直接执行并记账 | 另按风险弹确认，或逐对象隐形补授权 |
| 全部允许遇旧revision | 返回冲突并刷新校验 | 免询问被误写为免版本检查 |
| 超档动作与主动切档 | 保留草稿及明确切档入口 | 静默切到Auto或无理由吞掉动作 |
| 模式变化和撤权竞态 | 执行点采用最新事实，派发后核对回执 | 旧卡、旧配置或晚回调恢复权限 |
| 安全审查恢复 | 准确版本反例及审查齐备，限定能力开放 | 换档或重启自动解除阻断 |
| 记忆并发编辑 | CAS冲突保留两方修改供核对 | 自动摘要覆盖新人工修改 |
| 来源撤权后上下文待发 | 缓存和已拼上下文失效，零新增披露 | 旧摘要或排队任务重新引入来源 |
| 记忆读写与历史检索 | 三个能力独立按设置执行 | 开启其中一个隐含开启另外两个 |
| 产物与身份越权探针 | 能力由可信注册表给出，身份只改偏好 | 生成文本或名称变化产生新授权 |

这些验收需同时记录ModeGrant来源、规则版本、对象revision、派发时间和receipt，不能仅截图确认框存在或不存在。Auto和全部允许至少各有断网、重复点击、撤权、杀进程及outcome_unknown恢复样例；所有结果仍待后续实际工程验证。

### 本版新增的组合反例矩阵

| 编号 | 合成场景 | 必须证明 |
| --- | --- | --- |
| V12-A1 | 旧三档×四维×五时长，缺失/损坏配置 | 旧行为有显式映射，不扩grant/有效期；损坏不默认开通 |
| V12-A2 | taint clean/unknown/tainted×新/已知目的地×model/write/outbound | 全允许新端点免首次询问、纯taint不重复问；真权限失效仍拒绝 |
| V12-A3 | reviewer allow/confirm/block/异常超时×模型/工具 | 区分风险意见/可信硬限制；全允许无隐形确认、拒绝或无限hold |
| V12-A4 | capability_hold后换档/重启/content_review通过 | hold不被清除，恢复证据绑定准确构建与能力 |
| V12-M1 | 五类记忆表含scope/source/kind/时间/disabled/过期/inference/lineage | 字段差异可核；候选经验不进上下文，离线整理可用 |
| V12-M2 | 人工编辑后整理回滚；遗忘后恢复旧备份/晚提案 | 不覆盖人工；墓碑重放先于激活，快照/提案正文不偷复活 |
| V12-E1 | 同intent双击/重连/重启，同action异payload | 同意图原回执或原状态，异payload冲突，不每次点击铸新键 |
| V12-E2 | dispatching断线、cancel请求与提交竞态、核对无结果 | 不伪造成功/取消，unknown核不出仍unknown |
| V12-E3 | 摘要迟到/失败、模型摘要版本、压缩/展示撤回 | 不改权威终态，不删效果账本；可核正文生成版本 |
| V12-E4 | scope seq乱序/重复、epoch旧回调、cursor过期 | 有界重放/快照一致，不声称跨设备全局exactly-once |
| V12-E5 | 旧摘要在撤权后搜索/分享/通知/模型输入 | 当前权限再次投影，标题/计数/引用也不旁路 |
| V12-C1 | 同字段并发、异字段但关联不变量冲突 | 均不自动覆盖；仅证明读写集与条件不冲突才可确定性刷新 |
| V12-P1 | MCP HTTP端点变化与stdio服务schema变化、原型恶意导航 | 目的地/凭据身份重核，只读服务不泄露无权数据，沙箱不扩桥接 |

以上是待执行验收，不是本轮测试结果。每项对应完整SHA、fixture hash、具体命令、实际输出和非作者复核；静态报告不能替代任一绿灯。

### 记忆报告原11例逐项处理

编号MEM对应《MEMORY-LIFECYCLE-04》原编号；来源段落见第2章。表中行为是1.3验收目标，不是现有测试结果。M末尾正常、空态、离线、取消和重复点击作为补充状态集，不另计为第12例；本机离线管理不必等待联网。

| 本版ID | 原例与定位 | 处理 | 修订后的合格结果 | 实施与页面 |
| --- | --- | --- | --- | --- |
| MEM-A1 | A1，M:P0241–44 | 采纳并限同库 | 同一CoreHost两个窗口以v3编辑，先到v4，后到CAS冲突并保留草稿与当前版；保留base才可三方对比。两独立设备库不当同库并发 | D05；S06/S07 |
| MEM-A2 | A2，P0245–48 | 采纳 | 提案基于旧版，当前对象、来源或lineage已变就拒绝；保留提案证据，确定性重算不强制模型，不覆盖当前值 | D05；S06 |
| MEM-B1 | B1，P0249–52 | 修订 | 删源立即封锁该依赖；无其他有效来源的派生事实不入上下文，独立获准来源重验后保留。检索零命中只针对不可用依赖，不等于全库物理清空 | D06；S06 |
| MEM-B2 | B2，P0253–56 | 修订 | 排队上下文执行前重验；能确定性剔除且合同完整则按当前模式继续，缺必要事实待补充/重规划。不笼统让全部允许再确认 | D06；A03/T02 |
| MEM-C1 | C1，P0257–60 | 采纳并加强 | 整理后人工改任一相关内容、lineage、用途或核实状态，完整fingerprint不符则整次回滚拒绝；不复活墓碑目标 | D05；S06 |
| MEM-C2 | C2，P0261–64 | 修订键绑定 | 重复回滚复用稳定回滚intent，绑定原run和完整应用状态，只生成一次补偿版本；不是run_id加单条版本即足够 | D05；S06 |
| MEM-D1 | D1，P0265–68 | 采纳并加强 | 当前旧墓碑先域外保全，再可信合并备份凭据；候选经验、run/proposal正文、索引、摘要和待发上下文过滤验证前不激活 | D06；S05/S06 |
| MEM-D2 | D2，P0269–72 | 未来同步后置 | 首期测旧备份导入及无凭据换机隔离；旧设备重新上线的同步收敛另案，不能把未设计的同步列为首期通过 | P3；S05.1 |
| MEM-E1 | E1，P0273–76 | 采纳 | 撤权后的迟到摘要经authority_revision、来源和遗忘凭据复核，禁止进入当前展示、记忆、检索和下轮输入；最小审计仍按权保留 | D03/D06；T02 |
| MEM-E2 | E2，P0277–80 | 采纳并限现权 | 压缩时保留仍获准历史、当前输入和送达身份；崩溃仅恢复策略允许持久部分，未持久正文不可恢复须提示；已失权内容仍隐藏 | D03；A01/T02 |
| MEM-E3 | E3，P0281–84 | 修订 | 关闭自动记忆后旧自动提交拒绝或保持不可自动应用候选，不靠转待确认绕过；重新开启不复活旧提案，手工管理独立 | D05/D06；S06 |

### 恢复报告原14例逐项处理

编号REC对应《RECOVERY-TRACE-03》F1至F14。原F14的期望“旧版本快照被丢弃”在本版补足同一游标域与版本判据；不从不同时间戳、epoch或内容块数猜新旧。所有恢复仍使用本机桥与同一schema，不要求报告示例的REST端点。

| 本版ID | 原例与定位 | 处理 | 修订后的合格结果 | 实施与页面 |
| --- | --- | --- | --- | --- |
| REC-F1 | F1，R:P0343–45 | 采纳 | block中途断流，按同域已应用游标补拉/快照恢复；文本、通知、计数不重复，展示恢复不重执行业务 | D03；A01/T02 |
| REC-F2 | F2，P0346–48 | 采纳并细化 | 重复去重；乱序先有界缓冲/补拉，缺口不推进持久游标。合法过滤/合并跳跃仅依协议推进证明，不按原审计跳号猜缺口 | D03；T02 |
| REC-F3 | F3，P0349–51 | 采纳 | cursor过期后原子安装数据、水位与权限一致的快照，保留独立新输入/草稿；同域旧快照不覆盖新投影 | D03；A01/T02 |
| REC-F4 | F4，P0352–54 | 修订 | 无法补齐显示partial/unavailable；无新鲜证据不推导完成，但已有真实成功回执不因展示缺口而撤销 | D03；T02 |
| REC-F5 | F5，P0355–57 | 修订 | 执行中进程死亡：可能派发无回执先核对，核不出仍unknown且不重跑；已证明未派发按相应合同恢复，不加FullAllow人工风险确认 | D03；T02/T03 |
| REC-F6 | F6，P0358–60 | 修订 | claim后dispatch前故障，可证明零派发显示未派发；边界不明才unknown。认领本身既不是成功，也不能证明一定执行过 | D03；T02 |
| REC-F7 | F7，P0361–63 | 修订多轴 | Stop与完成竞态，cancel_state、execution_phase和每项effect_outcome按证据独立收敛；停止未来工作可与成功/unknown并存 | D03；T02 |
| REC-F8 | F8，P0364–66 | 采纳并限收敛 | Stop丢包保留stop_unconfirmed，只有执行器事实可更新；无最终证据可持续未知，不承诺必然停妥 | D03；T01/T02 |
| REC-F9 | F9，P0367–69 | 采纳并拆层 | 旧generation的真实结果核验后进入原账本或从当前连接重查；显示片段可拒绝，不能连真实回执一起丢弃 | D03；T02 |
| REC-F10 | F10，P0370–72 | 采纳 | 迟到retract只对匹配scope/片段ID/版本生效，不能误删新片段，也不删除调用、回执或效果历史 | D03；A01/T02 |
| REC-F11 | F11，P0373–75 | 修订 | 离线退出使本机旧审批引用失效，不宣称远端全部拒绝；重登取当前权威集合，旧决定不复用，合法新审批可出现 | D01/D03；T03 |
| REC-F12 | F12，P0376–78 | 不采自动一致 | 两独立设备各自恢复；拒绝他设备/他库/他流游标和审批混入。相同fixture验证语义一致，跨设备最终一致留未来同步 | P3/D10；S05.1 |
| REC-F13 | F13，P0379–81 | 采纳并绑定意图 | 消息发送超时后复用Rust持久提交意图映射，先查受理/送达；新传输request不能新造业务键或第二条已确认消息 | D03；A01 |
| REC-F14 | F14，P0382–84 | 采纳并修判据 | 慢HTTP快照不得覆盖快WS已应用状态；按同域权威水位和权限判断，不按墙钟、complete_blocks或不同epoch大小比较 | D03；T02/T03 |

### 1.3新增的15条组合反例

新增N-M01至N-M07与N-R01至N-R08补强原25例，均用脱敏合成库、固定时钟与假提供方先验证；不自动授权真实账号、模型或设备实验。每条证据包含实现SHA、schema/fixture hash、库与scope/stream身份、故障点、对象/策略/权限版本、游标、实际输出、数据库diff和独立审查。

| 编号 | 故障或组合输入 | 必须证明 | 证据与责任任务 |
| --- | --- | --- | --- |
| N-M01 | 四控制合法组合与conversation_memory_write=false | 自动写为0；读取、保存、检索各自服从策略；手工CAS独立，UI不标无痕 | 策略版本、请求用途、写入与投影；D05 |
| N-M02 | 提案排队、生成及提交前关闭后重开自动记忆 | 旧自动提交拒绝，重开不复活，无FullAllow额外风险确认 | 阶段日志、policy_generation、库差异；D05 |
| N-M03 | 同ID同revision异正文/lineage及跨域版本极值 | 分叉隔离；小revision与大遗忘generation不作比较，不误放行也不误删独立对象 | 谱系摘要、冲突清单、禁止集合；D05/D06 |
| N-M04 | 只有旧root墓碑，域外为空；保全/替换/验证前后崩溃 | 当前禁止集合先保全，候选未验证不能激活，旧可用库和证据仍在 | 保全回执、恢复阶段日志、逐入口检查；D06 |
| N-M05 | 两来源事实分别删源、撤权、停用和彻底遗忘 | 失效依赖不复用，独立有效来源重验；索引/通知/导出候选/队列同步封锁而非等物理purge | lineage读集、各入口及清理进度；D06 |
| N-M06 | 正文不变但lineage/用途/核实状态已变，双击回滚 | 整次fingerprint冲突拒绝；有效重复意图只生成一份新补偿版本 | 完整fingerprint、CAS、intent与receipt；D05 |
| N-M07 | 压缩期间未送输入与tool_use/result随后撤权或失败 | 压缩不丢当前输入/送达身份，崩溃恢复受留存策略约束；配对回执可追，失权摘要不注入 | 消息ID、覆盖digest、权限、回执映射；D03/D06 |
| N-R01 | 接收、写投影、写游标、提交、通知及内容/头阶段崩溃 | 无游标超前、无混版树；旧头不引用被原地改坏的新内容 | 事务/恢复日志、持久游标及投影digest；D03 |
| N-R02 | 相同块数旧正文迟到、旧completed消息及合法retract | 接纳由同域权威版本决定，不以块数大小拦合法撤回或接受旧正文 | 事件、接纳理由、正文与事实表；D03 |
| N-R03 | 快照S覆盖，缓冲S-1/S/S+1/S+3且缺S+2 | 水位去重与有界补拉无丢更新；缺口不抢先推进，合法推进证明另测 | 快照、缓冲上限、应用顺序；D03 |
| N-R04 | 旧进程/展示代际成功回执与旧retract同时到 | 拒旧展示覆盖，通过原身份核账保效果，不将新片段误撤回 | action/attempt/digest/receipt及重查；D03 |
| N-R05 | 同意图换attempt/tool_call/generation；不同意图同参数 | 旧意图仍同业务键，同键异payload冲突；新真实意图不被永久去重 | intent到provider key映射、假回执；D03 |
| N-R06 | FullAllow远端非幂等回执未知且仅普通确认被点击，无明确新业务指令 | 核对无果仍unknown、零新派发、无风险确认；可证未派发另合法续办；用户真实新意图另按V131-T05 | 核对日志、dispatch计数及UI主操作；D03 |
| N-R07 | 离线退出且审批待决，再登录 | 本机旧引用失效，远端标未确认；当前新待决集与旧决定分开 | authority变化、审批ID、实际回执；D01/D03 |
| N-R08 | 两库同scope/seq/对象ID，或旧库恢复重建日志 | 不同store/stream不混入；新stream快照不重铸业务键。旧备份prepared而备份后已派发，恢复仍先核对、无证据不续发；无同步承诺 | 库/流身份、保全账本、导入隔离与dispatch计数；D03/D06/D10 |

以上原25例和新增15例不得合并写成40条“已通过”。原V12矩阵继续保留；相同故障可共享fixture，但必须逐ID说明覆盖与差异，不以截图、计数或竞争产品行为替代账本、权限和库差异证据。

### 1.3.1补充验收门槛

下列为本轮新增/修订范围的待执行用例，独立于已保留的原25＋15编号；不宣称任何测试已通过。

| 编号 | 输入或故障 | 必须观察的结果 | 归属 |
| --- | --- | --- | --- |
| V131-T01 | FullAllow＋taint＋新端点，none/personal/commercial，及有显式禁用/撤权对照 | 当前任务有效允许数据按规则投影且零额外确认；禁用/撤权拒绝有可信来源/版本，不能借风险重问 | D01b/单元14 |
| V131-T02 | unreviewed或未知枚举；模型伪造none；可信规则完成分类 | 分类前零模型/业务披露，模型不能降级；可信分类后重新投影按真实类别，旧plan不盲复用 | D01b/单元03/14 |
| V131-T03 | 业务正文混credential canary，另有绑定认证header及重定向 | 正文/日志无秘密，合法认证仅至绑定服务；更换新业务目的地不复用凭据，记录假传输证据 | 单元18/W7 |
| V131-T04 | Hub未配置、远端搜索、发布超时/notFound/换地址 | 未连接不影响本机；来源/历史完整，查询不自动导入；旧发布仍unknown、不自动重发，原账本绑定不被地址变化解除 | 单元05/W3/W5 |
| V131-T05 | 旧效果unknown，用户真实“再做一次”及模型伪造/重连对照 | 真用户发起新intent＋当前显示/旧记录/目标范围绑定，内联可能重复，FullAllow零额外问；伪造ref、重连或普通确认零新派发；原unknown及回执独立 | D03/W4/W5 |
| V131-T06 | 本机导出unknown后用户新副本；冻结内容/目标/阶段身份被替换 | 合法同冻结内容＋新exportId/A/B＋新目标可形成独立副本；旧unknown不变；换内容/覆盖原目标不冒用例外，系统能力照验 | 单元19/W5 |
| V131-T07 | 设备消息、accept、本人导入研究说明、回传/重启重复 | 送达/已读/接受/导入分轴，accept不运行研究，人工结果需评估；重启不重复既有阶段，不假称跨端全序 | 单元17/S05.1/W5 |
| V131-T08 | D03a fixture与M12回放错store/stream、快照游标超前、迟到真实回执 | 错域拒绝；快照/水位一致应用；旧展示代际不抹真实效果，unknown核对不自动重发 | D03a/M03/M12 |
| V131-T09 | 新装/旧配置迁移及四档切换 | 新装Auto，低风险无第五档；旧缺失/损坏/explicit custom分别保守继承，不自动扩大权限；旧期限不延长 | D01a/D01b/W7 |
| V131-T10 | 自动提取/历史检索首次提供、升级、分别开关 | 两项首次默认off，未提供前不可操作；一个开关不启用另一项、不改变现有保存或手工记忆管理 | D11/W7 |
| V131-T11 | 提取已入队后关开关/撤权/忘记/人工更新，重复回调 | 当前策略/来源/墓碑/CAS重验；不晚写复活、不覆盖新人工版本、不把模型候选变verified，不重复写 | D11a/D05/D06 |
| V131-T12 | 跨会话检索命中跨scope/删源/旧索引/不准保留正文 | 不披露失权正文，结果带可定位来源/时间/版本；检索不自动存记忆或隐式外发embedding | D11b/D06/W6 |

DOCS-G0只核B01/B02文本与迁移追踪，不等待这些工程用例全部通过；受影响真实能力分别在D01b、D03、D11及W3/W5/W7出口前关闭缺口，保持无关离线首片可推进。

### CI与真实安装包矩阵

以下为建议范围，不是当前已有runner或设备的声明。实施前确认目标设备；缺少执行环境不能用交叉编译替代设备证据。

| 层级 | 建议目标 | 验证内容 | 放行条件 |
| --- | --- | --- | --- |
| 内核 | Rust受支持host工具链 | fmt/lint、领域、合同、store、权限、恢复 | 每个相关提交，依赖锁和准确SHA |
| 对照 | 固定Dart与Rust | 首片fixture差异、负例、批准差异表 | 合同/规则/存储变化必跑 |
| 桌面开发 | Electron与配套Rust，Windows/macOS | 真stdio、来源校验、断连、取消、离线 | 两OS分别运行，不只跑浏览器组件 |
| Windows包 | 首批建议x64；ARM64另立条目 | 从包安装、Rust路径、文件授权、启动退出 | 候选包在Windows执行，记录hash |
| macOS包 | 优先arm64；支持Intel时另测x64 | 配套二进制架构、路径、权限、升级回退 | 每个宣称支持架构有执行证据 |
| Android绑定 | arm64-v8a与测试x86_64 | 库装载、绑定校验、错误/取消/释放 | 真FFI，绑定与库同一版本 |
| Android应用 | arm64真机；x86_64模拟器；最低/目标API | 安装、离线、旋转、进程恢复、URI、TalkBack首片 | 真机为发布门禁，模拟器不替代所有真机项 |
| Android原生兼容 | 4KB及16KB页环境 | 所有原生依赖对齐、安装及实际加载 | 不能只检查主Rust库 |
| 发布候选 | 最终组合SHA | 全相关回归、包hash、版本清单、升级回退 | 签名/公证/商店发布另需相应授权 |

APK中Rust及绑定依赖均需检查16KB兼容，按[Android官方指南](https://developer.android.com/guide/practices/page-sizes)落实；ABI覆盖以[NDK官方文档](https://developer.android.com/ndk/guides/abis)为依据。UniFFI生成绑定不等于完成平台分发，需以包内实际加载和生命周期证据验收。[UniFFI官方说明](https://mozilla.github.io/uniffi-rs/latest/)

### 资源测量的条件与限制

首轮应在批准的目标本机或测试机测真实release安装包。固定设备/CPU/RAM、OS/架构、电源与温度、包hash、同一数据集/功能范围、网络/模型状态与缓存状态。旧Flutter与新包必须走可比路径，不能拿全功能旧包与空壳新包比较后宣称整体收益。

| 指标 | 记录方法 | 限制 |
| --- | --- | --- |
| 包体 | 下载包与落盘体积分开，列原生库、模型、缓存 | 模型是否包含保持一致 |
| 启动 | 到可交互与到首个业务结果分别计时 | 冷/热各至少5次，列每次及中位数；小样本不宣称可靠p95 |
| 空闲 | 固定稳定窗口采样，合计Electron进程及Rust | 不只报renderer；后台任务一致 |
| 峰值 | 固定列表/文件/任务与完成后回落 | 首片不覆盖OCR/大模型，不能外推全功能 |
| 交互 | 输入、滚动、切页、取消响应与长阻塞 | 相同屏幕和数据，主观顺滑不替代记录 |
| 恢复 | 终止到可查状态/继续操作耗时 | 正确性优先于速度 |

阈值在第一轮测量后结合目标硬件确认，不预先保证。超标时定位进程、列表、解析、桥接并重估，不通过取消沙箱、跳过校验或泄漏日志换性能。[Electron性能指导](https://www.electronjs.org/docs/latest/tutorial/performance)

### 数据切换门禁与回滚

首期新旧应用使用独立数据目录；新包不得自动开旧库，未知schema拒写。回退只停新体验并用原旧包/旧数据，不反向同步测试库变化。

P3先停相应写入口，做一致备份并验证可读与可恢复；转换副本后核对记录、版本、引用、金额、附件摘要和任务状态，确定新库唯一writer再切换。文件与数据库非同一事务，导出另有临时文件、摘要、完成记录和恢复步骤；恢复旧库不能撤回外部动作。

| 门禁 | 必须具备的证据 | 不满足时 |
| --- | --- | --- |
| DOCS-G0文档采纳 | B01分类来源/已定默认与B02 Hub映射已修、逐项回应及MIGRATION-TRACE；唯一集成人核准入口切换 | 文档修订待核，不能称权威入口已切换 |
| G0开始首片 | 固定合同、A00/D01a/D03a/SPIKE-01、所有权、合成样本、旧版可用及授权范围 | 停在设计，不抢占writer |
| G1试用首片 | M01–M28证据、双端一致、红绿/变异、真包、无阻断风险 | 继续修首片，功能保持关闭 |
| G2扩大能力 | 每片证据及D01b/ADR-AUTH-02对应出口，记忆D05/D06、新增生产者D11对应出口、相关历史风险复核 | 不开放受影响能力，不改名关闭风险 |
| G3碰正式数据 | 已批准范围、副本迁移/恢复、写入权及回滚代价 | 生产库仍由旧客户端持有 |
| G4正式替换 | 最终SHA、签名包、平台矩阵、升级回退、支持说明及切换决定 | 保留旧体验，不称全量完成 |

新库正式写入后，回旧版须用已验证的反向转换/导出，或恢复迁移前备份并明确处理新增写入；不能静默丢弃恢复点后的变化。任务取消、切路由、软件降级与数据库恢复是不同动作。

## 11 风险 待定项与决策清单

### 必须继承的风险

C6 的商敏投影与句柄生命周期、CF 的原因和旧值重算恢复、LE06 的外部结果未知不重试、锁与子进程及 native assets，均作为迁移必须复核的风险主题。本文不把这些动态事项列为已完成或未完成的实时状态表；进入相关切片时应查最新提交、审查意见和 CI，再明确关闭证据。

新语言和新 UI 会引入原先不存在的传输、线程、生命周期与打包边界。现有绿色测试用于发现语义，不直接证明新实现安全。Rust 编译通过也不能证明授权目标正确、商敏投影无泄漏或外部请求不会重复。

| 风险 | 触发条件 | 阻断或缓解 |
| --- | --- | --- |
| 规则双写 | 前端自算业务状态或私自写库 | 内核唯一写入口，双传输共享合同测试 |
| 迁移过宽 | 同时重写 UI 规则 数据与同步 | 按只读切片、受控写入、模块扩展推进 |
| 权限绕过 | renderer 或生成内容伪造批准 | 内核验证能力与计划摘要，敏感投影在查询侧裁剪 |
| 不明外部结果 | 请求发送后进程退出或超时 | 执行账本和回执核实，禁止盲重试 |
| 数据损失 | 新旧客户端共写、降级到旧 schema | 独立数据根目录，迁移备份与恢复门禁 |
| 桥接与生命周期 | JNA 包体或性能、回调竞态、杀进程 | 真机测量，句柄和取消测试，必要时评估窄 JNI |
| 体验不一致 | 两端仅复刻外观，缺失恢复行为 | 按业务路径和错误状态共同验收 |
| 工期失真 | 把首片人日总量当全功能排期 | 完成盘点和首片实测后重估，不承诺一月全迁 |

### 实施前需要锁定的选择

以下保留原技术选项和产品待决；其中全部允许包括新网站/API已于本版确认为决定，不再列待决。技术选型要在spike后冻结，不能把建议当已验证。

1. 桌面首发操作系统和版本、Android 最低 API 与设备 ABI，以及是否包含平板作为正式支持范围
2. 第一条只读切片的业务样本与固定期望，建议从供应商或询价候选详情选一个边界明确的查询开始
3. PDF 渲染和 OCR 引擎、离线能力、依赖许可证和包体预算
4. 模型供应商、文件外发规则、日志保留与本地诊断导出范围
5. React 与 TypeScript 作为 Electron 界面实现的确认，以及 UniFFI 性能和实际包验证的退出门槛
6. 性能预算、正式数据切换时点与恢复标准；这些决策晚于首个隔离闭环，不提前执行同步或旧数据迁移
7. 旧standard/readOnly/custom的显示/迁移及ModeGrant期限细则；正式四档、新装默认Auto、低风险并入Auto已定，不能静默扩大旧权限；全部允许免额外询问及包括新目的地的已确认语义不能反向改写
8. Android屏幕读取是否需要，若需要是手动单次还是明确会话范围；系统能力、提示与后台寿命须另行设计
9. 临时会话是否加入，以及历史、记忆读写、任务产物和诊断留存各自语义；不先承诺“无痕”
10. 记忆容量与保留策略，包括配额、主题组织、压缩归档、过期和删除恢复；本版不硬编码未批准的容量
11. 是否限定个人账号；如需组织或多账号，成员隔离、共享范围和管理责任要单列验收，不由身份偏好推导
12. ADR-AUTH-02的可信理由类型和旧reviewer迁移映射；不可把此实施细化变成重新决定全允许是否对高风险提问。若要更严格模式，须另列明确产品变化
13. 可选聊天留存控制的具体规则；当前消息确已保存，不能在新控制未提供时宣称不保存。自动对话记忆与跨会话检索已决定提供且首次默认关，具体实现由D11完成，不再待是否纳入
14. 既有设备消息/研究任务交接在新端的开放波次与暂留旧端安排，须显式记录，不能静默取消
15. Q04真实发送、Q06 FX及其他新增子片的具体范围与开放条件；文档候选不是单项批准。未知效果下用户新意图已按第5章决定，不能再以待决理由关闭该目标合同

### 设计完成与实施完成的区分

1.3新增模型为MemoryControlPolicy、EventCursor/ProjectionSnapshot及相应恢复记录的设计合同；最终编码仍由M03单一schema生成。它们不替代原MemoryRecord/Task/EffectReceipt权威对象，不代表源码已有表、接口或平台服务。临时会话、容量、旧模式完整映射和其他既有待决继续按原边界处理；未知效果下用户明确新意图按第5章可信关联合同实施，已定本机导出新副本额外约束保留，不偷加FullAllow确认。

1.2补齐旧授权/记忆机制、全部允许含新目的地的决定、两类复核和执行摘要；1.3进一步固定记忆版本/策略/删除传播与恢复分层、Stop和游标故障合同。未定选项有明确实施出口；已定语义继续约束后续合同，不允许用待决占位制造两套执行结果。A00、spike、M/D/W均为任务和验收要求，没有实际产品代码、测试或发布状态。

本报告完成后可以审查路线、合同、任务依赖和验收样例。只有后续实际实现、测试、真机安装与审查证据满足相应关卡，才能宣称某个切片完成。全量生产切换必须另行确认数据迁移、真实用户数据、发布签名与风险接受，用户本轮已明确设计确定后开始改造，因此文档阻断关闭后可按后续明确任务推进隔离开发；这仍不授权真实数据外发、付费调用、凭据扩权或生产上线。

### 进入实际执行前的确认范围

以下事项需在具体执行前明确范围并取得必要授权，本方案未代为批准：

- 正式数据库、联系人、供应商报价或商敏样本的使用，尤其向模型、服务或测试人员传输时的数据、目的地与用途
- 真实模型/API实验的提供方、数据、预算上限和外发行为；合成离线fixture不授权付费调用
- 新凭据、长期访问、签名证书、商店账号和权限扩展；准备工作不能隐含扩大授权
- 安装到用户电脑、替换旧体验、生产迁移、导出覆盖已有文件、发布分发或旧版退役
- 设备采购、付费CI、云机或新订阅；环境未验证前不承诺测试日期

## 12 逐项审查处理与实施退出条件

本章对照用户转交的《Muyon v1.1 两册设计审查报告》（2026年10月13日，258行）与《Claude Android 1.261009.20 执行摘要专题 静态分析》（10页）。前者只读核验固定SHA，未打开DOCX或运行产品测试；后者是base APK静态线索，有反编译失败、未知后台实现及混合常量枚举限制。两者均不能作为Muyon新架构已实现或已验证的证据。

本版将评审分为“采纳”“部分采纳”“待决”“不采纳”。这些是文档处理状态，不代表阻断已经通过实现测试关闭。B1/B2/B3相关实施退出条件分别落在D01、D05/D06、D04；无关的盘点、只读合同和离线原型可以继续。不能把报告的静态建议当成停止所有工作，也不能用文档写完替代工程关闭。

### 正式评审的逐项处理

| 项目 | 处理 | 正文修改与理由 | 实施退出条件 |
| --- | --- | --- | --- |
| B1 授权缺口 | 部分采纳 | 第6章补旧三档/四维/五时长、taint与旧端点底线。采缺口，不采将来源/新端点改称硬前提后继续询问；最新决定全允许含新网站/API | D01a及D01b，旧配置fixture、正式ADR替代范围 |
| B2 记忆继承 | 采纳缺口 | 单元21、第5章、D05/D06补memories/experiences/tombstones/dream_runs/dream_proposals。S06是已有入口重设计，CAS和两级删除是增强 | 五类记录差异、离线整理、回滚/遗忘反例 |
| B3 两类审查 | 部分采纳 | capability_hold与content_review分名、对象、状态、清除权；旧reviewer覆盖model和tool。不采全允许confirm必问推荐 | D04/ADR-AUTH-02双分支全枚举验证 |
| I1 单一合同源 | 部分采纳 | 已有语义合同仍不够，补schema权威源/生成责任；JSON bytes与同源类型化绑定先spike，不强宣一种已选 | SPIKE-01、M03同语义同摘要 |
| I2 幂等键issuer | 采纳并补强 | Rust铸plan/key，创建plan之前也复用稳定intent；相同参数的合法再次执行可以是新意图 | 双击/重投递/重启及异payload冲突 |
| I3 原型与MCP | 部分采纳 | 原文已有耦合表和S03入口；新增单元22/23补全追踪。客户端实为HTTP，不以Android stdio解释其困难 | 生产module/bin覆盖，HTTP与stdio独立矩阵 |
| I4 隐含依赖 | 采纳 | M02→D01a→M03，M14/M18/M19明确依赖；不改成首片仅每次询问 | 无环依赖图与最小模式合同 |
| I5 编辑粒度 | 部分采纳 | 主题浏览与单条本机确定性编辑统一；原文未证明靠模型解析，不把推断当事实 | 离线编辑零模型请求，显式新增/删除 |
| I6 恢复墓碑 | 采纳机制缺口 | 1.1已有防复活目标，现补恢复域外单调凭据、先重放后激活；不称新设计已发生覆盖bug | 旧备份恢复/凭据失败/快照提案清理 |
| I7 业务首片页 | 采纳 | D01.1名称首片、D01.2物料、D01.3公司资料与共享发布；问数据/AI任务归A01/T01 | 每旧Section有映射，首片不扩联系人范围 |
| I8 旧入口映射 | 部分采纳 | 底层LAN/通知/知识已盘点，补设备/消息/专题/呈现三档的页面追踪；不新造无必要顶级入口 | 关闭视图不取消、策略持久化、不删旧功能 |
| I9 工期 | 部分采纳 | 保留24.5旧时间盒，新增spike与分包区间；不把审查40–60等无实测估数写成事实 | G1实测后重估，包级等待/返工单列 |
| I10 自动重建 | 部分采纳 | 原CAS保留；补读集/写集/业务条件均无冲突上限，异字段也未必安全 | 同字段及跨字段不变量反例 |
| S1 链接锚点 | 采纳 | open 227、builder 95、freeze 26、load 170，保留原完整SHA | 链接位置静态核对 |
| S2 线框数量 | 采纳 | 两册统一15组；1.2新增F11至F15，1.3更新F07/F09/F10/F11/F12/F15 | 两册目录及图号一致 |
| S3 批量按钮名 | 采纳 | 旧按钮“允许本批”，区别于“全部允许模式” | 文案与旧合同分别迁移 |
| S4 自动记忆标签 | 采纳 | 明确只控自动写入，关闭不阻止显式手动管理 | 三项能力各自测试 |
| S5 双层单实例 | 部分采纳 | 已有目录锁/单writer目标，补Electron实例协调与OS目录锁；隔离目录可并行用旧版 | 等价路径、崩溃、旧writer互斥 |
| S6 新能力标识 | 部分采纳 | 真实发送与FX相对旧基线新增；S07已是新增页，补styleText实际披露而非重复指责 | 发送adapter/FX独立合同，身份不授grant |
| S7 PDF单引擎 | 部分采纳 | 认同锚点漂移风险，原文并未决定两端各抽文本；单引擎作为优先候选，实测后选 | 同字节/坐标/Unicode/旋转fixture及许可 |

### 执行摘要专题的逐项处理

| 项目 | 处理 | 本版落实 |
| --- | --- | --- |
| 单步摘要与连续折叠组 | 采纳 | 第5章ExecRun/ExecStep投影，失败/unknown/等待用户不被折叠隐藏 |
| summary_pending与迟到摘要 | 采纳 | 与任务终态独立；迟到/失败不重写回执与完成事实 |
| 压缩回执 | 采纳 | CompactionReceipt记录代际和计数方法，界面仅显示边界，不泄露压缩正文 |
| ExecRun/ExecStep/Receipt新权威账本 | 部分采纳 | 采用展示字段，不另造权威；原Task/Attempt/ModelTurn/ToolInvocation/EffectReceipt保持权威 |
| INSERT OR IGNORE可保一次执行 | 不采纳该推导 | 唯一登记不能证明派发/效果/回执原子；同ID异payload冲突、unknown不自动重发 |
| “StepVerified”代表unknown已解决 | 不采纳简化 | 查询仍无证据就仍unknown，核实必须有真实回执/提供方事实 |
| 自由摘要可完全重算 | 不采纳 | 确定性计数可重算；模型文本存版本、来源、生成与授权revision |
| 单调seq即全局恢复保证 | 部分采纳 | 仅scope内seq＋epoch＋cursor＋snapshot，至少一次事件投递，无全局exactly-once |
| Retracted撤回 | 部分采纳 | 仅撤展示片段，不删真实效果与审计 |
| 离线/撤权/取消九态 | 部分采纳 | 保留反例；取消request不等cancelled，离线不一概宣称后台继续 |
| 远程Code/Research全部属于普通聊天 | 不采纳泛化 | 静态能力区分不同产品域，不为Muyon自动新增云子代理或远程控制 |
| 原第9页四档/仅个人/卡片只发新请求 | 不采纳过期约束 | 独立Auto，个人账号待决，确定性业务动作可直Rust |
| 摘要分享与投影 | 补强 | 摘要内容/标题/计数/引用/产物跳转均受当前权限，旧摘要不旁路 |

### AUTH TRACE 02 的采纳与限定

用户新增提供的9页AUTH-TRACE-02报告及PR69固定head下12份证据片段已加入本版静态核对。本轮没有APK运行或动态实验；提交摘录不含完整控制流，因此下述完整链结论仍须标为报告作者的静态分析，不能升级为独立端到端保证。

- Claude CL-03：认领先于execute，重复认领有“已运行但结果不可用”的文案分支；文案不证明效果发生。最多只支持所核调用路径、本地唯一键及同一账本生命周期中的重复抑制，清库/删除/迁移和其他入口另核。认领后执行前崩溃可为零次，不能推导外部或跨设备exactly-once
- Orbit GPT-02：所见请求身份、paramsDigest、SHA-256计算与比较支持参数绑定方向；规范化完整实现与不匹配返回在片段中不完整。仅适用于Orbit/Codex系app-server审批路径，不外推普通聊天或所有连接器，也不据此声称其他产品无绑定
- Claude Code CL-04：决定载荷还含ccrNotifTraceId；未见显式参数摘要不等于服务端没有不可变请求绑定。“sending empty”日志字符串不证明实际空值发送路径已完整还原
- GPT-04只含四条DIL字符串及偏移，不能证明执行前URL规范化或完整拦截覆盖。CL-06的可选ui.domain来源检查不等于全部新站点的用户授权或网络出口防泄漏保证；工具列表/跳过询问两层也不等于所有路径都有两次硬拒绝
- Muse MU-01：PartiallyApplied是审批决定合并结果，不是外部业务部分成功；approvalId/decisionKind/alwaysScope/reason结构不证明服务端缺参数绑定或效果幂等。Rust atomic组仍全成全败，independent组才按真实回执逐项结算

固定出处：[Claude认领片段](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/CL-03-claim-before-execute.txt)、[Code决定字段](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/CL-04-notification-approval-args.txt)、[Orbit摘要片段](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/GPT-02-params-digest-reuse-check.txt)、[DIL字符串](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/GPT-04-dil-host-action-gate.txt)、[Muse决定结构](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/MU-01-approval-decide-chain.txt)。

对Muyon的净增验收：认领后未派发崩溃、重复时回执未形成、参数摘要不符拒绝复用、旧批准过期/撤权竞态、派发后Stop保持unknown，以及审批部分生效不得改写atomic语义。它们补强第5/10章，不能用一张ID认领表替代现有账本设计；也不恢复全部允许的新端点确认或强制业务按钮回模型。

### MEMORY LIFECYCLE与RECOVERY TRACE的逐项采纳

以下处理新报告中的竞品证据与工程推导。M、R标题、样本、段落定位及不可变附件哈希见第2章；未取得的完整反编译片段不补造仓库行号。公开API、开源组件与App行为不互相代证，未发现均保留检索范围和未知。

| 编号 | 来源定位 | 处理 | 本版采用边界 |
| --- | --- | --- | --- |
| E01 | M:P0004/P0056/P0072 | 部分采纳 | 所见客户端无版本条件仅作对照；StateFlow CAS非服务端CAS，服务端锁未知 |
| E02 | M:P0006/P0061/P0227 | 收窄 | 不保证删除全部派生记忆，不等于所有对象一概不传播；Muyon读点封锁为自身设计 |
| E03 | M:P0076/P0147 | 部分采纳 | 写入活动可定位但非持久回执；成功绑定实际对象revision与操作结果 |
| E04 | M:P0074/P0142/P0171/P0225 | 分产品采纳 | 字段、官方语义和实际过滤点分开；不照搬首条消息锁死模式，也不擅定临时会话/容量 |
| E05 | M:P0077/P0122/P0231 | 部分采纳 | 压缩状态与未送输入可借鉴，API内容结构不证明App私有实现；Muyon字段是新设计 |
| E06 | R:P0008 | 不采推论 | JSON并集缺id不证明SSE传输层未处理id，需parser及重连链证据 |
| E07 | R:P0011–12/P0067–73/P0116 | 采纳分域 | 普通聊天、远程Code和本机工具分别描述，不拼成单一通用协议 |
| E08 | R:P0035–40/P0064 | 不采绝对保证 | complete_blocks有已完成独立分支，同计数可异正文；fingerprint非时间顺序，不能证明永不回退 |
| E09 | R:P0041–42 | 保留推断 | 内容先写头后写需不可变版本或事务一致性；原地更新可污染旧头所见树 |
| E10 | R:P0166–67/P0203 | 限条件风险 | 先offset后emit可能有窗口，但依服务端语义和补偿；不是复现丢失或全App保证 |
| E11 | R:P0172/P0187 | 不采泛化 | 流服务片段未见工具执行不等于App无本机工具；只有Muse本机执行的总结不成立 |
| E12 | R:P0248–49/P0065/P0144 | 限路径与生命周期 | 稳定ID且认领记录可用时抑制重复启动，不证明外部效果至多一次，清记录也非未执行证据 |
| E13 | R:P0215/P0218/P0222 | 部分采纳 | max游标不证明发射前去重；审批集合HTTP/WS协调不等聊天流共享持久版本 |
| E14 | R:P0142 | 修订 | NOT_STICKY仅限定无待送启动Intent时的自动重建，后续显式启动仍可发生，不证明远端任务终态 |

工程建议的接纳映射：C01四控制与内部不写标志、C02 CAS谱系、C03旧墓碑保全、C04删除语义、C05完整回滚、C06压缩输入与配对、C07快照与游标、C08展示/事实分层、C09幂等与unknown、C10 Stop/生命周期、C11证据索引，均已融入第3/5/8/10章和对应D任务。第10章保留11＋14个原编号及逐项修订；15条补充用例是新增目标。

不采纳报告中未经本轮用户确认的“临时会话和容量已决定不加”、条目version与墓碑epoch大小比较、选择性回滚自动入首版、旧generation一律丢所有结果、tool_call.state可删执行事实、所有外部键等于tool_call_id、非幂等未知一律人工确认，以及两设备自动最终一致。相应替代合同在正文，不能由旧报告覆盖本轮已定全部允许、Auto与业务UI直Rust。

### v1.3采纳评审逐项处理

对照Claude的2项阻断、6项重要及5项建议。本表“采纳/修订”指设计文本处理，不代表工程测试关闭；源码事实取固定01e56cc2，本轮新增产品决定优先于评审推荐。完整旧文档继承与部分替代表见[MIGRATION-TRACE](MIGRATION-TRACE-v1.3.1-2026-10-14.md)。

| ID | 处理 | 修订落点与关闭边界 |
| --- | --- | --- |
| V13-B01 | 采纳缺口，修订建议默认 | 第6章补Sensitivity、Q7最终分类、可信禁外发来源及版本、credential正文/认证分离；按用户决定FullAllow任务内personal/commercial允许、unreviewed先禁。DOCS-G0追踪缺口可复核；D01b/单元14实际wire验证未完成 |
| V13-B02 | 采纳 | 单元05、第7章D01.3及W3/W5纠正远端Hub、搜索/历史/预览/发布/reconcile与S03配置。页面、迁移及图索引一致后关闭文档缺口；服务测试未运行 |
| V13-I01 | 采纳遗漏，限定证据 | 单元17/S05.1/W5保留消息与研究任务交接；生产接线不称已上线，accept不等于执行研究。开放排期待明确，不采纳默认仅留旧Flutter/退役建议 |
| V13-I02 | 部分采纳，已取得新决定 | 第5/7章区分已有保存/当前会话/记忆行为与新增控制；自动提取和跨会话检索已定纳入且首次默认off，D11另排期/加预算；可选留存控制仍待决。不采纳“基线不保存聊天”或“首版不提供”推荐 |
| V13-I03 | 采纳歧义，按用户新决定修订 | 第5章先核对、不自动重发；真实用户明确再做一次可新意图，acknowledged_unknown_ref必须可信绑定，旧unknown保留。普通确认/ref不作事实或授权；本机导出旧新副本例外额外约束保留 |
| V13-I04 | 采纳 | D03a 2–4人日为M03前置；M12改完整顺序域/快照持久游标/迟到回执；从已有恢复预算前移消重，非机械加总；D11的净增另计 |
| V13-I05 | 采纳追踪，拒绝无依据升级 | 独立MIGRATION-TRACE逐项8源及后续采纳；Folio语义继续约束，Q04/Q06只列新增设计而非已批准；保留CR17和export-N2后续决定 |
| V13-I06 | 采纳唯一建议落点 | 第6章统一AUTH-01→建议0006、AUTH-02→建议0007；已核提交未占用但未盘点全部分支预留，落地前复核；本包不改生效ADR |
| V13-S01 | 采纳 | FullAllow taint不加问已定，待映射仅其他正式档/legacy的详细规则，不把taint再列FullAllow待决 |
| V13-S02 | 采纳 | 第二册S04版本标记更新为1.3.1，不改变旧历史对照中的版本 |
| V13-S03 | 采纳限定 | D01b区分旧枚举存在与无生产issuer/writer证据；真实库副本统计需P3授权，保留全矩阵合成fixture，不凭推测缩减验证 |
| V13-S04 | 采纳 | 第二册F01–F15增加相对PNG链接；本册链接第二册/图索引，不虚构新增图片或重新渲染通过 |
| V13-S05 | 采纳 | D09账号范围分析加入Hub与只读MCP服务的既有共享事实，不等同完整组织隔离承诺 |

补充核验纠正：文档提交e014b097相对843bc791实际新增22文件，不是评审写的32；ADR-0005“每次waitingConfirmation”只是历史段落，后文已有AUTH-1按授权分支，不把整份ADR误写永久逐次确认。以上修订均保留原决定证据，不重写历史。

### 剩余决定和可继续工作

已定内容不重问：Electron/Kotlin Compose/Rust离线、业务UI直Rust、正式四档且新装默认Auto、全部允许高风险免问且包括此前未用新网站/API。尚未定的产品选择包括旧配置映射与期限细则、屏幕读取、临时会话、容量策略、账号限制、可选聊天留存控制和旧设备功能迁移排期。personal/commercial和unreviewed在FullAllow的默认规则、自动提取与跨会话检索纳入且默认关闭、未知效果下用户明确新意图均已由用户明确，不再列待决。schema编码、PDF/OCR引擎、遗忘凭据布局是技术spike选型；content_review可信理由和旧映射是实施合同冻结，不能用它推翻免问语义。

文档阻断关闭后，按用户“设计确定就开始改造”的决定与具体执行范围，可继续M01/A00、D01a与D03a草案、恢复/记忆合同与离线合成fixture、三项spike设计；进入真实工具/模型前须有对应模式/复核合同与测试，进入记忆新路径前须有继承与遗忘/回滚证据。真实数据、付费模型、用户设备安装、外部发送、代码推送及生产切换须按后续任务授权执行。本轮只交付新版本设计文档。

## 附录 证据索引与术语

### 证据使用原则

源码链接固定到完整 SHA；产品文档、官方招聘和平台文档沿用原注明时点；第2章竞品更正沿用1.1于2026年10月13日的核对记录；1.2、1.3及1.3.1追加固定源码与用户转交静态评审，不宣称再次在线验证所有历史官方链接。后续内容可能变化。引用用于支持特定事实或技术约束，不表示参考产品内部采用本报告设计。

本文区分当前源码事实、目标方案与待验证项。后文接口、页面、阈值和任务均为设计；代码存在、历史CI绿色或组件调试页可见，不等于新跨端路径已经接入或通过验收。

### 关键术语

- CoreHost：每个设备上管理内核生命周期、数据库写入与订阅的受控运行实例
- Projection：按访问目的和权限筛选后的数据视图
- Capability：限定动作、目标、计划、时效与次数的授权引用，可来自有效模式或必要确认，不是布尔批准标记
- Revision：业务对象版本，用于冲突检查和审批绑定
- Idempotency key：一次业务意图的稳定去重标识，不等同于一次传输的 request_id
- Execution ledger：外部动作的执行账本，记录准备、模式授权或必要确认、派发与确定或未知结果

- ModeGrant：来自用户所选模式与范围的可信授权记录；全部允许据此免额外询问，不等于忽略现有访问权限
- RiskDecision：确定性规则对动作和事实给出的风险与原因；Auto据此选择自动或确认，全部允许不追加风险确认
- MemoryProjection：按来源权限和当前用途投影的记忆内容，区别于底层完整记录与历史检索
- Capability hold：限定能力与构建版本的工程阻断，只由对应修复/隔离、反例、独立审查及事实重查清除
- Content review：单次模型载荷或工具效果的内容复核，不授权限、不清工程hold、不代替回执
- 允许本批：旧批量确认按钮的新显示名，区别于新版全部允许模式
- ExecRun与ExecStep：任务和工具账本的展示投影，不另造成功事实
- SummaryVersion：版本留存的摘要正文，模型自由文本不能宣称确定性重算
- Cutover：在验证后转移某一范围的使用或数据写入权，不只是切换一个界面开关
- EventCursor：本机存储、scope和许可投影stream内的seq水位，不是原审计全局序号
- MemoryControlPolicy：四控制及会话自动写入限制的策略合同；策略域与对象、权限、遗忘版本分开
- HistoryCompleteness：许可投影范围内的历史覆盖程度，不影响已核实效果的真值
- historical/unreconciled：恢复导入记录尚未与当前执行证据核对的状态，不能直接当作未派发


