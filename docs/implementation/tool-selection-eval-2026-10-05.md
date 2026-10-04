# 工具选择评测 2026-10-05

数字来自 `apps/muyon/lib/assistant/selection_eval/selection_eval.dart` 这一次对离线规则的运行。生产策略没有被切换。概率不是授权：低于 1.0 的 choice 弃权，并且即使命中也只是候选，仍要走宿主审批。

重跑并写回本文件。普通 `flutter test` 不带 `MUYON_WRITE_EVAL_REPORT=1`，因此不会改这个文件：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  NO_PROXY=localhost,127.0.0.1,::1 \
  MUYON_WRITE_EVAL_REPORT=1 \
  flutter test --no-pub --timeout 120s apps/muyon/test/selection_eval_test.dart
```

| 策略 | top-1 | top-3 | 误选写入/外发 | 弃权质量 | 延迟 ms | 费用 |
|---|---:|---:|---:|---:|---:|---:|
| registered-rule-model-v1（离线精确匹配工具 id，否则弃权） | 8/11 | 8/11 | 0 | 4/4 | 0.741 | 0 |
| LLM | not measured | | | | | |
| Laya | not measured | | | | | |
| Jev | not measured — evidence review only, no API call | | | | | |

离线规则只在提示词去掉空白后等于某个已注册工具 id 时给出候选。自然语言、含糊请求和让助手自行批准或改选写入工具的对抗提示都会弃权。这是当前基线，不是上线选择。

Laya：not measured. This run did not install Laya, download a checkpoint, or call a local service. The project README (not a measurement here) says the English checkpoint's noul head has label bias and that score is the weakest head; tool selection would use choice over tool ids plus "none", with abstention below min_confidence. Python is not available on Android. An on-device trial would need an ONNX export through the existing flutter_onnxruntime, a tokenizer, the checkpoint size, and CPU latency on this machine. Those numbers were not collected.

Jev：not measured — evidence review only, no API call
