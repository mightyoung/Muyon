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

- collection cell 的 fact/sourceSpan 引用通过现有引用入口可达，身份仍只取当前宿主
  snapshot.facts/sources，复用原 ObjectRef/ArtifactRef 路由；没有增加行 tap 业务 mapping。
- 保存及异步插件页取得后重新核 task/surface/conversation/node、当前 scope 和只读状态；
  scope 失效不 push 已取得页面，finally 释放 lease。取得页后复核当前 fact 身份。
  对象/原文在 checkpoint await 后同样重复当前 snapshot 的引用身份校验。

## 独立行为验收

`apps/muyon/test/aiui4c_navigation_test.dart` 注册 10 项（390 手机 route 与 1280 桌面 pane）：

1. 三组真实按钮打开正式 library-2 Choice/Checklist/CompareTable 加 NumberStepper，
   选择稳定 ID（前两者）与 finite number 编辑，未绑定 collection 的对象不冒入口，
   通过当前 collection cell 的 ObjectRef 打开注册插件公共页、返回、关闭，再关闭/重开真实
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
插件页是通过真实注册 ObjectPages 协议打开的 FakeRuntime 公共夹具，不是科研/询价生产插件
的新覆盖。本片使用固定 validated snapshot；当前页面未接快照热发布/recompute ports，
没有声称 await 中 snapshot 热替换的真实页面验收。
F4a/b 历史变异不能作为本片新 source 已执行证据。
