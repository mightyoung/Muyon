# PublicUI U1：纯 JVM codec 与计划校验候选

基线：`fd26dcdabcdac996bc2881e8141cac2b519966fc`（首次U1实施基线；最新集成反馈修复见文末）。分支 `task/publicui-u1-preparation-20261023`，隔离工作树 `/workspace/muyon-publicui-u1`。没有AGENTS.md，未改main/develop。固定计划 `64900d4a6a46a9ef2919bcf922fb059413b1ce82`；U0具体外观仍draft，U2/U3未启动。

## 已获准的环境准备与实际结果

用户明确批准仅官方Kotlin2.2.20与org.json20250517，工作目录 `/workspace/publicui-tools/`，沿用已有Java。此前缺编译器exit127是历史工具阻断，不改记RED。

- 下载JetBrains官方 `https://github.com/JetBrains/kotlin/releases/download/v2.2.20/kotlin-compiler-2.2.20.zip`：78,709,601字节，SHA256=`81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420`，与仓库pin及官方发布元数据相符；校验后仅解压到工作目录。
- 下载Maven Central `https://repo.maven.apache.org/maven2/org/json/json/20250517/json-20250517.jar`：82,710字节，SHA256=`3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796`，与既有仓库固定记录匹配；没有新增app/Gradle依赖。
- 版本自检：`kotlinc-jvm 2.2.20 (JRE 21.0.12.1+1-1-deb13u1-Debian)`；编译使用 `-Werror -jvm-target 17`。不改系统PATH、JDK、凭据或系统包；未安装Gradle、Android SDK、Rust及其他依赖。
- 当前原cards离线runner实际45项通过。安装文件和provenance留工作目录，原始日志不入库；摘要见后表。

## 固定上游与范围

C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`；C2 `b626c18a5dff184519e59bb866e5ed37362ac84e`；C3源码 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`；证据封套 `4d49a580cb518d9b0b80c9df3df1ff564194a639`。完整读取其源码、fixture和三REPORT；它们仍是父任务授权消费的待合候选，不称已进入develop。上游619次测试/Clippy结果未在本环境复跑。

本片仅新增 `product/ui/publicservices/PresentationModels.kt`、`PublicValueCodec.kt`、`PlanValidator.kt` 与对应 `test/.../PlanValidationChecks.kt`、`run-offline.sh`。既有2份U1准备文档随实际状态更新。没有改ChatScreen、旧卡片、Foundation、Shell、数据库、services/mod.rs、core lib.rs或FFI。

- 公共值codec直接消费固定C1 `types.json`，SHA256=`af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5`。runner以git show读取本地固定对象，核摘要，无下载/新fixture拷贝；实际8 cases、6 legacy身份向量全部纳入。没有另造C1 DTO或原命令校验器；Kotlin只适配wire，原身份授权仍归Rust。
- 新U1模型为计划明定的呈现模型：十族sealed Props、String revision、opaque ref、只读ValidationContext。未知字段/组件/action、无效schema、snapshot/source不符、坏图/超限降为TextOnly。原答由AnswerRef独立保留，不在校验器重写。
- ValidatedPlan私有构造，没有unchecked factory；验证并发布同一套深复制/只读集合，调用者后续改输入不影响结果。没有HostCommandPort、反射派发、网络或UI回调执行。没有注入一个永不调用的fake来伪称测得dispatch计数；零执行边界由无命令入口及非法action拒绝共同核对。
- UIPlan wire采用计划字段名camelCase，C1 wire仍为固定snake_case；字段集合严格封闭。UIPlan decoder只解码，只有validate路径能产生ValidatedPlan。

## TDD 原始终态与固定源

命令 U1：`bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices/run-offline.sh`。

