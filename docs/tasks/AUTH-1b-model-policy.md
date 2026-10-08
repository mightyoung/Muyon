# AUTH-1b category policy and model wire slice

Parent 已授权在 production clean / automatic 后持续实施 C；本隔离 `task/auth-1b-model-policy` 从修复 automatic 的固定 `4ce5d05d9a900473d7af36ec759a3bb7958b1bf0` 开始，automatic 固定4ce已获 parent 精确批准，独立复核86/strict通过、CI37753949695 success；普通合入develop c1dbe2d27b3b9a54debd1c0a214a19987844ac40，集成strict7.8s/full1084~3，postmergeCI37762781798运行中。输入基础已普通集成 develop640bac5、postmergeCI37752542394 success。保持历史 DB/迁移事实和数据，UI/main/release 不在范围；原始 logs/drivers/tmp 不提交。

## 交付顺序

1. 宿主 settings 的真实 category policy：默认 standard、readOnly、custom 与 read/model/write/outbound 四类收紧开关。更新仅已确认 HostUiGrantToken；缺旧设置使用已定义标准默认，已存在但无法解析的设置 fail closed。readonly / category off 在候选、prepare、人工确认、自动签发与 effect 前都不可绕过；实际 policy内容版本进入审批绑定，变化使排队许可 stale。先真实 Host + Inquiry Store / grant 行为 RED，再代码。
2. C 的 host-owned model permission：主模型、摘要、恢复及协议兼容重发的实际不可变 wire bytes / 来源 / 完整 endpoint+profile identity / scope绑定；local/ownDevice标准 mode_auto 显式来源且 grantId 可空，不伪造；规则 grant 关联真实 ID 与使用审计。模型/快照/bare GateAllowed 字符串不能签发。Noop未审查，本地review链只能收紧，异常/超时人工、block仅review记录不制造transport状态。每个真实请求先ledger再bytes，review及最终guards覆盖credentials / ledgerqueue / connection / chunk窗口。
3. 撤销订阅实际GrantStore owner，同步拒新使用并取消在途HTTP流；真实ledger cancelled，已发字节不承诺撤回。兼容重发每actual wire都复核/审查/入账，同一次许可不多退/多消耗；恢复不可复用已消费许可。摘要不得扩大此前确认暴露面或清除taint。
4. 对实际宿主、SQLite、loopback协议fixture和真实grant源做行为回归，明确domain效果与fixture计数差别；相关取消/主模型/摘要/ledger/恢复既有回归、strict/full、有效mutants逐字节恢复，固定SHA独立review和exactCI。只有parent另行批准精确审查提交后普通merge develop及integration/postCI；真机/provider后置。

## 当前门禁

本任务书只形成授权内的正式实施范围；尚无C通过或上线声明。任何category/model default必须按ADR0002/4/5与已批准保守默认执行，若实际语义冲突再向parent报告。新增接口不暴露为agent/model/module可调用的grant/policy issuer；不以任务JSON、任意常量sourceRevision或origin推断可信权限。

## Category policy checkpoint（C尚未完成）

第一项实际实现已接入宿主，settings仅确认UItoken更新；pending/failed写入跨同DB服务实例fail closed，成功重试恢复；真实mutation changeId防止损坏serial修复后ABA复活。四类候选过滤、prepare/review/签发/人工/effect复核及policy版本绑定；主模型/摘要卡版本复核、实际共享gateway credentials/beforeSend/ledger/connect/chunk边界。

新23项实际Host/Inquiry Store/SQLite/loopback回归通过（8s）。有效RED包括readonly/write-off/损坏设置仍写入、model-off仍提卡、corrupt-ABA复活、共享gateway在beforeSend关闭model后仍发送，均先留原log再修复。13个有效Expected/Actual行为mutants全部检出并逐字节恢复。首轮strict三个style infos不认通过，修正后strictclean8.6s；恢复全量1107通过、3既有跳过（2:52）。原logs/drivers只/tmp；native/JSON/outbound顺序fixture计数不称真实领域transport或provider证据。

模型自动许可、实际wire内容审查/许可原子消费、摘要/兼容重发/恢复及撤销在途尚未实现；此固定类别检查点不代表完整C接受，未获合develop批准，后续仍需独立review、exactCI及parent精确批准。
