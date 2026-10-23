# Documents D2 → PublicUI：固定 Kotlin 测试验证与剩余 gate

日期2026-10-23。状态：**STRUCTURAL_RED / IMPLEMENTATION_PENDING**，没有行为RED/GREEN，不宣称Kotlin兼容端口完成。此报告独立于U1；不沿用U1的34组或cards45作为D2通过数。

## 固定输入与隔离

- 最新develop仍为 `fd26dcdabcdac996bc2881e8141cac2b519966fc`，报告分支 `task/publicui-documents-jvm-check-20261023` 从该SHA创建，工作树 `/workspace/muyon-documents-jvm-report`。仅新增此Markdown；不把Documents待审候选误作产品实现基线。
- 待验Documents固定候选 `6e79be12fb537655454e8f28265439da02550530`，独立detached只读验证树 `/workspace/muyon-documents-jvm-review`。已经完整读取 [PUBLICUI-HANDOFF](https://github.com/mightyoung/Muyon/blob/6e79be12fb537655454e8f28265439da02550530/docs/tasks/public-v02-D2/PUBLICUI-HANDOFF.md)、D2 REPORT、两个测试文件及共享fixture；该验证树执行前后HEAD不变、工作树干净。
- 固定测试规范最初源 `a815fd5ad415d52bd20e66367ff250a2c3c2d2f3`；本次读取6e79封套中保持的原文件，没有复制/修改测试或fixture来换通过。Contracts依赖 `4d49a580cb518d9b0b80c9df3df1ff564194a639` 仍是候选，不称已合develop。

## 已获准工具与实际命令

仅使用当前UI环境已获用户明确批准并完成校验的 `/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc`，版本2.2.20；已有Java21.0.12.1；编译选项原runner的 `-Werror -jvm-target 17 -include-runtime`。org.json20250517也已在该获批工具目录，但此原测试runner不依赖它。没有下载/安装其他工具、移动环境或借用Rust安装授权。

在固定6e79验证树运行：

```sh
KOTLINC=/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
  bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents/run-offline.sh
```

实际 **exit1**。首个诊断为缺生产源文件：

```text
error: source file or directory not found: /workspace/muyon-documents-jvm-review/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/services/documents/IndexCompatibility.kt
```

随后是VectorDescriptor、validateCompatibility、LegacyIndexEntry、isPubliclyResolvable未解析。编译器实际启动，故原工具缺失exit2已解除；尚未成功编译，测试main/断言均未执行。这是结构RED，不是兼容行为失败，不填0失败或PASS。

首次命令误留在U1工作树，runner不存在而exit127；已保留单独日志initial-wrong-worktree.log。随后在正确固定验证树执行上述命令取得exit1，未把错误目录结果当D2编译证据，也未隐藏重跑。

## 可消费的事实与未冻结边界

共享Rust fixture `crates/muyon-core/tests/fixtures/public_pipeline.json` 的SHA256实核为 `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`，contract/schema=1/1，synthetic=true；descriptor为synthetic-model-v1、synthetic-tokenizer-v1、768维、synthetic-chunk-v1。仅JSON/摘要元数据校验，不是实际embedding或引擎兼容性验收，不另维护模型事实。

原测试表达相同descriptor应true，model/tokenizer/dimensions/chunk任一变化应false，以及4种缺失旧条目字段应false。没有完整旧条目true分支；仅返回false的isPubliclyResolvable可通过其全部反例，不能以这些检查宣布已建立可信公共来源解析。

原runner无引擎/查询执行端口，本片不能测真实engine invocation=0；静态纯检查与动态请求计数分别记。没有真实OCR、embedding、index build、模型调用或Reader/FD操作。

交接明确要求：**“随后若父任务明确生产文件owner承接”**才在最小桩后取得行为RED并实施。原始PublicUI文件范围只有ui/publicservices及计划指定测试/文档；目前收到的是验证材料承接，未明确把 `product/services/documents/IndexCompatibility.kt` 的生产写入所有权交本线。同时LegacyIndexEntry完整记录的成功/可信host解析语义在交接中明确未冻结。本片停止在精确结构验证，不新建该生产类型、不抢占Documents文件、不假设字段齐全就获授权。

继续所需的两个具体决定（不是再次申请工具安装）：

1. 父任务/原Documents owner明确生产文件由谁实现、固定哪个接口与fixture；本线可按明确交接做纯JVM适配，不改Contracts独占登记。
2. 明确 `isPubliclyResolvable` 是仅结构候选检查还是含可信host解析的判定；后者需可信解析输入，不能自行增加wire approved/resolved字段或只看三个非空值就返回true。真实授权/来源打开依旧后置。

现有测试还未在完整生产签名下编译，不能保证不存在后续语法/fixture读法问题。当前Regex字段提取适用于此固定简单fixture，但未检synthetic/major或重复键；未来适配如需更广wire读取，应消费同一真源并明确其解析边界，不能把本次元数据读取当严格codec验收。

## 仓库外证据

原始日志在 `/tmp/publicui-documents-jvm-evidence/`，不入库。

| 输入/日志 | SHA256 |
| --- | --- |
| 原IndexCompatibilityChecks.kt | `1af37ba7665b990a661983fbf787291a65e49312d19bb3f1c622695fdca33ac9` |
| 原run-offline.sh | `eab2395d8b4b8cc29f7d0b9ed35afa21ac026a38ce8a889154172d4f8fff5fbc` |
| public_pipeline.json | `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2` |
| initial-wrong-worktree.log | `91ba356e9df7f8e74eb7011a3a8bb352ff7bbf15df79b68455c8b6e448a0e6f4` |
| structural-red.log | `c1a9d493feba2c5474884ad87b20d773839f004316d3a6dbfebc446fdc576241` |
| inputs.log | `192651863cc0ec17f0155519ac94c82455ba1d54c71bda5f235e446880a68fe8` |

独立验证/报告审查pending；报告静态核验与固定SHA随完成封套补充。未运行Rust、全项目Gradle、Android/设备、真实index/host解析/生产dispatch。U0仍draft，U2/U3与Reader原安全gate保持。

当前阻断不是审批拒绝或不明写入：精确action为编译固定D2测试；target为缺失的IndexCompatibility.kt与四个符号；reason为生产接口/文件未交付且owner/true语义未冻结；outcome=编译exit1、没有测试执行。仅正常push独立报告候选，无合入、强推、删分支或部署。
