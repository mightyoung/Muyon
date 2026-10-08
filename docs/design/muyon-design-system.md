# Muyon 设计系统 v6

组件库：`packages/muyon_ui`。依据 [v6 tokens](v6/tokens.md)、
[组件清单](v6/components.md)、[第七轮说明](v6/round7-notes.md)。
本阶段提供通用组件和 debug 示例，不迁移询价页面，不连接助手执行。

## 信息架构

手机底栏与桌面图标轨同序五项：**AI 助手 · 业务插件 · 工作台 · 数据交换 · 设置**。
导航仅画图标；选中用实心图标、tint 背景，名称由 tooltip 与 Semantics 提供。
资料入口归工作台，记忆归助手设置。组件通过 `onChanged(index)` 交给壳层路由。

## Token 与颜色规则

`MuyonTokens.of(context)` 读取 ThemeExtension；`muyonTheme(brightness)` 生成主题。

| v6 名 | Dart 名/兼容别名 | 浅色 | 深色 |
|---|---|---|---|
| bg | canvas / bg | FCFCFC | 0A0A0A |
| sf | surface / sf | FFFFFF | 141414 |
| sk | sunken / sk | F1F3F6 | 1F1F1F |
| rule | rule | E2E6EC | 2B2B2B |
| rs | ruleStrong / rs | C3CAD6 | 3F3F3F |
| ink | ink | 111827 | F2F2F2 |
| ink2 | ink2 | 4B5565 | C4C4C4 |
| ink3 | ink3 | 636C7E | 9A9A9A |
| acc | accent / acc | 2458D3 | F0A649 |
| onacc | onAccent / onacc | FFFFFF | 0A0A0A |
| tint | accentTint / tint | E8EFFF | 3A2A12 |
| deep | accentDeep / deep | 1B47C2 | F5C27A |
| red | red | B8302A | FF7A70 |
| redbg | redBg / redbg | FDE8E6 | 3A1F1D |
| green | green | 17693F | 4CC38A |
| greenbg | greenBg / greenbg | E6F4EC | 17301F |
| warn | warn | 8A5A00 | E8C547 |
| warnbg | warnBg / warnbg | FFF1D6 | 2E2A10 |

红表示失败、危险、外传；warn 表示需注意，并同时出现 warning 图标与中文；
绿表示成功；琥珀只作深色主色；待确认和选中同用 tint/deep。
颜色不能成为状态唯一线索。正文类配对按 WCAG sRGB 线性化与相对亮度公式
测试 ≥4.5，包括 warn/sf、warn/warnbg。旧 amber、amberBg、nav、navHover、
navInk、navInk3、groupRow 名及构造参数保留供原调用方编译；它们不是新增
组件的 v6 语义角色。询价 Folio 主题不改，独立冻结旧配色检查继续存在。

字体 Noto Sans SC，回退 PingFang SC 等；散列/代码使用 Consolas/Menlo。
圆角 token：业务 `radius=8`、input/dialog 12、option 16、card 20、group 24、
composer 28、pill 999。间距 `spacing=[4,8,12,16,20,24]`；旧 space1～space6
仍保留，space5=24、space6=32 不重新编号；新增 space20。

## 尺寸与布局

高度由完整内容与 padding 决定，**48 是最小点击区，不是固定控件高度**。
所有动作使用 minimumTarget=48、ConstrainedBox 或 Material padded target。
文字不设 maxLines、ellipsis 或裁切；200% 文字下按需增高，长散列可换行；浅深色均测试 320/390/1280。
比例布局用 Flexible/Expanded；MasterDetail 在 1000 断点以上按 3:2 分栏，
窄屏用独立详情路由。PageScaffold 是内容骨架，调用方提供页面滚动容器。
Dialog 限制最大可视高度为视口 85%，内部滚动，未固定内容高度。

命名的定尺寸例外只有 glyph/数据几何：iconSize=24、navigationIconSize=28，
tableHeaderHeight=42、tableRowHeight=52（表格对齐），switchWidth/Height=46/28、
switchThumbSize=22（视觉几何；未来开关仍须外加 48 点击区）。本阶段没有
实现固定高度表格或开关。圆角和最大 Dialog 宽度不是固定控件高度。

## 15 个组件与用法

