# Muyon Android 测试与验收规格

配套：[总计划](muyon-android-refactor-20261020.md) · [任务卡](muyon-android-refactor-tasks-20261020.md)。以下均为待执行规格，不是本轮测试结果。

## 证据等级与入口

1. 合同/单元：规则、状态、投影与有界输入；不能证明真实Android或业务持久化。
2. SQLite/文件/进程：独立物理核对和真实进程终止；不能证明Android生命周期或真实provider。
3. API26：真实APK、Service、生成绑定、Rust与私有存储；不能由JVM录制port、API36或纯ABI构建替代。
4. 真实provider：有效调用授权及预算内，通过实际产品入口产生模型/搜索证据；fixture、本地fake、HTTP200均不能替代。

每项记录 source/build id、命令、exit code、实际测试数、通过/失败/skip、设备/API、输入语料digest、日志/产物hash。`NOT_RUN/BLOCKED/FAIL`必须显式保留；缺结果不算零失败。原始敏感输入、密钥、provider响应头/正文不进Git。

## 合同与领域

| ID | 场景 | 必须断言 |
| --- | --- | --- |
| CT01 | Supplier八字段与Unicode差分 | name必填/200 codepoints，别名/分类/备注限额和rating枚举，控制字符→trim/NFC顺序，Kotlin/Rust同fixture同语义；超大revision不经浮点转换 |
| CT02 | 论文/来源/blob契约 | 手填title规则不误用于JSONL导入；source id/rev与本地ID分离；未知字段策略明确；项目scope/digest/大小完整绑定 |
| CT03 | 权限与状态 | stale lease/撤权/改scope/改params/改revision拒绝；UI或模型不能造capability；取消、unknown、notFound、committed区分；lookup无派发 |
| CT04 | 同源绑定与版本 | 真实UniFFI生成文件一致；协议/业务/DB版本各自检查；未知安全字段或不兼容主版本不继续执行 |
| SU01 | 新增与完整修改 | 八字段往返、稳定ID、同名区分、重启一致；非法输入零业务副作用 |
| SU02 | 竞争/重放 | 双击相同intent一次效果；异参intent冲突；并发同revision至多一提交；查原回执不按当前数据重造 |
| SU03 | 删除/恢复 | deleted普通列表隐藏但旧引用可投影；新引用拒绝；restore新revision/新回执；删改竞争与重启语义明确 |
| RE01 | 项目/文库/读取 | 空库新建项目；导入/手填论文同文库可见；跨项目拒绝；附件读取按scope授权 |
| RE02 | 快照语义 | 目录/ZIP同内容等价；重复id+rev保留并提示；已引用同修订改内容拒绝；refresh消失未引用记录按合同处理 |
| RE03 | PDF手填 | 必填校验、可选元数据、取消无提交、重复原intent不增加论文；同名附件不覆盖；不自动联网 |
| RE04 | 新数据的业务读取 | 新供应商和论文可被当前scope的受控只读工具看到；撤权/删除/跨项目不外发；不要求PDF自动全文提取或新检索引擎 |

## 真实存储与故障

| ID | 故障/负例 | 独立核对 |
| --- | --- | --- |
| DB01 | 新库初始化/缺库/错版本/锁/磁盘满 | 仅显式初始化可建库；读不迁移/清库；锁错误与其他错误不混同；失败无错误成功回执 |
| DB02 | 事务各窗口 | SQL修改后、history后、intent终态后、receipt后、COMMIT前故障均不留半状态；commit后丢回包保留完整结果且可查原回执 |
| DB03 | 真进程竞争/重开 | 不同OS进程同intent与CAS竞争；SQLite独立连接观察业务/意图/history/receipt计数与绑定；真实SIGKILL不冒充异常抛出 |
| DB04 | 准入/业务权限与跨库 | barrier控制业务授权复验后/COMMIT前与撤权、取消的两种先后；业务grant/generation同库事务排序，撤权先COMMIT则无新提交，业务先COMMIT则保留事实；无跨FFI重入/双库写锁死锁；业务已commit但admission未结算时查原回执、零重发；新epoch拒绝旧写grant |
| FS01 | 不可信目录/ZIP | 穿越、绝对/盘符路径、NUL、symlink、规范化重名、声明/实际大小、30MiB单文件/150MiB总包/10000文件边界、坏ZIP/JSONL；全部保留原库且无可见半项目 |
| FS02 | blob/DB各窗口 | 复制中、校验后、blob固化后、DB发布前后、回包前终止；已发布引用均可读且digest正确；重复原intent无第二记录 |
| FS03 | 文件来源与清理 | 源URI撤权/源文件删除仍可读私有副本；barrier并发固化未发布+GC、发布释放pin+GC、已持reader+GC；pin持久化前后/重启窗口均不删除有效引用，pending/unknown pin不超时清理；deleting禁止新租约/发布；重用blob核digest/长度，损坏/缺文件明确错误 |
| AR01 | ZIP元数据/平台端口 | 自家导出round-trip；中文名/无descriptor/有descriptor；UNIX symlink/特殊类型、CEN-LOC冲突、重叠/重复/越界offset、截断、ZIP64/加密/多卷/未知组合；不能用ZipEntry类型默认值伪造验证，原始封存archive与清单/实际CRC/长度绑定；API26平台流同一输入可重复读取且有界 |
| RC01 | I04旧script→HTTP重开 | 按原合同和候选执行，不推断、不重发；记录原始状态、身份和实际进程/传输证据；平台拒绝时BLOCKED |
| RC02 | 业务/导入重启恢复 | 查询原intent/receipt；pending unknown不自动重试；取消窗口与commit后结果一致；无UI success flag制造已保存状态 |

