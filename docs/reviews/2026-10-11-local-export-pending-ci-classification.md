# LE02 / LE04 / LE05 在途源 CI 只读分类

本次仅看固定远端源、实际 checkout、job 元数据、SHA256 校验的完整 ci-log artifact，未运行三分支测试、未改作者源码或覆盖门禁、未派重复修复任务。

| 任务 | 固定源 / 实际 checkout（已核对一致） | CI run | 八包 analyze/test | 实际失败分类 |
|---|---|---|---|---|
| LE02 | `cb3852d2a13947e59b2bb3bcb745a64bb78f5336` | [38154753182](https://github.com/mightyoung/Muyon/actions/runs/38154753182) | 8/8 analyze；3563 pass /207 skip /0 fail，API268/host1824 | `coverage:report`，module_api 分母漂移 |
| LE04 | `58c46f85e4e4eecae787d680aba300860d565fae` | [38157331109](https://github.com/mightyoung/Muyon/actions/runs/38157331109) | 8/8 analyze；3574 pass /207 skip /0 fail，API268/host1841 | 同上 |
| LE05 | `e6991e79aa1fccfa2ea6bbc571d1c1ab72efa1a3` | [38155605391](https://github.com/mightyoung/Muyon/actions/runs/38155605391) | 8/8 analyze；3588 pass /207 skip /0 fail，API268/host1855 | 同上 |

三个 run 均 completed/failure。失败 step 是 `Analyze and test every package`，但完整脚本摘要的首个/唯一失败为：

> COVERAGE SUMMARY: FAILED: denominator drift: packages/muyon_module_api/lib/; review/remeasure, never silently accept

随后 `CI SUMMARY: FAILED (coverage:report)`。八套 analyzer/测试、Doctor23 与 coverage checker 自测已绿；Laya 被后续 job 条件跳过，不能称已通过。这不是三项业务断言失败，也不是新的 analyzer 报错。后续应组合最新 develop 已审覆盖基线后重新测量核验；不从旧源 job 推断新组合必绿，不豁免其他未来失败、不静默更新门禁。

完整 CI artifact ZIP：LE02 11708198596 / SHA256 `0b3ae3481d22e18d211224fd06faf80e9cfdb061a8026888ec54a2708ebe01e7`；LE04 11709032576 / `41090fb9c6914cc6bc925790faf5d8784e0f0e75b6ff691d3c2ef5b1367e9d7c`；LE05 11708334835 / `495aa5fc9c6e1639d4b3950645180349642c4c2e0c49d6299a6d81d319900c9d`。三者下载与 ZIP 散列已核验，decoded job logs 中实际 `git log -1 --format=%H` 与固定源一致。原始日志留在工作树外 `/tmp/aiui-chain-evidence/`；机器分类与 checkout proof 在 `/workspace/reports/LE02-LE04-LE05-readonly-*.json`，未入 Git。

REG3e-a（`task/reg-3e-manual-runs`）完整当前 SHA：`4c44a0a210e530c4890a361e4fb94f11a339f24c`，[源 CI38157204944](https://github.com/mightyoung/Muyon/actions/runs/38157204944) completed/success、metadata headSha 一致。本轮未独审此实现，不以源绿视为已可合入。
