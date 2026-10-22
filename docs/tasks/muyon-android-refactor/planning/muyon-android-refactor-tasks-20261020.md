# Muyon Android 改造任务卡

配套：[总计划](muyon-android-refactor-20261020.md) · [验收规格](muyon-android-refactor-tests-20261020.md)。状态全部为未开工；任务规模用 S/M/L 表示相对工作量，不冒充工期承诺。以下产品路径均为计划新建。所有owner不得覆盖他人改动；变更公共文件须交公共owner整合。

## P00 — 固定候选与来源（M，集成人）

- 输入：develop、PR86/88/89/91–99、live canary和已确认目标。
- Ownership：新增 `docs/tasks/muyon-android-refactor/SOURCE-MAP.md`、证据索引和隔离worktree；不改业务代码。owner表记录P01→P02→P04的绑定/FFI写权交接；schema仅P03、dispatcher/Service仅P04、Manifest/Gradle/CI仅集成人。
- 工作：核远端head/祖先/未合差异；标每项采用源、产品文件、测试与review；保留原作者PR和HOLD原因；记录现有调用授权及预算事实，不从文字批准推导额度。
- 输出：唯一集成base与每一增量source；ABI/工具链/SDK/API26/NDK现状；无重叠文件owner表；当时有效的集成治理。
- 验收：每个复用实现能定位commit和文件digest；不把多个不同base的绿灯合成候选通过；dirty主checkout完整保留。
- 依赖：无。阻断：来源无法取得、关键source不明时不猜测，受影响卡保持未准备；其他独立规划/测试可继续。

## P01 — 正式业务/权限/恢复契约（L，核心owner）

- 依赖：P00。Ownership：`docs/contracts/muyon-android/{schema,semantics,fixtures}/`与 `crates/muyon-core/src/contract/`；只写schema源，生成绑定按P02→P04交接，不与其同时写。
- 工作：固定supplier CRUD/restore、project/paper/import、受控blob、scope/plan/authority、revision/intent/receipt、pending/unknown/recovery_action；区分admission和业务状态；明确取消线性化点和读/写边界。
- 范围：只冻结本次Android合同与Rust/Kotlin向量，不关闭完整跨端M03，不将Electron或全平台oracle纳入前置；本次required场景仍须全部执行，不接受skip代替。
- 字段：Supplier八字段，`merged_into`保留且不开放合并；独立PDF title非空≤500 codepoints，project+附件必需，其余元数据可选；导入保留宽松JSONL记录及来源修订。
- 输出：schema、错误表、状态转移表、operation白名单、规范化/编码向量、创建/删除/恢复完整回执样例、版本不兼容拒绝规则；新store schema/version与初始化权限；业务grant/generation同业务事务的撤权/commit线性化；FileSource/ArchiveEntry有界元数据与读取lease接口。
- 验收：同向量Rust/Kotlin语义和digest一致；非法权限/未知安全字段/超限/大revision/同intent异参明确拒绝；不能将实验CLI输入当真实授权。
- 测试：CT01–CT04。对外部API陌生部分由实现owner核对官方文档，记录版本链接；不为此提前新增依赖。

## P02 — 产品工程与既有代码提取（L，集成人/Android公共owner）

- 依赖：P01。Ownership：根Rust workspace、`crates/muyon-core`模块入口、`crates/muyon-android-ffi`、`apps/muyon_android`工程/Manifest/生成绑定/构建配置、`tools/muyon_android/`入口；业务子模块由各卡负责。
- 工作：从固定source连接现有共享Core/Service/provider/生成器和检查器，仅按业务需要最小提取；不先全面搬目录。fixture默认不进入产品variant；产品应用、DB、附件命名空间独立，禁止自动升级Flutter旧库。交付后FFI/生成Kotlin写权移交P04。
- 输出：可构建空壳及来源映射；精确工具链/锁文件、包名、appId、ABI、构建命令和候选build id；只使用现有依赖。
- 验收：旧实验适用回归仍通过；新APK native库与source/build id一致、生成Kotlin与真实生成产物一致；API26能启动停止/重连Service，不把空壳视为业务完成。
- 测试：PK01/PK02、AN01。若原代码只能以实验crate为依赖，先提取共享实现，不让产品运行时依赖synthetic启动器。