关键逆向验证仅针对事务、CAS、幂等、绑定、unknown不重发、导入路径和预算检查：变异必须可编译/启动，失败落在目标行为断言；恢复源码hash后重跑。不能用编译失败充当RED。

## API26 用户链路

| ID | 真实操作 | 通过条件 |
| --- | --- | --- |
| AN01 | 安装启动/Service连接、断开和重连 | ABI、APK内.so、runtime build id匹配固定source；privateService正常；主线程不被业务IO阻塞；close/drain后无陈旧回调 |
| AN02 | 设置→普通发送→搜索Service | 原PR99两用例均真实执行；失败重现与修复证据成对；超时定位实际阶段；IME/生命周期不靠盲sleep规避 |
| AN03 | 供应商新增→详情→完整修改→软删→撤销/恢复 | 真实UI→Service→Rust→SQLite，重启核ID/字段/revision/deleted与回执；旧引用可读，新引用拒绝；无fake port |
| AN04 | 选择目录导入、选择ZIP导入 | 系统picker实际提供输入；论文/来源/附件在文库可见；摘要与物理数据一致；失败不发布半成品；重启可用 |
| AN05 | 独立PDF＋手填信息 | 无项目可显式新建；title+PDF保存后可找到论文并打开私有附件；原源失效仍可访问；取消不提交 |
| AN06 | 双击/旋转/返回/取消/杀进程/重连 | 无重复写；unknown只查原状态；未确认草稿与已提交分开；旧session回调不误报当前成功；当前值和历史回执分开 |
| AN07 | 聊天/业务读取/真实搜索 | 在当前scope看到刚添加供应商与论文；真实provider结果可核；无全文提取能力时不伪造读过PDF；受限字段和密钥不出界 |

模拟器API26是用户指定范围；x86_64实际运行和arm64构建证据分别报告，不将arm64交叉编译称为arm64设备运行。真机/屏幕阅读器/正式发布未要求，保留未测边界，不以此扩大当前任务。

## 真实模型与搜索

| ID | 场景 | 通过条件 |
| --- | --- | --- |
| CH01 | 既有header修复离线回归 | 原合法header/错误header/限制用例保持；不宣称已确定历史unknown的确切原因；修复后Android rebuild/lint/device另验 |
| CH02 | 普通发送与同会话连续发送 | 产品真实入口得到完整accepted answer；上下文仅当前允许历史；usage与计费有证据或明确unknown；HTTP200不等于成功 |
| CH03 | 真实搜索/空结果/受控错误 | 真实SearchHost/transport可核外部结果；搜索来源与当前配置/请求身份绑定；空结果及错误不造来源或触发自动重发 |
| CH04 | 预算/取消/恢复/外发 | 所有live调用有有效授权和累计预算；旧unknown reservations保留；取消/重启不隐式新请求；凭据只经现有可信端口，日志无密钥 |

真实请求数量及费用上限采用执行时可验证的既有授权；本计划不替用户扩额度。没有有效授权可继续全部离线/本地任务，但CH02–CH04相关实测及整体目标保持未完成。

## 结果门禁与构建身份

| ID | 门禁 | 拒绝条件 |
| --- | --- | --- |
| PK01 | 双ABI生产者/生成绑定/APK | producer缺失、失败、取消、skip；生成字节不一致；APK.so路径/ABI/digest/build id/SDK或对齐不符 |
| PK02 | API26产品variant | product运行时含synthetic provider/fixture owner兜底；默认load旧.so；包名/DB路径覆盖旧Flutter；工具链来源不明 |
| OR01 | instrumentation结果解析 | 即使adb exit0，存在FAILURES/failed test/运行数缺失/required测试未执行也使gate失败；保留PR99结果检查器经验 |
| OR02 | 最终候选聚合 | 不能拼接不同source/build/variant的结果；必需场景skip或未跑拒绝完成；I04 HOLD不由改selector规避 |

## 已存在可复用命令与未来命令

以下现存命令来自canary的 `.github/workflows/web-search-send.yml`，只在P00固定且具备工具链的相应checkout执行；并不代表本轮执行过：

```sh
cargo test --locked --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test contract --test agent_search --test service_send -- --test-threads=1
bash experiments/redesign/android-rust-bridge-lab/checks/search_send_device.sh
```

P02/P03应提供并在CI验证以下**计划入口**，这些文件/路径当前尚未建立，不得称可立即运行：

```sh
cargo test --locked --manifest-path crates/Cargo.toml --workspace
apps/muyon_android/gradlew -p apps/muyon_android :app:assembleDebug :app:lintDebug
bash tools/muyon_android/verify_api26.sh
```

具名target、工具链、环境变量和设备选择由P02固定；不得让新脚本暗中触发live或旧受限suite。真实调用用独立显式入口，离线/构建命令默认无网络模型访问。

最终证据包包含SOURCE-MAP、每项test结果和hash、APK/库身份、设备信息、原始日志位置、数据库/附件核对摘要、有效授权/预算引用（不含秘密）、任务完成表和未测边界。短期CI artifact不是唯一长期证据。
