# Laya 专门化脚本

这里只放可再分发的合成数据和图脚本。权重、虚拟环境、Kaggle 输出放在 `~/.cache/muyon-eval/`，不进仓库。不把 Python、PyTorch 或 Laya 加进 Flutter 应用。

## 第一阶段：改提问，不训练

- 选项文本是中文工具说明加一句英文括注。工具 id 只留在 `opt00` 这种不透明键上，不出现在模型读到的文字里。
- `head_max_len` 2048，`max_len` 3072。`predict_shortlist` 用已加载检查点编码器的均值池化做嵌入，`k=16`。没有第二个嵌入模型。若短名单丢掉「没有合适工具」，会把它补回再问一次。
- 先问一句「这是不是在请求某个已注册工具」（`noul`，显示文字不是 bare false/true），再在短名单上做选择。阈值只在 140 题的校准折（按 id 排序，下标能被 3 整除）上拟合：先把写入/外发误选压到 0，再提高 top-1，再提高弃权切分。否定集不参与拟合。
- `negation_set.json` 是额外评测，不并进 140 题，也不做训练数据。

```bash
python3 scripts/laya/test_stage1_contract.py
```

机器上没有 `flutter_tester`、`scripts/verify.sh` 或其他 `stage1_ask.py` 时才测量。线程封顶 4。检查点只读本地缓存。

```bash
~/.cache/muyon-eval/venv/bin/python scripts/laya/stage1_ask.py
```

结果写到 `~/.cache/muyon-eval/stage1-metrics.json`。门禁 1：留出折、对抗题、否定集上的写入/外发误选都是 0。失败则退出码 2，不开始 Kaggle。

140 题文件仍然只用于评测。本阶段不读 `.env`。

## 第二阶段：Kaggle 微调

`train_set.jsonl` 是合成题，不包含 140 题，也不包含整段留出的工具。`train_overlap.json` 记录和评测题的字符 5-gram 最大 Jaccard。

`laya_finetune_tool_selection_kaggle.ipynb` 用多语检查点 `convaiinnovations/laya-multilingual` 的修订 `1720e3e3357cfe1e281542e223f8273b0890ca34`，`laya==0.3.27`，两块 GPU。它不推送到 Hugging Face Hub，最后写 `NO_HUB_PUSH`。

只有门禁 1 的结果是 `pass` 时才提交。脚本只读 `.env` 里的 `Kaggle-apikey`，放进子进程的 `KAGGLE_API_TOKEN`，输出里的 `KGAT_` 会被抹掉。数据集和笔记本都是私有的，加速器是 `NvidiaTeslaT4`（GPU T4 ×2），并打开网络以便下载公开基座。

```bash
python3 scripts/laya/test_stage2_data.py
python3 scripts/laya/test_kaggle_submit.py
python3 scripts/laya/kaggle_submit.py
```
