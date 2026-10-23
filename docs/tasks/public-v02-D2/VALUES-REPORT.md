# D2 离线纯值合同：Rust与共享向量交付

2026-10-23。已完成本片Rust行为、共享fixture和严格测试数据投影；未完成Kotlin行为验证或D2整体生产验收。Documents单写Rust/共享fixture，PublicUI单写Kotlin生产/测试/runner。可信解析成功谓词未冻结；Reader/FD、真实OCR/embedding/index和D3仍保持原工程gate。

## 固定候选与输入

- 原任务分支：`task/public-v02-documents-20261023`。先以正常merge `229157a9ad8e5c66f588a7f396fce5bfd2027f9e` 刷新到已评审develop `e943856e4b6e2de26a9c2c8e2fa0912713b590e5`，其已含C1–C3。没有以main或未审登记组合为基线，没有合入develop。
- 可消费源码/fixture固定提交：`c95bc6a881bf721a982f907f1bd0bd37031dec40`，已正常push。后续证据提交不修改这两份数据。
- `crates/muyon-core/tests/fixtures/public_pipeline.json` 是唯一事实，revision=2，SHA256 `4f7fcb8f988ee390b6f8fffa39603e6b92f8d1e7ccb13667c414906a247d3cf5`。
- 同目录 `public_pipeline.values.tsv` 为严格派生，SHA256 `547e83849749b77397e460876da78ae1d881e4a58ae6c60151d1a99cc321412c`。逐列格式、Int域与交接条件见 [VALUES-FIXTURE-HANDOFF.md](VALUES-FIXTURE-HANDOFF.md)。
- 已完整读取D2-JVM-CLARIFICATION提案 `b15c7af6d17f79de0eb393fc66aacd8b142118e9`、计划/index修订 `db2964a42d3d882f3fe6285601f6b41e137c0367` 与PublicUI VALUES-HANDOFF `b83ffac4606799c9c31989b420e7be02d00e61ed`。

81个D向量覆盖PublicUI诊断全部34个单字符输入；25个W记录列出Rust 1.93.1实际White_Space；28个C向量只核既有DocumentRef/ResultId值形状及descriptor条件。Rust helper保留非零u32、Rust trim-empty及四字段原值精确相等，不采用JVM默认trim，不归一化版本。相同非空控制字符版本按原guard接受，不能推断模型存在。u32大于Int.MAX不截断；0仍是必须执行的typed反例。未配对UTF-16不在Rust String域，其跨语言生产政策未作决定。

公开纯函数 `pipeline::validate_vector_compatibility` 供原validate_search复用，没有添加类型、账本、引擎入口或生产codec。`shape_only_not_trusted_resolution`、`kotlin_api_frozen=false`、`trusted_resolution_implemented=false` 均显式保留。true不代表记录存在、scope/grant有效或来源可打开；旧科研索引未成为公共来源。

## 原始RED → GREEN

统一先 `source /workspace/documents-v02-tools/env.sh`，Rust为官方已批准的1.93.1；未安装Kotlin/新依赖，锁文件不升级。

1. `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_pipeline_values`：符号缺失结构RED，退出101。测试提交 `82194347267dea9e4aeca69f7adfcaf20688363d` 含可编译unavailable桩，实际行为RED为2 failed/2 passed，退出101。一次编辑脚本未匹配锚点，桩未改变，重复运行仍2 failed/2 passed（green-attempt-stub日志），不计GREEN。实际helper完成后同命令4 passed，退出0。
2. 增加派生表完整性测试，提交 `8021b2c70c5117d39d8658f2927b0f46d42689d2` 保存空表反例；当时工作区已有helper修复，运行相同命令4 passed/1 failed，退出101，失败原因是空TSV。该提交本身仍含旧桩，不冒称其独立全绿。
3. 完整表与PublicUI码点增量固定于c95提交；`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_pipeline_values --test public_pipeline` 为新5/5、原5/5，退出0。恢复容量中断后再核远端仍为c95、数据摘要不变，同命令再跑10/10退出0，没有重做已完成实现。
4. `python3 crates/muyon-core/tests/support/test_export_pipeline_values.py`：7/7退出0。此文件在c95之后证据提交纳入，覆盖投影一致、版本/语义标记、重复键/caseId、缺失/未知字段、bool维数/越界、null/空串/NUL/多字节、u32域和不归一化。它不参与Rust构建，也不增加Cargo依赖。

