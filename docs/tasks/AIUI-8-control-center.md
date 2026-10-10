# AIUI-8 助手控制中心：只读授权切片

2026-10-10；云端 Codex 承接（原 engineer 本轮不可调用）。用户已明确授权并行新功能开发。独立分支 `task/aiui-8-control-center-20261010`，固定开发基线 `0e7ea3197e7504ed7390465c7d0d1adee357f58e`（临时组合，不能称该 SHA 已发布 develop）。

## 本片交付与边界

- `AssistantControlPage.host(host: host)` 消费真实 `host.assistantGrants` 的 `GrantStore.list/audit` 公共只读接口；加载、空、失败、重试、刷新及单条规则/审计详情。
- 规则显示类别、工具、时长、撤销/过期/次数用尽/已保存状态；“规则已保存”不代表本次执行已获准，实际执行仍走原 gate、scope、审批、回执。
- URL 仅显示 HTTP(S) host/port/path；用户信息、query、fragment 不显示，非 Web/无法解析目的地隐藏。原始 scope、audit detail/task id、异常原文不展示；没有凭据读取接口。
- 数据去向复用已有 `DataFlowPage` 生产页；不重复建账本或伪造业务记录。本片不更改原数据去向页的过滤与显示契约。
- 页面没有授权签发 token、create/revoke、policy 写入、网络/后台发送。首次远程端点及外传 gate 保持原实现；本片也没有改模型普通问答确认。

设置真实入口由 F4c 唯一外壳 owner 顺序应用：`platform_shell.dart` import 新页；`settings()` 增加 `card('助手控制中心', '已授权规则、变更审计与数据去向', () => page('助手控制中心', AssistantControlPage.host(host: host)), Icons.admin_panel_settings_outlined)`。owner 已确认接口，当前本分支不写共享外壳文件；入口组合必须另验。

## 验证与未完成

先写 7 个行为测试：加载/空/既有账本入口，真实 SQLite 授权与审计只读/隐私，失败不泄密及重试，真实撤销状态，异步晚到/关闭，过期/用尽状态，URL 清理。随后实现页面。真实 SQLite 测试由测试显式宿主确认创建夹具，不是生产创建入口。

本云环境无 `flutter`/`dart`，专项命令 `flutter test test/aiui8_assistant_control_test.dart` exit 127（command not found）；没有观察到有效测试 RED，也没有本地 analyze/PASS。完整 analyze/8-suite 运行交由该源 SHA 的 Actions，终态及精确 checkout 由交付报告记录。未自动更新覆盖基线、ignore/exclude、降低门槛或修改旧测试。原始输出不入 Git。

尚未完成整套 AIUI-8：可视化自动/少用/只文字三档、模式/授权编辑入口、真机/读屏/字号及新外壳组合验收。本片只读页面不使自动授权编辑成为已交付；“少用”的具体呈现策略需要已采纳执行契约后另片实现，不自行发明 policy。
