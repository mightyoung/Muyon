# HK-5 E-1 真实模型基线（DeepSeek，本机）

分支 `task/hk-5-e1-real-baseline` · 基线 develop · 执行：Claude Haiku 5.5（本机）· 审查：leader A

## 背景
E-1 多步任务评测的真实模型基线一直没跑（第二阶段退出标准要求）。用户 2026-10-11 同意用本机 `.env` 里的 DeepSeek 在线密钥跑真实模型测试。

## 密钥（严格遵守）
- 密钥在 `/Users/muyi/Downloads/dev/muspace/.env`，该文件不能 `source`（键名带连字符）。只用下面这条命令把它读进环境变量，**不得** `cat`、`echo`、打印、写入任何文件、提交或日志：
  `export MUYON_EVAL_MODEL_KEY="$(sed -n 's/^deepseek-apikey=//p' /Users/muyi/Downloads/dev/muspace/.env | tr -d '\r\n')"`
- 读完用 `test -n "$MUYON_EVAL_MODEL_KEY" && echo key-loaded` 只确认非空。
- 跑完立即 `unset MUYON_EVAL_MODEL_KEY MUYON_EVAL_REAL`。整个任务里不要运行 `scripts/verify.sh`、`scripts/ci.sh`。

## 步骤
1. 检出本分支，`flutter pub get`。
2. 在 `apps/muyon` 下：
```bash
export MUYON_EVAL_REAL=1 MUYON_EVAL_MODEL_ENDPOINT=https://api.deepseek.com MUYON_EVAL_MODEL_ID=deepseek-chat MUYON_WRITE_EVAL_REPORT=1
export MUYON_EVAL_MODEL_KEY="$(sed -n 's/^deepseek-apikey=//p' /Users/muyi/Downloads/dev/muspace/.env | tr -d '\r\n')"
NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/agent_eval_test.dart --plain-name 'real model'
unset MUYON_EVAL_MODEL_KEY MUYON_EVAL_REAL
```
   先保留现有代理设置跑；如果是网络连不上 DeepSeek，再按 `agent_eval.dart` 注释里的写法去掉代理变量重跑一次，并在回报里说明用了哪种。
3. 只跑一次，如实记录，不挑结果。失败也要回报失败信息（不含密钥）。
4. 生成的报告是 `docs/implementation/agent-task-eval-deepseek-chat.md`。提交前检查：用 `grep -c` 确认报告里**没有**密钥（`grep -c "$(sed -n 's/^deepseek-apikey=//p' /Users/muyi/Downloads/dev/muspace/.env | tr -d '\r\n')" 文件` 结果必须是 0，且这条命令的输出只有数字），没有本机绝对路径；端点只写到 `https://api.deepseek.com` 这一级。
5. 报告顶部写明：运行的完整提交 SHA、日期、口径（CR-5 指出：现报告的「首个响应」是首个模型事件或整包时间，不是界面首字；空样本显示「未观察到」）。

## 不做
不改代码；不调其他模型；原始日志不进仓库。

## 提交与回报
只提交这份报告，提交说明 `docs(eval): E-1 real model baseline (deepseek-chat)`，推到本分支，`git ls-remote` 确认。
回报：提交哈希；通过 / 失败；各类任务成功率与时延 p50 / p95（照报告抄）；是否用了代理；密钥检查 `grep -c` 的结果（应为 0）；已 `unset` 的确认。
