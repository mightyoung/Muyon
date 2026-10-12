# Linux 验证证据收集

`scripts/linux_verification_evidence.py` 使用 Python 标准库，把调用方显式提供的
日志、退出码和候选提交汇总为 `manifest.json` 与中文 `summary.txt`。它不运行
Flutter、Dart 或应用，不扫描目录、不联网、不上传、不读取环境变量或凭证。
系统和工具版本由本次验证的操作者提供，脚本不会自动执行命令探测。

检查固定基线 `9d8a4118de74cda369ddd004c519d01a1e0752ba` 后，现有
`scripts/package_artifacts/package.py` 负责构建产物打包，`scripts/verify.sh`
负责执行验证门禁；都没有 Linux 启动、交互证据收集能力。本工具独立收集结果，
不修改或替代这些脚本与现有 CI。

## 输入与运行

本机新建输入 JSON，例如（所有示例都是手写合成数据）：

```json
{
  "candidate_sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "system": {"os": "Linux", "release": "6.8.0", "architecture": "x86_64"},
  "flutter_version": "Flutter 3.35.4",
  "dart_version": "Dart 3.9.2",
  "stages": {
    "unit_widget": {
      "log": "unit.log",
      "exit_code": 0,
      "command": ["flutter", "test", "--no-pub"],
      "started_at": "2026-10-12T01:00:00Z",
      "ended_at": "2026-10-12T01:01:00Z",
      "expected_cases": ["suite"]
    }
  }
}
```

日志路径相对于输入 JSON 所在目录解析，也可显式提供绝对路径。只读取列出的
文件；每个输入最多 10 MiB，仅接受普通文件。拒绝日志文件符号链接、`.env*`、
常见凭证文件和凭证目录，也检查解析后的目标路径。不要把凭证文件改名后当日志
提供。原始日志和完整命令输入保留本机，输出不复制它们。

```sh
python3 scripts/linux_verification_evidence.py --input /explicit/input.json --output /explicit/new-package
python3 -m unittest discover -s scripts -p test_linux_verification_evidence.py
python3 -m py_compile scripts/linux_verification_evidence.py scripts/test_linux_verification_evidence.py
```

输出目录必须是新目录；已有目录不会覆盖。CLI 退出码 0 表示证据包生成成功，
不表示验证通过；应检查 manifest 各阶段 `status`。输入 JSON 无效、不可读或
输出失败返回 2，终端只打印固定错误说明。

## 判定契约

阶段分为 `unit_widget`、`linux_build`、`linux_launch`、`linux_interaction`。
每个阶段都需要独立日志、退出码、命令参数数组、带时区的开始/结束时间以及非空、
不重复的 `expected_cases`。同一日志可以显式用于多个阶段，但其中记录必须匹配
该阶段和候选 SHA。交互通过还要求启动阶段通过。

日志应由测试包装器或人工验证者在完成核对后追加独立 JSON 行，例如：

```json
{"evidence_version":1,"candidate_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","stage":"unit_widget","case_id":"suite","outcome":"passed"}
```

`outcome` 只接受 `passed` 或 `failed`。人工交互的 case 应对应预先约定的操作与
可观察结果；操作者在实际执行并观察后才写入记录。脚本不会从自然语言、
`All tests passed` 或退出码 0 推断交互成功，也不使用模型判定。

非零有效退出码或匹配候选/阶段的失败记录产生 `failed`，包括同一 case 先通过
后失败的冲突记录。其余情况下，所有预期 case 均有匹配通过记录、元数据完整且
系统为 Linux 才能产生 `passed`。缺失文件、零记录、少 case、错误候选、错误阶段、
无效时间或未知工具版本均为 `unknown`。失败退出码即使缺失日志仍记 `failed`，
日志缺口仍通过安全 `error_code` 和缺失 hash 可见。

这些是调用方提供的结构化观察，不是独立运行证明。manifest 明确标记
`evidence_origin=caller_supplied_not_independently_verified`；SHA256 可核对保存
的输入文件字节，不能证明日志真实、应用启动或人工操作真实发生。

## 脱敏和核对

manifest 仅保留固定阶段名、状态、安全错误码、候选 SHA、提取后的数字版本、
允许的系统/架构值、时间、退出码、计数与摘要。日志记录原始字节数及 SHA256，
不输出日志路径、文件名或正文。命令保留少量固定工具/参数词，其余每个参数
变为 `[redacted]`；完整命令的 SHA256 采用 UTF-8 编码的
`json.dumps(command, ensure_ascii=False, separators=(',', ':'))` 计算，便于本机核对。
摘要仅显示固定中文文案、候选 SHA 和各阶段状态，不含用户路径、端点或密钥。

上述最小示例的中文输出为：

```text
Linux 验证证据（调用方提供，未独立核验）
候选 SHA：aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
单元/组件：passed
Linux 构建：unknown
Linux 启动：unknown
Linux 交互：unknown
原始日志仅留本机；unknown 表示证据不足。
```

独立测试覆盖缺失输入、失败、部分完成、阶段隔离、候选不匹配、取消式缺失、
不完整时间、冲突记录、原字节 hash、敏感 canary、凭证拒读、符号链接、体积边界、
CLI 输出及已有目录不覆盖。本次仅在 macOS 上以合成 Linux 数据验证收集器；
不构成 Linux 构建、启动、交互或发布验收。未接真实模型、文件选择器、生产工具，
未安装系统依赖或部署。

## 本次脚本验证记录

RED 提交 `69f58de94128e90352ec47908bf53a636776a355` 只有独立测试。
运行 `python3 -m unittest discover -s scripts -p test_linux_verification_evidence.py`
返回 1：因待实现脚本不存在而 `FileNotFoundError`，之后才新增实现。

最终同一命令返回 0：19 项通过。`python3 -m py_compile
scripts/linux_verification_evidence.py scripts/test_linux_verification_evidence.py`
返回 0。现有相关脚本回归：

```sh
python3 -m unittest discover -s scripts -p test_verification_gates.py
python3 -m unittest discover -s scripts/package_artifacts -p test_package.py
git diff --check
```

分别 10 项、26 项通过及差异检查通过，退出码均为 0。独立只读审查最终没有
未解决问题。这些检查未运行 Linux 应用，也未安装依赖。

补充反向变异在内存中替换源码后运行真实 unittest 断言，磁盘实现保持原样：

| 变异 | 对应测试 | 结果 |
| --- | --- | --- |
| 去掉 `passed_count == len(cases)` 判定 | `test_exit_zero_and_plain_log_do_not_prove_interaction`（先有启动证据） | 1 项失败，0 错误 |
| 命令投影改为 `list(command)` | `test_hashes_exact_bytes_without_copying_raw_log_or_secrets` | 1 项失败，0 错误；抓到 canary |

第一处变异最初没有被抓到，因为测试同时缺启动证据，仍会得到 unknown。
测试已补上通过的启动记录，隔离了交互证据不足这一条件；再次变异后成功失败。
最终在未变异的磁盘源码上重跑全部 19 项，均通过。
