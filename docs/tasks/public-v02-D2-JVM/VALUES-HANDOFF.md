# D2 Kotlin 离线值检查：PublicUI 分工准备与实测差异

日期：2026-10-23。状态：**准备切片，不是生产合同或 D2 GREEN**。父任务要求全面并行推进，PublicUI 保留纯合同 / codec 职责；B 正在复验 U1 `4d032fa9d293512bae6bdb4d6d8874fdd96a5e1f`，本片不改其候选。

## 固定输入及隔离

- 新分支 `task/publicui-d2-value-preparation-20261023`；工作树 `/workspace/muyon-publicui-d2-values`。
- 当前重新获取 develop 基线 `e943856e4b6e2de26a9c2c8e2fa0912713b590e5`（含 PR110 Contracts）；不从旧 main 或 Documents 未审候选建立产品基线。扫描未发现 AGENTS.md。
- 完整读取提案 `b15c7af6d17f79de0eb393fc66aacd8b142118e9` 的 `docs/contracts/public-services-v02/D2-JVM-CLARIFICATION.md`，文档 SHA256 `16ec27f1c3f53d7895208e3de9dcda3fac6baf0e357cff3fed030ef51d9a7033`。
- 完整读取修订计划 `db2964a42d3d882f3fe6285601f6b41e137c0367` 的 document-pipeline / public-services-index；前者文档 SHA256 `175de9bc0c8c720e9ff2facc1b9ed2569cbb95924e17a0070846b7c8ebd14310`。同时核其继承的 pipeline.rs guard 与原 JVM 测试 / runner / fixture。
- 旧 JVM 验证 `3c72963a1adcb47fe82819a70310465e3eb8aeb4` 和 Documents 交接 `6e79be12fb537655454e8f28265439da02550530` 保持历史状态：缺生产文件 / 符号，只有结构失败，未取得行为 RED/GREEN。

两份新输入仍明确：方案 A / B 未裁定、`IndexCompatibility.kt` 原 owner 为 Documents、具体交接未完成；修订计划写明本轮不补未决接口实现。父任务本轮授权可分工实施已确定值检查，没有给出该生产文件的明确转交。因此已请求明确生产文件分工，同时先完成本切片的独立诊断 / 测试矩阵。**没有把提案签名直接冻结成代码。**

Ruling：先交测试材料与实际平台差异，不创建另一套 VectorDescriptor / LegacyIndexEntry 或同名生产实现——保持单一 owner 与共同事实源——代价是当前仍没有 D2 Kotlin 行为 GREEN，需要明确分工后才能续接。

## 已实测：Kotlin 默认空白不能直接代替 Rust trim-empty

在已有批准工具 `/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc`、现有 Java 21.0.12.1 下运行本地诊断脚本，exit0，输出35个指定码点的 `isBlank` / `trim().isEmpty` 观察值；这不是35项生产断言，也不是产品测试 GREEN。未安装新工具 / 库。