## D01 — API26 搜索发送超时根因与修复（M，debugger→executor）

- 依赖：P00；可在原固定PR99 checkout先复现，最终修复须映射至P02产品代码。
- Ownership：专属 `SearchSendServiceLoopTest`、发送状态专属模块及诊断；触及Service公共文件时由P04 owner整合。
- 工作：复现run39279706227的两用例，记录UI动作、Service受理、Rust run、返回投影、UI订阅/IME/生命周期的阶段证据；定位第33行等待未满足的实际条件。
- 输出：一个可复现根因、最小修复、针对性回归和源修复映射；诊断只记录固定错误/身份，不输出密钥/原始业务内容。
- 验收：原失败用例与另外一条均执行通过；证明不靠放宽条件、延长超时或删断言过关；instrumentation exit0但tests失败仍使gate失败。
- 测试：AN02、OR01；根因未确定时只记录证据，不编造“已修复”。

## D02 — I04恢复证据闭合（M，独立验证owner）

- 依赖：P00。Ownership：专属I04测试/证据及所需最小修复建议；不擅改共用产品逻辑。
- 工作：按PR86固定合同补旧script状态转HTTP再重开的真实恢复证明，记录旧状态、来源绑定、是否发出外部动作；保留原HOLD与被拒执行记录。
- 验收：同一固定候选可重复核对预期；恢复不重发/不伪造回执；若平台仍拒绝，只保留BLOCKED证据，不绕过、不用不等价synthetic替代。
- 测试：RC01。该卡阻止整体集成完成，不阻止无关局部卡继续。

## P03 — 业务库、原子执行和原回执（L，核心存储owner）

- 依赖：P02。Ownership：`crates/muyon-core/src/store/{schema,execution,receipt}*`及专属测试；业务repo由S/R owner按接口实现，schema改动统一归此owner。
- 工作：新库显式初始化和版本检查；pending先持久；业务效果/history/committed/receipt同事务；CAS/幂等完整绑定；真实SQLite错误分类。业务grant/generation为本地业务唯一权限事实源，发行/撤销/取消与commit经同一写队列/DB事务排序；提交内不回调Kotlin owner、不持第二库事务；receipt绑定admission ID/generation。admission保留外发/计费guard，跨库仅关联核对不宣称原子性。
- 验收：同intent最多一次效果；同intent异参冲突；竞争CAS至多一成功；commit后丢回包查原回执；pending未知不重发；read/preview/lookup不暗改业务。
- 测试：DB01–DB04，真实进程SIGKILL和独立SQLite查询；逆向破坏事务/CAS/幂等/unknown保护时行为断言失败，恢复源码后通过。

## P04 — 可信owner与Service业务用例（L，Android公共owner＋核心owner串行整合）

- 依赖：P02/P03；接口设计可在P01后准备。Ownership：`apps/muyon_android/.../agentipc/`、`crates/muyon-android-ffi`导出、`muyon-core/src/application`公共dispatcher。
- 工作：新增supplier/project/paper/import具名入口及状态查询；真实确认→Rust业务grant，lease/scope/params/revision复验；唯一Service writer/排他owner锁，重启新epoch不得重用写grant；受控worker/取消/close-drain/回调生命周期。发行、撤权、取消线性化点为业务DB相应COMMIT；admission只管原有外发/计费和调度，不当业务授权库。P02交接后独占FFI/生成Kotlin。
- 输出：类型化Repository与Service端口、权限/确认流、原intent重连协议；手动/模型调用共用业务用例，模型无授权能力。
- 验收：真实Service→Rust→真实库；过期/变scope/撤权拒绝；native/Service断开保留unknown；重启查询原身份；无UI直接数据库写入或fixture owner兜底成功。
- 测试：CT03、AN01/AN06、DB04。公共生成文件只由此owner写，业务lane提交接口请求。

