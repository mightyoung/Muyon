# D2 Kotlin：固定离线值对拍候选

2026-10-23。仅交付纯声明值的兼容比较及必要形状筛查；不是可信宿主解析、真实向量检索或 Android 集成验收。

## 输入与所有权

- 本轮重新 fetch 的 develop 基线 `456effb553315026ccf7432889e9785426418427`（含 Contracts 和 Skill / Connector 登记）。隔离树 `/workspace/muyon-publicui-d2-kotlin`，分支 `task/publicui-d2-kotlin-20261023`，扫描未发现 AGENTS.md。未基于 main 或 Documents 未审候选开发。
- 完整读取 Documents 固定提案 `b15c7af6d17f79de0eb393fc66aacd8b142118e9`、计划/index修订 `db2964a42d3d882f3fe6285601f6b41e137c0367`，以及最终证据 `041d283445754de182c494dd3e0990faebf84864` 的 `VALUES-FIXTURE-HANDOFF.md`、`VALUES-REPORT.md`。前期独立诊断材料为 `b83ffac4606799c9c31989b420e7be02d00e61ed`，不复写其历史状态。
- 父任务经 Contracts 明确：本线唯一写 Kotlin 生产文件 / 测试 / runner；Documents 唯一写 Rust / 共享fixture / 语义对拍。本文及三个 Kotlin/runner 文件之外没有修改；没有改 services/mod.rs、core / FFI lib.rs、ResearchIndex、Reader、Shell、ChatScreen、旧卡片或PR108。
- 唯一事实来源固定于 `c95bc6a881bf721a982f907f1bd0bd37031dec40`：`crates/muyon-core/tests/fixtures/public_pipeline.json`，revision2，SHA256=`4f7fcb8f988ee390b6f8fffa39603e6b92f8d1e7ccb13667c414906a247d3cf5`。
- 消费其同目录严格派生 `public_pipeline.values.tsv`，SHA256=`547e83849749b77397e460876da78ae1d881e4a58ae6c60151d1a99cc321412c`。runner只git show本地固定对象并核两份摘要，无下载；不将数据复制进候选。本环境核固定摘要及逐条预期，JSON→TSV投影一致性依据原 owner 的独立Rust测试，未声称本环境重跑Rust636 / focused10 / Python7 / Clippy。

## 实际实现

`product/services/documents/IndexCompatibility.kt` 仅含离线声明值 VectorDescriptor、LegacyIndexEntry 和两项纯函数：

- `validateCompatibility(index,query)`：两端维数必须为正Int；三个版本按固定Rust1.93.1 White_Space规则判非空，再四字段原值精确相等。不trim后比较、不改大小写、不硬编码768、不读取模型文件或向量。空白集合不跟随JVM默认库漂移。
- `hasPublicReferenceCandidate(entry)`：DocumentId使用已有ASCII语法和128字符上限；ResultId在Unicode scalar字符串域内使用非空 / 无NUL / UTF-8≤128字节；model非null且自兼容。true只为后续解析的必要形状条件。ResultId允许空格 / 非ASCII的既有公共值域，没有误套原命令或DocumentId的ASCII限制。
- 没有旧名 `isPubliclyResolvable` 兼容壳，没有原ID猜测、第二账本、当前scope/grant读取、网络、引擎、文件读取、生产wire codec或命令入口。不以fake计数器声称engine invocation=0；静态无引擎/dispatcher依赖。

Ruling：这两个Kotlin声明是本地离线适配API，不冻结共享宿主成功谓词；共同fixture的 `kotlin_api_frozen=false` / `trusted_resolution_implemented=false` / `shape_only_not_trusted_resolution` 全部保留并由test reader严格核验。代价是这些纯函数不能替代未来宿主结果存在、scope/grant、精确revision、真实EmbeddingResult列表及来源打开的原子重验。

