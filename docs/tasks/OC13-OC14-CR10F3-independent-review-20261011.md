# OC13 / OC14 / CR10F3 独立组合复验

日期：2026-10-11。执行：dot 委托的独立验证者；只验证、报告和推 review 分支，不执行 develop/main 合入。

## 固定身份与组合方式

开工与变异恢复后两次 `git ls-remote` 核对：

| 对象 | 完整 SHA |
|---|---|
| develop | `2224c6faca32c28ebdaa148d741b1a618df87987` |
| task/oc-13-probe-throws | `c3fe22b5769016fc6e686f290213a52941dadb3f` |
| task/oc-14-update-value-semantics | `4b68b09be94463e19912e2469036e7435b3d4104` |
| task/cr10-f3-folio-taint-probe | `9f5216bb3768deb84522fb6c91415442f9ad6268` |
| 独立组合代码候选 | `cd3bb02d95f99c9f97c35d431c2c4976b6c3a52c` |

review 分支：`review/oc13-oc14-cr10f3-independent-20261011`。独立 worktree，原检出 `work` 与作者分支未改。
从固定 develop 顺序 cherry-pick 三个交付；OC13 / OC14 对应组合提交
`ef8803c974217de169a74ebe2506c87452684edb` 与
`19e59a94b64aa1b3f52dbf61748640c93513babe`。
CR10F3 最终提交的父链含 RED 测试 `b672b7465422ab42d10b1786b2de4e88e9c084c1`
及发送按钮 pump 修正 `f23eb63c6ac3131246669acb3573f264efa20b6c`，develop 不含该文件。
因此只摘最终提交会发生 modify/delete 冲突；本组合保留
`packages/inquiry_module/test/host_taint_probe_test.dart` 的固定源最终 GREEN 文件，
`git diff 9f5216bb -- <该文件>` 为空。进一步按交付文件逐个核对：
CR10F3 的全部 9 文件、OC13 测试文件及 OC14 测试文件都与各固定源逐字一致。
无逻辑编辑或删除测试以消除失败。

已读三个固定源任务书（OC13、OC14 任务书不在本 develop，按源 SHA 读取）、
`docs/tasks/REVIEW.md`、GB-1 不变量审计、CR-10 合入后审计、CR-11 值语义审计、
CR-14 设计及 ADR-0001/0002 和 ADR-0004 相关契约。
仓库与固定源树未找到 AGENTS.md / .agents/skills；`/workspace/.agents` 为空。
采用隔离 worktree 与 verification-before-completion 技能，委托明确授权覆盖旧文档中 leader 专属操作约束。

## 范围与交付核对

相对 develop：11 文件，963 additions / 15 deletions；OC13 仅原测试文件加 24 行，
OC14 仅新测试文件 282 行；CR10F3 为 7 个生产文件和 2 个测试文件。
不改事实读取 OC-11、已有 hosted 权限测试、2380 测试、门禁或 CI 配置。

| 交付 | 结论与依据 |
|---|---|
| OC13 抛错 → external；恢复 clean → live read clean | 满足；原文件 4 例含新增 2 例，本次通过且逆变异检出。仅锁当前 getter 行为，不证明旧 capture 恢复安全。 |
| OC14 未提供/null/空串/0/false/[]/空 values | 满足特征范围；7 例均真实宿主、真实选中、经 prepare/approve/invoke，重读 Store 与版本。省略保留、null/空串清空、0 保存、false 拒绝、[] 替换、{} 拒绝；公开七类型均无 boolean 字段。 |
| CR10F3 只读 probe 与身份核验 | 满足有界范围；`inquiry_plugin.dart:40` 先核真实 task/conversation，再核 facts 身份，unknown/抛错保守；runtime/attach 透传，Folio 无事实写接口。 |
| CR10F3 缺失/抛错/unknown/mismatch 与拒绝路径 | 满足；13 个包侧情形、10 个真实宿主测试及原 hosted 权限 5 例通过；网络 repeat 重新确认，拒绝后供应商不变。夹具模型，无真实模型证据。 |
| 生产真实 task/conversation 接线 | 部分；`apps/muyon/lib/app/adapters/inquiry_module.dart:80` 只传 probe，未传身份；`app_state.dart:99-110` 缺身份 → true → 强制确认。可接受安全退路，不能称完整身份接线。 |
| 作者原始 RED / 全量回报 | 不能独立追认为完整行为证据；RED12fail 含清理超时连锁，不等于 12 个独立拒绝行为。作者本机 2679pass/6skip/49fail（46golden、2load、1LAN）仅转交记录，不能写成本次全绿。 |

OC14 两项 M2 测试加强建议（不改作者分支，不阻断现有特征测试）：
`oc14_update_value_semantics_test.dart:8-12` 的 false 说明应注明 schema 已拒绝，未进入 normalizer；
两个负例 `:241` / `:276` 应进一步钉 `ToolPlatformException.code == invalid_parameters`。
目前只钉异常类型，但随后仍重读 payload 与 version，不能把该弱点夸成已发现业务失败。