## P05 — 受控附件与跨文件/DB恢复（L，核心附件owner）

- 依赖：P03。Ownership：`muyon-core/src/platform/blob*`、`store/blob*`、`application/import_intent*`及文件故障测试；Android picker归U02。
- 工作：复制前持久intent/staging identity；copying→pinned→committed/aborted；先验证digest并固化blob，再以DB事务同时发布记录/receipt和释放发布pin，不宣称文件操作也在SQL事务内；持久reader pin覆盖已打开读取者。GC同事务检查无引用/无pin且相关intent已知终态，再标deleting并禁止新publish/read；pending/unknown不得按超时释放，重启恢复后才GC；重用blob核digest/长度。
- 验收：复制中、固化后、DB提交前后、回包前故障均无成功半论文；已发布记录的附件实际存在且digest匹配；源URI撤权后私有副本可用；lookup只读，显式后台清理不冒充查询。
- 测试：FS01–FS03、RC02。禁止“文件rename+SQLite天然原子”假设；不为无历史迁移自动清库。

## A01 — ZIP元数据能力与有界reader（M，文件端口owner）

- 依赖：P01/P02。Ownership：`muyon-core/src/platform/archive_metadata/`及专属fixture/tests；不写解压引擎、不改P05 blob公共生命周期。
- 工作：从同一封存ZIP解析EOCD/CEN/LOC，生成可验证ArchiveEntry；ZIP32单卷、STORED/DEFLATED，正确处理data descriptor；固定编码/flags/extra/creator类型白名单，拒绝链接/特殊类型、错offset/重叠/CEN-LOC不一致。ZIP64/加密/多卷显式unsupported。
- 输出：无新依赖的元数据reader、范围合同、官方格式依据和API26平台能力证明；原始字节通过受控snapshot读端口取得，不信任Android伪填类型。
- 验收：自家研究导出round-trip、正常中文名称/descriptor通过；symlink/冲突元数据/超限/截断拒绝；校验后的条目与实际流CRC/长度匹配。平台ZipEntry不提供外部属性，不能仅换ZipFile便宣称完成。
- 测试：AR01、FS01。不能可靠通过则R02保持技术BLOCKED，记录替代方案，不能删断言或自行新增库。

## S01 — 供应商真实新增和完整修改（L，供应商owner）

- 依赖：P03，合入前P04接口存在。Ownership：`muyon-core/src/domain/supplier*`、`application/supplier*`、`store/supplier*`及专属测试；不私改公共schema/dispatcher。
- 工作：移植八字段校验与向量，create稳定ID、完整payload更新、分页查询/详情、CAS与真实原回执；不新增联系人或合并功能。
- 验收：八字段保存/重启一致；同名允许按稳定ID区分；空name/非法rating/超限/未知字段拒绝；缺省与null规则一致；scope/CAS冲突无业务副作用。
- 测试：CT01、SU01/SU02、DB02。旧Dart规则作差分oracle，不把已知旧缺陷当安全标准。

## S02 — 供应商软删、恢复和引用（M，S01同owner）

- 依赖：S01。Ownership：同S01模块后续串行变更；公共schema由P03 owner合入。
- 工作：delete/restore各新revision/receipt；普通列表过滤deleted，按ID仍可投影已删对象；保留原引用、拒绝新增引用；undo调用restore，不删除历史。
- 验收：删除/撤销/恢复及重启状态一致；旧引用显示已删除，新引用拒绝；删改/恢复CAS竞争有明确结果；原历史回执与当前值分离。
- 测试：SU03、DB02；引用fixture证明领域规则，报告未提供完整报价/询价产品入口。

## R01 — 科研模型、项目、论文和读取（L，科研模型owner）

- 依赖：P03/P05。Ownership：`muyon-core/src/domain/research/`、`application/research_catalog/`、`store/research/`和专属测试；公共schema请求P03 owner。R02/R03不写这些公共目录，交具名接口请求。
- 工作：项目显式新建；统一papers/entries、来源修订、文档与附件绑定；手填和导入共享可读投影但约束分开；列表/详情/附件读取及scope授权。
- 验收：新库新建项目；各入口论文出现在同一项目文库；source id/rev与本地ID不混淆；跨项目拒绝；重启记录及hash不变。
- 测试：RE01/RE04、CT02；保留原JSON和重复修订视图，不将任意JSON字段升级为工具执行参数。

