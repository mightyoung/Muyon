# JR-1 小清理（第一阶段遗留的可选项）

分支 `task/jr-1-cleanups` · 来源：[路线图](../superpowers/plans/2026-10-07-roadmap-phase2-4.md) §7 末行、P0-J3 审查的可选项 · 执行：junior（opencode）· 审查：leader（`reviewer-sonnet-low`）

## 只做这些（四项各自一个提交）
1. **`scripts/ci.sh` 跑 `scripts/test_doctor.sh`**：作为独立一步，失败时整体失败，摘要行与其他步骤格式一致。`.github/workflows/ci.yml` 通常不用改，确认 Actions 里能跑到这一步即可。
2. **研究页标题按字符截断**：`packages/research_module/lib/src/app/object_pages.dart` 里的 `_cardTitle` 按 UTF-16 截断，会切开 emoji；卡片标题处还有一份重复实现。抽成一个共享函数，按 `characters` 截断（`package:characters` 是 Flutter 自带的依赖，不算新增），两处都改用它。补测试：emoji、中文、组合字符都不会被切开。
3. **删除无用的 `@Tags(['screenshot'])`**：已经没有脚本使用这个标签。先用 `grep -rn "screenshot" scripts .github` 确认确实无人使用，再删除三个测试文件上的标签。
4. **P0-F1 测试注释**：在 `packages/supplier_core/test/lan_security_test.dart` 对应用例旁加一句注释，说明它守的是「`stop()` 返回前上传已结束并清理」。只加注释，不改断言。

## 不做
不改其他行为；不改已有断言；原始验证日志不进仓库，摘要写在提交说明里。

## 验证
`bash scripts/ci.sh`（本机 inquiry 的 golden 截图因 macOS 27 渲染漂移会失败，属已知情况，如实写明）；`bash scripts/test_doctor.sh`；`packages/research_module` 全量测试。

## 回报
分支与提交哈希、四项各自的改动、验证摘要行、Actions 运行链接。
