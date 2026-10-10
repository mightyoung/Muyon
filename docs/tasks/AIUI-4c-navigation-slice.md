# AIUI-4c 正式 typed/collection 导航切片

用户授权并行开发；唯一 leader 合入。执行分支 `task/aiui-4c-navigation-20261010`，
云工作区 `/workspace/Muyon-aiui4c-navigation-20261010`，冻结基线
`0e7ea3197e7504ed7390465c7d0d1adee357f58e`：已发布恢复片与已验证 coverage 组合。
原 PR35/source `308e119c772b4ad7399b5649357dc2baf81075f0` 保持不动。

依据 AIUI-4 §3～5、AIUI-5 正式修订契约与 leader 采纳记录、aiui-stream-contract、
ADR-0001 用户决定及 REVIEW。当前契约复用 library-2、宿主 editSpecs/collections、
单 UiWorkspaceController、HostUiWorkspaceStore CAS、NavigationAnchor 与 ObjectPages。
不改 core/API/codec/grant/业务映射，不新增模型调用、scope 或页面授权。

## 已有覆盖与本片缺口

F4a/b 已有四导航、route/pane 单 session、旧 scalar 真实插件返回/SQLite 重开、
CAS 保留输入、pending 只查回执、宿主换代 lease 与等待期间停止展示。
F3b 的 11 项重算验收不是 F4c scope/lease 导航验收。

本片修复两处现有外壳缺口：

- 正式 collection cell 仅准入 fact/computed；当前外围引用按钮提取已绑定 collection 的
  fact cell ObjectRef。sourceSpan cell 会被既有 validator 拒绝，不能据通用 helper 声称
  集合来源入口可达。复用既有 ObjectRef 路由；没有接 CompareTable 行 callback 或行 tap。
- 保存及异步插件页取得后重新核 task/surface/conversation/node、当前 scope 和只读状态；
  scope 失效不 push 已取得页面，finally 释放 lease。取得页后复核当前 fact 身份。
  对象/原文在 checkpoint await 后同样重复当前 snapshot 的引用身份校验。

## 独立行为验收

`apps/muyon/test/aiui4c_navigation_test.dart` 注册 20 项（390 手机 route 与 1280 桌面 pane）：

1. 三组真实按钮打开正式 library-2 Choice/Checklist/CompareTable 加 NumberStepper，
   选择稳定 ID（前两者）与 finite number 编辑，未绑定 collection 的对象不冒入口，
   通过当前 collection cell 的 ObjectRef 打开真实 Inquiry 公开对象页、返回、关闭，再关闭/重开真实
   SQLite 宿主，核人工值/选择/完整 anchor/draft revision。旧控件 callback 不 dispatch，
   lease 仅释放一次、业务调用为零。
2. 实际引用点击与受控插件 open 屏障期间改变 SQLite task scope；晚页不得出现，lease
   一次释放、原 checkpoint bytes 保留，关闭保存失败仍保留工作区，业务调用为零。
3. 两真实 controller/store CAS 胜负；typed 人工值保留，引用跳转与关闭均不能越过保存失败，
   插件不激活、胜者数据库投影不变、业务调用为零。

cleanup 必须先解除受控屏障、完成导航、unmount/drain，再以 workspaceOperation 在真实
event loop 关闭宿主/SQLite；无 sleep、skip、弱化已有拒绝断言。

云无 Flutter/Dart，官方 SDK 入口 HTTP403；本地行为 RED/GREEN、变异均未运行。
验证通过精确 source Actions，最终 leader 另做组合与非作者复审。原始日志不进仓库。
所需命令：`cd apps/muyon && flutter analyze && flutter test test/aiui4c_navigation_test.dart`
及既有导航/返回/store/recovery 全量；完整 CI 与 coverage 保持原门禁。

本片不是未来 14 场景整体完成，也不证明真实模型/真机/强杀/Mac golden。
本轮正向/lease 屏障使用 InquiryBusinessModule 子类继承真实 schema/aux/activate，
委托 InquiryModuleRuntime.open 与真实 SQLite resolver，仅包装实际 lease 的返回屏障/释放计数；
不注册业务工具，不替换成 Text 页。CAS 输家及 unsupported 拒绝使用原注册 FakeRuntime。本片使用固定 validated snapshot；当前页面未接快照热发布/recompute ports，
没有声称 await 中 snapshot 热替换的真实页面验收。
F4a/b 历史变异不能作为本片新 source 已执行证据。


## 宿主 authority 修复与有界退路

已定位真实等待窗口：插件完成 pinned resolve/objectPage 后，lease 返回的 await 期间
模块撤权或 SQLite 对象写入，旧外壳只核 snapshot 会错误展示新对象。复用既有
`host.modules.scopeAuthorityRevision` 与 `host.scopeAuthority.stamp`，不新增公共 probe API。
ready 路径在 checkpoint 前冻结非空 permission/source proof，checkpoint 后与取得 lease 后
同步严格同值检查；最终检查至 push 无 await。第一次 inactive 路径先保原单次 CAS，
失败零 module activation；成功后核原 inactive 状态身份、准备 runtime，再冻结非空 proof，
真实插件 full pinned revisionRef/contentDigest resolve 覆盖初始化前版本变化，plugin 后不得重冻。
此路径不声称初始化前已具有 ready source proof，也不增加第二次 CAS。

known 对象无完整 pin、无受信 source proof或任一 proof 变化，保当前工作区并提示，零业务页
导航/零 tool。unknown/removed 模块只允许宿主既有已保存引用文字退路，不调用 runtime/session
或读取对象/文件。当前 trusted proof 支持来自既有 host adapter 配置（Inquiry/Prototype）；
Research/任意插件的对象导航不能以 null==null 当通过，安全降级。
该 source stamp 保守覆盖整库/受管文件及权限/绑定变化，不能称精准对象 proof 或完整 H3。
真实插件自身 pinned resolve/objectPage 仍是必要条件；页面打开后的持续版本监控不在本片。

新增两 viewport 下真实 lease 取得后 revoke 与 SQLite 对象改版两类屏障，task scope/snapshot
保持、晚页零 push、实际 lease 一次释放、原持久草稿 bytes/typed count 保留、零业务调用；
另两 unsupported proof 拒绝行为。六正向都增加 SQLite 重开后首次 inactive 支持页往返。
上一版 5f source/PR CI 全绿（host1552/3skip）属于修复前证据，不能作为新 source 动态验收。
受保护旧正向 fixture 与安全退路冲突已交 leader 范围裁定，未经用户批准不改旧文件。

原 artifact 预览保持既有独立行为（变化来源显示当前文件及警告），此次 collection 不准 sourceSpan
cell，无新增原文读取入口；未泛化对象 fence 到旧文件预览，不把该既有流程计入完整 H3 验收。


AAA source/PR Actions 终态真实失败：宿主 analyze 两项新 fixture lint（use_super_parameters、
overridden_fields），host1549 pass/3skip/9fail，失败精确为待批准的九个旧正向 fixture，
自有16回归未报失败。修复 constructor/getter lint并追加四项自有回归：真实 Research.run
经实际 resolver 取双 fullpin，ready 模块但无 trusted source proof，保工作区/count/持久
checkpoint bytes/工具计数且零 ResearchRunPage；Inquiry 对象在初始化前真实 SQLite 改版，
关闭重开后 source proof 非空，但 actual pinned resolver 拒绝（reject1/lease0），保原 count。
后者不是 runtimeFor await 受控屏障；前者不是全库全表快照相等。新 source 仍需 fresh CI，
不得把静态提案或 AAA 的自有回归结果升格为新20回归运行通过。