| 阶段 | 固定source / 实际结果 |
| --- | --- |
| codec结构RED | 新符号不存在，exit1；只算结构失败 |
| codec可编译不可用桩 | `877a2247b2dff28e4bc3116b00ac22ee81dc8111`；exit1，8组通过/13组失败；正向精度及fixture断言真实失败 |
| codec GREEN | `2fbc48c1db07a1d4a644cb481e8a0c331ee80f11`；exit0，21组通过/0失败 |
| UIPlan初始测试/桩 | `f9f1282c34e16adf38f6f98f16f1a5198a810d72` 中测试字符串引号错误，编译exit1；不算行为RED。曾提前写入的未验证实现已丢弃，恢复桩并修测试后再开始 |
| UIPlan真实行为RED | `6c9a766d2e46cdc2ad4da8ed4434dec84ca8975e`；可编译后exit1，22组通过/8组失败；原codec组仍绿 |
| UIPlan GREEN | `d132cbd81b9e7c240e9f137894b551771ef972ee`；exit0，30组通过/0失败 |
| cards回归 | `KOTLINC=/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh`；exit0，45 checks通过，无host/network调用 |
| 项目完整单测命令 | `cd apps/muyon_android && bash gradlew --offline --no-daemon :app:testDebugUnitTest`；exit2，wrapper提示缺现有Gradle8.13，尚未启动编译/测试。不在本次安装许可内，不下载补齐 |

计数为检查组/既有runner checks，不冒充独立设备场景或逐断言数量。最终修复源码 `2571e9df1d235d31408532415d0181017a86e9a8` 已重新验证：U1 exit0，34组通过/0失败；cards exit0，45 checks通过。

## 已有验证覆盖与限制

实际检查覆盖u64/i64边界、超过2^53精确值、旧Long溢出拒绝、旧page1→0/page<=0拒绝、UTF-8多字节、严格JSON重复键/Unicode/大小、C1安全字段/身份/coverage、UIPlan节点256/257、深度16/17、children32/33、环/悬空/重复/不可达、文本65536/65537、source精确host绑定、Props错配/表单/结果列表、只读授权与动作撤权、不可变副本及流式残缺降级。没有渲染器，不宣称实际卡片/页面/TalkBack已验证。

Ruling：原计划ValidationContext只有sources，没有prepared/receipt/coverage/SaveAck解析证明。**不猜新公共类型或把allowedActions当通用事实目录**。当前Confirmation节点、非空Receipt.receiptRef、非空Attachment.stageCoverageRefs、Draft.saveStatus非unsaved一律TextOnly并返回host_*_resolution_required。十族类型和解码存在，不等于十族可信呈现已全部启用；完整可信ref解析需原owner后续固定接口/fixture。本片保持这部分功能关闭，代价是有效对象也暂时只能回看文本。

TaskProgress的数量/阶段只完成形状及相互一致性校验；不能代替真实TaskPort/job状态。SourceBinding只验证host字典身份/版本/digest/区间及quote字节长度边界，字典没有原文正文，**不证明模型quote逐字等于原文**。真正呈现这些事实仍须宿主解析，U2不得将此candidate当已完成的事实真实性验收。UI关闭、实时撤权、原回执调度均不在U1执行范围。

Money/Quantity/phase新规范未冻结，没有擅自实施；当前C1phase原String保持，不能推派发状态。C2/C3仅阅读边界，不复制账本、不将SaveAck当业务成功、不把cancel_requested当已停止。

## 独立审查与发布状态

非作者 `/root/review_u1_implementation` 审查固定 `d132cbd81b9e7c240e9f137894b551771ef972ee`，亲自重跑U1 30/0、cards45、diff-check，并用临时探针发现2项Important/P2：共享子图扩张、C1缺字段/可空输出语义。作者按实际影响均列必修；在一次修复pass中补4组独立回归，固定RED `b5533505a18aa7c20a24f38951432f266dd47a74` 为30通过/4失败；修复源码 `2571e9df1d235d31408532415d0181017a86e9a8` 为34通过/0失败，cards45通过。没有弱化断言或改上游fixture；修复由TDD闭合，没有把初审结论冒充修复源二次独审。仅正常提交/push本独立候选，不创建PR合入/部署。B仍是唯一develop合入者。

Ruling：拒绝多父节点，把计划限制为单根呈现树；否则241个唯一节点/16层可扩成1,229,782,938,247,303,441个呈现实例。代价是未来有意共享的DAG也会降级，需另审展开预算，不让唯一节点上限掩盖实际展开量。C1 Coverage.total改为必填；ScopeRef/嵌套Scope及ServiceError省略的Option字段输出null，与现有Rust DTO语义对齐。Rust缺total结论来自固定源码的deserialize_with且无default，本环境没跑Rust探针。

