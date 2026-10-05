# Laya 专门化脚本

这里只放可再分发的合成数据和图脚本。权重、虚拟环境、Kaggle 输出放在 `~/.cache/muyon-eval/`，不进仓库。不把 Python、PyTorch 或 Laya 加进 Flutter 应用。

## 第一阶段重做：全部只读工具，一个全局阈值

- 不使用嵌入短名单。选项是每一个 `effect == read` 的工具，外加 `none`。键是工具 id，值是中文说明加英文括注。写入、导出、联网工具不进入选项；模型若仍输出它们的 id，记作 `none`。
- `head_max_len` 2048，`max_len` 3072。`predict_batch` 批量 4，`sort_by_length` 关闭。选项若被头长度压到分不清，这次测量作废，不打分。
- 全局阈值和可选的 `noul` 切分只在 `train_set.jsonl` 上拟合。140 题、对抗题、否定集只做最终打分。留出的 93 题仍是按 id 排序后下标不能被 3 整除的那些，用来和 D-R6 的 46/93 比较，不参与拟合。
- 有、无 `noul` 都记下来。只有留出 top-1 严格更高、且写入/外发误选仍为 0 时才保留 `noul`。
- `negation_set.json` 是额外评测，不并进 140 题，也不做训练数据。

```bash
python3 scripts/laya/test_stage1_contract.py
```

机器上没有 `flutter_tester`、`scripts/verify.sh` 或其他 `stage1_ask.py` 时才测量。线程封顶 4。检查点只读本地缓存。

```bash
~/.cache/muyon-eval/venv/bin/python scripts/laya/stage1_ask.py
```

结果写到 `~/.cache/muyon-eval/stage1b-metrics.json`。门禁 1b：留出折、对抗题、否定集上的写入/外发误选都是 0，并且留出 top-1 ≥ 46/93。失败则退出码 2，不开始 Kaggle。上一轮失败的 `stage1-metrics.json` 留着不覆盖。

140 题文件仍然只用于评测。本阶段不读 `.env`。期望工具是写入或联网的题，在只读选项下不可能答对；脚本会把这个数量写进 `heldOutExpected`。

## 第二阶段：Kaggle 微调

`train_set.jsonl` 是合成题，不包含 140 题，也不包含整段留出的工具。目标只有只读工具 id 和 `none`。写入或联网请求的标签是 `none`。`train_overlap.json` 记录和评测题的字符 5-gram 最大 Jaccard。

门禁 1b 不再挡住这一步。D-R8c 改为只给只读选择器能回答的 67 道留出题打分（49 道期望只读，18 道期望 none），外加对抗题和否定集。决定阈值不在这 67 题上拟合，也不再在整份训练集上拟合。按训练行 id 排序，下标能被 5 整除的行留在本机，作为验证折；上传到 Kaggle 的是其余行。验证折按「只读 / none」和请求语言（中文、中英混合、英文）重加权，使加权后的比例对齐那 67 题里训练数据能够覆盖的格子。训练集没有英文请求，67 题里的 12 道英文精确 id 记为对不上，不把它们的比例摊到别的语言上。权重为 0 的格子不参与拟合。拟合规则仍是：先要求写入/外发误选为 0，再取更高的加权 top-1，再取更高的阈值。微调权重下载到本机之后才做这次拟合。

`laya_finetune_tool_selection_kaggle.ipynb` 用多语检查点 `convaiinnovations/laya-multilingual` 的修订 `1720e3e3357cfe1e281542e223f8273b0890ca34`，`laya==0.3.27`，两块 GPU。它不推送到 Hugging Face Hub，最后写 `NO_HUB_PUSH`。

提交前检查训练标签、泄漏报告和 67 题的 49/18 划分。失败就不读 `.env`。通过之后才读 `Kaggle-apikey`，放进子进程的 `KAGGLE_API_TOKEN`，输出里的 `KGAT_` 会被抹掉。数据集和笔记本都是私有的，加速器是 `NvidiaTeslaT4`（GPU T4 ×2），并打开网络以便下载公开基座。

```bash
python3 scripts/laya/test_stage2_data.py
python3 scripts/laya/test_stage2_threshold.py
python3 scripts/laya/test_kaggle_submit.py
python3 scripts/laya/kaggle_submit.py
```
