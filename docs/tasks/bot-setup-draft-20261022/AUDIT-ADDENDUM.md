# 原始证据追加：新离线复验，不回填旧结果

2026-10-22 UTC。父侧要求补充可审计的作者/非作者11项结果与五变异原始输出。该明确追加授权优先于旧报告“不提交原始测试日志”的历史记录；本次只新增本报告目录内容，不改生产代码、测试、导航或构建。

## 原记录可恢复性

原作者 GREEN、非作者 GREEN 与五变异的 stdout/stderr 当时仅出现在会话工具输出，未保存为日志文件，当前无法恢复其原始字节。旧 jar、变异源副本和审查摘要不能替代原始运行日志，因此没有将新日志称作旧记录。

可恢复内容：原 `/tmp` 中三个编译 RED 日志与旧变异驱动，已按字节复制到 `evidence/original-red/`；`inventory.json` 记录 SHA256、大小、保留的文件 mtime 与本次采集时间。旧 mtime 不是独立可信时间戳；驱动不是执行输出，RED 文件也不补造未保存的旧退出码。

## 新复验范围与命令

新复验基于提交 `79cf88974f6a44cb8e30df0e81d827a9376303b1`；组件/测试源与已独审 `f9920c75b05904ab54250c2c65cc6dca3db27390` 相同。本次 HEAD 只有后续证据变更，未重新宣称历史运行通过。

作者新运行：

```sh
python3 docs/tasks/bot-setup-draft-20261022/evidence/capture-author.py \
  --compiler /tmp/bot-setup-tools/kotlinc/bin/kotlinc \
  --output docs/tasks/bot-setup-draft-20261022/evidence/author-rerun
```

`capture-author.py` 先执行原 `run-offline-checks.sh`，原样保存作者11组结果与stderr，再在临时副本运行五项变异。每个变异均独立编译、要求编译成功，再要求 JVM 因行为断言非0退出；编译错误不能算检出。副本不修改仓库源，运行后删除临时jar/源码。确切变异文本、替换次数与副本源hash见metadata。

非作者在独立上下文执行原脚本：

```sh
KOTLINC=/tmp/bot-setup-tools/kotlinc/bin/kotlinc \
  apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh
```

非作者自行采集 `evidence/independent-rerun/` 日志与环境元数据。它是新的独立复跑，不是旧日志恢复，也不代替完整产品复审。

## 证据索引

- `evidence/author-rerun/baseline.stdout.log`：作者原始11项输出；stderr单独保存。
- `evidence/author-rerun/*-compile.*.log`、`*-run.*.log`：五变异的原始编译与执行输出，包括触发失败的栈和断言行。
- `evidence/author-rerun/metadata.json`：完整命令、输入源/测试/脚本SHA256、JDK/Kotlin版本日志、UTC起止、退出码、五变异规则与各输出SHA256。
- `evidence/independent-rerun/`：非作者原始输出及独立采集的命令/环境/hash记录。
- `evidence/SHA256SUMS`：全部新增证据（除清单本身）的校验清单。

上述环境记录只捕获工具版本和公开源码路径，不导出环境变量、凭据、用户数据或原unknown台账。仍是离线、单owner内存组件验证；未构建APK、未做设备/持久恢复/正式创建验收，未触发真实模型/搜索请求或修改旧预占。

## 本次实际结果

- 作者新复验：2026-10-22 03:54:47.472993–03:55:28.808751 UTC；baseline exit0，11/11 PASS；五项变异均 compile exit0、run exit1，原始stderr包含对应行为断言失败。
- 非作者新复验：2026-10-22 03:55:08.577016–03:55:16.421678 UTC；exit0，11/11 PASS，stderr为空。metadata SHA256：`7f224a83979ac7ec9c56bfc7e772b716437b5164781feea3541b7677a3180766`。
- 作者和非作者 baseline stdout 字节一致，SHA256：`3917e3e515a15c3ed7f6ee46bdadfa63d7e5cf7e90ef25cc14e369394b544098`。
- 新增41个证据文件的SHA256已入清单，另含清单本身；源/测试/原脚本与固定HEAD字节相同。未用新跑结果冒充原始历史日志。

从仓库根目录验证清单：

```sh
(cd docs/tasks/bot-setup-draft-20261022/evidence && sha256sum -c SHA256SUMS)
```
