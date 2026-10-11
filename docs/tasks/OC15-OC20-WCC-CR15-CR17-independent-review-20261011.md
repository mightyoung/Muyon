# OC15–20、WC-C 与 CR15–17 文档独立组合复验

2026-10-11；独立 worktree `/workspace/Muyon-review-oc15`，分支 `review/oc15-oc20-wcc-cr15-cr17-independent-20261011`。只纳入已授权固定交付，不改作者分支；原始日志、临时脚本仅 /tmp。没有真实模型、Android、MUYON_EVAL_REAL、强推/删除/部署；活动 writer 保留。

## 固定来源与完整依赖

| 交付 | 固定完整 SHA | 原作者提交 / 依赖 |
|---|---|---|
| 当前 develop | `140a1b305271ca6a753bf6d2fd99f6b9c0e7c044` | PR49/50 + 分工 ADR 已合，合后 CI38141848455成功 |
| OC15 | `16610b333833164f7a0dc7aedc6c08a50957ce80` | 新测试244行；任务876dfc42父为f8cbd32 |
| OC16 | `e5088b54cc3a5366bf8c4e3486a999da96fa7551` | 新测试214行；任务0c518f80父为固定 PR49 ee831084 |
| OC17 | `f88e4b1b463009a8fdd058378ffe70685475021d` | 新测试305行；任务b0e3af6b父为固定 PR49 ee831084 |
| OC18 | `e8ae249b66dddaa4f7a18ff90da9400acdd6e912` | 任务18f7c0c8父为当前140a；增强F/D既有回执竞态测试 |
| OC19 | `b1a935ad70833273491e4163d22c58bd0d618967` | 任务ab939eab父为当前140a；仅新增真实刷新导入特征测试 |
| OC20 | `41acfb097c49f767afa66c1db95b83b165701a29` | 任务d95b8716父为当前140a；仅新增CR13 N3现状特征测试 |
| WC-C | `6bd0c7c6673fb4e3745789178e77a139b379e92e` | RED99fc937151bced08448c3162c0ce43be623435e7；任务d1cbd7e8父为固定PR50 |
| 分工/CR17/WC-D-F ADR | `f7c76fd0fe564f75511f09cecc6a40850af9a95e` | 相对已合35f6597只增加ADR两行，无产品 delta |
| CR15/16/17 文档 | `c09debd02334a7dfe873a52fdc08c473088f85b9` | 完整1a964df→f34ee3f→c09debd；六份Markdown131行，父基线140a |

顺序：已合 PR49/50 基线140a → OC15组合37d9844 → OC16组合da47ee4 → 固定ADR与ChatGPT文档 → OC17组合42cfdef → 独立审查一行修正OC15日志表520b737 → OC18。原四交付完整候选 **`b912a227315a64463a65931441d8b15c37b8a22a`**（父520b737与固定e8ae249）；相对140a共16文件1047增加/6删除，只有测试及文档；apps/lib、packages、scripts、.github **全部无 delta**。所有 source ancestry 保留，无 cherry-pick 遗漏依赖、无冲突。OC18两个回执测试文件与作者e8ae249逐字一致，原f6519fd独立增强未覆盖丢失。

后续新交付分别加入：OC19形成 `ccbf3f2a76a980141eb09ef74ba9a813f530e2c8`（仅OC15–19+文档；未单独跑远端全量CI），再加入固定WC-C形成五份OC的组合 **`3ec36a03f252a5c6cf2df73697dc0a06210a0a96`**（父ccbf3f与6bd0c7）。该五份候选22文件1871增加/143删除；产品仅WC-C的inquiry_record_tools.dart，原WC-D lookup/identity/API/Store/CI门禁零delta。没有把原四交付候选的绿用于新增OC19或WC-C。

OC20在未推develop前到件，按用户新授权同批加入，形成最终完整候选 **`f64d2c126a963b26bcc7d12b68aa6d9be085161e`**（父3ec36a与41acfb0）。相对140a为24文件2105增加/143删除；产品delta仍仅WC-C一个文件，OC20仅测试及任务文档，无额外实现。当前统一CI必须针对这个六交付+WC-C候选，旧四份或五份结果都不能冒充。

