# AIUI-2 接口与只读修复交接

基线：AIUI-2 `0183918652095b47f2d2327cc9f470ed674959dd`。
正式参考：AIUI-1 `276b29146d3eb902380cceac708209cc6ef344c0` 的
`docs/design/aiui-stream-contract.md`、`validation.dart` 与 `state.dart`。
这是执行者的修复/阻断交接，非 leader 验收或合并批准。

已读 HANDOVER-A、HANDOVER-LEADER、AIUI-2、REVIEW。
当前分支及 AIUI-1 参考树未提供 HANDOVER-B/C/D；未假定其内容。
stream contract 不在 AIUI-2 基线中，通过指定 AIUI-1 提交读取，未移植 AIUI-1。

## 本轮组件库修复

`MuyonForm` 原来只禁用提交，任意 ready 子组件仍接收输入。
现在在子树边界阻止指针、焦点/键盘与辅助功能动作，保留文字和语义标签。
父表单转只读时撤销已聚焦输入；重新 ready 后恢复编辑，草稿保留。
新增 `form_read_only_test.dart` 使用真实 Toggle、Choice 自填输入与原生
TextField，检查点击、语义动作、焦点撤销、恢复编辑和提交。
不改 debug 示例或 golden 基线来隐藏问题。

## 仍阻断流式接线：leader 决定及 AIUI-5 分工

| 项目 | 当前不兼容 | 责任与建议（尚未采纳） |
|---|---|---|
| Toggle | boolean change 配 edit；现有 editField 只允许 string 事件和 string uiState，拒绝 `edit_input` | bool Widget 保留。leader 决定正式 typed edit 契约、状态类型和 payload 校验，再由契约所有者实现；不得悄悄 stringify bool 或放宽 AIUI-1 |
| CompareTable | tap/detail 登记无 value，拒绝 `detail_input`；纯 Widget 无点击回调 | 属组件库目录登记问题。建议先移除未实现的 tap，或 leader 正式定义选中行的对象身份、绑定和动作映射，AIUI-5 接线。不能将 rows 别名为 value 冒充对象身份 |
| Chart、Table、CompareTable、Timeline | Widget 使用集合，快照绑定校验只允许 scalar | AIUI-5 宿主 adapter 负责宿主来源、编码/解码和降级；若扩展快照类型，先正式变更契约。仅 JSON stringify 通过 validator 不是集成完成 |
| Checklist | fact items 不可通过 edit；uiState 集合仍不符合 scalar；Widget 发出 index,bool | fact 模式只读。leader/AIUI-5 定义稳定项身份、宿主集合 codec 和编辑映射；不得以模型动作 string 化改语义 |

正式 adapter 方案至少应明确：版本、宿主声明的 id 与数据来源、允许的数据形状、
数量/大小限制、拒绝畸形数据及文字降级、保留事实/计算版本和来源、
typed 状态与事件映射、对象身份与允许动作。模型只能引用宿主数据和动作，
不能提供值、编码内容或新状态键。正式 stream contract §1/§4/§5 的边界继续适用。

新增 `library_contract_boundary_test.dart` 精确断言上述拒绝错误及无
ValidatedUiPlan，并用 scalar 对照排除树/目录错误。它记录现存阻断，
不宣称全目录已兼容。正式方案落地时应明确更新这组边界及新的正面集成测试。
本轮不修改 validator、AIUI-1、旧断言、业务页面或产品流程。

## 验证与证据范围

云工作区初始无 Flutter/Dart；下载官方 SDK 遭端点 HTTP 403。
运行时回归与全量 analyze/test 交给原分支精确 SHA 的 Linux CI；结果见提交
说明及执行回报。未在用户 Mac 安装依赖。原始日志只留云工作区/CI artifact。
Linux CI 的 macOS golden 跳过不构成 golden 验收；macOS verify 仍需独立执行。
本轮不合入 develop/main。
