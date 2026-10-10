# F5b H2 core export 组合记录
父任务明确要求接收 PR21 head97a2e8263a5f38b5659b4123b78fadea90eb35f9 的 H2。仅任务分支 merge 依赖，merge提交1bfd253；core实现与原10测试归PR21作者，Codex未改core逻辑。F5b owner应用ui_contract.dart单行export 'src/ui/recomputation.dart'；伴随去掉core测试临时src重复import（否则unnecessary_import阻断fatal-infos），这是集成清理，不重写原测试。

本机缓存Flutter/Dart/no-pub：现有API+typed+PR21core115PASS（明确排除尚待GREEN的collection RED文件）；仓库外core测试副本移除src import后仅public export消费10PASS。初次analyze唯一info为上述冗余import，清理后重核。此组合不声称collection38个RED或运行publish/33widget已GREEN。日志/tmp/aiui-f5b-logs；无SDK/依赖下载，无develop合并。H2已接入，F3b仍需最终组合。