| 组件 | 输入与用途 |
|---|---|
| PageScaffold | title、description、actions、PageState；loading/empty/filteredEmpty/error 各带图标文字及适用的恢复动作 |
| MasterDetail | master、detail、onClose；窄屏“打开详情”，独立详情页返回；宽屏比例分栏 |
| StatusBadge | BusinessStatus；中文、图标与 success/danger/warn/neutral 四色调 |
| ObjectChip | label、onPressed；missing=true 显示“已不存在”，禁止旧回跳动作 |
| SegmentedPill | 2～3 labels、selected、onChanged；空间不足时折行 |
| IconRail | selected、onChanged；五项 tooltip + 语义标签 |
| BottomIconBar | 同图标轨，五项等比例分配，无可见导航文字 |
| ConfirmCard | ConfirmItem、BusinessStatus、onDecision；五个完整核对字段及展开内容 |
| BatchConfirmCard | 仅写入/外传 items；外部内容时取消“全部允许”，不接受只读操作 |
| WarnBanner | 外部内容 warning 图标、warnbg、完整中文，可附动作 |
| ScopeChip | 全局/工作区/项目/选中 N 个对象；展开明确传入的对象列表，不沿关系读取 |
| MuyonDialog | title、message、confirmLabel、onConfirm；可滚动核对说明与取消/确认 |
| MuyonToast | message、BusinessStatus、可选动作；live region；show() 使用 ScaffoldMessenger |
| RoundIconButton | label、icon、filled、onPressed；主色或描边，禁用仍保留名称 |
| TitlePill | label、可选 onPressed；完整标题，动作模式加展开图标 |

后两项来自 v6 通用组件清单，与任务书的 13 个主要类组成 15 项套件。

确认卡固定字段：**做什么 / 对谁 / 发送内容 / 摘要散列 / 后果**。
只读无决定按钮；写入“仅这一次 / 拒绝”，更多可选择本次任务/本次对话/始终允许。
被内容审查要求确认、因外部内容逐次确认时不显示写入“更多”。新端点仅发送这一次/拒绝；
已授权端点加本次对话允许；远程模型加本次对话允许发往此端点。任何外传都无始终允许。
任务 externalContent=true 或状态为 externalContent 时，所有卡均只保留一次/拒绝，
外传与远程模型取消对话级按钮，写入取消更多，显示外部内容提示。该规则以
[frontend memo](v6/frontend-memo.md) 为准，优先于稿内遗留按钮错误。
已确认、已拒绝、授权放行、拦截状态无决定按钮。这里只回调选择，所有授权校验与
执行仍由后续助手接入承担，卡片不持有或生成授权。

## 状态词表：唯一来源

代码唯一来源为 `BusinessStatus.label`；目录与 ConfirmCard/StatusBadge 共用，
不在各页面复制中文映射。

| 枚举 | 中文 |
|---|---|
| success / failed / warning / neutral | 已成功 / 失败 / 需注意 / 未开始 |
| pending / running | 待确认 / 进行中 |
| confirmed / rejected / authorized | 已确认 / 已拒绝 / 已由授权放行 |
| expired | 授权已过期，需重新确认 |
| scopeChanged | 范围已变化，需重新确认 |
| contentReview | 被内容审查要求确认 |
| blocked | 被内容审查拦截 |
| externalContent | 因外部内容需逐次确认 |
| deleted | 已不存在 |

PageState、BatchState、ConfirmationKind/Choice 也在各自枚举里持有中文标签。

## 无障碍与目录

动作名称由 Semantics 提供，包含 tap action、enabled 与 selected 信息。
图标导航没有隐藏的可见文字；hover/长按 tooltip 显示名称。
InkWell 支持键盘激活与 2px 主色焦点边框；状态图标不单独重复朗读。
通知使用 liveRegion；Dialog 提供中文路由名；缺失对象没有可调用动作。

Debug 启动：`flutter run --dart-define=MUYON_COMPONENT_CATALOG=true`。
仅 kDebugMode 注册 `/debug/components`，在数据库初始化前打开独立目录。
目录可切换浅深色、选择 15 类并浏览每类状态，交互仅演示，不接业务页面。
新 golden 使用仓库已捆绑 Noto Sans SC，在 Mac 生成与比对；Linux 明确跳过
本组件库 golden，仍执行全部尺寸、回调、语义、对比度和状态词表测试。