待父任务转交Contracts的共享fixture增补要求（本线未改其文件、未声称已交付）：coverage-total-absent应invalid；scope-optional-omitted应补account_id/project_id=null；error-options-omitted应补original_intent_id/details_ref=null。当前本地回归已覆盖，跨语言fixture仍由Contracts owner登记。

实际剩余：缺Gradle导致全项目单测未运行；Android编译、SDK、设备、TalkBack/页面验收全部NOT_RUN；U0外观未认可，U2/U3未启动；上述可信ref/原文解析gate未解除。没有真实模型、Connector授权、付费实验、凭据配置、强推或删分支；未发生审批拒绝或不明写入。

## 仓库外原始日志摘要

原始日志在 `/tmp/publicui-u1-evidence/`，不入库。早期环境/准备证据随历史提交 `1bfc42071969591770b5899c6195e02181d5a4a3` 保留，不能当作本次产品GREEN。

| 日志 | SHA256 |
| --- | --- |
| codec-structural-red.log | `5a9d356487737980de4bf917c12b90976b24c0ce832bfa4f5c1666a02d349625` |
| codec-behavior-red.log | `8d988662272609674b3dc0af51fae0ef409bc271877164159bf9a45811ffe376` |
| codec-green.log | `36262c7023fba04dbe23962feebb2b114c0ef40d8a00e33a4a46961122251e25` |
| plan-structural-red.log | `b77a106eba174f3ec50419ecca39206615991eca42255e7fb6c60408d389c7bc` |
| plan-behavior-red.log | `f44a91f2e82f31eac17fc716851ad2635be20548d1e80effc48d786d366c73e0` |
| plan-behavior-red-fixed.log | `1dc52c37bf190375c904bee913ebae96bce2faf06263bb44569757a48ff486e7` |
| plan-green.log | `392c34a2d9c6aa2837d1b946c0774f408887a447680a8113e88a66d587488ffc` |
| cards-green.log | `7c4fdd18b1886ed9eafaf14138f7ec36a26a7758ed3d51f6b1923ee8e2fac02c` |
| kotlin-version.log | `b75ceb3f2b6570a97d4496c4d08b20ba54379b13c527c457270df8f5df43f9b9` |
| java-version.log | `bf61371a588e139353579c26bedbc9693004380fe8e053aa012cb6f7d2c43f20` |
| project-suite-blocked.log | `b7512eb8fcf1348379f75c4f42cba6eb1689934c3e287aa6aa364de19db1ef0f` |
| tool-provenance.json | `82ea094f3d263fa75ceb513bee056b81fa2af9349a93f15f0ceaa9d2a9f6162e` |

## 独审修复与最终复跑日志

| 日志 | SHA256 |
| --- | --- |
| review-fixes-red.log | `cdcb263b37c99afab4808e188953a4eb87b51cb7b5807e9e39738152e6feb2a2` |
| review-fixes-red-separated.log | `2b777f347e1ee64ce1a1acd378134571bdb4f7299497017776403deff1055b02` |
| review-fixes-green.log | `ce296a6b0e2616c630d33003e30006bd0385f850ce0f097bb7ece5b633a86418` |
| final-u1.log | `ce296a6b0e2616c630d33003e30006bd0385f850ce0f097bb7ece5b633a86418` |
| final-cards.log | `7c4fdd18b1886ed9eafaf14138f7ec36a26a7758ed3d51f6b1923ee8e2fac02c` |

独审原始输出留仓库外 `/tmp/u1-independent-publicservices.log`、`/tmp/u1-independent-cards.log`、`/tmp/u1-independent-probe.log`；前二摘要分别与初次plan-green.log、cards-green.log一致，探针摘要=`a20019b22cf70a8b80b352b2b23a0b5ec65e6a21624599de97957d63f47f5515`。这些是独立reviewer实跑，不是作者再次生成的假独审。没有待保留Minor。

## B 集成反馈修复：Android JSON API 与负零

