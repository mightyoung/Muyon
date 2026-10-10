# AIUI-9 宿主只读本体卡切片

执行任务 `/root/aiui9_cards`；分支 `task/aiui-9-ontology-card-adapter-20261010`。
基线 `0e7ea3197e7504ed7390465c7d0d1adee357f58e`（develop 与已审 coverage 临时组合）。
用户本轮已授权实质功能并行；设计依据为 AI 原生方案 §4.4、ADR-0004 FieldKind/Q7、现行 v2 本体与范围契约。

## 交付边界

- `InquiryOntologyCardAdapter.read` 是后续页面 owner 的只读入口，消费宿主当前激活的询价模块、AssistantScope 和完整 pinned ObjectRef；实际读取 supplier_core SQLite 的保存快照，核对项目、revision、内容摘要、范围及模块/工作区 lifecycle fence。
- 本体结构来自实际 registered BusinessModuleV2；展示字段按当前 FieldKind 显式处理，未知对象或高版本保留只读退路。结构化 object 值不展开任意嵌套内容，只提示原页面查看。
- 输出为固定可信宿主模板，复用现有 `muyon_ui.KeyValue`。无模型组件名、动态 UIPlan、模型动作、路由或可执行 callback，因此不经过动态计划 validator。投影前拒绝混入对象/重复字段；字段形状校验仅服务只读展示，不复制领域 validate，不声称提供领域写校验。
- 当前保存事实与模型建议独立显示，后者标为「建议（尚未写入）」，从不覆盖保存事实。credential 字段连名称及建议也不进入投影；personal/commercial/unreviewed 的原值与建议在投影前遮盖，无可揭示按钮。
- 关联字段仅为未活化文字，无对象 opener/lease；旧修订、跨范围及删除对象不生成卡片。标题使用本体类型名，避免对象标题绕过敏感字段遮盖。
- 通用修改能力说明来自实际 registry 的 provider/effect/available/type enum，未登记类型明确提示原页面操作；本切片全部禁用提交。原页面入口为声明文字，未接 F4c 导航；没有独立原页面的类型提示从询价业务页面操作。

## 测试与验证

新增 14 项行为测试：实际宿主 SQLite→范围解析→读取适配→投影→KeyValue，建议不写事实/无业务回执，旧 revision、跨选定 scope、无绑定 workspace、已删除拒绝；敏感文本与语义无泄漏；高版本/未知类型退路；混合对象/重复字段拒绝；引用与结构化值不活化；非法值不当事实；当前全部 FieldKind 显式处理；未核验内容不提升为事实；不可信建议的单项/集合/总文本预算拒绝。
云端未检测到 Flutter/Dart CLI，未声称本地 analyze/Flutter 测试通过。精确提交的 Linux CI 将执行现有八库 analyze/全测试/coverage/Laya；原始日志不进仓库。新增 source 库存与 DA 交 coverage owner 独立测量，不修改 baseline/checker/floor。

本切片不等于 AIUI-9 新建/编辑/关联/批量写卡完成；没有提交 payload、插件双重校验、授权执行、真实回执或页面接线。未改 core/API/UI/registry/tool/既有测试，没有真实权限、账号、业务网络、部署或打包操作。


## 首轮独立审查修复

首源 `6d6322d722500a27a1869012e282932dcd43c131` 发现统一 resolver.prepare 会激活其他模块并写登记状态，故不能合入。修复使用仅 inquiry 的 ScopeSource 包装器禁用 prepare，仍复用原 ScopeResolver 的范围/版本检查，不复制授权规则。真实 fixture 不再用 global resolver 预激活所有模块；断言其他模块保持 inactive，module_registry 前后逐行相同。建议文本单项预算复用 `uiStringEditMaxBytes`，总文本与字段/列表项限额复用 `UiStreamLimits.v1`；超限值不序列化进入组件，不改变领域保存/协议校验。旧源运行不作为修复源验证。
