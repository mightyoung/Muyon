# AIUI-2 集成独立复审

2026-10-09，冻结 `4e45836efcb85c86f5c8de57e6b07795aab6166a`，目标 develop
`36a516af6af92679fc47b79a1d4679c37258d030`。独立只读 reviewer 完整复核
114 文件（3754 新增、96 删除，含92张golden），未发现新的确定阻断。
没有 pubspec、validator、业务页面或模型修改；diff --check 通过。

Tabs 修复急切 initState 初始化、didUpdateWidget 按新 children 长度收敛索引，空列表复位0；
五项同 key/State 回归覆盖缩减、空挂载增长、清空恢复、重排及 initial 更新不覆盖用户选择。
[red CI](https://github.com/mightyoung/Muyon/actions/runs/37966050968) 的两项 RangeError
对应 `606c592ba4acfe02ab9146d3f316f103fcf15950`；最终
[green CI](https://github.com/mightyoung/Muyon/actions/runs/37967537808) 精确 head 已核对：
analyze 8/8、test 8/8、muyon_ui +311 ~152、host +1247 ~3。未合旧缺陷 SHA。

Form 保留 Semantics.blockUserActions、ExcludeFocus、AbsorbPointer 三层只读锁，提交禁用；
真实 Toggle/Choice/TextField 回归覆盖指针、语义、失焦、草稿和恢复编辑。
新组件/原组件状态、单份目录、文字等价物、48触区、320宽/200%字号及 token 使用已复核；
Chart 无第三方依赖。指定语义标签/40触区变异有原交付记录，未在本云机重跑。

全库独立审计结论由父任务转交：typed edit、CompareTable detail identity、集合 codec/Checklist
stable item mapping、新目录 renderer/recovery 是 AIUI-5 后续正式接线门槛，不构成组件库永久阻断。
边界拒绝测试和 validator 保持，不为了合入弱化校验。不宣称33组件已经生产端到端消费。
本机无 Flutter/Dart，运行证据来自精确 CI 与下一轮组合门禁；Linux macOS-only golden 跳过
不代表 macOS 或设备最终验收。原始日志不入库。