本节取代旧候选 `fb4cedf7b4f01f58e335669dbabd0936964384f4` 的可集成性判断；旧候选不得合入。B 报告的正式测试源码 API 编译阻断属有效发现，历史离线 GREEN 仅对 Maven 运行时成立。本环境没有将 B 的编译结果冒充自己复跑。

本轮已 fetch 最新 develop `8a8b0319e12aa898d7b2c862b9213374488aefba`，完整阅读新增计划评审及事实附记；与原基线相比仅根 Rust pin/现有工程 gate 和文档变化，没有改本片/Android Gradle。为保持 B 已审查候选的可比性，本修复在原隔离分支追加提交，未自行合入/变基/强推 develop 或其他候选。新增架构建议未自动执行。

### 实际测试入口与 API

实际阅读 `apps/muyon_android/app/build.gradle.kts`、根插件固定和 `gradlew`。Kotlin/Compose 2.2.20、JVM17、compileSdk36；没有 `testImplementation(org.json)`，本片默认 `src/test` 会参与 Android 测试 Kotlin 编译。原 `JSONObject.similar` 属 Maven JSON 扩展，Android API 无此方法，因而必须从默认测试源码移除，不能加正式依赖或移动测试隐藏失败。

测试 oracle `sameJson` 仅调用 Android 已有 `JSONObject.keys/get`、`JSONArray.length/get`、`JSONObject.NULL`，递归比较对象键集合、数组顺序、类型与值，字符串不会转成数值，缺字段不同于显式 null。固定 fixture 的数字都是整数；数值比较接受 Int/Long 装箱差异，使用其十进制表示，不将 revision 转浮点。不宣称这是覆盖全部 JSON 小数等价关系的通用比较库。新增 oracle 正/反例包括键换序、数组换序/长度、嵌套值、null/缺失、String/Number、Boolean/String。正式依赖和测试目录均保持原样。

### 严格兼容分析

