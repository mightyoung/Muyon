# PR36～39 有界功能集成审查

2026-10-10；父任务明确授权唯一云端integrator端到端正常合develop，不停在绿色Draft。
冻结基线 `c265eb13564ce8b485297fbdd3f1ddb351256e0d`；main保持
`cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`。原PR23/30保留，不关闭或删除。

## 固定来源与谱系

| 来源 | 完整源SHA | 已核源 / PR CI |
| --- | --- | --- |
| PR36 AIUI-8 | `aef127ff501e7c0d141152bec69aa4e9f3719828` | [38048233373](https://github.com/mightyoung/Muyon/actions/runs/38048233373) / [38048244033](https://github.com/mightyoung/Muyon/actions/runs/38048244033) SUCCESS |
| PR38 原F4c片 | `5f6e291e3bf36a436c45a02afde983d77df7b92c` | [38049637152](https://github.com/mightyoung/Muyon/actions/runs/38049637152) / [38049639051](https://github.com/mightyoung/Muyon/actions/runs/38049639051) SUCCESS，仅旧head证据 |
| PR38 对象准入修复 | `aaa175343eee08a4e53576b621bef2c17c16c06a` | [38052426475](https://github.com/mightyoung/Muyon/actions/runs/38052426475) / [38052429669](https://github.com/mightyoung/Muyon/actions/runs/38052429669) 待终态，旧fixture冲突待确认 |
| PR39 设置组合 | `76400fe0b640d89ec8bf72123a58b5040b63ee63` | [38049686964](https://github.com/mightyoung/Muyon/actions/runs/38049686964) / [38049689477](https://github.com/mightyoung/Muyon/actions/runs/38049689477) SUCCESS |
| PR37 AIUI-9 | `055a8cbd1e82a63ef632abb013bfc9b2f180172d` | [38049438912](https://github.com/mightyoung/Muyon/actions/runs/38049438912) / [38049441446](https://github.com/mightyoung/Muyon/actions/runs/38049441446) SUCCESS |

先普通merge PR39，再普通merge PR37。PR39已经包含PR36/38及入口补丁，不再次整包合入。
代码组合 `dc9a72c14b1bf28a8641f6e127bc45fececb281b`，父提交为
`bbea3112cb74b5203e3402e1a881f18492f9650f` 与固定PR37；前者父为基线与固定PR39。
四源均为精确祖先，所有交付blob逐项相同，基线coverage审查文档保留；无冲突或cherry-pick。
相对基线仅8个宿主生产文件、4个新增测试、3个任务说明；集成者另补设计与交接摘要。
旧测试、组件/API/codec/validator、CI/scripts、baseline、依赖或权限没有修改。
原组合文档head `cec2a66faa80f8fcd3753987d3dca5eea5e6cade` 的
[38051505714](https://github.com/mightyoung/Muyon/actions/runs/38051505714) 实际SUCCESS，
job 12:19:02–12:34:57 UTC；八库分析/测试通过、host1575/3skip。它含已确认的准入缺口，
绿色不批准合入。405源码hash、八库库存/DA复算、43门禁通过；397未改源码无命中下降，
host16680/19320；19未加载仍unknown，baseline不变。新修复不能沿用此测量。
随后仅增量普通merge PR38修复到临时候选 `2efef5f85fdf46498469a95f9ca50b37795f5c1c`，
父为摘要提交 `3be13e02258da1a50f72f1906acda9ae013ebb98` 与固定aaa175源；
不重复整包合PR36/38/39，全部既有来源祖先保留，develop尚未推进。

## 跨组件与安全核实

非作者云端核实代理按REVIEW，对照ADR、总体设计和aiui-stream-contract追完整链路。
当前Claude/engineer调用工具未暴露，`claude` CLI不存在；不把本轮Codex静态审计称Claude。
本地Flutter/Dart亦不可用，动态证据只能由精确Actions checkout提供，不称本地通过。

- 控制页只读真实GrantStore.list/audit，状态不等于执行已授权；URL去用户信息/query/fragment，
  audit原文、task/scope及异常原文不进新页。没有create/revoke、policy写入或发送。
  generation/mounted防晚结果安装，真实设置入口两视口行为测试不替代页面非空SQLite测试。
- 既有DataFlow页直接展示其账本端点/错误、工具摘要、批准目的地与读取异常，未在本批修改。
  新页脱敏保证不扩展到该route。实际ModelProfile与gateway有既有校验/脱敏，未确认凭证泄漏。
- 本体卡只读取已活跃询价保存快照，ScopeSource禁prepare，不激活其他模块；复核完整pin、
  project、scope、revision/digest与module/workspace fence。保存值和建议分开展示，credential
  整字段排除，其余敏感/未核验值遮盖；模型不给组件、路由或callback。数量、单项与总预算
  含建议，未知版本/类型只读，能力说明来自真实registry；全部提交禁用，未接业务写卡或页面。
- collection引用仅来自当前已验证plan绑定的集合及宿主facts/sources；导航checkpoint及await
  前后复核任务/作用域/当前snapshot身份，finally释放lease。该检查不等于最终宿主权限或
  实时对象revision/digest证明。aaa175修复另核现成模块authority和同步整来源stamp，
  ready跨checkpoint、inactive单CAS成功后才prepare取非空证明，真实插件核完整pin，
  lease后最终同值检查至push无await。未知模块仅宿主已存提示，不调用插件；已知缺pin或
  proof不支持则留workspace。未新增行tap业务mapping或授权；collection cell仍仅fact/computed。
- 持久化复用同事务scope/revision CAS，失败不覆盖赢家或pop；CAS后才安装，await中fence
  失效要求重开。成功CAS后旧验证投影可能已写盘的原有界限制保留，不伪称磁盘/内存全部回滚。
- 三路动作、captured plan、pending/receipt锁、共享validator/renderer与stream坏行否决保留。
  既有整库测试包含33schema的stream2/final校验/实际render、typed输入payload、legacy边界、
  codec roundtrip、未知operation不replay、跨SQLite恢复、两实例CAS与壳层拒绝行为，不只构造器烟测。

两名非作者独立审查交叉确认当前导航撤权缺口，撤回此前中间合入建议：
真实询价lease返回至外围await恢复间，现有revokeCapability使module runtime失效，
却不改变task scope或snapshot，旧最终检查仍可能push旧页面；DB末窗口也会按旧R8显示R9。
原owner已交aaa175，双非作者精确静态复审认为这两对象窗口机制已关闭，未见新增确定生产阻断。
16项本片行为测试委托真实Inquiry schema/SQLite/resolver与实际lease，含四项撤权/DB屏障、
两项unsupported拒绝，原typed/selection/anchor/重开与CAS失败零激活断言保留。
这是静态结论，尚不准合：旧3文件9项正向fixture缺proof或pin，迁移范围待用户确认，
未经确认未修改；已请求只迁真实Inquiry/fullpin并保留全部行为断言，不能跳过或降低门禁。
整来源stamp为保守变化证明，不独自证明精确对象/字段权限；真实pinnedresolve必须保留，
初始化前变化依它核对。不能以固定snapshot或该修复宣称完整H3。其余33组件契约未见新增确定回归。
范围交叉核实：本批新增集合入口只有fact对象，collection cell不准入sourceSpan；
ArtifactPreview及三项旧预览测试相对基线未改，不新增文件读取或路由。
本次修复限定对象导航；既有“当前文件＋来源变化警告”语义保留，完整来源预览H3另片验收。
核实代理亲跑9个checker、5个DA、10个gate行为测试及bash语法/diff检查通过。
旧source CI不替代本批新增完整组合与develop发布CI；原始日志/逐行诊断不入仓库。

## 完成范围与遗留

AIUI-8只读规则/审计及真实设置/旧数据去向入口；三档、授权编辑与真机无障碍未完成。
F4c固定snapshot、真实询价公开协议委托夹具及真实SQLite：不是完整生产询价/科研插件联调、
live publication/recompute、future14或设备强杀验收。AIUI-9是未接页面的只读适配/模板，
不是新建/编辑/关联/批量卡、双重领域校验、授权执行或真实业务回执完成。
Mac三项golden、真实模型与各平台真机仍后置。2380全文扫描碰撞有字段级提案但范围未确认，
受保护文件未改；一次通过不能称原风险修复。可选补验为read provider代际竞态、建议集合/总预算
语义负例及active inquiry await撤权屏障，不为比例降低校验或刷镜像覆盖。

源测量保留19个unloaded为unknown；自动严格gate只有API/models/transfer三范围，整库hash/DA
是独立人工审计补充。已知transfer_service:1203 catch的正向+1不重置floor827，不称命中全集恒定。
固定新组合的逐库测量和终态，以及正常发布后的远端读回见补记/执行回报。只代码集成，不打包部署。