## 本次验证

Linux x64，Flutter 3.47.5（官方 tag `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`）、Dart 3.13.4。
安装 SDK 和缓存在仓库外；pub get 生成的三个 analysis_options 改动已恢复。
PDFium/SQLite 原生资产先按官方 hook 经环境代理下载，再取消代理运行 localhost 测试；
前两次原生资产下载失败发生在加载前，属于环境失败，未作为行为测试计数。
未导出 `MUYON_EVAL_REAL`，未跑真实模型、Android、部署。

目标命令从 `apps/muyon` 执行：
`flutter test --no-pub --reporter expanded ../../packages/muyon_ui/test/dynamic_external_content_default_test.dart test/oc14_update_value_semantics_test.dart test/inquiry_host_taint_probe_test.dart ../../packages/inquiry_module/test/host_taint_probe_test.dart ../../packages/inquiry_module/test/assistant_permission_hosted_test.dart`。
首次 GREEN 与全部变异恢复后 GREEN 均 **39 pass / 0 skip / 0 fail，exit 0**。

| 临时逆变异（每次一处，finally 恢复原字节） | 检出结果 |
|---|---|
| OC13 surface getter catch 返回 false | exit 1，2pass/2fail；`surface_probe_that_throws_treats_content_as_external [E]`，Expected true / Actual false；恢复 clean 的另一新增例也失败。 |
| OC14 update_record 的 allowClear true → false | exit 1，6pass/1fail；`explicit null clears contact phone and quotation notes [E]`，Expected succeeded / Actual failed。 |
| CR10F3 host probe 的 facts.requiresConfirmation → false | exit 1，6pass/4fail；真实 external acceptance live read、unknown facts、runtime 透传、真实 tainted 写入提示均检出。 |
| CR10F3 host probe catch null → false | exit 1，9pass/1fail；`real host probe read failure remains unknown and requires confirmation [E]`，Expected null / Actual false。 |

三个相关包 `flutter analyze --no-pub --fatal-infos` 均 exit 0、No issues found。
`muyon_ui` 全量 **380pass / 152skip / 0fail**；152 skips 为两套 macOS-only golden。
当前 `muyon_module_api` 全量 **250pass / 0skip / 0fail**；这覆盖了 CR10F3 较旧 source CI 的 198 例未包含的当前契约增量。
全部变异后产品路径 `git diff HEAD -- apps/muyon/lib packages/inquiry_module/lib packages/muyon_ui/lib` 为空，
报告写入前 `git status --porcelain` 为空，`git diff --check` 通过。原始日志只在 /tmp，不入仓库。

## 精确 CI 与合入条件

固定 CR10F3 [source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069)
核对 headSha 为 `9f5216bb3768deb84522fb6c91415442f9ad6268`，completed/success；不是组合结论。
固定 develop 的 [CI 38130983896](https://github.com/mightyoung/Muyon/actions/runs/38130983896)
completed/failure：host 1688pass/3skip/1fail，`personal_agent_streaming_test.dart` 的全文
`not contains 2380` 元数据偶撞；为委托已知基线，未重复修改，修复归其他活动 writer。

独立组合 [CI 38133907362](https://github.com/mightyoung/Muyon/actions/runs/38133907362)，
headSha 为 `cd3bb02d95f99c9f97c35d431c2c4976b6c3a52c`。
**终态 completed/success**，job `114453716726`，2026-10-11 11:18:25 UTC 完成；
8/8 analyze、8/8 suite、门禁脚本、doctor 23 场景、coverage、Laya 步骤均成功。

| 组合 CI 套件 | pass | skip | fail |
|---|---:|---:|---:|
| module_api | 250 | 0 | 0 |
| muyon_ui | 380 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 220 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 1706 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |

合计 3410pass / 207skip / 0fail。Linux 平台/字体与真实模型的 skip 不算相应能力验收。
2380 已知基线误报本次未触发，不能据此称该测试已修复。
完成时再次 ls-remote：develop 与三个作者固定 SHA 均未变。

**建议可合入这三项有界交付**：目标与必要逆变异、最新 develop 组合 CI 均已通过；
OC14 M2 建议交 root / 后续测试 owner 小修，不改作者固定交付。
CR10F3 当前宿主缺身份时强制确认可接受，但完整 task/conversation 身份接线与非宿主污染继承仍未覆盖；
不声明 CR14 或整个 AIUI 验收完成。实际合入若基线移动，须在新基线重新组合验证；
不要仅 cherry-pick CR10F3 最终提交而遗漏其新增测试。

本报告提交为纯文档，使用 `[skip ci]` 避免为同一代码重复全量门禁；
CI 证据严格属于上述代码候选 SHA，不把文档提交冒称已受测 SHA。

本验证者不合入 develop/main，不改作者分支，不 forcepush/delete/deploy。