读取固定 Android 16 官方源码（仅下载源码文本供阅读，未编译/执行/安装）：[JSONTokener.java android-16.0.0_r1](https://android.googlesource.com/platform/libcore/+/android-16.0.0_r1/json/src/main/java/org/json/JSONTokener.java)，`readLiteral` 对无小数点文本先 `Long.parseLong`，小范围转 Int。`-0` 因此成为 Int(0)，原先解析后 `unsignedInteger` 无法恢复其负号。[Android JSONObject API](https://developer.android.com/reference/org/json/JSONObject) 确认使用的平台方法集合不包含 similar。上述是源码/API核查，并非本环境 Android 运行结果。

固定 Maven JSON 20250517 用现有批准编译器实跑探针：`-0 → Double(-0.0)`；`0 → Integer(0)`；`-0.0/-0e0 → Double(-0.0)`；`0.0/0e0 → BigDecimal`。Android 源码会把后两者交给 Double 分支。原类型守卫在这些小数/指数上均拒绝，但在 `-0` 上会因平台而分歧。边界 `2147483647 → Integer`、`4294967295 → Long`、`18446744073709551615 → BigInteger`（Maven）；Android 超 Long 可能转 Double，仍拒绝。公共数值字段只接受 schemaVersion/pageIndex/i32 范围及 failed_units/u32 范围，均在 Long 内；u64 revision、计数、偏移、i64时间始终是规范十进制**字符串**，不经过这些转换。

修复在 `JsonGrammar` 仍持有原始数字 token 时拒绝精确数值 `-0`，发生于任何 org.json 转换之前；字符串 `"-0"` 不受词法规则误伤（revision 等自己的规范校验仍会拒绝它）。合法数字 `0` 保留。该守卫只服务本片 wire，非通用 JSON 标准声明；JSON 本身允许 -0，但当前支持的数字字段是规范无符号整数。小数/指数继续在 typed integer 守卫拒绝，未把它们截断/四舍五入。负零嵌套、schemaVersion/pageIndex/failed_units、小数/指数、i32/u32 边界及 TextOnly 降级已补回归。不声称修改了上游 fixture 或已运行 Rust 对照。

### 实际 RED/GREEN 与项目门禁

同一命令：`bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices/run-offline.sh`。

| 固定源 / 阶段 | 实际结果 |
| --- | --- |
| `ef3a16dd4a99d029bc0dc466d59a32bceb5bc6ea` RED | 可编译，exit1，30通过/7失败。原始负零 transport 拒绝断言真实失败；新结构 oracle 尚未实现，导致自身及5个正向 fixture 失败。不把已有 Maven typed 拒绝负零当新增行为 RED |
| 实现后首次 GREEN | exit0，37通过/0失败；随后补齐 schema/page 字段验收边界 |
| 修复源码 `ce979ce9aab677cb1f3a44eefbfb96abef7ae905` | exit0，38通过/0失败；这38组是纯 Maven JVM检查，不是Android设备结果 |
| cards 原入口回归 | 使用原命令/同一批准 KOTLINC，exit0，45 checks通过 |
| `cd apps/muyon_android && bash gradlew --offline --no-daemon :app:compileDebugUnitTestKotlin :app:testDebugUnitTest` | exit2，NOT_RUN：缺已有 Gradle8.13，未进入 Android 编译/测试；未下载SDK/额外依赖 |

本片测试仍是 main 检查入口，无 JUnit 注解；Gradle 编译这些源码可发现 API 错误，但 `testDebugUnitTest` 本身不能当这38组已执行。需 B 在已有 Android 环境复验默认测试源码编译，并按已有可用 Android JSON 运行入口复验解析行为；本环境不伪造 Android API stub 或切换正式依赖来填 PASS。U0仍draft，U2/U3未启动，原可信ref与原文真实性限制继续适用。

### 本轮仓库外证据

日志 `/tmp/publicui-u1-evidence/`；没有新增工具/库安装，无拒绝操作/不明写入。项目 gate action=上述 Gradle命令，target=当前隔离分支Android app，reason=Gradle8.13执行文件缺失，outcome=未运行（非审批拒绝），待B现有环境复验。

| 文件 | SHA256 |
| --- | --- |
| android-compat-red.log | `84e3f1bfaa98de0fa2ab851dfcd2e8aeb7fdbe9ac7df389d0c4a8a23ac5503f9` |
| android-compat-green.log | `27c240a25890856c2187d02c79b9ed776fda3fde2f99b054645e0adec0078a8f` |
| android-compat-final.log | `cf086828a10985946f258044b4a0ca7ad2d6cf5668eac60e51dcfae70b325373` |
| android-compat-cards.log | `7c4fdd18b1886ed9eafaf14138f7ec36a26a7758ed3d51f6b1923ee8e2fac02c` |
| android-compat-gradle.log | `b7512eb8fcf1348379f75c4f42cba6eb1689934c3e287aa6aa364de19db1ef0f` |
| json-number-probe.log | `f1cf3b0ec37d4ac2fe1f5aa3dd99fc6ff92e2c21a8d1e37507cbb9610d9f0a4b` |
| Android-16-JSONTokener.java | `744c9ffb50c2472d7269c8d64a7d8331ea1a1691fb6536619ac9590e9ebbbd4b` |

### 本轮独立审查

非作者 `/root/review_u1_implementation` 对固定 `ce979ce9aab677cb1f3a44eefbfb96abef7ae905` 审查兼容修复差异、实际app依赖、Android源码和测试oracle；未发现新增 Critical/Important，允许交B作为本次修复候选，并未批准合入。亲自执行 U1 38/0、cards45、原候选/原基线到修复源两份 diff-check 均exit0。核对 RED 为1项负零真实行为失败+6项oracle桩失败，没有把桩计为产品缺陷。

独审日志 `/tmp/u1-androidcompat-independent-publicservices.log` SHA256=`cf086828a10985946f258044b4a0ca7ad2d6cf5668eac60e51dcfae70b325373`；`/tmp/u1-androidcompat-independent-cards.log` SHA256=`7c4fdd18b1886ed9eafaf14138f7ec36a26a7758ed3d51f6b1923ee8e2fac02c`。审查时仅作者更新两份报告，产品/测试字节保持固定候选。独审同样没有运行Android集成，仍待B已有环境；未安装或改工作树。
