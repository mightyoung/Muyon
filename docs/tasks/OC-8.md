# OC-8 ADR-0004 里已删除函数的过时引用加注（只改文档）

分支 `task/oc-8-adr4-stale-refs` · 基线 develop · 执行：opencode · 审查：leader A

## 背景
你在 OC-2 删掉了 `apps/muyon/lib/platform/business_tools.dart` 里的 `registerBusinessTools`。`docs/adr/0004-module-contract-v2.md` 还有两处提到它（第 32 行、第 353 行）。第 32 行在「§2 现状」表里，是当时的历史描述，**不要改原文**，只在合适位置加注。

## 只做这些
1. 在 §2.1 那张表（第 32 行所在的表）**结束后的第一个空行处**插入一段（单独成段）：
   > 2026-10-11 注：`registerBusinessTools` 已删除（OC-2）。现在询价工具由询价 v2 适配器的 `registerTools` 登记（`apps/muyon/lib/app/adapters/inquiry_module.dart`），宿主在 `MuyonHost.open` 中调用 `host.modules.registerTools()`（`apps/muyon/lib/app/bootstrap.dart`）；原型与科研工具经 `registerNonInquiryBusinessTools`（`apps/muyon/lib/platform/business_tools.dart`）。上表保留为当时的历史记录。
2. 第 353 行这句里，把「这与今天 `registerBusinessTools(host)` 在 `open` 里一次性登记（`bootstrap.dart:213`）的时机一致」改为「这与当时 `registerBusinessTools(host)` 在 `open` 里一次性登记的时机一致（该函数已于 2026-10-11 删除，现由 `host.modules.registerTools()` 登记）」。
3. 写进注里的两个文件路径，先用 `ls` 确认文件确实存在；`registerTools`、`registerNonInquiryBusinessTools` 用 `git grep -n` 确认在对应文件里。任何一项找不到就停下回报，不要写。

## 不做
不改其他行、其他文件；不改代码。

## 提交与回报
一个提交：`docs(adr): annotate removed registerBusinessTools references`，只含这一个文件，推到 `task/oc-8-adr4-stale-refs`，`git ls-remote` 确认。

**回报必须是下面 4 行，每行都要有内容：**
1. 提交哈希：
2. 第 3 步四项确认的结果（每项一句）：
3. `git diff --stat origin/develop` 的输出：
4. `git diff origin/develop -- docs/adr/0004-module-contract-v2.md` 中以 `+` 或 `-` 开头的行数：
