# 工具选择评测 2026-10-05

数字来自 `apps/muyon/lib/assistant/selection_eval/selection_set.json` 这一次对离线规则的运行。生产策略没有被切换。概率不是授权：低于 1.0 的 choice 弃权，并且即使命中也只是候选，仍要走宿主审批。

启动时 `public_tools.dart` 和 `business_tools.dart` 注册的 `ToolDescriptor.description` 仍是空字符串。评测集里的说明来自 `agent_tools.dart` 和各工具的实际用途，只放在题面和标签对照里，没有改生产注册。

重跑并写回本文件。普通 `flutter test` 不带 `MUYON_WRITE_EVAL_REPORT=1`，因此不会改这个文件：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  NO_PROXY=localhost,127.0.0.1,::1 \
  MUYON_WRITE_EVAL_REPORT=1 \
  flutter test --no-pub --timeout 120s apps/muyon/test/selection_eval_test.dart
```

| 策略 | top-1 | top-3 | 误选写入/外发 | 弃权质量 | 延迟 ms | 费用 |
|---|---:|---:|---:|---:|---:|---:|
| registered-rule-model-v1（离线精确匹配工具 id，否则弃权） | 54/140 | 54/140 | 0 | 26/26 | 3.330 | 0 |
| LLM | not measured | | | | | |
| Laya | measured. package=laya==0.3.27; checkpoint=convaiinnovations/laya-multilingual; revision=1720e3e3357cfe1e281542e223f8273b0890ca34; threads=4; threshold=0.95; calibration={"split":"sorted task id, index % 3 == 0","thresholdRule":"zero false write/external, then higher top-1, then higher threshold","sweep":[{"threshold":0.0,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.05,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.1,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.15,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.2,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.25,"top1":31,"tasks":47,"falseWrite":8,"abstained":1},{"threshold":0.3,"top1":31,"tasks":47,"falseWrite":7,"abstained":3},{"threshold":0.35,"top1":31,"tasks":47,"falseWrite":7,"abstained":3},{"threshold":0.4,"top1":31,"tasks":47,"falseWrite":6,"abstained":5},{"threshold":0.45,"top1":30,"tasks":47,"falseWrite":5,"abstained":9},{"threshold":0.5,"top1":29,"tasks":47,"falseWrite":5,"abstained":11},{"threshold":0.55,"top1":30,"tasks":47,"falseWrite":3,"abstained":13},{"threshold":0.6,"top1":28,"tasks":47,"falseWrite":3,"abstained":15},{"threshold":0.65,"top1":29,"tasks":47,"falseWrite":2,"abstained":18},{"threshold":0.7,"top1":28,"tasks":47,"falseWrite":2,"abstained":20},{"threshold":0.75,"top1":27,"tasks":47,"falseWrite":2,"abstained":21},{"threshold":0.8,"top1":27,"tasks":47,"falseWrite":1,"abstained":24},{"threshold":0.85,"top1":24,"tasks":47,"falseWrite":1,"abstained":27},{"threshold":0.9,"top1":21,"tasks":47,"falseWrite":1,"abstained":30},{"threshold":0.95,"top1":20,"tasks":47,"falseWrite":0,"abstained":34},{"threshold":1.0,"top1":12,"tasks":47,"falseWrite":0,"abstained":43}],"tasks":47,"top1":20,"falseWrite":0,"abstained":34,"p50Ms":423.543,"p95Ms":669.015,"byCategory":{"adversarial":{"tasks":4,"top1":4,"falseWrite":0,"abstained":4,"shouldAbstain":4},"ambiguous":{"tasks":2,"top1":2,"falseWrite":0,"abstained":2,"shouldAbstain":2},"chinese":{"tasks":10,"top1":2,"falseWrite":0,"abstained":7,"shouldAbstain":0},"exact":{"tasks":9,"top1":5,"falseWrite":0,"abstained":4,"shouldAbstain":0},"misleading":{"tasks":3,"top1":2,"falseWrite":0,"abstained":3,"shouldAbstain":2},"mixed":{"tasks":10,"top1":4,"falseWrite":0,"abstained":6,"shouldAbstain":0},"paraphrase":{"tasks":9,"top1":1,"falseWrite":0,"abstained":8,"shouldAbstain":0}},"calibration":{"abstain":{"tasks":34,"correct":8},"[0,0.5)":{"tasks":0,"correct":0},"[0.5,0.9)":{"tasks":0,"correct":0},"[0.9,1)":{"tasks":9,"correct":8},"1.0":{"tasks":4,"correct":4}}}; heldOut={"tasks":93,"top1":46,"falseWrite":0,"abstained":64,"p50Ms":439.113,"p95Ms":817.457,"byCategory":{"adversarial":{"tasks":6,"top1":6,"falseWrite":0,"abstained":6,"shouldAbstain":6},"ambiguous":{"tasks":6,"top1":6,"falseWrite":0,"abstained":6,"shouldAbstain":6},"chinese":{"tasks":18,"top1":5,"falseWrite":0,"abstained":13,"shouldAbstain":0},"exact":{"tasks":19,"top1":16,"falseWrite":0,"abstained":3,"shouldAbstain":0},"misleading":{"tasks":7,"top1":6,"falseWrite":0,"abstained":7,"shouldAbstain":6},"mixed":{"tasks":18,"top1":6,"falseWrite":0,"abstained":12,"shouldAbstain":0},"paraphrase":{"tasks":19,"top1":1,"falseWrite":0,"abstained":17,"shouldAbstain":0}},"calibration":{"abstain":{"tasks":64,"correct":18},"[0,0.5)":{"tasks":0,"correct":0},"[0.5,0.9)":{"tasks":0,"correct":0},"[0.9,1)":{"tasks":17,"correct":16},"1.0":{"tasks":12,"correct":12}}}; notes={"labelBias":"held-out non-abstaining choices, top labels [('research.objects', 4), ('inquiry.match_item', 3), ('inquiry.project_budget', 2), ('inquiry.quote_options', 2), ('inquiry.search', 2), ('embedding.build', 1), ('inquiry.compare_quotes', 1), ('inquiry.data_quality', 1)]. Keys are the tool ids rendered verbatim.","chinese":"held-out chinese top1 5/18","mixed":"held-out mixed top1 6/18","adversarial":"held-out adversarial abstained 6/6 falseWrite 0","shortlist":"no embedding shortlist; all 29 labels were in one choice. option-collapse reports 0/140; state truncated 0/140.","readme":"This run did not call noul or score. README, not this measurement, says English noul can follow false/true labels and that score is the weakest head. README also says laya-multilingual ships without fitted temperatures, so answer_confidence is max(p) and is not a calibrated probability."}; onnx={"exported":false,"reason":"not exported. The laya==0.3.27 wheel includes ONNXAgent but not scripts/export_onnx.py. onnx, onnxruntime, and onnxscript are not installed. After the checkpoint was on disk, /System/Volumes/Data had about 1.6 GiB free, which is not enough headroom to install the ONNX extra and write a second model-sized file. flutter_onnxruntime 1.8.5 is already a direct app dependency and was not given a model to run.","runtime":"flutter_onnxruntime 1.8.5","sizeBytes":null,"tokenizer":"checkpoint tokenizer/tokenizer.json","cpuP50Ms":null} | | | | | |
| Jev | not measured — evidence review only, no API call | | | | | |

## 分类

| 类别 | 题数 | top-1 | 误选写入/外发 | 应弃权 | 实际弃权 |
|---|---:|---:|---:|---:|---:|
| exact | 28 | 28/28 | 0 | 0 | 0 |
| chinese | 28 | 0/28 | 0 | 0 | 0 |
| mixed | 28 | 0/28 | 0 | 0 | 0 |
| paraphrase | 28 | 0/28 | 0 | 0 | 0 |
| ambiguous | 8 | 8/8 | 0 | 8 | 8 |
| misleading | 10 | 8/10 | 0 | 8 | 8 |
| adversarial | 10 | 10/10 | 0 | 10 | 10 |

## 校准

离线规则只有弃权（置信度 0，计入 abstain）和精确工具 id（置信度 1.0）。中间桶在这次规则运行里应为空。弃权桶里“判断正确”只计预期就是 none 的题。

| 置信度 | 题数 | 其中判断正确 |
|---|---:|---:|
| abstain | 112 | 26 |
| [0,0.5) | 0 | 0 |
| [0.5,0.9) | 0 | 0 |
| [0.9,1) | 0 | 0 |
| 1.0 | 28 | 28 |

离线规则只在提示词去掉空白后等于某个已注册工具 id 时给出候选。自然语言、含糊请求和让助手自行批准或改选写入工具的对抗提示都会弃权。这是当前基线，不是上线选择。

Laya：measured. package=laya==0.3.27; checkpoint=convaiinnovations/laya-multilingual; revision=1720e3e3357cfe1e281542e223f8273b0890ca34; threads=4; threshold=0.95; calibration={"split":"sorted task id, index % 3 == 0","thresholdRule":"zero false write/external, then higher top-1, then higher threshold","sweep":[{"threshold":0.0,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.05,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.1,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.15,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.2,"top1":32,"tasks":47,"falseWrite":8,"abstained":0},{"threshold":0.25,"top1":31,"tasks":47,"falseWrite":8,"abstained":1},{"threshold":0.3,"top1":31,"tasks":47,"falseWrite":7,"abstained":3},{"threshold":0.35,"top1":31,"tasks":47,"falseWrite":7,"abstained":3},{"threshold":0.4,"top1":31,"tasks":47,"falseWrite":6,"abstained":5},{"threshold":0.45,"top1":30,"tasks":47,"falseWrite":5,"abstained":9},{"threshold":0.5,"top1":29,"tasks":47,"falseWrite":5,"abstained":11},{"threshold":0.55,"top1":30,"tasks":47,"falseWrite":3,"abstained":13},{"threshold":0.6,"top1":28,"tasks":47,"falseWrite":3,"abstained":15},{"threshold":0.65,"top1":29,"tasks":47,"falseWrite":2,"abstained":18},{"threshold":0.7,"top1":28,"tasks":47,"falseWrite":2,"abstained":20},{"threshold":0.75,"top1":27,"tasks":47,"falseWrite":2,"abstained":21},{"threshold":0.8,"top1":27,"tasks":47,"falseWrite":1,"abstained":24},{"threshold":0.85,"top1":24,"tasks":47,"falseWrite":1,"abstained":27},{"threshold":0.9,"top1":21,"tasks":47,"falseWrite":1,"abstained":30},{"threshold":0.95,"top1":20,"tasks":47,"falseWrite":0,"abstained":34},{"threshold":1.0,"top1":12,"tasks":47,"falseWrite":0,"abstained":43}],"tasks":47,"top1":20,"falseWrite":0,"abstained":34,"p50Ms":423.543,"p95Ms":669.015,"byCategory":{"adversarial":{"tasks":4,"top1":4,"falseWrite":0,"abstained":4,"shouldAbstain":4},"ambiguous":{"tasks":2,"top1":2,"falseWrite":0,"abstained":2,"shouldAbstain":2},"chinese":{"tasks":10,"top1":2,"falseWrite":0,"abstained":7,"shouldAbstain":0},"exact":{"tasks":9,"top1":5,"falseWrite":0,"abstained":4,"shouldAbstain":0},"misleading":{"tasks":3,"top1":2,"falseWrite":0,"abstained":3,"shouldAbstain":2},"mixed":{"tasks":10,"top1":4,"falseWrite":0,"abstained":6,"shouldAbstain":0},"paraphrase":{"tasks":9,"top1":1,"falseWrite":0,"abstained":8,"shouldAbstain":0}},"calibration":{"abstain":{"tasks":34,"correct":8},"[0,0.5)":{"tasks":0,"correct":0},"[0.5,0.9)":{"tasks":0,"correct":0},"[0.9,1)":{"tasks":9,"correct":8},"1.0":{"tasks":4,"correct":4}}}; heldOut={"tasks":93,"top1":46,"falseWrite":0,"abstained":64,"p50Ms":439.113,"p95Ms":817.457,"byCategory":{"adversarial":{"tasks":6,"top1":6,"falseWrite":0,"abstained":6,"shouldAbstain":6},"ambiguous":{"tasks":6,"top1":6,"falseWrite":0,"abstained":6,"shouldAbstain":6},"chinese":{"tasks":18,"top1":5,"falseWrite":0,"abstained":13,"shouldAbstain":0},"exact":{"tasks":19,"top1":16,"falseWrite":0,"abstained":3,"shouldAbstain":0},"misleading":{"tasks":7,"top1":6,"falseWrite":0,"abstained":7,"shouldAbstain":6},"mixed":{"tasks":18,"top1":6,"falseWrite":0,"abstained":12,"shouldAbstain":0},"paraphrase":{"tasks":19,"top1":1,"falseWrite":0,"abstained":17,"shouldAbstain":0}},"calibration":{"abstain":{"tasks":64,"correct":18},"[0,0.5)":{"tasks":0,"correct":0},"[0.5,0.9)":{"tasks":0,"correct":0},"[0.9,1)":{"tasks":17,"correct":16},"1.0":{"tasks":12,"correct":12}}}; notes={"labelBias":"held-out non-abstaining choices, top labels [('research.objects', 4), ('inquiry.match_item', 3), ('inquiry.project_budget', 2), ('inquiry.quote_options', 2), ('inquiry.search', 2), ('embedding.build', 1), ('inquiry.compare_quotes', 1), ('inquiry.data_quality', 1)]. Keys are the tool ids rendered verbatim.","chinese":"held-out chinese top1 5/18","mixed":"held-out mixed top1 6/18","adversarial":"held-out adversarial abstained 6/6 falseWrite 0","shortlist":"no embedding shortlist; all 29 labels were in one choice. option-collapse reports 0/140; state truncated 0/140.","readme":"This run did not call noul or score. README, not this measurement, says English noul can follow false/true labels and that score is the weakest head. README also says laya-multilingual ships without fitted temperatures, so answer_confidence is max(p) and is not a calibrated probability."}; onnx={"exported":false,"reason":"not exported. The laya==0.3.27 wheel includes ONNXAgent but not scripts/export_onnx.py. onnx, onnxruntime, and onnxscript are not installed. After the checkpoint was on disk, /System/Volumes/Data had about 1.6 GiB free, which is not enough headroom to install the ONNX extra and write a second model-sized file. flutter_onnxruntime 1.8.5 is already a direct app dependency and was not given a model to run.","runtime":"flutter_onnxruntime 1.8.5","sizeBytes":null,"tokenizer":"checkpoint tokenizer/tokenizer.json","cpuP50Ms":null}

Jev：not measured — evidence review only, no API call

## 阶段 1b（2026-10-05）

门禁 1b 失败。Kaggle 没有开始，`.env` 没有打开。数字在仓库外 `~/.cache/muyon-eval/stage1b-metrics.json`。上一轮 `stage1-metrics.json` 仍保留。

`laya==0.3.27`，检查点 `convaiinnovations/laya-multilingual` 修订 `1720e3e3357cfe1e281542e223f8273b0890ca34`，4 线程，CPU，离线。没有嵌入短名单。选项是 17 个只读工具加 `none`，键是工具 id，值是中文说明加英文括注。`predict_batch` 批量 4，`head_max_len` 2048，`max_len` 3072。预热时 18 个选项都分得开，题目也没有被截断。

阈值只在 `scripts/laya/train_set.jsonl` 的 2240 行上拟合：先要求写入/外发误选为 0，再取更高的 top-1，再取更高的阈值。写入和联网工具不在选项里，所以每个切分上的误选都是 0，拟合结果是阈值 1.0。训练集 top-1 从阈值 0.00 的 612 升到 1.00 的 1048。`noul` 在训练集上的切分是 0.85、选择阈值 0.9，top-1 1055。留出折上两步提问是 20，只做选择是 27，因此丢掉 `noul`。

正式分数是阈值 1.0、只做选择。留出 93 题 top-1 27，写入/外发误选 0，弃权 84。对抗题 10/10、误选 0；否定集 24/24、误选 0。这 93 题里期望只读 49、期望 none 18、期望写入 12、期望联网 14。后 26 题在只读规则下不可能算对。27 分来自 18 道 none 的正确弃权，以及 9 道置信度 1.0 的精确 id。分类只供阅读：exact 9/19，chinese 0/18，mixed 0/18，paraphrase 0/19，ambiguous 6/6，misleading 6/7，adversarial 6/6。校准：abstain 84 题里 18 题正确；1.0 是 9/9；中间桶是 0。只做选择的延迟 p50 662.748 ms，p95 991.612 ms，是 93 次顺序 `system_one`，预热不计入。

把留出折的阈值从 0 扫到 1，最高是 0.50 时的 29/93。这次扫描没有用来拟合，也到不了 46。阈值 0 时，49 道期望只读的题对了 15 道。三道精确 id 没有在 1.0 命中：`exact-inquiry-describe` 选了 `inquiry.spec_classes`（0.9998），`exact-inquiry-search` 选了 `inquiry.spec_classes`（0.9794），`exact-inquiry-query` 选了 `research.objects`（0.6969）。

生产策略仍是 `registered-rule-model-v1`。`ReadOnlyLayaToolSelection`（`laya-readonly-v1`）在提问前只保留 `ToolAccessLevel.read`。模型点名写入或外发 id 时，结果里也不会出现这个 id。

## 阶段 2 改正后的可比子集（2026-10-05）

手机验证已由用户确认。D-R8c 把打分改到只读选择器能够回答的 67 道留出题：期望只读 49，期望 none 18。另外仍看对抗题和否定集。26 道期望写入或联网的留出题不再拿来和 D-R6 的 46/93 比。

阶段 1b 的逐题预测还在 `stage1b-metrics.json`。同一阈值 1.0、只做选择，滤到这 67 题是 top-1 27/67，写入/外发误选 0，弃权 58。分类：chinese 0/12，mixed 0/12，paraphrase 0/12，exact 9/12，ambiguous 6/6，adversarial 6/6，misleading 6/7。这 27 分和原先 93 题上的 27 分是同一批命中；被拿掉的 26 题当时都没答对。阈值打到 0 时，这 67 题仍是 27/67，但分类不同：chinese 2/12，mixed 3/12，paraphrase 1/12。门禁 2 用来比较的是阈值 1.0 的正式分数。

D-R6 的 `laya-metrics.json` 只有汇总，没有逐题预测。同一 67 题的基线要用原来的提问重测：29 个标签（工具 id 加中文说明，外加 none），阈值固定为已经公布的 0.95，不重新拟合。重测先核对留出 93 题是否仍是 46/93、误选 0。对上之后，67 题的数字才和 D-R6 可比。没对上就单独写明，不把它当成基线。

67 题的标签和语言格子是 `none|zh` 18、`read|zh` 25、`read|mixed` 12、`read|en` 12。语言按请求里的汉字和拉丁字母判定，不用评测类别当语言。决定阈值改在训练验证折上拟合：2240 行按 id 排序，下标能被 5 整除的 448 行留在本机，不上传。这 448 行的格子是 `none|zh` 197、`read|zh` 141、`read|mixed` 99、`none|mixed` 11。英文格子对不上（`read|en` 12），不把这份比例摊到其他语言。`none|mixed` 不在 67 题的目标里，权重为 0。上传 1792 行。微调权重回到本机之后才用这个加权验证折选阈值。140 题和否定集不参与拟合。

门禁 2 还没有结论：微调还没打完分，D-R6 的 67 题基线也还没重测。阶段 3 未开始。生产策略没有切换。

私有数据集 `amurdaddy/muyon-laya-tool-choices` 已上传 1792 行合成题。标题已被占用时改为创建新版本，版本说明是 “Synthetic tool-choice rows”。状态解析原先把 CLI 的版本警告和 `ready` 粘成一行，第一轮因此没有推内核；修正后数据集状态是 `ready`，私有内核 `amurdaddy/muyon-laya-tool-finetune` 第 1 版已推送。推送后的状态是 `KernelWorkerStatus.RUNNING`。加速器元数据是 `NvidiaTeslaT4`，笔记本要求两块 GPU，并写 `NO_HUB_PUSH`。凭证只进了子进程的 `KAGGLE_API_TOKEN`。权重还没有下载，SHA-256 还没有。
