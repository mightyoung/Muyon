# Perplexity Android APK：信息收集与展示设计解构

核查日期：2026-10-22（北京时间）；执行位置：云端。对象：用户提供的 Drive APK。本文是静态包分析与官方公开文档交叉阅读，不是安装实测、界面截图或服务端架构审计。

## 1. 结论先行

最值得 Muyon 借鉴的不是某个搜索框皮肤，而是把五类东西分开：**问题与输入材料、正在进行的工作、结构化结果、可回查的证据、可持续组织的项目**。该 APK 的资源与 DEX 数据结构共同支持这一判断。

1. 输入不只是文字：文件、图片、拍照、语音，以及来源范围和搜索模式都有独立表达；附件存在“本地 → 上传中 → 已上传”的状态。
2. 过程不只是转圈：有目标关联的搜索结果步骤，有“正在搜什么”文案和按工具区分的状态。不能由此证明每个状态都在当前账号启用。
3. 答案不只是 Markdown：结果对象同时持有 Markdown、引用、相关问题、附件、结构化答案块和研究报告；正文与证据是有关联但不同的对象。
4. 引用不只是末尾贴几个网址：有引用归属、引用索引、单条/分组点击、引用集合与全部检索结果的区分，并为打不开的来源保留错误路径。
5. 项目不是单纯聊天文件夹：静态资源同时出现会话、文件、链接、指令与产物组织；现行官方称 Projects，代码里仍有 collection/thread/space 旧名。

最重要的限制：没有运行这个 APK，无法交付它的真实界面截图，无法证明任何界面的准确布局、功能开关、账号权益、实时响应或引用正确率。APK 内没有服务端搜索排序、模型推理和引用真实性的完整实现，不能由客户端反推出这些机制。

## 2. 样本身份与分析范围