读六份 OC 任务与WC-C任务、完整 source diff/祖先、CR13、REVIEW/invariants/ADR及新三份ChatGPT报告。未发现新增本地AGENTS/.agents/skills；沿用 using-git-worktrees、verification-before-completion；用户授权独立验证与唯一 integrator 正常合入，不委派重复开发。

## 原用例与交付判据

- 官方 Flutter3.47.5 / Dart3.13.4；pub get自动生成配置已恢复，缓存与analyzer state在/workspace，不改HOME。
- OC15四用例、OC16三用例、OC17三用例：组合10 pass / 0 skip / 0 fail；所有临时变异恢复后再跑10 pass / 0 fail。合入OC18后五测试文件共30 pass / 0 skip / 0 fail；逆变异恢复后再跑30 pass / 0 fail。加入OC19后32 pass / 0 fail；加入WC-C后十个测试文件合计106 pass / 0 skip / 0 fail（OC/回执32 + WC-C/general/lookup/characterization74），全部变异还原。host/module_api/inquiry三包strict analyze均No issues found。
- OC15：S3 position变大仍保持枚举顺序，S1自己的引用不变；S2 argument / level变化；旧顺序摘要均在实际审批/写路径被拒，业务全行/顺序不变；新鲜摘要正对照可移动。不会靠选中对象自己变了误抓邻居摘要缺失。
- OC16：交换 S2/S1精确两个section upsert、项目/module/type正确、摘要等于真实重读、S3排除；heading更新实际changes为 **1 section + 2 outline upsert**；边界无操作为空changes且摘要明确位置未变化。临时强化update用例后独立核对三项module/digest全部正确（3 pass），已恢复原测试，不能把强化版本说成CI已跑。
- OC17：两条真实outline链接下的TEMP trigger直接SQL前提均确实抛SqliteException。原始负例拒绝成功并比较sections/outline/import change_log/muyon_change_log完整快照；正对照无trigger，删除section+两links，实际模块日志恰好3条delete。

### OC19：真实刷新导入候选变化的既有行为

- 真正通过ResearchExchange.importResearch刷新同一项目/文档，同源notes字节不变，P/Q候选扩大为P/Q/R，明确验证R存在、P六字段digest与D contentDigest均未变，再执行已批准确认：只剩P、ambiguous=false、method包含manual、持久receipt succeeded。
- 正对照通过真实刷新增加P rev2，重读确认P paperRev/digest确实变化，旧审批被拒，完整binding行快照不变、changes空、持久receipt failed；不是直接SQL伪造。
- 独立候选数量逆变异仅在confirm_binding当前摘要加数量标记，以初始2候选为基准（count=2保持原摘要，count=3追加标记）；list_bindings仍返回合同原六字段摘要，测试前提照常成立。第一个用例抵达工具执行并expected succeeded/actual failed（第185行），第二正对照通过；1pass/1fail。说明检出候选集合新增后重确认这一相反策略，明确不声称新增产品语义。恢复后两用例通过。

### OC20：CR13 N3延期债务的现状边界

- 实际审批删除section与两条outline，首次result恰好3项delete；receiptFor实际重读result.changes空，但objectRefs完整JSON与首次相同，三个被删id仍全部保留，module=research/project=P。更新同链首次3项upsert，重读changes空、refs完整JSON相同。
- API toJson/fromJson逆变异同时添加changes序列化与恢复（ref JSON与op enum name），首项 `delete_section first result carries delete changes but persisted receipt has none [E]`；Expected empty / Actual 3 ObjectChange，第二项也失败，总0pass/2fail，真实存储重读路径触发而非启动错误。逐字恢复后两项绿；最终十一测试文件108pass/0skip/0fail，host strict analyze No issues found。
- 两条测试顶部明确契约版本化时同步改写，当前绿**不是N3修复或版本化回执交付**。将来完善契约必须同步更新这两条现状断言，不把旧行为视为永久规范。

### OC18：实际持久回执引用，而非仅内存 result

- F两条commit-A/B-update/delete竞态补上持久objectRefs完整JSON、digest/revision及与B不同；D十条竞态读持久objectRefs并检查列表精确长度、完整JSON与A marker，明确不同于B。D完整JSON部分先前已由独立f6519fd加入，本交付主要增量为F持久引用覆盖和D长度/marker显式断言，不夸称新增十个用例。
- `ToolRegistry.receiptFor` 实际SELECT result_json并jsonDecode/ToolCallResult.fromJson，每条都重读数据库，不是复用返回对象。OC18合并无冲突；原D部分提交故障、完整结果JSON断言及changes空集合仍保留，CR13 N3没有冒称关闭。
- 只在宿主持久化前复制并改写JSON，把第一条引用contentDigest或revisionRef改为null，原内存result保留完整。两项逆变异分别触发8/4个真实断言失败（见下表）；证据指向SQL存储/解码这条路径。

