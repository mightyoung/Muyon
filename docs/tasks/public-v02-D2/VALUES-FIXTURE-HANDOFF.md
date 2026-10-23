# D2 离线值向量：Documents → Contracts / PublicUI

状态：固定输入候选，Rust focused已通过；Kotlin行为验证由PublicUI执行，本环境未运行JVM。本片不冻结可信解析，不实现Kotlin，不改变Reader/FD或模型gate。整体分工已由父任务明确：Documents单写Rust/共享fixture；PublicUI单写Kotlin生产文件、测试、runner；Contracts核共同语义，不互改文件。

## 固定输入

- 唯一事实JSON：`crates/muyon-core/tests/fixtures/public_pipeline.json`，revision=2，SHA256 `4f7fcb8f988ee390b6f8fffa39603e6b92f8d1e7ccb13667c414906a247d3cf5`。
- 可直接消费的派生TSV：同目录 `public_pipeline.values.tsv`，SHA256 `547e83849749b77397e460876da78ae1d881e4a58ae6c60151d1a99cc321412c`。Rust测试逐字核其完整投影，不能作为第二事实源单独修改。无需PublicUI安装Python或JSON库来消费该文件。
- 81个描述符比较向量、28个引用候选值向量；完整25个Rust White_Space码点，包含PublicUI诊断的34个单字符输入。已读取PublicUI固定材料 `b83ffac4606799c9c31989b420e7be02d00e61ed`。
- Rust参考提取到 `services/pipeline.rs::validate_vector_compatibility`，既有validate_search复用。仅非零u32维数、Rust trim-empty和四字段原值精确比较；不装模型、不查记录、不授权。
- DocumentId/ResultId向量分别调用现有DocumentRef::new、C1 ResultId::parse核对；true只表示值形状条件，不表示可信可解析。共享标记 `candidate_semantics=shape_only_not_trusted_resolution`、`kotlin_api_frozen=false`、`trusted_resolution_implemented=false`。

当前root Rust固定1.93.1。U+0085是Rust空白，U+001C..001F不是；U+0000/180E/200B/2060/FEFF也不是。此处是版本字段的既有trim-empty规则，不能套到ID，也不能“改善”为额外控制字符政策。相同非空控制字符版本按现有guard可兼容，不表示模型存在；版本字符串不trim、不改大小写、不作兼容别名。Rust实际运行核对，不把PublicUI的源码推导当本环境执行。

## TSV精确测试数据格式（非生产wire codec）

UTF-8文本，以真正TAB分列、LF结束。顺序为H、B、全部W、全部D、全部C。消费者必须核major/schema/revision、synthetic/未冻结/未解析标记、必填列数、唯一caseId和各类行数；不能只读旧base样本或缺字段默认0。数字是规范十进制，布尔只允许true/false。数据字符串均为原样UTF-8小写hex，不trim/normalize；必须严格解码，不能替换损坏字节。nullable字符串的`-`表示null，空列表示空串，实际连字符是hex `2d`，三者不可混淆。

| tag | 列（含tag） |
| --- | --- |
| H（12列） | H、muyon.public-pipeline-values、contract_major=1、schema_major=1、revision=2、synthetic=true、kotlin_api_frozen=false、trusted_resolution_implemented=false、shape_only_not_trusted_resolution、D数量81、C数量28、W数量25 |
| B（5列） | B、base model hex、tokenizer hex、dimensions、chunk hex |
| W（2列） | W、Rust White_Space Unicode scalar十进制码点 |
| D（12列） | D、caseId、index model hex/tokenizer hex/dimensions/chunk hex、query同四列、expected_rust_compatible、jvm_dimensions_supported |
| C（14列） | C、caseId、documentId hex或null、resultId hex或null、model四列或全部null、expected_document_id_valid、expected_result_id_valid、expected_descriptor_valid_rust、jvm_dimensions_supported、expected_rust_shape_candidate、expected_jvm_shape_candidate |

`jvm_dimensions_supported`表示正值域1..Int.MAX_VALUE。维数0仍可构造typed Int输入，必须运行反例确认不兼容，不能借false标记跳过。2147483648/4294967295是合法Rust u32；对JVM不能截断/转负后伪测typed函数，应显式报告超出Int投影域。本片不提供生产codec，也不把域检查称为codec通过。负数不在Rust u32域，PublicUI可在其原生Int测试中补-1/Int.MIN_VALUE拒绝，不新增第二模型事实。JVM单独surrogate不在Rust String域，typed候选规则/生产codec仍待共同明确，不在本fixture偷偷选成功语义。

## 可执行参考及交接条件

```sh
source /workspace/documents-v02-tools/env.sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_pipeline_values --test public_pipeline
python3 crates/muyon-core/tests/support/export_pipeline_values.py
```

第二命令只向stdout导出测试数据；Rust独立核验已提交TSV与JSON一致。不生成生产代码或建立IDL选型。

新纯值函数结构RED为符号缺失；可编译unavailable桩后2 failed/2 passed行为RED，实施后4项GREEN。增加空派生表反例为4 passed/1 failed，生成完整表后5项GREEN，既有pipeline5项通过。完整回归、独审、固定源码SHA见后续报告，不将focused通过当JVM/生产验收。

PublicUI应消费固定JSON或该严格派生表；保留原缺字段反例，加入正向兼容/候选true和完整边界向量，先真实行为RED再GREEN。纯形状名称不能继续使用含可信解析成功含义的旧isPubliclyResolvable；具体Kotlin名字/实现只由PublicUI/父任务按纯值边界承接。本片不提供该旧名恒false壳，不实现可信解析、当前scope/grant、记录存在、实际向量归一化或来源打开。
