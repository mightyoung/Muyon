# Documents → PublicUI：Kotlin兼容性测试规范交接

状态：READY_FOR_HANDOFF，未运行，不表示PublicUI已收到或完成。父任务明确Kotlin安装授权只在当前UI环境，Documents不自行扩大授权。此交接只请求统一承接测试规范/离线验证；真实引擎、ReaderFD、Shell页面及公共登记均不在范围。

## 固定输入与文件

测试规范来自Documents候选 `a815fd5ad415d52bd20e66367ff250a2c3c2d2f3`（后续本分支未改其内容）：

- `apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents/IndexCompatibilityChecks.kt`
- 同目录 `run-offline.sh`
- Rust真源fixture `crates/muyon-core/tests/fixtures/public_pipeline.json`，SHA256 `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`。包含synthetic标记和model/tokenizer/dimensions/chunk字段；Kotlin按同名语义投影，不能独立维护另一组模型事实。

Contracts依赖固定于 `4d49a580cb518d9b0b80c9df3df1ff564194a639` 候选，仍非develop验收；Documents不改其types/fixtures/登记文件。

## 原阶段未满足验收

1. 尚不存在生产 `product/services/documents/IndexCompatibility.kt`。计划新增VectorDescriptor、LegacyIndexEntry及两个纯检查函数，未实施，不能称Kotlin端口完成。
2. Documents runner实际退出2（无kotlinc），尚未进入编译；既无结构RED，也无行为RED/GREEN。测试规范未经Kotlin编译验证，语法/fixture读法问题仍可能存在。
3. 需验证相同descriptor兼容、model/tokenizer/dimensions/chunk任一变化拒绝，尤其768与其他维数不兼容；旧paper-only/缺documentId/resultId/model记录必须false。字段齐全也不能自动证明宿主解析/授权成功；true分支的可信host边界尚未固定，不可补猜ID或把形状校验当授权。
4. 当前只有纯校验签名，没有可注入引擎或查询执行端口，不能用一个从未接入的fake计数器宣称engine invocation=0。无查询时零OCR/embedding/build请求的运行验证需真实可测试边界；静态无引擎依赖与动态请求计数应分别报告，禁止启动真实模型来补证据。
5. Android/设备/真实index/production dispatch、来源打开时的当前scope/grant校验仍未验；纯JVM通过不能替代这些门槛。

## 承接步骤（仅已授权范围）

在PublicUI原已选隔离工作区消费固定测试规范及fixture，先复核当前develop和文件owner，不覆盖原Shell工作。使用UI环境已有且获准的KOTLINC路径：

```sh
KOTLINC=<UI现有获准编译器路径> bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents/run-offline.sh
```

先观察缺生产文件/符号的结构RED；随后若父任务明确生产文件owner承接，在最小unavailable/false桩编译通过后取得真实行为RED，再实现纯兼容校验。若仅承接测试验证，报告精确结构阻断，不自行扩实现所有权。LegacyIndexEntry完整记录的成功/host解析语义须与Documents/父任务明确，不增加wire自批字段。

分别回报完整候选SHA、编译器版本/来源、fixture摘要、原始结构/行为RED及GREEN命令/退出码、断言范围、独审与未验项；原始日志仓库外保留SHA256。测试only/合成结果必须明确标记，不安装本环境工具、不运行真实OCR/embedding、不接FD或连接外部服务。
