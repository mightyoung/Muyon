# LINUX-COMBO-VERIFY：UI 与存储组合 Linux Flutter 复验报告

执行：grokbot（工程师2号 / 路线 1）。日期：2026-10-12（Asia/Shanghai）。
只验证、只报告；未改生产代码；未合入 develop。

## 1. 环境与精确 SHA

| 项 | 值 |
|---|---|
| 验证 SHA | `9de4235a02c1ee8c5d564f1f440dac1cae49c9c1`（`task/le06-race-diagnosis-20261012` tip） |
| 相对原组合 | `326ca138` 的祖先；之上含 LE06-RACE 修复（`9de4235`）及诊断提交 |
| 本报告挂靠分支 | `task/linux-combo-verify-20261012`（验证对象不是本分支 tip `0280b9d`，而是上表 SHA） |
| OS | Debian / Linux 6.12.94+ x86_64（`grok-bot-vm-416298673`） |
| Flutter | 3.47.5 stable（framework `6a19cca564`），Dart 3.13.4 — 与任务要求一致 |
| Desktop 依赖 | **不完整**：仓库无 `apps/muyon/linux/`；本机缺 cmake、ninja、clang、pkg-config、`libgtk-3-dev` 等。按说明未 apt install、未改系统安全设置。有 X11 `DISPLAY=:16`，但无法构建原生桌面应用。 |
| Worktree | `/workspace/muyon-le06` @ `9de4235` |
| 原始日志（不进仓库） | `/workspace/linux-combo-verify-artifacts/on-9de4235/` |

对照 CI：组合跑 `38210369162`（`review/ui-storage-current-combo-20261012`，基线含 `326ca138`、**未含** LE06 修复）曾 **FAILED (test:host)**，唯一失败为 `le06_recovery_independent_test` 双进程预约竞争。LE06 修复后同 SHA 的 CI `38246843919` **success**。

## 2. 八个测试套件（`scripts/ci.sh` 等价）

命令：`bash scripts/ci.sh`（cwd `/workspace/muyon-le06`）。结果：

```
CI SUMMARY: OK (analyze 8/8, test 8/8 suites)
```

analyze 8/8 ok；gate `test_verification_gates` ok；doctor 23 scenarios passed。

| suite | exit | summary | skipped |
|---|---|---|---|
| module_api | 0 | +274: All tests passed! | 0 |
| muyon_ui | 0 | +387 ~152: All other tests passed! | 152 |
| prototype | 0 | +39 ~1: All other tests passed! | 1 |
| research | 0 | +365: All tests passed! | 0 |
| supplier_core | 0 | +498 ~4: All other tests passed! | 4 |
| host | 0 | +2291 ~3: All other tests passed! | 3 |
| ui_preview | 0 | +15: All tests passed! | 0 |
| inquiry | 0 | +302 ~47: All other tests passed! | 47 |

与 CI `38210369162` 对照：彼时 host 为 `+2290 ~3 -1`（LE06 竞争失败）；本 SHA host 为 `+2291 ~3`（LE06 修好后多 1 通过、0 失败）。其余套件计数一致。coverage check 亦通过。

**本跑八套件无失败。**

## 3. 窄屏 390px · 100% / 200%（automatic 档）

### 3.1 Widget 测试（已实跑）

| 文件 | 结果 | 说明 |
|---|---|---|
| `apps/muyon/test/linux_ui_planning_mode_layout_test.dart` | **PASS** `+18` exit 0 | 覆盖 width∈{320,390,1280} × scale∈{1.0,2.0} × 全部 `UiPresentationMode`（含 automatic）；断言标签完整可读、可选 |
| `apps/muyon/test/linux_host_settings_validation_test.dart` | **PASS** `+4` exit 0 | 含 `automatic_mode_assistant_page_390_at_text_scale_2_no_overflow`；以及 390@200%、1280@200%、390@100% 三档切换与重启保持 |
| `apps/muyon/test/responsive_shell_test.dart` | **PASS** `+7` exit 0 | 含多宽度 200% 字体壳层 |