Ruling：共享Rust String输入域无法表示未配对UTF16；为避免JVM编码替换损坏输入后获得成功，当前入口对实际检查到的域外字符串抛本地 `IllegalArgumentException`，不将其记作共享false/成功向量，也不定义生产codec或ServiceError投影。该前置条件有单独真实RED/GREEN，未改共享fixture。代价是未来承接者须先维持输入域并明确错误投影，不能把这个exception当已冻结wire行为；跨语言域外Boolean语义仍UNFROZEN。

## 严格测试入口与覆盖

命令：`bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents/run-offline.sh`。使用已有批准Kotlin2.2.20，`-Werror -jvm-target 17`，现有Java21.0.12.1。与U1不同，本片无需org.json，无任何新依赖 / 系统修改 / SDK / Gradle安装。

test-only TSV读取器严格UTF-8解码，拒替换损坏字节；检查H所有版本 / 语义标记 / 数量、B字段、W/D/C顺序、必填列数、唯一caseId与W码点、规范u32 / Boolean / 小写hex、null哨兵与空串 / 实际连字符差异。它不是生产wire codec，也不参与宿主授权。读取器没有将缺字段默认0或把Regex漏读当成功。

| 实际固定向量 | 本轮执行范围 |
| --- | --- |
| D 81 | 79条投影为typed Int并调用真实比较，含维数0反例；2条u32>Int.MAX显式核投影拒绝，未转换成负数或虚构typed函数已跑 |
| W 25 | 全部逐条使同值版本判空失败；81条D同时覆盖全部34个诊断码点，包含NEL与001C..001F分歧 |
| C 28 | 26条执行真实组合形状判定；2条超Int模型核投影拒绝。每条还用合法其他字段独立核DocumentId / ResultId预期，避免组合短路掩盖某一ID规则 |
| 补充8组 | 原4个缺字段反例、native -1 / Int.MIN拒绝、本地UTF16域前置条件，以及5组严格投影反例（版本 / 标记、结构、数字 / Boolean / partial-null、UTF8 / hex / 换行、null / 空串 / 连字符） |

142是检查组总数，不是142条typed兼容比较，也不代表Android设备场景。所有事实预期直接来自owner固定向量；本地负Int与域前置条件单列，不另造模型事实。

## 可编译行为 RED → GREEN

同一D2 runner，原始输出在仓库外 `/tmp/publicui-d2-kotlin-evidence/`。

| 固定源码 / 阶段 | 实际终态 |
| --- | --- |
| `59b4f79178db00987b02c90e8eaa3f92bd65ae69`：完整测试 / 两个可编译false桩 | exit1，96通过/45失败；same-valid、正Int边界、有效候选及合法ID probe真实失败。不是符号不存在的结构RED |
| `a67c05fad8e74cc1bceb3171ebd94b0dc1aa0313`：另补域前置反例，仍为原桩 | exit1，96通过/46失败；新增断言明确观察到未抛前置拒绝，不把它冒作共享fixture向量 |
| `e89d11541b018b038b677ceedc212ceb3660e788`：最小实现 | exit0，142通过/0失败；D typed79 / outsideInt2，C combinedTyped26 / outsideInt2，W25 |

RED期间C组在合法ID probe失败后短路，因此RED的combinedTyped计数为0，不宣称当时26组后续断言都执行。GREEN已完整执行上述范围。

## 回归与未运行边界

- 原cards入口：`KOTLINC=/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh` → exit0，45 checks。未修改旧卡片。
- 实际阅读app Gradle依赖和默认src/test入口；新代码仅使用Kotlin/Java共有API，没有Maven JSON专有方法或额外测试依赖。这是源码核对，不是Android编译通过。
- 项目命令：`cd apps/muyon_android && bash gradlew --offline --no-daemon :app:compileDebugUnitTestKotlin :app:testDebugUnitTest` → exit2，缺已有Gradle8.13，未进入编译/测试，**NOT_RUN**。没有安装未经许可SDK / 依赖。默认src/test会参与编译；这里的main检查无JUnit注解，不能拿Gradle task完成冒充142组已执行。
- U1 `4d032fa9d293512bae6bdb4d6d8874fdd96a5e1f` 的集成由B独立处理，未合进本工作树，不以其Maven GREEN冒充Android通过。
- Android设备 / UI / 可信来源解析 / 真实模型 / OCR / 向量查询 / scope/grant / 原子发布均未运行。本片不使旧ResearchIndex条目变成ResultRef。U0仍draft，U2/U3未启动，Reader / FD / D3 gate不变。