Rust测试独立使用实际值parser与helper逐条核JSON，再独立重编码核TSV完整字节。Python exporter是仅测试stdout工具，不是生产wire/IDL。Rust通过不等于Kotlin通过。

## 回归、独审与剩余验收

原完整workspace日志：39个测试二进制，636 passed/0 failed/0 ignored，退出0，包含既有Office窄能力12项。严格core all-target Clippy和两份Rust文件rustfmt check通过；恢复后再次运行focused10项、Python7项、Clippy及格式/diff检查均退出0。恢复workspace结果见下方补记；未运行真实引擎、Android或任何可信解析生产流程。

独立审查者 `documents_preparation_review` 审查c95源码、数据及待提交Python测试：Important无；独立离线新Rust5/5、原pipeline5/5、Python7/7，均退出0。Minor为交接文档25/34数量措辞容易误读，已准确改为81 D覆盖34输入、25属于Rust空白、W列出25；未改变fixture或guard。

本片没有登记文件改动，沿用待Contracts owner登记要求：在 `crates/muyon-core/src/services/mod.rs` 登记 `pub mod documents;`、`pub mod sources;`、`pub mod pipeline;`。新helper属于pipeline，不增加新登记行；core/FFI lib.rs无新增需求。当前实际develop尚不含本Documents候选，测试通过include路径测试本模块，不宣称生产公共入口已接线。

PublicUI可直接消费c95固定输入并交真实Kotlin行为RED/GREEN；本环境未安装/运行JVM，此项NOT_RUN且不是权限拒绝。无受拒操作、无不确定push结果。可信解析成功语义/未配对surrogate政策待共同裁定；scope授权、结果存在、真实来源打开、生产引擎和原子发布/取消仍不属于此纯值切片。本片不替代这些gate。

## 原始日志摘要

日志在仓库外 `/workspace/documents-v02-evidence/`，以下SHA256用于复核，不提交大日志。

| 日志 | SHA256 |
| --- | --- |
| d2-values-baseline.log | `057c12eb04ae5f588bce338d27949db3851caa6eb4b9127756113bee5c1e85cd` |
| d2-values-structural-red.log | `fa2cc95cccd6e9a8e14152d6f54c731f47dfeb3784b6fefd10d75eac51a7f204` |
| d2-values-behavior-red.log | `5f3f8ee7e09a95e7bae54b0bf42b0d0441d672f5a3101b1a264bed552aa4fbb4` |
| d2-values-green-attempt-stub.log | `27447fd722eecf7c534bf70d4786d209e1689258198c19fcb6a449788aad907e` |
| d2-values-green.log | `a903e912df275d615d0349db795648e3869a6741f6ffa38859d7aeb71eec1d30` |
| d2-values-projection-red.log | `95ef9c20724cac8c9b83fc8a6c754a36bb2da287e8c6485faed5de2acb6069a4` |
| d2-values-projection-green.log | `6be1253f4f3817ce474c651034741786816297dba523ba96436bed34e6b27e45` |
| d2-values-export-tests.log | `e19a86747084065fc6026e9e5463e2291a2e56061843e8a27e0424f4fed284be` |
| d2-values-workspace.log | `c2cc3c1df82daffebb55147a02aabb991e9fd92d7497e82a2da15e7f285f430b` |
| d2-values-clippy.log | `5dbca0fadc7168f66b95d39610734755f55296129f52f677c67f8d3b89ee5fcc` |

Cargo.lock SHA256：`d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`，与本片开始一致。

恢复完整回归实际命令：`cargo test --manifest-path crates/Cargo.toml --workspace --offline --locked`，退出0，42个测试结果块（含doc-test块），636 passed/0 failed/0 ignored。`d2-values-recovery-workspace.log` SHA256 `dc2f5db5ba65056b9c2ec7a849960c5555d7b31797a05f091a058f995f6b4358`。