|项目|本次取得的证据|
|---|---|
|来源|[用户提供的 Drive 文件](https://drive.google.com/file/d/1oS9T7TS8m4GG6fzvatOQvnBzu40y6PN4/view)|
|文件名 / 大小|perplexity.apk / 108,147,851 字节|
|Drive 修改时间|2026-10-22 02:18:47.399 UTC，即北京时间 10:18:47.399；不是 APK 发布日期|
|SHA-256|643142eb02102f466c5b8e051e78ae006a5675c969dab56ae9ff1d2fcb3be86f|
|包名|ai.perplexity.app.android|
|versionName / versionCode|2.101.0 / 260665|
|minSdk / targetSdk|32 / 37，均来自 manifest 声明|
|入口|ai.perplexity.app.android.ui.main.MainActivity|
|证书 SHA-256|b5c7a5c959b1626fb0e77bc5b72e8c394ab5c2671702a8ddf10b9bdbb0bf6d18|
|证书主体|CN=Android，O=Google Inc.；只提取到证书，未与可信官方发行证书对照，也未完成 APK 签名完整性验证，不能认定为官方未修改原版|
|静态覆盖|解包 2,717 项；4 个 DEX 共 186,609 个字符串；解析 manifest、默认/中文字符串资源，并读取相关 DEX 类/方法指令中的常量与字段|

证据等级：A=包内结构/方法静态证据；B=包内资源文案；C=官方网页描述；D=本文设计推断/建议。A、B 均不等同于功能已在用户设备运行。未安装运行 APK，未登录账号，未调用包内接口，未使用包内凭证，未上传第三方分析平台，未改 Muyon。

## 3. 信息收集：入口、范围、状态分别建模

### 3.1 多入口共享输入上下文，而不是把所有入口混成一个按钮

B：中文资源有 file_source_camera / gallery / library，分别指向拍照、选图和文件；a11y_search_view_actions_voice_input、main_v2v_*、assistant_* 则分别描述口述、语音对话与 Android 系统助手。a11y_search_view_actions_source_and_mode_selector 明确将来源输入与搜索模式放在相关但可区分的选择器中。

A：manifest 声明 CAMERA、RECORD_AUDIO，并包含 AssistantActivity、WakeWordEnrollmentActivity 等组件；资源包含声纹和唤醒词模型文件。这仅证明包有相应组件与资产，不代表权限已经授予、功能已开启、数据实际上传或持续监听。

C：[图片上传官方说明](https://www.perplexity.ai/help-center/en/articles/10354840-uploading-images-on-perplexity)描述移动端从“+”选图库或拍照。[Android Assistant](https://www.perplexity.ai/help-center/en/articles/10450852-how-to-use-the-perplexity-android-assistant)描述系统助手入口。两者不能被当作同一输入流程的实测。

D：Muyon 应先把“要问什么”和“使用哪些材料”做成同一草稿的两部分，附件 chip 可删除、查看状态。语音先作为可编辑转写入口，系统级助手/唤醒词另立范围，不必为了模仿竞品扩大权限。

### 3.2 附件有生命周期，附上文件不等于已理解全文

A：classes2.dex 的 Lj12;→toString 显示 AttachmentState：id、localFile、localFileInfo、remoteFile、uploading、uploaded。Lqzl; 表示可保存附件状态；classes.dex Lkvc; 的 f/g/i 方法出现 thread-attachment-chip、thread-attachment-item、thread-attachments-summary 的 UI 标识。

B：file_upload_error_* 区分格式不支持、过大、过小与审核失败；额度提示还分日/周口径，但实际额度不能从静态文案确定。

C：[File Uploads](https://www.perplexity.ai/help-center/en/articles/10354807-file-uploads)说明长文件提取相关部分；音视频主要处理语音转录，视频视觉场景不建立可检索索引。不要把“接受视频文件”写成“理解视频画面”。

D：Muyon 需要比竞品更明确的本地研究材料状态：已选取、已保存、OCR 中、文本已提取、索引中、可检索、部分失败。每个状态来自真实结果，显示页数/提取范围和失败原因；不能用上传成功代替解析成功。

### 3.3 来源范围与执行权限不要混在一起

B：source_web、source_academic，以及 Drive、GitHub、Notion、Slack 等 connector 描述表明来源有种类。部分 connector 文案同时包含搜索和写入动作，不应把“连接来源”理解为天然只读。

C：[Pro Search](https://www.perplexity.ai/help-center/en/articles/10352903-what-is-pro-search)描述不同搜索范围；[来源选择说明](https://www.perplexity.ai/help-center/en/articles/10354759-why-can-t-i-see-focus-mode-on-my-search-bar)含企业专属和退役中能力，不能直接套用所有个人 Android 账号。

B：connector_details_feature_standard_search_description 与 high_precision_description 还区分查询时检索和选定项目持续同步；连接成功不等于全量导入。connector_permissions_section_read/write 和 allow/ask/block 明确区分读取、写入以及询问策略。静态数量/套餐文案不可直接当作当前账号权益。

D：Muyon 查询前显示“当前项目材料 / 全部本地材料 / 公开网络”，另显示将外发哪些内容。材料检索权和外部写操作权拆开；先完成已有本地能力，不因静态看到 connector 就扩展到第三方账号。

## 4. 过程展示：工作步骤必须有真实事件依据

A：classes2.dex Lifm;→toString 是 SearchResultsStep(uuid, goalId, webResults)；Ligk;/Llgk;/Logk; 为远端搜索步骤与内容模型，Lk2i; 为 SearchResultsReceived(sources)。这支持“目标—步骤—来源”链路，而不是只有一个正在思考标志。

B：searching_web_query / workflow_searching_query 可带具体查询；workflow_tool_searching_* 分文件、学术、图片、网页、连接器等；语音状态的可访问文案明确提供停止操作。

C：[Advanced Deep Research 官方说明](https://www.perplexity.ai/help-center/en/articles/13600190-what-s-new-in-advanced-deep-research)描述阅读中的来源、中间发现、报告进度及运行中追问。这是跨平台官方宣称，不能补足本 APK UI 实测空白。

D：Muyon 可展示“搜索到 8 条 → 打开 5 条 → 提取成功 4 条 → 引用 3 条”，但每个数字必须来自实际事件；无法确定总量时不显示百分比。步骤记录 query、source IDs、started/completed/failed/cancelled 与错误。未知费用、请求 unknown、局部失败要留在状态中，不用成功动画覆盖。

## 5. 信息展示：正文、来源与可信提示是三层

### 5.1 答案容器是结构化数据，而非一段大字符串

A：classes.dex Lrs0;→toString 的 Ask 模型同时包含 resultMarkdown、webResults、markdownCitations、relatedQueries、attachments、widgets、structuredAnswerBlocks、workflowResearchReport、pendingFollowups、inlineClaims、status、expiryEpochMillis 等字段。字段共存只证明客户端容器支持这些形态，不保证每次回答都会产生这些内容。

D：Muyon 应区分正文块、证据块、表格/公式块、文件产物与后续问题；各块可独立失败、重试或更新。聊天结果与可长期保存的研究报告分开，不把“已生成一段回复”当成“报告版本已归档”。

### 5.2 引用有身份与归属，可展开、可失败

A：classes.dex Lcvd; 为 MarkdownCitations(citedWebResults, webResults)，存在“引用到的来源”和“全部检索来源”的区分；Ld9p; 为 CitationAttribution(contextUuid, backendUuid)。classes2.dex Lhc7; / Lic7; 区分 CitationClicked(sourceIndex) 和 CitationGroupClicked(webResults)。Ltd7; 的 r0/t0 方法明确包含无可打开来源、空引用 URL、空 session ID、未支持来源的错误路径。

B：computer_session_tab_sources、computer_sources_group_web / connectors、group_expand/collapse 表示来源页及分组；claims_title_sources / calculation、claims_calculation_chain、claims_copy_formula 表明部分答案可展开来源或计算依据。

D：Muyon 最有价值的实现是“段落主张 → 证据片段 → 原始 PDF 页码/文件版本/URL”。引用按钮应能落到真实原文位置，不只打开 PDF 首页。检索命中与正文支持分开计数。来源不可打开就显示原因，不悄悄删掉编号或给出空跳转。

### 5.3 信任标识不能取代事实核验

A：classes2.dex Ljs5;→I 方法有 has_trust_indicator、trust_level、trust_type 字段。B：trust_category_academic / government / trusted 与 trust_details_content_description 显示存在分类和详情入口。仅此无法证明信任分级算法、权重、人工审核或对事实正确性的保障。

D：Muyon 更适合展示可解释的证据类型：“作者实验 / 官方说明 / 独立复现 / 用户观察 / AI 推断”，并显示版本、日期、可访问性。域名来自政府或论文平台并不等于该项论证成立，避免无解释的绿色可信勾。

## 6. 追问、项目与持续收集

A：Ask 模型含 relatedQueries、pendingFollowups、collectionInfo、isBookmarked、fromHistory；RemoteAsk 序列化模型保留 parent_info、collection_info、bookmark_state、privacy_state、expiry_time。B：资源支持把会话加入项目、历史按模式组织、项目文件/链接/指令等。

C：[Session 官方说明](https://www.perplexity.ai/help-center/en/articles/10354769-what-is-a-thread)把问题、追问、回答、来源归入一个会话；[Projects](https://www.perplexity.ai/help-center/en/articles/10352961-what-are-projects)聚合文件、任务和指令。网页已更新为 Sessions/Projects；APK 内同时保留旧命名是演进痕迹，不代表存在两套独立功能。

D：Muyon 应把追问保持在当前材料/项目上下文内，并允许用户明确切换范围。项目保存证据、报告版本、失败记录，而非只存聊天标题。建议先做“从答案收藏一个证据片段到项目”，再考虑自动持续收集；后者需要真实授权与可审计执行。

## 7. 隐私与不可下结论的部分

- Manifest 声明日历、联系人、短信、位置、屏幕上下文等权限，说明包面对更广泛系统助手场景；不说明这些权限被授予或信息已被采集。本文不是隐私审计。
- 无痕资源有“不保存活动/不进资料库”与“24小时后过期”两种表述；二者可能描述不同层级或历史界面，不能据此承诺零留存。
- AI Data Retention 标题下的文案实际描述模型改进用途；不能把该开关等同历史删除、个性化关闭或零保留。隐私设计至少区分历史可见性、保留期限、记忆引用、训练用途与第三方共享。
- 声纹文案称默认设备端存储，改善识别的数据分享可选且默认关闭。这里只读到了说明，没有验证网络传输或默认开关。
- 无法静态确定实际后端模型、检索索引、排序算法、抓取成功率、引用支持率、订阅门槛、服务端实验分流、接口计费和账号地区差异。
- 此包具有混淆，短类名只能在该 SHA 样本中定位，不是稳定模块 API 名。

## 8. 给 Muyon 的具体优先级清单（建议，不是已实现）

### P0：使现有研究流程可解释、可验收

1. 附件状态机与失败恢复：文件已存储、OCR/解析/索引分别记结果；退出重进不丢状态。验收：故意坏文件和中断后仍能解释失败、重试不重复入库。
2. 原文可定位引用：稳定 source ID + 文档 hash/version + 页码/片段范围；引用与正文段落绑定。验收：点击每个编号可到对应片段，失效源可见。
3. 真实过程日志：检索/解析/生成的真实事件，不给无依据百分比。验收：取消、超时、unknown 与部分成功均保留。
4. 回答与证据分栏/分层：先读摘要，按需看引用与原文。验收：未被引用的检索结果不会被误标为答案依据。

### P1：降低持续研究成本

5. 项目内资料范围选择，追问沿用范围且可见；明确本地与网络边界。
6. 报告、笔记、证据、会话分类型归档；同一报告以新版本追加，不覆盖旧判断。
7. 引用卡显示标题、作者/机构、日期、文档页码、证据类型与可访问状态；可信标签必须能解释。
8. 草稿附加图片/文件、可移除 chip、解析预览；语音先转写可编辑，不急于做持续录音/唤醒。

### 暂不建议照搬

不先做大而全的系统助手权限、第三方写入连接器、无依据的“可信评分”、伪进度动画、自动研究闭环或真实付费请求。优先闭合已有本地研究与证据链，再按已批准边界扩展。

## 9. 下一步验证应是什么

静态拆解已完成这一轮。若要准确比较布局和操作成本，下一步是对**来源身份先核实**的 APK 进行受控运行，记录输入面板、上传失败态、过程页、引用展开、来源分组和项目归档；当前未安装或运行用户提供的 APK。安装/运行这个来源未核实的包需要单独确认，不应把本次“分析”授权扩展为运行授权。

Muyon 设计评审可以立即使用本报告的 P0 清单，但实现顺序需结合实际分支与现有任务确认，本文没有修改仓库或创建新任务。

## 附录：可复核证据定位

- manifest：AndroidManifest.decoded.xml；包元数据：metadata.json。
- 资源：resources-'zh'.xml，以本文列出的 key 搜索；默认 resources 对应英文回退。
- DEX：dex-evidence-index.json 保存相关字符串出现的 dex/class/method；selected-class-evidence.json 保存目标类字段和方法常量摘要。原始位置由本报告 SHA 固定。
- 官方补充：official-research.md 提供13个官方链接、页面时间与版本限制。

复核要点：文件哈希固定样本；资源 key 可复找；class/method 只证明静态设计；官方文档是跨平台现行描述；没有任何截图或线上效果被冒称实测。
