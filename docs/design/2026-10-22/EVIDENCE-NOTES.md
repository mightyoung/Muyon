# 候选、CI 与历史证据适用边界

2026-10-22 UTC 只读核对，原文件和旧记录均保留。当前证据优先于旧索引中未限定日期的“当前”措辞，但不改写其历史事实。

| 对象 | 本轮核对 | 适用边界 |
|---|---|---|
| 候选分支 | `codex/muyon-android-refactor` = `f4781e16ddf4e542b983fbd77f266a0071148255` | [远端快照](evidence/remote-heads.txt)；本归档从该提交分支 |
| PR100 | OPEN，head 同候选，base develop | [PR 快照](evidence/pr100.json)；未合入 |
| main | `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` | 本轮不修改 |
| develop | `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e` | 本轮不修改；唯一合入者仍 Leader B |
| 产品 CI | [39547561616](https://github.com/mightyoung/Muyon/actions/runs/39547561616) 与 [39547554395](https://github.com/mightyoung/Muyon/actions/runs/39547554395) SUCCESS，同 f478 完整 SHA | Rust/checker、Android build、required-product 成功；该工作流只编译 instrumentation，不执行设备 suite |
| 通用 CI | [39547561549](https://github.com/mightyoung/Muyon/actions/runs/39547561549) SUCCESS，同 f478 | 不能取代设备、真实模型和费用证据 |
| Android Rust bridge | [39547561570](https://github.com/mightyoung/Muyon/actions/runs/39547561570) 顶层 SUCCESS | select 成功，其后 required/full/Android 等 SKIPPED，不能表述为桥接全套通过 |
| Compose lab | [39547561657](https://github.com/mightyoung/Muyon/actions/runs/39547561657) SKIPPED | 不是成功运行 |

完整运行列表见 [candidate-runs.json](evidence/candidate-runs.json)。本轮只查询现有 CI，不重新派发构建、不触发真实模型/搜索。

[旧设备套件报告](../../tasks/muyon-android-refactor/product-device/final/README.md)绑定 `7b063cb4089fe21fdaf82657bcf00408e3f138b1`，不是 f478；[D01](../../tasks/muyon-android-refactor/D01/README.md)保留 PR99 原 `590fbc026b2fc5d200236d1877482b03752d0d8f` 的 2 tests / 1 failure。旧失败不得抹除，旧成功也不能改标当前候选通过。新模型、notice/checker 与打包条件的变化见[10-21 产品 CI 与资源修复记录](../../reviews/2026-10-21-product-ci-and-resource-remediation.md)，早期 artifact 的 PASS 仍只适用早期 gate。

[I04/D02 既有审计](../../tasks/muyon-android-refactor/i04/README.md)仍 BLOCKED，RC01 NOT_RUN；历史被拒绝操作不重试、不拆分、不改名绕过。[C01 独审](../../tasks/muyon-android-refactor/C01/FINAL-REVIEW.md)仅覆盖其列明范围，不等于整卡验收。PR86/依赖集成 HOLD 不由本归档解除。

两次真实请求仍 unknown；预占 ¥0.002620 未结清，实际费用未知，不改成失败/成功/零费用，不重发。当前候选同 SHA 设备验收、生产费用证明及真实模型/搜索闭环继续待核；本批仅完成来源归档和计划登记。