### OC17：失败确实发生在写入后、持久结果完整回滚

临时强化测试用SQLite自定义函数收集不可被事务回滚的内存追踪，先清除直接SQL前提的事件，再调用实际工具：

- delete路径：`after-first-link → before-second-abort`。
- update路径：`after-section-write → after-first-link → before-second-abort`。
- 证明工具确实抵达注入点，不是scope/摘要拒绝或启动异常导致假绿。删除单条SQL自身也有ABORT原子性，不能仅凭该负例夸称独立证明外层事务；update先写sections再写outline，以及下面真实拆事务变异，补足跨语句原子边界。
- 失败后autocommit=true；宿主真实回执为interrupted，receiptFor重新解码的持久状态一致，不夸称failed或成功。业务写事务确实回滚，但宿主保守未知状态保留。
- 用数据库实际文件另开 **OpenMode.readOnly** 连接，重读四张业务/日志表，全部与调用前快照相同；强化版3 pass，随后恢复作者原字节。不是内存夹具或伪造回执。

## 逆变异（独立重做，不冒充作者原日志）

每项均编译/加载成功，观察到下面实际行为断言；全部还原到固定候选相同字节。未取得作者原始变异log，不依赖“作者称检出”作为独验结论。

| 逆变异 | 检出结果 / 失败第一行 |
|---|---|
| OC15 _sectionRows 去掉position（任务必需） | 3pass/1fail：`move_section refuses when a neighbour position changed but order is the same [E]`；Expected failed / Actual succeeded |
| OC15 去掉argument | 3pass/1fail：`move_section refuses when a neighbour argument changed [E]`；failed→succeeded |
| OC15 去掉level | 3pass/1fail：`add_section refuses when a neighbour level changed [E]`；failed→succeeded |
| OC16 move只报被移动段落（任务必需） | 2pass/1fail：`move_section changes list both swapped sections [E]`；Expected length2 / Actual1 |
| OC16 update少报第二条outline | 2pass/1fail：`update_section heading change lists the section and every linked outline row [E]`；Expected length3 / Actual2 |
| OC16 边界误报一项变化 | 2pass/1fail：`noop move at boundary has empty changes [E]`；Expected empty / Actual有项 |
| OC17 删除第一条link后COMMIT+新BEGIN再删第二条（任务允许拆事务） | 2pass/1fail：`delete_section rolls back when an outline delete fails midway [E]`；outline持久快照少第一条link |
| OC17 section UPDATE后COMMIT+新BEGIN再更新links | 2pass/1fail：`update_section heading rolls back when a linked outline update fails [E]`；Expected S1 / Actual改后S1 |
| OC18 持久JSON第一条contentDigest置null，内存result不变 | F/D目标20项中8项失败；首项F `I-2 receipt keeps A snapshot when B updates after commit [E]`，持久完整JSON实际字段null |
| OC18 持久JSON第一条revisionRef置null，内存result不变 | 同20项中4项失败；首项D `create_task receipt keeps A snapshot when B updates after commit [E]`，持久完整JSON实际字段null |

COMMIT后立即开始新事务，保持外层ManagedConnection错误清理可执行；两项OC17变异没有“ROLLBACK无事务”、清理超时或启动失败。测试抓到真实部分提交，不以连锁错误充数。OC15–18共10项独立逆变异均检出；每项先恢复再施加下一项，最后git diff --exit-code与30项恢复后绿验证通过。

### M1 已在独立 review 分支修正

OC15原`log()`查导入`change_log`，不是宿主`muyon_change_log`。临时强化检查4pass后，依REVIEW小而确定修复规则，独立审查提交 `520b737bed8f565515ecacfdc802f674affc929a` 只把该SQL表名改为实际宿主表（一行替换），使正式组合CI包含真实宿主日志守卫。作者16610b分支未改，产品无改动，没有放宽任何断言；最终候选三测试10pass，OC15三个字段逆变异也按修正后的守卫重新检出。该修正不是原作者交付，来源与证据分别列明。