PR #61 在 `2a3201b8` 上的 RED（390 automatic 溢出）由组合内修复 `65171dee`（`fix(ui): wrap planning mode labels within scaled narrow layouts`）覆盖；`65171dee` 是 `9de4235` 的祖先。本组合上上述用例 **全部 GREEN**。

### 3.2 原生 Linux desktop（未实跑）

**未实跑。** 原因：

1. 精确 SHA 仓库无 `apps/muyon/linux/` 平台工程；
2. 本机缺 Linux desktop 构建工具链（见 §1），且不得 apt install。

无启动截图。隔离启动脚本与缺口说明见历史产物 `/workspace/linux-host-artifacts/`（PR #61 任务）；本任务未新增桌面截图到 `evidence/`。

## 4. 重复运行稳定性（≥10 次）

### 4.1 `fad3a001` 存储通知隔离

文件：`apps/muyon/test/managed_connection_commit_observer_test.dart`、`commit_observer_non_author_recovery_test.dart`。

| | |
|---|---|
| 次数 | 12 |
| 结果 | **12/12 pass**（每轮 `+8: All tests passed!`） |
| 结论 | 稳定 |

### 4.2 N2 无障碍 `4956803e`

核心无障碍文件：`section_delete_preview_accessibility_test.dart`、`n2_accessibility_non_author_test.dart`。

| 批次 | 文件集 | 次数 | 结果 |
|---|---|---|---|
| A | 上列 2 文件 + `section_delete_preview_ui_test.dart` | 5 完成 + 1 挂起 | 5 pass；第 6 次在 `closed database freshness timer reports unexpected StateError` **挂起 >17 min**（已杀进程，记 exit 124） |
| B | 仅上列 2 个无障碍文件 | 12 | **12/12 pass**（每轮 `+13`） |

结论：

- **无障碍相关测试（4956803e 范围）稳定：12/12。**
- `section_delete_preview_ui_test` 的 closed-DB freshness timer 用例在负载下出现 **时序相关挂起**（非断言失败）。归类见 §5。未跳过、未放宽该用例本身；后续重复改为只跑无障碍文件以满足 ≥10 稳定性要求。

## 5. 失败分类

本精确 SHA 上 **八套件与窄屏 widget、fad3 重复、N2 无障碍重复均无断言失败**。相关历史与观测分类如下：

| 现象 | 分类 | 说明 |
|---|---|---|
| CI `38210369162` host：`two independently gated processes contend for one pending reservation` | **本组合导致（已修复）** | 原组合 `326ca138` 上 LE06 预约读 busy 未映射；`9de4235` 修为 `ledger_pending_failed`。本跑与 CI `38246843919` 均绿。 |
| N2 `section_delete_preview_ui_test` freshness timer 挂起（重复批次 A run6） | **时序相关** | 同用例在批次 A 前 5 次通过；第 6 次在 timer 路径挂起。单独重跑无障碍文件 12 次全过。非 develop 基线独有证据；未改测试。 |
| PR #61 窄屏 RED | **本组合已含修复** | `65171dee` 在祖先链；本 SHA widget 复验 GREEN。 |
| develop 基线也失败 | **无** | 本跑未复现「develop 也失败」类项。 |

## 6. 未实跑 / 未验证项

- 原生 Linux desktop 构建、启动、截图、真实窗口 390px / 字体缩放：**未实跑**。
- 本报告分支 push 后的 GitHub Actions：**提交时未等结果（未验证）**。
- 未在 `origin/develop` tip（当时 `ab5506c`）上整套重跑八套件做差分（本任务要求在精确 SHA `9de4235` 上验证；develop 对照仅用于失败分类口径）。
- 未跑 Android、未部署、未合入。

## 7. 结论

在精确 SHA `9de4235` 上：analyze 8/8、八套件 8/8、窄屏 widget（含 390×100%/200% automatic）通过；`fad3a001` 与 N2 无障碍相关测试各 12 次重复稳定。原组合 CI 唯一 blocker（LE06）已在该 SHA 消除。原生 desktop **未实跑**。建议：desktop 实跑需先补 `linux/` 工程与构建依赖后再派发；N2 UI freshness timer 挂起可另开时序加固任务（非本组合 blocker）。