待外部复验 action=`Android compileDebugUnitTestKotlin/testDebugUnitTest`，target=本候选app，reason=当前环境无既有Gradle8.13，outcome=未运行、非审批拒绝。B可在已有Android环境另验固定候选；未发生受拒操作、强推、删分支、合入、部署或不明写入。

## 原始证据摘要

| 日志 | SHA256 |
| --- | --- |
| behavior-red.log | `0d03d031230489e706a387196d23c8ea3518741509350e92467001cd69b0b917` |
| domain-precondition-red.log | `607fd1a7bda3a64e5b5a024f906a535773e84051b8b5a25f857546e1c4eb155e` |
| green.log | `3380f451ae3e9380c341c08829ed1489af800fbf00badbd5cc917f30ff00fab7` |
| cards.log | `7c4fdd18b1886ed9eafaf14138f7ec36a26a7758ed3d51f6b1923ee8e2fac02c` |
| project-suite.log | `b7512eb8fcf1348379f75c4f42cba6eb1689934c3e287aa6aa364de19db1ef0f` |

## 独立审查与裁定

首个 `/root/review_d2_kotlin` 因模型capacity失败，未产生审查结果，不计作独审。随后非作者 `/root/review_d2_available` 完成固定 `456effb553315026ccf7432889e9785426418427` → `e89d11541b018b038b677ceedc212ceb3660e788` 的整片审查：Critical0 / Important0 / Minor1，可交B候选，不代表自动合入或D2生产验收。实际重跑D2 exit0 /142组、cards exit0 /45 checks、固定范围diff-check通过；正式Android命令本人亦exit2缺已有Gradle8.13。独审核原RED日志和false桩，但未重跑历史RED，不将核读冒作执行。审查期间只有作者撰写本报告，产品/测试/runner字节仍为固定e89。

Final: minor (deferred): `IndexCompatibility.kt` 的 candidate 先检查ID值域，再按形状短路，model含未配对surrogate时，有效IDs会抛前置异常，而document=null / document="/" / result=""会先返回false。独立探针已确认。这是共同域外输入的诊断一致性，不会产生错误true，也不改变共享向量；后续在输入域 / codec错误处理明确时可决定是否提前检查model并补组合反例。本片保留，不以此扩展共享政策。

审查者 Declined to judge 各项裁定：

- Ruling：Android完整编译 / 设备 / 正式测试因Gradle缺失未验，现仅提交纯值候选与标准库API静态核对，交B已有环境另验——不扩大SDK安装范围——代价是本候选仍可能有本地未发现的平台集成问题，不能称Android完成。
- Ruling：Rust回归及JSON→TSV正确性采用固定owner报告 / 独审 / 输入摘要，未在本环境运行Rust——保持工具授权与单一事实owner——代价是共同投影若有未检出的错误，需要owner修fixture后两端重新对拍，当前142组不证明Rust本体。
- Ruling：可信宿主解析、授权、真实模型 / 向量、生产codec、Reader/FD仍属于原工程gate，本片没有接线或验收这些能力——不把shape true升级权限——代价是纯函数无法交付真实搜索 / 来源打开，必须保留后续owner与端到端验证。

独审无必须修问题，没有第二修复 / 重审pass；仅按明确授权正常提交push独立候选，唯一合入者仍为B。没有用独审可交候选结论替代正式Android或生产验收。
