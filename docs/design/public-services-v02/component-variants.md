# Public services v0.2：组件变体候选

本稿是 U0 的具体评审输入，designStatus=draft，publicservices codeStatus=absent，integrationStatus=not_connected，acceptanceStatus=NOT_RUN。整体实施计划获准执行，不代表以下具体尺寸、密度和页面组合已经获准。设计 GREEN 尚未发生；U2/U3 外观实施继续关闭。U1 纯合同另等父任务交付 C1 固定接口及 fixture SHA。

## 固定输入与来源

- 实施计划与总索引固定为 `64900d4a6a46a9ef2919bcf922fb059413b1ce82`：[U0–U3](https://github.com/mightyoung/Muyon/blob/64900d4a6a46a9ef2919bcf922fb059413b1ce82/docs/superpowers/plans/2026-10-23-intelligent-ui.md)、[总索引](https://github.com/mightyoung/Muyon/blob/64900d4a6a46a9ef2919bcf922fb059413b1ce82/docs/superpowers/plans/2026-10-23-public-services-index.md)、[v0.2 设计](https://github.com/mightyoung/Muyon/blob/64900d4a6a46a9ef2919bcf922fb059413b1ce82/docs/superpowers/specs/2026-10-23-public-services-ui-design.md)。这些文档尚不在本产品基线，链接固定 SHA，不复制另一套合同。
- 产品检查基线为最新 develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`，隔离分支 `task/publicui-u0-20261023`。初始旧 work/main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` 未作基线。扫描 /workspace 和该 develop 树未发现 AGENTS.md。
- 视觉方向为 [400e206 统一规范](https://github.com/mightyoung/Muyon/blob/400e206135690c284c8402521e3135cfb7bfaee8/docs/design/2026-10-22/ui-v1.0/Muyon-统一UI规范与覆盖-v1.0.md)，完整读取文字；本轮另核看图 01、02 与 08。其余图片不作本轮逐图核看或运行证据。规范图 03/04/05/06/07 为下文语义映射依据，不把栅格尺寸当 token。
- Foundation 实际路径是 `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/`。计划写的 `ui/foundation/` 在基线不存在。读取 FoundationTokens.kt、FoundationComponents.kt、README.md；保持所有者文件不变。
- Shell 最新只读候选封套 `07aeb5e45fda046446557f5083553ef2c885fc85`，其 REPORT 固定生产源 `d61be4b50c3f4877022008e5493ade1ba78a96ad`。报告区分编译/lint、独立组件 fixture 与完整产品运行；这里未复跑，也未合入该候选。shellFinalSha 尚待父任务/原 owner 正式交接；该字段保持 pending，不把候选当已合基线。

本设计封套 `reviewPublicUi(...)` 是文档输入输出，不新增产品 API。existingFoundationPaths、approvedVisualDirection、cardInventory 见本页；pageCompositions 见 [页面矩阵](page-acceptance-matrix.md)。所有公共十族的具体变体仍 draft；既有代码存在只记 present，不反推 reviewed 或 PASS。

## Foundation 现状盘点（不作为视觉定稿）

下表均由产品基线 `fd26dcdabcdac996bc2881e8141cac2b519966fc` 的真实源码读取；FoundationTokens.kt 最近变更提交 `a810f204c27658a43f3ed13cca7ea0e59ce450b8`。完整来源：[Tokens](https://github.com/mightyoung/Muyon/blob/fd26dcdabcdac996bc2881e8141cac2b519966fc/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/FoundationTokens.kt)、[Components](https://github.com/mightyoung/Muyon/blob/fd26dcdabcdac996bc2881e8141cac2b519966fc/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/FoundationComponents.kt)。

| 真实名称 | light | dark | 用途 |
| --- | --- | --- | --- |
| FoundationPalette.background | #F5F5F3 | #252523 | 柔白/柔黑背景 |
| FoundationPalette.panel | #FAFAF8 | #30302D | 面板 |
| FoundationPalette.text | #2E2D2B | #F5F5F3 | 正文 |
| FoundationPalette.secondary | #646360 | #C2C1BA | 次要说明，仍需可读 |
| FoundationPalette.border | #80807C | #999991 | 必要边界 |
| FoundationPalette.link | #3F6480 | #A8C7DE | 明确来源链接，非整屏主色 |
| FoundationPalette.action | #2E2D2B | #E5E5DF | 浅色炭黑主操作；深色遵从已有反色 |
| FoundationPalette.onAction | #FAFAF8 | #2E2D2B | 主操作前景 |
| FoundationPalette.error | #923B35 | #FFB4AB | 错误文字与标记 |
| FoundationPalette.detail | #766653 | #C2AE96 | 少量身份细节，不铺底 |
| FoundationTokens.minimumTarget | 48.dp | 48.dp | 最小触控区域，无固定最大高度 |

FoundationTheme 将 bodyMedium/bodySmall/labelLarge/labelMedium/labelSmall 设为 16.sp、24.sp 行高；bodyLarge/title 等仍来自 Material Typography()，不能声称整套字阶已定为 16sp。FoundationTheme(dark, reduceMotion=true) 提供 LocalFoundationPalette/LocalFoundationReduceMotion；surfaceTint=Transparent，普通 Material 容器映射中性色。以上仅记录现状；新外观的深浅色映射须连同全套控件重新评审，本任务不改源码。

以下是**控件局部 literal**，不是命名全局 token：Button Primary/Secondary、TextField、Menu/Feedback 圆角 12.dp；Tag 圆角 8.dp；边框 1.dp；Selection/Tag 水平 8.dp、垂直 4.dp；Feedback/EmptyState 内边距 16.dp；减少动效菜单宽 200..320.dp、高至屏幕 .8 倍。ActionCards.kt 的 CardFrame 圆角 20.dp、内边距 16.dp、内容间距 12.dp 也只是既有卡片实现。这些旧值只作现状记录，不默认继承为新外观；机制复用与外观重做分开。任何提炼公共 token 或更改 literal 必须交原 owner，本稿不新建 token 类。

## 最新用户反馈：全套外观重新审阅

父任务传达用户否定菜单组件截图，并明确“全部都要改”。此后旧 Foundation/卡片/Shell 的现有尺寸、间距、层级与默认 Material 外形都只作机制参考；B 已暂停旧 UI 候选合入。400e206 的原定视觉方向与用户参考是目标，旧测试绿色不是外观延续许可。

本执行者经 Library 授权 read + materialize 成功取得并实际核看 `libfile_84662ec2d4888191bc902a28cc593fa7`（1080×1920；文件名标明 819509ce… / COMPONENT-NOT-PRODUCT / API26）。原图是独立组件 fixture，不能作真实页面验收。父任务此前无法读取该文件；这里仅陈述本执行者自己的核看，不声称父任务已视觉核对。图中是普通文字标题、无胶囊边界的底部输入区、较大的矩形更多操作弹层；它没有完整真实对话/资料/确认内容，不能从空白 fixture 推断产品正文的排版。用户否定适用于全套外观，不能只改截图里的一个菜单项。

以下 W1–W10 都是 **proposed/draft**，数值由本次提议，不冒充400e206或源码既定值。它们覆盖基础控件、卡片、菜单、弹窗、气泡；必须先在 P1 的真实页面组合与 P3/P4/P8 表单上下文一起审阅，再交 Foundation/Shell owner 实施。PublicUI 当前仅交文档，不覆盖其文件。

| 候选 / 部件 | 具体尺寸、层级、间距提议 | 状态与页面审阅要求 |
| --- | --- | --- |
| W1 页面节奏/文字 | 内容边距 16dp、段间 16dp、关联项间 8dp；正文16sp/24sp、说明16sp/24sp、标题20sp/28sp；不靠缩字表达次级 | 深浅色/320dp/200% 分别核看；长标题换行；正文和错误不被装饰弱化 |
| W2 按钮 | 最小48dp触控，标准视觉最小48dp高，横向内边距16dp，圆角12dp；主操作炭黑（深色反色待审），次操作1dp中性边界，弱操作文字 | ready/pressed/focus/disabled/loading/error/unknown 各有样例；loading/unknown 不重发；有持续原因文本 |
| W3 输入/选择/标签 | 输入最小56dp高、圆角12dp、标签置顶/错误置下；选择整行最小48dp，勾选与文字同行；非交互标签圆角8dp | 填写、只读、禁用、错误、焦点、长值/多行逐态；选择不提交；标签不伪装按钮 |
| W4 内容卡片 | 统一候选圆角16dp、内边距16dp、块间12dp；单列；标题/状态→摘要→正文→来源→编辑→动作→历史/错误 | 十族共享层级，不复制十套壳；未知/失败不折叠关键信息；紧凑仅显式摘要态 |
| W5 菜单/导航 | 更多菜单锚定触发按钮、候选宽240dp且不超视口减32dp、圆角16dp、条目最小48dp；会话菜单主身份/置顶与普通列表分层，按图01提出主Agent+置顶横向区；卡宽不锁112dp，候选最小128dp并由标题完整性决定增宽/换行，320dp可横向滚动而不压缩 | 以原参考的主Agent/置顶会话结构为目标；不是项目格。选中标记+语义；遮罩禁穿透，键盘/返回关闭且保留草稿。主Agent选中以边界+“当前”文本及selected语义标出；图钉候选16dp显示并在卡右上留48dp热区，不占底部大块；当前横轨实现不被默认为批准 |
| W6 弹窗/确认 | 候选宽=min(360dp,可用宽-32dp)，圆角20dp，内边距20dp；标题→可信对象/差异/范围/成本/到期→返回/批准；窄屏按钮纵排 | 200% 可滚动看完全部内容及操作；focus/disabled/error/expired 明示；关闭不确认；披露与修改独立 |
| W7 对话气泡 | 用户短气泡候选最大可用宽78%、内边距12dp/16dp、圆角20dp；助手正文占内容宽、不套多层重边框；来源单独卡 | 原答/引文/检索候选分层，不用灰色弱化关键事实；长字/大字可全宽改纵排；不把78%当已验像素比例 |
| W8 胶囊输入/身份 | 输入候选最小56dp高、圆角28dp，输入/附件/发送触控各>=48dp；头部居中身份，菜单/更多采用候选40dp圆形可见容器，内部图标24dp显示、外部热区至少48dp；附件/发送图标24dp显示且热区>=48dp，主角色候选48dp展示，最多一处 | 以400e206图02胶囊与居中身份为目标；键盘弹起不遮来源/停止/错误；Hidden/Static/Animated 分别核看。热区与显示尺寸必须分开；单聊候选单气泡24dp、群组双气泡24dp，不以同图标仅换文案区分；角色尺寸不是原图测量结论 |
| W9 状态/空态/错误 | 图标+明确标题+原因/恢复动作，候选内边距16dp、间距8dp；正常/空/未知/失败/离线/partial/过期并列样例 | unknown 与 failed 不共用成功符号；无 total 不造百分比；加载保留旧内容和版本；错误持久可读 |
| W10 焦点/动效 | 候选焦点2dp中性外描边、与外形间隔2dp；依系统设置且支持本地 reduceMotion；禁装饰位移/旋转时仍有文本阶段 | 描边对深浅背景辨识待实测，不称已达标；键盘/TalkBack 顺序不随动画变化；控件 press/focus 动效需要实际评审 |

原 Shell 本轮只读复核补充：第二图实际测试宿主含工程说明及 Spacer 大留白，不是目标会话构图；Header/InputDock 缺图02圆形动作与胶囊整体关系；置顶112dp卡宽造成断行，图钉占底部大块、主Agent选中弱、单聊/群组无图标区分；48dp热区被当显示图标尺寸。以上作为用户反馈后的改进输入，不将单个 fixture 问题外推为已证全部产品缺陷。W5/W8 明确图标/热区/选中和置顶布局；页面 S0/P1 要共同复核。默认浮层、表单、禁用、反馈与气泡也必须重审，不能只调颜色。

W 系列与 V 系列有重叠时，W 是本次全套重审的具体视觉候选，V 保留密度/行为条件；实际实现以用户审阅后的明确版本为准。任何原生控件可保留可访问语义与事件门控，外形/排版不能直接默认沿用。尚无 W1–W10 具体视觉批准，设计 GREEN 保持 pending。

## 现有图标/品牌：入库与引用分开核对

用户要求先查仓库已有 icon。本表仅核对产品基线 `fd26dcdabcdac996bc2881e8141cac2b519966fc` 的 Android 素材与源码引用，不声称已完成仓库历史/其他平台全部盘点；父任务进一步库存映射待交接。优先使用已入库原素材，不自造图标，也不默认用临时 Material 图形代替。新视觉 W5/W8 中的单聊/群组等形状只是语义要求，具体资产选择先等库存核验与用户评审；不能据候选文字新画一套。

根 R 为 `apps/muyon_android/app/src/main/res/`；K 为对应 `src/main/kotlin/com/mightyoung/muyon/product/`。以下 present 表示文件或引用存在，**不是**最终页面视觉 PASS。

| 资产（R 下） | 入库状态 | 当前页面引用状态（K 下） | U0 处理 |
| --- | --- | --- | --- |
| drawable-nodpi/muyon_brand_icon.png | present；原品牌资源提交 `11d28aa8c85cfeb41a3efffefa6ab446257fc0c1` | ui/shell/ConversationShell.kt 有 painterResource 引用 | 原样使用，不从生成图导出笔刷变体 |
| drawable-nodpi/muyon_brand_mascot_front.png | present；同提交 | ConversationHeader 的 mainAgent 分支有引用 | 每屏最多一个主要角色，显示尺寸与点击热区分开 |
| drawable-nodpi/muyon_brand_mascot_views.png | present；同提交 | 本轮未发现生产 Kotlin 引用 | 不能因已入库就写“页面已用” |
| drawable/wb_menu.xml | present，24dp VectorDrawable | ConversationHeader/旧 design.Workbench 有引用 | 原几何优先核对；可见24dp与外48dp热区分开 |
| drawable/wb_add.xml / wb_send.xml | present，24dp VectorDrawable | 旧 chat/ChatPresentation.kt 的 ChatInputDock 有引用；当前 ChatScreen 调用 ShellInputDock，后者为 Text("+")/Text("↑") | 已入库不等于当前输入页实际引用；交 Shell owner 做资产映射，保留原门控 |
| drawable/wb_chat.xml / wb_document.xml | present，24dp VectorDrawable | 旧 design/Workbench.kt 的 Destination 声明有引用；尚不能证明 S0 当前导航条目引用 | 优先核查可用单聊/文档资产；群组/搜索/关闭/置顶/设置逐一等完整库存，不造缺失事实 |
| drawable/muyon_avatar.png | present | 本轮未在 S0 的上述文件发现引用 | 旧头像与原角色不混作新品牌定稿 |

参考图中的图标绘制不等于可直接切图资产；即使源码存在默认图标，也仍需在 S0/P1 整页验证图标风格/比例/选中/禁用/焦点。此阶段不复制、重绘、换色或改资源文件。

## 候选尺寸、密度与共用交互变体

以下 V1–V6 全部 proposed/draft，只是供具体评审的选项，不是已经冻结的 Foundation 值。十族逐项采用 V1–V6，族表写出差异；不能只因采用共用规则就认为该族设备验收通过。

| 候选 | 具体取值/规则 | 审阅点 |
| --- | --- | --- |
| V1 标准尺寸 | 宿主可用宽度填满，页面左右各 16dp，单列；卡内 16dp，块间 12dp，卡间 16dp，卡圆角候选 16dp | 这些值是公共布局提案；320dp 可用内容宽随系统 inset 变化，禁止固定内容高度 |
| V2 紧凑密度 | 仅折叠摘要：卡内 12dp、摘要间 8dp；展开恢复 V1；操作目标仍 >=48dp，字号不缩小 | Choice/Form/Confirmation 的编辑及决策区始终 V1；不靠挤压按钮或隐藏错误实现紧凑 |
| V3 禁用/加载 | 禁用有可见原因并语义 disabled；加载保留已有内容及文本阶段；总量未知无百分比；读权限失效清受限正文并停止订阅 | 动作撤权仍保留允许读取的原答；Loading/Unknown 不可重复执行 |
| V4 错误/焦点 | 持久行内错误（文字+符号，不只色彩或 toast）；焦点沿槽位顺序，回到发起锚点；保留原生 focus/pressed 机制，外观按 W10 重审 | 焦点必须可见；若原生实际不足，提交 owner 修正，W10 描边是新候选而非既定 token |
| V5 可访问/小屏 | 320dp 单列，200% 自动增高，按钮纵向换行；完整标签和来源入口可达；读屏每控件一个有名称的焦点 | 错误、来源、停止、原文入口不截断；引用页码用展示基数，内部锚点不改写 |
| V6 减少动效/身份 | Hidden / Static / Animated 均不改变任务；reduceMotion=true 选静态文本进度，无装饰转场；每屏主要吉祥物 <=1 | 复用原资产，不能再在卡内重复放一个主角色；Foundation 只抑制其菜单/加载动画，其他控件仍须实测 |

V1 与 V2 的选择提案：默认标准；聊天结果/附件/任务/草稿/回执可显式折叠摘要，初次失败或未知详情不自动折叠。科研/询价详情默认标准。Bot/Skill/Connector 编辑表单不提供紧凑编辑态。双列、横向动作条、专门桌面断点均未定，不在本稿猜值。

## 十族逐项变体与真实页面去向

代码列只计既有复用基础；新的 publicservices 模型/renderer 均 absent。全部行 designStatus=draft、integrationStatus=not_connected、acceptanceStatus=NOT_RUN。页面 ID 对应页面矩阵，属于未来组合目标，不能当已接入口。

| 族 / 尺寸与密度 | 既有基础（present/absent） | 禁用 / 加载 | 错误 / 焦点 / 可访问变体 | 页面组合 |
| --- | --- | --- | --- | --- |
| MessageBlock：V1；摘要可 V2，原文展开 V1 | 聊天正文 present；公共族 absent | 动作撤权不隐藏可读原答；断流保留原文/已验证片段，未验证计划无事件 | 降级可读文字+原因；原答入口独立；正文与来源按 V4/V5 读序，读权失效撤正文 | P1/P5/P6/P7 |
| ChoiceCard：V1，摘要 V2，编辑始终 V1 | cards.ChoiceCard present | 无选项说明空态；被禁选项附原因；加载不替用户选择 | 单/多选以语义+勾选；错误紧邻组；自定义输入独立名称；选择只改草稿 | P3/P4/P5/P6/P8 |
| FormCard：V1，无紧凑编辑态 | FoundationTextField/Selection present；通用 Form absent | 只读字段可看但不可改；保存中/未知遵循可信草稿态，不把输入当提交 | text/decimal/choice/boolean 各有标签/错误；首错可聚焦且不夺走正在编辑焦点；200% 标签不挤成图标 | P3/P4/P6/P8 |
| ResultList：V1；折叠摘要 V2 | 聊天结果 present；公共列表 absent | 无命中写“本次无命中”，不宣称资料不存在；取快照中留旧数据和版本 | 每项独立 查看/来源/填草稿/请求动作，禁止整行隐式提交；来源缺失降级，长标题换行 | P1/P5/P6/P7 |
| SourceCard：V1；目录摘要 V2，引用全文 V1 | cards.EvidenceCard present | 来源不可访问禁定位并说明；历史来源不跳新文件；读权失效去引文 | cited/candidate/unassessed 文本分开；revision、UTF-8 区间与页位置可读；原 Evidence 缺 unassessed，待适配不能伪装 cited | P1/P2/P5/P6/P7 |
| AttachmentCard：V1；摘要 V2 | cards.AttachmentCard present | 解析/OCR/embedding/索引四阶段分列；unknown/partial 不合成完成率 | 阶段错误与失败单元可展开；读屏按四阶段，打开来源与请求处理区分；长文件名换行 | P1/P2/P5/P6 |
| TaskProgressCard：V1；摘要 V2 | FoundationFeedback present；公共进度族 absent | total 缺失显示阶段/processed；停止请求绑定原 intent，不把关闭当取消 | 取消请求/已停止/撤销效果各异；polite 阶段播报，避免逐数量抢焦点；停止按钮可达 | P1/P2/P3/P4/P8 |
| DraftArtifactCard：V1；摘要 V2，编辑 V1 | cards.DraftCard/ProjectCards present | unsaved/saving/saved/unknown/conflict 文案分开；save ack 必须匹配当前修订 | 冲突保留手改，先比较；保存与业务提交分开焦点/标签；旧 Failed 不硬映射为公共 conflict | P3/P4/P5/P6/P7/P8 |
| ConfirmationCard：V1，无紧凑决策态 | cards.ConfirmationCard present | 只解析可信 preparedRef；版本/账户/参数/权限变化禁旧确认，显示原因 | 修改/披露分开，目标/范围/成本/到期可读；批准和返回均可达；普通“继续”只是导航 | P3/P4/P5/P6/P7/P8 |
| ReceiptCard：V1；历史摘要 V2，未知详情 V1 | cards.ReceiptCard present | unknown 仅原查询，不新意图盲重试；accepted 不标成功；费用未知不写 0 | 原 IntentId/历史与当前版本分开；取消请求不写已撤销；未知/error 持久文本，查询后焦点留原处 | P1/P2/P3/P4/P5/P6/P7/P8 |

旧卡片 CardBinding 的 Long/state/attempt 和 SourceRef 的 1 基页码不能冒充新 UIPlan 合同。旧 ReceiptStatus 也未覆盖全部 C2 状态；超过 Long.MAX_VALUE 的公共 revision 不截断回旧动作。确认/回执字段与结果只从宿主解析，不能拿模型自报 approved/saved/complete 构造可信卡。此表是适配缺口清单，不授权改旧卡片。

## 槽位、四轴与批准条件

每个节点固定读序为 identity/header → status → summary → content → evidence → localEditors → primaryAction → secondaryActions → receipt/history → help/error。空槽不调换剩余槽；页面顶层和各节点分别维持该顺序，不能将所有节点的 status 集中到顶端造成跨卡读序混乱。来源按钮在 evidence 槽，主要操作在 primaryAction，原回执及查询在 receipt/history。错误在字段旁可关联说明，并在 help/error 提供汇总入口。

始终分开原始回答、UIPlan、UiState、BusinessSnapshot、业务意图与原始 Receipt。UiState 的展开/选中不更新 BusinessSnapshot；草稿保存是另一修订；IntentId 不由 UI eventId/JobId 替代。验收必须同时能看到“正文可读、草稿未存、执行未知、来源过期”。action 撤权禁动作，read/scope 失效隐藏受限内容并停止订阅。事件局部查看、草稿编辑与领域请求各有标签，renderer 无 HostCommandPort。

当前设计 RED gaps：十族还没有用户认可的具体 V1/V2 选择；公共 Focus/TalkBack/小屏/深浅色/动效未验；页面组合未审；shellFinalSha 未正式交接；C1/C2/C3 固定依赖未交付。已存在控件及 Shell 独立组件 fixture 不能关闭这些 gaps。

GREEN 必须记录评审者、日期、固定本稿 SHA、明确选择的 W1–W10、V1–V6/十族差异及 P1–P8 组合；不同意项保持 draft 并列修订。代码、页面接线、设备/TalkBack 分栏更新，具体设计 reviewed 也不能将 acceptanceStatus 改成 PASS。U1 可在 C1 交付后独立做模型校验；U2 仍等 C2/C3/U1/外观认可，U3 再等真实页面及 Android 设备输入。
