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
