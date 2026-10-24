# Development offline runner：补纳既有 UiState 检查

2026-10-24。只修 PR123 独审后置的 runner Minor，不修改生产UI、视觉或现有测试断言。

- 重新fetch develop=`50eb6092fd80706ef597407415be05a5975d0a83`；隔离分支 `task/development-runner-ui-checks-20261024`，工作树 `/workspace/muyon-development-runner`。未使用旧main。
- 已读最新 [PR123 合入交接](https://github.com/mightyoung/Muyon/pull/123)、`docs/tasks/README.md`、`docs/tasks/REVIEW.md` 与当前HANDOVER职责补注。旧云端不可开发 / Flutter时代限制不恢复为新授权；本次父任务明确授权本云端只修此Minor，B仍唯一合入者。仓库未发现AGENTS.md或相关本地 `.agents/skills`。
- 已有Kotlin2.2.20 `/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc`；现有Java21.0.12.1；已批准 `json-20250517.jar` SHA256=`3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796`。没有下载 / 安装 / 新依赖 / 系统修改。

## 最小修复

`apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/development/run-offline.sh` 仅新增三行：

1. 既有编译清单加入生产纯状态文件 `development/DevelopmentUiState.kt`。
2. 加入已有 `development/DevelopmentUiStateChecks.kt`。
3. 原Controller main之后，以同一jar/classpath调用 `com.mightyoung.muyon.product.development.DevelopmentUiStateChecksKt`。

保留原 `set -euo pipefail`、`-Werror -jvm-target17`、JSON classpath、临时目录释放和Controller入口；两组任一失败仍使runner失败。没有更改生产文件或测试文件。现有Controller使用合成draft/port fixture；本片没有增加provider调用、授权、网络或原生接线。

## 实际 RED / GREEN

统一命令（完整）：

```sh
KOTLINC=/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
JSON_JAR=/workspace/publicui-tools/json-20250517.jar \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/development/run-offline.sh
```

- RED输入为原基线50eb：runner本身exit0，只输出 `PASS development controller/runtime: ... zero sends`；对实际日志要求出现 `6/6 PASS` 的覆盖检查exit1，明确报缺DevelopmentUiStateChecks完成。这是**runner覆盖遗漏RED**，不是生产行为失败、编译失败或既有六项检查失败；未虚构旧测试本身FAIL。
- GREEN源码 `54c7b6dfcf33b3b3cd656aa8d75704272d8a8389`：同一命令exit0；原Controller整组完成，UiState六项逐条PASS且摘要 `6/6 PASS`。两组完成标记的同一覆盖检查exit0。
- `bash -n .../development/run-offline.sh`、`git diff --check` 均exit0。没有为这三行修复新增镜像测试或弱化既有断言。

六项原检查覆盖选择变化 / late callback、卸载拒绝、scope key分隔及null碰撞、A→B→A不复活、确认绑定显示的plan/scope/draft/revision、scope generation只接受原生非负整数。它们不是六个设备 / 真实provider场景；Controller原有CAS、scope/session撤销及原回执恢复检查保持。

## 验证范围与交付

本片只证明现有纯JVM入口现在会执行两组检查。不运行真实provider / Android设备 / UI截图 / 模型 / 账号授权；不修改PR108、CI workflow或产品gate，不部署、不合main/develop、不强推或删分支。原基线CI成功不转记给本源码。提交带skip-ci避免仅runner修复自动扩大到完整模型/SDK准备；Draft PR交B后由其决定原CI入口，实际本candidate CI状态另在PR/最终回报核实，不填PASS。

Ruling：用实际runner输出的完成标记证明遗漏与闭合，不把旧exit0当两组均已运行——代价是这是入口覆盖证明，不能代替Android/设备或生产效果验收。没有其他设计改动。

## 仓库外证据

原始日志在 `/tmp/development-runner-evidence/`，不入库。

| 日志 | SHA256 |
| --- | --- |
| red-runner.log | `1c319783c73568c52d27ee64fd1137dd9d2a89a889d722ce50ad0a623d07b867` |
| red-coverage.log | `4f07764bef3069dcbf743ecb65ededd874e22203cbbb77b3078d6e3569143ca7` |
| green-runner.log | `f8ad5b53929f91d36f95f8ab2b4f33cb3faa5ed89bee472a0e65d69065b17fc7` |
| green-coverage.log | `6c99150040a9572a4fab22a66eab53a3f88f410f22af3cc0d8417a78fe69da56` |

独立非作者 `/root/review_development_runner` 对固定base50eb到源码 `54c7b6dfcf33b3b3cd656aa8d75704272d8a8389` 完成只读审查，C0/I0/M0，可交B候选，不直接合入。亲自使用指定现有Kotlin/JSON/Java重跑runner exit0，Controller完成与UiState6/6均确认；bash-n、固定范围diff-check通过；确认原set-e / Werror与失败传播保留，fake端口禁止真实exchange。没有修改或安装、没有二次代理。后续只补本文，不改变已审runner字节。

独审未验项裁定：Android / 实机、完整Rust与真实provider不是三行runner纳入修复的新增能力；保持未验，不能从纯JVM检查推断生产效果。候选CI、PR和push须由作者另核，基线CI不可替代；唯一合入者仍为B。无待后置Minor。

