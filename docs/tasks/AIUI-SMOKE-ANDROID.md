# AIUI-SMOKE-ANDROID 默认开启候选的真实模型 + Android 冒烟

分支 `task/aiui-smoke-android` · 执行：**Claude Haiku 5.5**（本机会话，有 Flutter、adb、模型密钥环境变量）· 审查：leader A · 上位：[AIUI 默认开启计划](AIUI-DEFAULT-ENABLE-PLAN.md) 第三个时间窗口与验收矩阵

用户决定（2026-10-10）：冒烟由 Claude Haiku 5.5 执行；本机构建、测完卸载；**构建完先停下，等用户连接手机**。

## 开工前提（缺一项就停下回报，不自己补）
1. Leader B 给出**默认开启候选**的完整提交 SHA，且该候选已通过审查与组合 CI。
2. 候选里带有冒烟用的集成测试（建议 `apps/muyon/integration_test/aiui_smoke_test.dart`，由接线任务一起交付），覆盖下面「验收项」里能自动化的部分，模型配置走 `--dart-define`（写法同 [North Star 运行手册](../implementation/north-star-inquiry-runbook.md) 第 79 行起）。没有这个测试就停下回报，**不要自己写测试或改代码**。
3. 模型端点、模型 ID、密钥只从本机环境变量读取；不打印、不回显、不写进任何文件。

## 步骤
1. `git fetch` 后在本分支检出候选 SHA 的内容（`git checkout <SHA>` 到分离 HEAD 即可），记录 `flutter --version`。
2. **构建（不需要手机）**：在 `apps/muyon` 下用候选测试作为入口构建一次调试包，预热缓存并确认能编译：
   `flutter build apk --debug --target integration_test/aiui_smoke_test.dart --dart-define=...`（参数同运行时）。
   跑测试和构建时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`。
3. **停下**，告诉用户：「构建完成，请连接手机并打开 USB 调试，连好后告诉我」。**不要**自己执行 `adb devices` 轮询或尝试连接，等用户回复。
4. 用户确认后：`adb devices` 取设备 id，执行
   `flutter test integration_test/aiui_smoke_test.dart -d <设备id> --dart-define=...`。只跑一次，如实记录，不挑结果。
5. 需要手动的项（见验收项 5、6）用 adb 完成：`adb shell am force-stop com.mightyoung.muyon` 后 `adb shell monkey -p com.mightyoung.muyon 1` 重启；`adb exec-out screencap -p > /tmp/…png` 截图后自己看图判断。截图只留在 `/tmp`，确认画面里没有密钥、端点、个人信息后，才可以选用最多 3 张入库到 `docs/evidence/aiui-smoke/`。
6. **卸载并清理**（无论成败都做）：
   - `adb uninstall com.mightyoung.muyon`，测试包若存在也卸载（`adb shell pm list packages | grep muyon` 查出来的全部卸掉），再用同一命令确认已无残留；
   - 删除本机 `apps/muyon/build/app/outputs/` 下这次生成的 apk（里面编进了密钥）。

## 验收项（对应计划的验收矩阵）
1. 对话提交后出现询价本体卡片；事实和建议分开显示；来源标签与对象、版本对应。
2. 卡片里所有业务提交按钮都是禁用的；没有新增写入确认。
3. 无模型 / 断网时退回文字加固定模板；取消和超时后没有半截卡片。
4. 撤销选定范围或对象版本变化后，不再显示旧数据。
5. 杀进程重启后，已保存的卡片恢复。
6. 在设置里关掉 AIUI，杀进程重启后仍然是关闭状态。
7. **延迟**：首字延迟和「提交到首张卡片完整显示」各记至少 5 次的单次值和中位数，对照本机 `<1.5s`、远程 `<3s`（卡片可见没有既定阈值，只记录）。

每项写：通过 / 失败 / 未测（附原因）。不能把离线夹具的结果写成真机结果。

## 约束
- 不导出 `MUYON_EVAL_REAL` 跑 `verify.sh`、`ci.sh`；本任务也不需要跑它们。
- 报告里端点只写到路径，本机路径写成 `<repo>`，不出现密钥。
- 安装包、原始日志不进仓库、不上传。
- 不改产品代码、不改测试、不合并 develop。

## 产出与回报
报告 `docs/evidence/aiui-smoke/2026-10-android-smoke.md`（候选 SHA、设备型号、Android 版本、模型名称、每项结果、延迟原始值与中位数、步骤），提交并推回本分支。
回报：分支与提交哈希；7 项结果；延迟中位数；**已卸载的确认输出**（`pm list packages | grep muyon` 为空）；没做到的项及原因。