Rust 1.93.1 的 [char::is_whitespace 实现](https://github.com/rust-lang/rust/blob/1.93.1/library/core/src/char/methods.rs#L869) 与 [固定 Unicode White_Space 表](https://github.com/rust-lang/rust/blob/1.93.1/library/core/src/unicode/unicode_data.rs#L706) 已只读核对。下表 Rust 结果是**固定源码推导**，本环境未运行 Rust；Kotlin 两列为实际运行结果。

| 单字符输入 | Rust trim 后为空（源码推导） | Kotlin isBlank | Kotlin trim 后为空 |
| --- | --- | --- | --- |
| U+0085 NEL | true | false | false |
| U+001C / 001D / 001E / 001F | false | true | true |
| U+0009..000D、0020 | true | true | true |
| U+00A0、1680、2000..200A、2028、2029、202F、205F、3000 | true | true | true |
| U+0000、180E、200B、2060、FEFF | false | false | false |

若方案 A 继续要求跟随既有 Rust guard，直接用 Kotlin 默认 isBlank / trim 会在 NEL 上错误接受、在 U+001C..001F 上错误拒绝。它们是版本字段的空白规则，不是 DocumentId / ResultId 规则；不能把同一规则套到所有 ID。不能顺便“改善”为另一套可见字符政策；若要拒绝额外控制字符，须由 Documents / Contracts 明确变更参考语义。

后续字段比较仍应保留原字符串：`"v"` 与 `" v "` 不相等；`"v"` 与 `"V"` 不相等。两个相同的带空格非空版本按现有 guard 仍为非空，再作精确比较；这里不新增 trim-normalize 兼容别名。

可重现诊断（仅标准库）：

```kotlin
val points = listOf(0x0000, 0x0009, 0x000A, 0x000B, 0x000C, 0x000D,
    0x001C, 0x001D, 0x001E, 0x001F, 0x0020, 0x0085, 0x00A0, 0x1680, 0x180E) +
    (0x2000..0x200B) + listOf(0x2028, 0x2029, 0x202F, 0x205F, 0x2060, 0x3000, 0xFEFF)
for (point in points) {
    val s = String(Character.toChars(point))
    println("U+%04X isBlank=%s trimEmpty=%s".format(point, s.isBlank(), s.trim().isEmpty()))
}
```

命令：`/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc -script /tmp/publicui-d2-values-evidence/blank-probe.kts`。仓库外原脚本额外打印运行环境；脚本 SHA256 `cc8ae7ee3ecb0eaf40c4de2498609bb647921735f2eca4257849f766170dbc50`，日志 SHA256 `1d2a17be4e18ade732ce745b36acf538a79733174c1fa44f0b4bf5cf8ed62357`。不提交日志或第三方源码。

## 待共同 fixture 登记的用例建议

这是向 Documents / Contracts 提供的增补清单，**不是第二份 fixture 或已冻结新规范**。唯一共同 fixture 仍为 Documents 的 `crates/muyon-core/tests/fixtures/public_pipeline.json`，旧 SHA256 `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`。PublicUI 不写此文件，不把 synthetic 768 固定成唯一维数。

| 类别 | 应补材料 | 边界 / 判断来源 |
| --- | --- | --- |
| 描述符正向 | 原 synthetic 描述符自比较；其他正 Int 维数；相同合法版本原样比较 | 纯值兼容，不证明模型 / 向量存在 |
| 单字段差异 | 模型、分词、维数、分块逐一变化；交换 index/query 再测 | 四字段精确相等 |
| 相等但非法 | 三个版本分别为空 / Rust 空白；维数0 / 负数 | 自比较也不能通过非法描述符 |
| 双向非法输入 | index非法/query合法与交换；两端同时非法 | 不能仅检查其中一侧 |
| Unicode空白 | U+0085；U+001C..001F；完整 White_Space 组；零宽字符反例；空白混合 | 先由 Rust owner 跑参考，再发固定fixture SHA；不能采用两语言默认库各自定义 |
| 原样字符串 | 前后空格但含版本、大小写、中文与emoji版本、相同非空控制字符版本 | 依原guard非空 + 精确相等，不增隐式归一化 |
| 维数边界 | 1、2147483647；0；未来wire 2147483648 / 4294967295 | Rust u32 与 JVM Int 值域不同；typed Int 接口不能伪测超Int输入，未来codec必须显式拒绝，当前无codec |
| 候选缺失 | 保留原4个缺字段 / model反例，补合法候选true | 只有方案 A 被选择才改名 hasPublicReferenceCandidate；不得保留旧授权含义名称来做形状检查 |
| DocumentId | ASCII128/129；空串、空白、NUL、路径斜杠、非ASCII；合法标点_.:- | 既有DocumentRef ASCII语法 |
| ResultId | ASCII128/129；`甲`42个+`ab`=128字节 / +`abc`=129字节；emoji32/33个=128/132字节；空串/NUL | 既有C1 UTF-8字节长度；不可用UTF-16长度，不强套ASCII |
| 字符串编码 | 单独高 / 低 surrogate、成对emoji、JSON转义与解码后字节边界 | JVM String可含非Unicode标量；Rust String不能，codec必须拒绝替换损坏输入；当前typed候选语义留共同确认 |
| fixture入口 | major / synthetic / 必填字段 / 描述符类型 / 维数lexeme | 原Regex读取器不能证明这些条件；最终解析方式由owner与承接者确定，不新增依赖或用缺字段默认值换通过 |

未来 RED 必须在最终签名和 owner 明确后，用可编译不可用桩观察真实正向断言失败，再实施。当前不创建假stub / 恒false实现，不把这份矩阵、旧符号不存在或诊断日志称作行为RED。

## 可信解析与授权边界

`hasPublicReferenceCandidate` 即便以后被选用且返回 true，也仅为“可送后续宿主解析”的形状必要条件。它不证明记录存在、scope / account / grant、精确 revision、来源可读、查询获准或生产引擎可用。

`validateCompatibility` 只比两份声明；未来可信搜索仍需原 owner 解析真实 EmbeddingResult，逐条核 descriptor、输入集合与 IndexSnapshotRef，再在搜索返回和来源打开处重验授权。不能用 legacy paper / digest 猜 ResultId；不能用 wire `resolved=true` 或 callback布尔值代替可信来源。`isPubliclyResolvable` 的宿主成功语义继续 UNFROZEN / NOT_IMPLEMENTED。

未完成项：方案 / 文件转交、共同fixture新向量、最终签名、Kotlin生产实现和行为RED/GREEN；Android / 设备 / 引擎 / Reader / FD / 真实业务全部 NOT_RUN。没有可注入引擎端口，因此不报告 engine invocation=0。U0外观未认可，U2/U3未启动。

待定 action=`实施 D2 Kotlin 生产纯函数`；target=`product/services/documents/IndexCompatibility.kt`；reason=固定计划仍要求 Documents owner 与父任务明确选择 / 交接；outcome=**待交接，未执行，非审批拒绝**。独立诊断和材料已完成；没有绕过 Reader / FD、安装SDK / 新依赖、改旧PR108、合入或部署。