## R02 — 目录/ZIP私有快照导入（L，科研导入owner）

- 依赖：R01/P05/A01/U02a。Ownership：`muyon-core/src/application/research_import/`和专属语料/测试；Android有界归档读流适配接口由U02a owner独占实现。受控port可先跑Rust规则，但不能因此关闭Android导入。
- 工作：复用路径/大小/重复/引用保护规则；冻结清单后受控流入库；显式导入目标项目和source identity；新导入/refresh/原intent查询分开；汇总数量/冲突/拒绝。
- 验收：目录/ZIP相同fixture产生等价论文/绑定；同id+rev重复保留并提示；已引用同修订改内容拒绝；refresh只按合同清理消失且未引用条目；穿越、symlink、重名、超限、坏ZIP/JSONL全部无可见半成品。
- 测试：RE02/FS01/FS02/RC02。若旧语义移植失败，先保留RED并修，不以静默upsert简化。

## R03 — 独立PDF和手填元数据写入（M，科研新增owner）

- 依赖：R01/P05，可与R02在不同子模块并行。Ownership：`muyon-core/src/application/paper_create/`及专属测试；不改R02导入规则或R01 store/schema。
- 工作：类型化论文新增、title/project校验、可选元数据保存、私有PDF绑定、原intent/receipt；不自动联网提取元数据、不引新PDF引擎。
- 验收：必填缺失不提交；同名文件不覆盖；源文件删除/撤权后副本可打开；取消、无权限、超限、磁盘/复制失败不会显示保存成功；重复原intent无第二论文。
- 测试：RE03/FS01/RC02。PDF格式验证范围明确，不把头部检查称为完整恶意PDF检测。

## U01 — 供应商Compose和交互（M，供应商UI owner）

- 依赖：P04/S01/S02；页面可从P01起按固定投影开发。Ownership：`apps/muyon_android/.../supplier/`、专属ViewModel与instrumentation。
- 工作：列表/详情/完整编辑/新建、删除确认与撤销恢复、冲突/unknown查询；复用既有SupplierPage/ScreenModel交互保护，扩展为完整payload。
- 验收：键盘/返回/重复点击不引双提交；错误与恢复动作可见；历史回执和当前值清晰；API26真实port完成CRUD，不以recording port验收。
- 测试：AN03/AN06、SU01–SU03；与Service公共owner交接接口，不共同改binder。

## U02a — Android文件与归档端口先验（M，Android文件owner）

- 依赖：P01/P02/A01；真实产品调用接P04。Ownership：`apps/muyon_android/.../platform/files/`及专属能力instrumentation，不写research UI。
- 工作：真实picker URI→不可变私有snapshot；FileSource/ArchiveEntry/读lease按合同；平台有界流解压前核Rust清单，每块检查计数/取消/CRC并核最终长度，拒绝不可观测类型，不暴露任意文件路径。
- 验收：API26目录/ZIP/PDF读流、源撤权后的副本、取消/超限和A01元数据比对通过；早期能力证据是R02真实导入前置，不必等业务UI。
- 测试：AR01、FS01、AN04/AN05的文件能力子集；最终业务提交由U02b/V01验收。

## U02b — 科研Compose业务集成（L，科研UI owner）

- 依赖：P04/R01/R02/R03/U02a。Ownership：`apps/muyon_android/.../research/`及专属业务instrumentation，不写U02a平台端口。
- 工作：项目/文库/详情、目录/ZIP导入和PDF表单；调用U02a冻结文件端口与Rust用例，显示导入摘要和错误。
- 验收：API26三入口均从真实picker进入，取消不写库；无需假造URI为普通路径；复制后原源失效仍可读；独立PDF与快照论文在同一文库可见，附件有可操作打开入口。
- 测试：AN04/AN05、RE01–RE04；平台缺现成依赖时记录技术缺口，不擅加库。

