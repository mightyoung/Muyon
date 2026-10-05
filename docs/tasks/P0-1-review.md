# P0-1 审查结论

审查对象：`task/p0-1-ci` @ `b716bd3` · 审查：leader（代码核实由 Sonnet 子代理执行）· 日期：2026-10-06

**结论：小修后合并。** 没有阻断项。F1 本轮修复，F4～F6 顺手修复。修复改由 **junior** 执行（engineer 手上有 B 2.4 修复和 P0-4），排在 E11 之后。F3 另开任务 [P0-F1](P0-F1.md)。

## 范围
只新增 `.github/workflows/ci.yml`（55 行）与 `scripts/ci.sh`（82 行）。`verify.yml` 与 `verify.sh` 都没有改动。✅

## 交付核对
- **ci.sh：**
  - analyze 的包列表、测试套件列表，与 `verify.sh` 的差异为空；
  - 没有放行清单；
  - 退出码为 0 且有汇总行才判为通过；
  - 先带代理执行 `pub get`，再去掉代理跑测试，比 `verify.sh` 更合理。
- **ci.yml：** 全部满足：
  - 触发：push 到 develop、main、`task/**`、`review/**`，以及发往 develop、main 的 PR；
  - ubuntu-latest，Flutter 3.47.5 stable，开启缓存；
  - `PIPESTATUS` 退出码透传；
  - `if: always()` 上传日志；
  - 只读权限，并发组会取消过期运行；
  - 运行四个 Laya 测试。
- **排除**：部分满足，见 F1。

## 退出码可信度（子代理在副本中注入故障）

| 注入的故障 | 结果 |
|---|---|
| analyze 错误 | 判为失败，并点名出错的步骤或 suite |
| 测试失败 | 同上 |
| 测试中途 `exit(1)` | 同上 |
| 顶层 `exit(3)` | 同上 |
| import 了不存在的文件 | 同上 |
| `pub get` 失败 | 同上 |
| 测试挂起 | 同上 |
| 失败测试带 `screenshot` tag | 退出码为 0，被排除（见 F1、F2） |

## 运行结果
- **Actions 第 2 次运行**（`b716bd3`）：通过，ci.sh 用时约 6 分 46 秒。七个包的 analyze 全部 ok，七个测试套件全部 ok。
- **Actions 第 1 次运行**：判为失败，属于误报。Actions 上的 reporter 没有输出汇总行，脚本按设计判为失败；`--reporter compact` 已修复这个问题。
- **沙箱中完整运行一次**：supplier_core 中有 1 个已有测试不稳定，导致整体判为失败（见 F3）。其余各套件的计数与 Actions 完全一致。

## 本轮修复

**F1（应改）排除范围与注释不符**（`ci.sh:7-12, 30, 62`）
`--exclude-tags screenshot` 排除了 3 个文件，共 48 个用例：
- `screenshot_test.dart` 和 `ontology_screenshot_test.dart` 在 Linux 上本来就会因缺少 macOS 字体自动跳过；
- `generated_icon_sources_test.dart` 使用仓库自带的字体，不和 golden 比对，在 Linux 上能通过，却也被排除了。

**leader 决定采用方案 A：**
- 去掉 `--exclude-tags`；
- 注释改为说明：依赖 macOS 字体的 golden 测试在 Linux 上通过 `skip: !hasFont` 自动跳过，日志中会出现约 `~47` 个跳过。子代理已实测，在 Linux 上 inquiry 为 `+276 ~47`，退出码 0；
- 去掉排除后，F2 不再存在。

**顺手修复：**
- **F4**：把「拉完依赖后才去掉代理」这句注释移到 unset 代理的那一行附近。
- **F5**：汇总行中的 `analyze 7/7, test 7/7` 是写死的，改为实际计数。
- **F6**：`flutter analyze` 加上 `--no-pub`，避免在已经去掉代理之后重新解析依赖。

## 另开任务
- **F3** → [P0-F1](P0-F1.md)：`packages/supplier_core/test/lan_security_test.dart` 中的 `stop cancels pending uploads and completes cleanup before returning` 在沙箱里 14 次失败 11 次（`SocketException: Broken pipe`），在 Actions 上通过。ci.sh 没有排除它，也不应排除。

## 只做记录
- **F7**：ci.sh 失败时会跳过 Laya 步骤，与 `verify.yml` 一致；分支同时有 PR 时会跑两次；Actions 日志中有 Node.js 20 弃用警告。

## 修复方式
1. 执行者（junior）检出 `review/P0-1`，只修改 `scripts/ci.sh`，提交并推送。
2. 推送后，GitHub Actions 会在 `review/P0-1` 上自动运行。回报中附上：运行链接与结论，以及本机运行 `bash scripts/ci.sh` 的摘要行。
