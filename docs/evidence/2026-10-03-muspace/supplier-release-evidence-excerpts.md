# T12 发布验收矩阵

更新：2026-09-24。基线：[批准设计](../superpowers/specs/2026-09-16-supplier-inquiry-design.md)、[RALPLAN PRD](../../.omx/plans/prd-supplier-ralplan.md)、[A01–A18 验收规格](../../.omx/plans/test-spec-supplier-ralplan.md)。

**结论：当前为开发候选，正式发布未放行。** Android/Windows 验证按用户明确要求延期，不执行、不算失败、也不算通过。其他缺口继续保留。


以下为原表独立行的逐字摘录（其原链接仍指向来源仓，不是本附件已复制的证据）：

| 核心完整测试 | PASS，534/534 | [本轮日志](../../artifacts/development/core-tests-20260927.log)、[静态分析](../../artifacts/development/core-analyze-20260927.log)；包括图批处理、关系分页、投影与既有核心回归。 |

| 应用完整测试 | PASS，116/116 | [本轮日志](../../artifacts/development/app-tests-20260927.log)、[静态分析](../../artifacts/development/app-analyze-20260927.log)；不能代替 integration_test 目录下的设备集成测试。 |

| A15 | 10 万报价/50 万修订全链路：**PARTIAL** | [性能报告](performance.md)、[10 万查询及 oracle PASS](../../artifacts/benchmark/query-100000-20260923/oracle.json)、[当前版正式导入及 oracle PASS](../../artifacts/benchmark/formal-import-100k-projection-reuse-uncapped-20260924/oracle.json)、[当前版分进程全链路报告](../../artifacts/benchmark/full-chain-100k-projection-reuse-resumed-20260927/report.json)与[独立 oracle PASS](../../artifacts/benchmark/full-chain-100k-projection-reuse-resumed-20260927/oracle.json)、[高熵 5000×2000 单卷 PASS](../../artifacts/benchmark/strings-high-entropy-5000-2000-20260927/report.json)、[50 万单实体深链中止](../../artifacts/benchmark/deep-500k-page200-20260924/STOPPED.md)、[小样本 UI 时延 PASS](../../artifacts/development/web-ui-latency-20260924-final.json) | 当前版源库、备份、恢复、123 卷导出及重开摘要一致；分进程续跑缺原导入/备份计时且导出日志有异常长间隔，不能证明连续性能。正式导入 989.7 秒超过桌面 600 秒门；高熵 5000×4000 单卷被压缩门限拒绝；50 万单实体深链、10 万报价 UI 与 Web 总内存未齐。 |

| macOS 宿主 Dart/native SQLite、Flutter 测试运行器 | PASS（限定范围） | 核心 [534/534](../../artifacts/development/core-tests-20260927.log) 与[当前整库 analyze](../../artifacts/development/core-analyze-20260927.log) 通过；应用 [116/116](../../artifacts/development/app-tests-20260927.log) 与[当前整库 analyze](../../artifacts/development/app-analyze-20260927.log) 通过；无 macOS target，不代表 macOS 安装包或设备集成验收。 |

| Android / Windows | DEFERRED | Android 默认应用支持目录已接入 `path_provider`，但用户延期的实际安装、文件交互、生命周期与持久化验证未执行，不据共享 Flutter 代码或目录测试宣称通过。 |