## C01 — 普通聊天、搜索与真实业务读取集成（L，聊天owner）

- 依赖：P04/D01；业务读接S01/R01。Ownership：`muyon-core/src/agent/`中既有provider/工具组合、`apps/muyon_android/.../chat/`；公共Service改动交P04 owner。
- 工作：移植既有header修复、预算/凭据/TLS/请求身份与会话规则；连接真实SearchHost/transport；供应商和科研新增数据通过受控只读工具可见；模型写建议仍走P04确认/授权用例。
- 验收：离线parser回归+设备rebuild/lint通过；真实模型有完整accepted answer/usage或明确unknown，不按HTTP200判成功；真实搜索有外部结果证据；失败/空结果/超时不重发、不泄漏凭据；来源披露只含当前授权数据。
- 测试：CH01–CH04、AN02/AN07。缺有效付费授权/预算时本卡真实实测保持未完成，继续本地工作，不清除旧reservation。

## V01 — 固定候选API26用户链路（L，独立test-engineer/verifier）

- 依赖：U01/U02b/C01。Ownership：专属产品Android测试、测试数据生成、`tools/muyon_android/verify_api26*`和证据；不改产品实现以让断言变绿。
- 工作：从空的独立测试库走本次真实UI→Service→Rust→SQLite/附件；核供应商CRUD、三种论文入口、聊天搜索与读取、取消/冲突/重启。
- 验收：AN01–AN07全部执行；失败计数为零且无隐藏skip/fixture替代；apk/source/so/runtime标识一致；fixture与真实provider报告分开。
- 交付：实际命令/exit/count/device/API/日志/截图及物理库/附件核对；发现缺陷回对应owner修复后重验受影响范围。

## V02 — 故障窗口与整体恢复（L，独立验证owner）

- 依赖：V01/D02；专属核心故障测试可先于UI独立进行。Ownership：专属进程/设备故障测试，不与产品writer共享工作目录。
- 工作：按RC/DB/FS规格，在pending、实际SQL后、commit前后、blob固化、回包前、Service终止/重连执行故障；独立核物理事实、原intent、费用reservation和附件引用。
- 验收：无半业务/错误成功/重复写或自动模型重发；current与历史receipt分离；I04实际证据闭合；未知计费不清零。
- 保留边界：模拟器kill不证明断电、跨设备同步或分布式exactly-once。

## V03 — 门禁、证据封存与集成交接（M，唯一集成人＋verifier）

- 依赖：V02，所有required任务完成。Ownership：产品专属CI/workflow、`docs/tasks/muyon-android-refactor/ACCEPTANCE.md`、证据manifest；公共workflow由唯一owner修改。
- 工作：固定required jobs/selectors，检验producer终态、APK与库身份、真实tests计数；刷新旧任务状态；按有效治理向LeaderB交付集成，不自行强推/合并。
- 验收：新候选完整适用回归、lint、contract、Rust/store、双ABI包装、API26、真实provider证据都有source绑定；缺失/取消/skip拒绝整体通过；密钥/正文不入仓，长期证据保留哈希与脱敏摘要。
- 交付：最终SHA和文件映射、完成任务表、未覆盖项、可回退提交/独立数据目录；无真机/发布/历史迁移通过宣称。

## 派工约束

四个以内并发执行槽的建议组合：集成人/核心公共owner、一个供应商lane、一个科研lane、一个Android或验证lane；按当前依赖调度，不能把五个逻辑owner解释成必须同时启动五个进程。接口和schema准备结束后才释放相应业务卡。所有专属实现用 `executor`，根因定位用 `debugger`，测试策略用 `test-engineer`，完成证据用 `verifier`；只有用户明确进入team运行时才用worker。

共享文件由公共owner串行整合：Cargo/锁文件、schema/迁移、公共dispatcher、Service、生成Kotlin、Gradle/Manifest、CI。子任务交完整有界合同和专属文件列表，使用隔离worktree；不能在dirty主checkout相互覆盖，也不能在子任务未返回最终结果前标卡完成。
