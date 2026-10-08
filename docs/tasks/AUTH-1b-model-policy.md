# AUTH-1b category policy and model wire slice

Parent 已授权在 production clean / automatic 后持续实施 C；本隔离 `task/auth-1b-model-policy` 从修复 automatic 的固定 `4ce5d05d9a900473d7af36ec759a3bb7958b1bf0` 开始，automatic 固定4ce已获 parent 精确批准，独立复核86/strict通过、CI37753949695 success；普通合入develop c1dbe2d27b3b9a54debd1c0a214a19987844ac40，集成strict7.8s/full1084~3，postmergeCI37762781798 success。输入基础已普通集成 develop640bac5、postmergeCI37752542394 success。保持历史 DB/迁移事实和数据，UI/main/release 不在范围；原始 logs/drivers/tmp 不提交。

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

固定C1提交 d23127824e4218ac58794a98a0998a7ed1179048 已独立 strict11.7s / 114项实际回归 CLEAR，exactCI37763155551 success；该快照是类别策略检查点，不代表完整C接受。下述C2继续在同隔离任务分支实现，尚未获合develop批准。


## C2 actual model wire implementation

实际 MuyonHost 的主模型与摘要已使用私有 host-owned permission。可信来源是当次真实宿主 profile 选择，或磁盘当前 ProfileRepository 的精确配置；历史 task JSON、模型回复、bare GateAllowed 不能签发。完整 profile ID / endpoint URI / identity / location / proxy / model / purpose / credentialRef 分离绑定，scope 仍用既有粗范围键，逐对象 revision 继续独立验证。默认 standard/readOnly 的真实 local/ownDevice 无代理请求可 mode_auto，grant_id 为 NULL；custom 或新远程 endpoint 先提人工卡。已人工批准 endpoint 的真实 model grant 按实际 ID 原子消费，不伪造次数或审批。

实际 provider 渲染的 wire bytes 先本地 ReviewerChain 再独立 review 行，Noop reviewed=0；allow/confirm/block/异常/超时只可收紧。每次实际兼容重发单独审查和 ledger，确认变体使用既有人工卡；同一许可仅首次耗 grant。GrantStore 使用与审计和真实 outbound INSERT 同事务；INSERT失败全回滚，已提交发送失败不退款。主请求和摘要均核验真实 task/profile/scope/memory/policy/有效期、精确 wire 与 review 行，credentials/ledger队列/connect/chunk均复核；共享 owner 的 grant/policy 更新取消在途 token，等待 credential RPC 也可停止。已发送字节不承诺撤回。摘要沿用既有曝光约束，host facts 不因压缩清除；重开后的恢复只有当前实际配置才能继续自动。

可用性证据来自真实宿主与实际领域存储：Inquiry 原生工具把预算行数量10改为12，有真实单次 grant、成功 receipt 和引用；Research 实际导入 paper.md、research.objects 检索并生成真实引用，纯读流程无需 grant 或逐轮人工卡。NorthStar fixture 模型完成两次读、实际 inquiry.create_inquiry 写入、错误 digest 与重复确认拒绝、close/reopen 数据相同；六次模型发送均有真实 ledger/review。模型答复为 loopback 脚本，不称真实模型或真机证据。NorthStar fixture 补 stop 协议字段，旧“每次发送必人工确认”断言调整为实际来源与精确 review 字节校验；领域效果、写入审批、错误工具及数据保留断言均保留。

新8个文件26项 actual Host / SQLite / loopback 回归，覆盖 local native/JSON/ownDevice、五类review结果、ledger失败回滚、并发最后一次、次数重放、不同profile同URI、新请求协议变体、摘要taint、磁盘恢复配置、实际wire篡改/review行篡改、held HTTP及held credential取消。相关既有测试用真实只收紧的confirm reviewer保持原工具阶段断言；旧坏凭据测试检查自动模式立即失败及原密钥不泄露断言。初轮全量发现 NorthStar 旧协议/计数约定及一例流式DB清理错误；前者已修复、两项NorthStar通过，完整流式文件24项独立通过，断线重接后重新执行全量，1133通过、3既有跳过（5:56），strictclean14.7s。旧/tmp日志丢失，不采用653中途结果。

14个有效 Expected/Actual 变异全部检出且逐字节恢复：mode_auto失效、profile identity合并、伪造manual来源、Noop伪审查、独立review行不复核、wire不绑定、grant不消费、重发重复扣次、忽略变体confirm、取消grant/policy订阅、credential等待不可取消、历史恢复JSON冒充可信配置、提前提交grant消费。C1的13变异仅对应固定d231快照，不将其冒充C2证据。断线重接后重新跑同14个变异并核对源码SHA256，全部有效且逐字节恢复；恢复后strictclean14.6s，26项实际模型/领域回归全部通过（25s）。恢复基线全量1133通过、3既有跳过（5:56），对应源码保持完全相同。原始日志/驱动仅/tmp；固定SHA独立审查和exactCI待完成。

UI设置入口及其他产品页接线由UI任务负责；此任务不修改UI。未扩展新的后台grant发行入口或远程审查，不接入实际云模型，不替代真机测试。仅所列实际Inquiry/Research闭环及宿主基础接口有行为证据，其他模块业务闭环本轮未覆盖。历史迁移/数据保留，main/release不在授权内；develop须parent精确版本复审批准。
