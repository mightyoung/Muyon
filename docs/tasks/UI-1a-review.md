# UI-1a 最终审查

2026-10-08 · 最终实施 SHA `20f56b6c72bad0d46d8fe18c78914da8c0f029b6` · 分支 `task/ui-1a-design-system`。本记录由 Mac 执行者按 leader B 已提供的独立审查结论整理，不将作者自检冒称独立审查。

## leader B 结论

**APPROVE**。独立 Mac 核实任务 `01a118f5-43c7-75b8-aa8d-e69034150021` 对精确 SHA 用 git archive 副本复核；两独立视角无阻断。leader B 已核对 exact-head CI `37687503677` 为 success：<https://github.com/mightyoung/Muyon/actions/runs/37687503677>。本审查文档的新 SHA 仍须单独 CI 通过，合入候选另作验证。

## 独立核实与限制

- 独立 UI 全量 225 通过，包含 60 个 Mac golden；UI 和宿主 strict analyze 无问题；非 debug route 测试 1 通过。
- 独立核实没有重跑宿主 890 通过/3 跳过，也没有重跑三项变异；这些属于实施方已留存证据，不冒称独立结果。
- 实施方最终原始摘要：`No issues found! (ran in 6.4s)`（UI）、`No issues found! (ran in 6.1s)`（host）、`00:13 +225: All tests passed!`、`01:35 +890 ~3: All tests passed!`、`00:00 +1: All tests passed!`（非 debug VM 路由）。原始日志在 `/tmp/muyon-ui-1a/`，不提交。
- 三项行为变异（底栏触达高度 48→40、移除 Semantics label、dark warn 改成 deep）各 exit 1 被杀死，恢复后全量通过；第三项由字面 token 断言捕获，不声称它造成对比度失败。
- 非 debug 路由是 VM profile define 核实；没有实际 release 二进制/设备/真实模型证据。这些取证延期，不能用本次测试代替。

## 范围与修复

15 项组件与 v6 tokens、theme、debug catalog、组件测试和新 golden；新增 debug 主入口是任务允许例外。没有接助手授权、改询价业务/theme/旧 golden 或 REG 实现。

用户已明确允许旧 token parity 断言升级 v6，并要求保留独立冻结 Folio 兼容断言；本任务按此窄例外执行，不以宽泛修改旧测试换取通过。

实施中的独立审查发现外部内容确认规则、远程模型文案与实际双亮度测试遗漏，均已修复并重新验证；最终无剩余阻断。外部内容标记独立于业务状态，移除其长期/对话自动授权选项；读取无授权按钮；模型明确标为远程模型。固定尺寸只限 spec 指定 glyph/视觉尺寸，交互目标为至少 48。

## 合入门禁

仅合 develop，main/release 不动、不强推。先检查最新 develop、记录本审查提交的实际 CI；隔离合入候选若完整 tree 与获批文档候选一致，记录等价验证，否则重跑受影响检查。普通 push 后 ls-remote 与候选 HEAD 逐字一致；合入后的新 SHA CI 另行回报。