## WC-C 独立静态 / 动态审查

- 基线固定PR50已在最新develop140a ancestry；完整source范围3产品/测试文件+539/-137（含RED测试345行），另保留WC-C任务文档26行。旧delete用例只改名称移除误称stale，逐字断言不变；新增真实stale例先保留contact版本1预览，再将记录改成2并刷新selection，隔离引用预览陈旧与selection陈旧。
- 四类冲突以WriteConflict抛出；state.write仅捕获FormatException，Store.transaction异常ROLLBACK，外层catch再返回failed+受信data。checkBeforeEffect及已提交result优先保留，不改ToolCallStatus、reg4c身份、WC-D lookup或Store领域规则。独立阅读与父任务安排的只读审查均无新增Critical/Important；只读静态结果不替代本次动态。
- 11个新增冲突用例、20个generic write、38个WC-D lookup、5个characterization合计74pass；加入OC19时与OC/回执合跑106pass，加入OC20后108pass。检查全数据库表payload/version/tombstone/change_log/muyon_change_log/meta业务receipt快照；测试用直接handler绕开宿主预拒只用于到达模块自身分支，实际宿主审批测试同时保留。
- 逆变异纯文本出口（删除受信data，保留failed）：11项中10fail，首行 `changed selected snapshot is scope_changed [E]`，error_code缺失；不是编译/启动错误。
- 逆变异在Store.transaction内catch WriteConflict并正常返回result：10pass/1fail，唯一失败 `late conflict rolls back nested writes and receipts before conversion [E]`。授权guard已嵌套写供应商v2/日志与meta reg4c:rollback-probe，错误被正常转换后错误提交，快照明确检出部分写与probe留存。原实现回滚后快照完全相等；无清理超时。两个逆变异后逐字还原，git diff --exit-code通过。
- 非阻断测试建议原样记录：helper只在显式version时核current_version，operation_id_reuse/referencing_changed尚未逐项精确锁field_paths与无行详情；消费审批的重试只断言任意ToolPlatformException，未精确锁approval_required及重试后DB快照。这是覆盖强化建议，未证实产品缺陷，未扩写作者测试。
- 作者Mac三包48fail（其称46截图、1预览不稳、1编译断言复跑绿）的来源归因**没有独立验证**；本次官方Linux全量结果另列，Linux字体skip不等同于Mac截图差异证明。WC-C不修复WC-D-F的非法create ID/请求必填结构，CR16 I1/I2仍开放。

## 文档门禁与未关闭事项

