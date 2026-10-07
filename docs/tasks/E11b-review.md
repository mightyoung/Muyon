# E11b 审查

审查分支 `review/E11b` @ `14db9dc`（与 `task/e11b-object-page-tests` 相同）· 审查 leader · 核实子代理 `reviewer-sonnet-medium`（Opus 那次因额度中断，改由 Sonnet 重做）· 2026-10-07

**结论：通过，合入。** 无阻断、无应改。

## 范围
3 个文件，+120/−5：`research_object_open_test.dart` +53、`research_module.dart` +17/−5（`:501` 卡片标题与新增 `_cardTitle` `:713`）、`research_runtime_test.dart` +50。已有测试没有被修改。

## 核对
| 项 | 结论 | 依据 |
|---|---|---|
| N1 辅助函数返回 null 时释放会话 | 满足 | `research_object_open_test.dart:363` 起：对象已删除、`objectPage` 抛异常两种情况都断言会话随后抛 `Session disposed` |
| N4 卡片标题 | 满足（复用为部分满足，见可选 1） | `research_module.dart:713-724` 去 `# `、换行，按 rune 截到 60 加「…」；测试 `research_runtime_test.dart:269` 起覆盖带 `# ` 标题与 70 个 emoji 的长标题 |

- **变异**：删掉 `object_pages.dart` finally 中的 dispose → 新测试失败；截断改为 UTF-16 `substring` → emoji 断言失败。
- **重跑**：research_module 与 apps/muyon `flutter analyze` 均 `No issues found`；research_module 全量 `+211`；`research_object_open_test.dart` 在临时加上 P0-F2 修法后 `+6` 全部通过。
- **不加 P0-F2 修法时**该文件 `+3 -3`：已知超时一例、其连带失败一例，以及 E11b 新增的「the helper disposes the session when it returns null」（`Reentrant call to runAsync() denied`，同样是连带，不是自身断言失败）。P0-F2 合入后应全部通过。
- **Actions**：14db9dc 没有运行记录（任务分支 push 当时没有触发）。

## 可选（记录）
1. 卡片标题的 `_cardTitle` 是新写的一份，与 `packages/research_module/lib/src/app/object_pages.dart:227` 页面标题的同名函数重复；**页面标题版仍按 UTF-16 截断，会切开 emoji**。第一阶段之后抽成共享函数并改为按 rune 截断。