- f7c76fd 相对已合35f6597恰为ADR新增两行。既有Leader B集成/独验/合develop、Leader A派发/组织审查分工保留；CR17四决定第3项按用户指定research-skill v6.8：schema2项目、固定论文版本claims V2、needs_review，assertions此次不导出；登记WC-D-F为合入后补修、不回退。
- c09debd六文件和ADR共七文档逐文件与固定 source byte相同，链接存在、无冲突标记、git diff --check通过；无附带产品、平台、CI门禁或作者任务实现改动。
- [research-skill项目](https://github.com/mightyoung/research-skill)、[evidence schema](https://github.com/mightyoung/research-skill/blob/main/references/evidence-schema.md)只读参考核对schema2、claims/assertions区分；本次仅入库用户决定，不执行该skill、导出器或新增LE实现。
- CR15历史“可合入”与当时固定head/静态范围保留；CR16新 **I-1非法create ID / I-2请求必填结构** 保持开放，旧C0/I0和green CI不能否定它们。**本次文档/test合入不等于WC-D-F完成或CR16关闭**。Haiku与Codex任务未交付不自行修改，不重复派WC-C；到件优先独验WC-D-F。原Haiku回报登记仍由Leader A负责。
- CR13 N-2/N-3、probe生产task/conversation身份接线、真实平台能力等既有边界不扩大为完成。AIUI/SN整链等待SN6、最新develop组合CI与统一外审；SN5/PR52最新固定交付11225c4f2823ab45cb1e9421aeda0eb03969be95，本次未纳入。CR18任务已只读读取：CR分支现7de86d28752adf3550b957e7084d7acfce7b7fd7比本次固定c09仅增CR18说明，保留既定CR15–17来源，未来整链按CR18执行，未收到统一外审结论前不合AIUI。

## 精确 CI / 结论

- OC15 source [38142230488](https://github.com/mightyoung/Muyon/actions/runs/38142230488)：completed/success，原始checkout16610b完整SHA已独立读取，旧f8基线不代替当前组合。
- OC16 source [38143118572](https://github.com/mightyoung/Muyon/actions/runs/38143118572)：completed/success，原始checkout精确e5088b完整SHA，旧PR49基线不替代当前组合。
- OC15单独组合 [38143180403](https://github.com/mightyoung/Muyon/actions/runs/38143180403)：completed/cancelled（加入OC16后并发替换），不是失败，也不是合批绿。
- OC15/16组合 [38143494854](https://github.com/mightyoung/Muyon/actions/runs/38143494854)：completed/success（13:49:49 UTC），准确da47ee4完整SHA；只覆盖OC15/16，不证明后加OC17与日志表修正；无OC17，不能作为三份完整组合证据。
- 原三测试/文档组合 [38144569055](https://github.com/mightyoung/Muyon/actions/runs/38144569055)：completed/cancelled（M1一行审查修复后并发替换），不计失败或最终绿。
- 最终三测试+宿主日志守卫+固定文档 [38144900388](https://github.com/mightyoung/Muyon/actions/runs/38144900388)：completed/success，精确520b737；这是三交付组合，不能代替新增OC18的四份组合。

- OC18 source [38145185269](https://github.com/mightyoung/Muyon/actions/runs/38145185269)：completed/success，metadata固定e8ae249完整SHA。
- WC-C source [38143752223](https://github.com/mightyoung/Muyon/actions/runs/38143752223)：completed/success，metadata固定6bd0c7完整SHA，原PR50基线不替代当前组合。
- OC17 source [38144008841](https://github.com/mightyoung/Muyon/actions/runs/38144008841)：completed/success，metadata固定f88e4b完整SHA。
- **原四交付+宿主日志守卫+固定CR15–17/ADR文档** [38145882285](https://github.com/mightyoung/Muyon/actions/runs/38145882285)：completed/success（14:24:31 UTC），8包analyze/8测试套件均通过，3549pass/207skip/0fail；原始checkout与metadata精确 **b912a227315a64463a65931441d8b15c37b8a22a**。

- 五份OC15–19 + WC-C + 固定CR15–17/ADR文档 [38146738156](https://github.com/mightyoung/Muyon/actions/runs/38146738156)：completed/success（14:38:47 UTC），3562pass/207skip/0fail；该五份组合不含OC20，原始checkout与metadata精确 **3ec36a03f252a5c6cf2df73697dc0a06210a0a96**。

- **最终六份OC15–20 + WC-C + 固定CR15–17/ADR文档** [38147161205](https://github.com/mightyoung/Muyon/actions/runs/38147161205)：completed/success（14:40:29 UTC），3564pass/207skip/0fail；8包analyze与8测试套件均通过，Doctor23、Laya、coverage及制品步骤全部success，原始checkout与metadata精确 **f64d2c126a963b26bcc7d12b68aa6d9be085161e**。


| 最终六份组合测试套件 | pass | skip | fail |
|---|---:|---:|---:|
| module_api | 250 | 0 | 0 |
| muyon_ui | 380 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 231 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 1849 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry（host assets harness） | 302 | 47 | 0 |
| 总计 | 3564 | 207 | 0 |

结论：固定OC15–20、WC-C与固定CR15–17/ADR可按授权正常合入。独立目标108pass、14项逆变异均检出；OC15宿主日志守卫M1已修，WC-C无新增Critical/Important，两条非阻断测试覆盖建议保留。新全量依据是精确f64d2c候选，不能拿旧source、旧四份或五份结果冒充。

LE01交付202e44af独立隔离验证，两个Important已以三个合法API输入回归动态复现，268作者原测试通过仍不放行。LE01未包含于本候选/API250、未改baseline；等待Parent决定补修归属，其证据另存工作区报告，不把本批绿误称LE01绿。CR16 I1/I2仍待WC-D-F，CR13 N3仍延期，AIUI仍须SN6+CR18统一外审。


本文docs-only后继与真正跑过CI的代码/文档候选严格区分，不冒称后继自身跑过完整CI。原始日志不入仓库；正式合入另读完整develop SHA及合后CI终态，所有分支保留。
