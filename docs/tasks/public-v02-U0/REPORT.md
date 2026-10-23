# PublicUI U0：可审阅文档切片与依赖阻断

2026-10-23，执行环境 Linux /workspace。分支 `task/publicui-u0-20261023`，隔离工作树 `/workspace/muyon-publicui`，基线为本轮 fetch 的 develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`。固定计划 `64900d4a6a46a9ef2919bcf922fb059413b1ce82`，视觉依据 `400e206135690c284c8402521e3135cfb7bfaee8`。原始 checkout 为旧 work/main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`，未作产品基线，未修改。

## 交付与当前状态

- [组件变体](../../design/public-services-v02/component-variants.md)：真实 Foundation 名称/值/完整源 SHA；局部 literal 与 proposed 公共尺寸分开；十族的尺寸、密度、禁用、加载、错误、焦点、可访问变体及页面去向。
- [页面验收矩阵](../../design/public-services-v02/page-acceptance-matrix.md)：八页面的真实/缺失入口、组合候选、七状态与 320dp/200%/TalkBack/减少动效待验格；代码、接线、实测三栏独立。
- U0 仅候选文档准备。designStatus=draft，publicservices codeStatus=absent，integrationStatus=not_connected，acceptanceStatus=NOT_RUN；具体外观设计 GREEN **pending**。已纳入最新用户“全部都要改”反馈：W1–W10 重审全套基础控件/卡片/菜单/弹窗/气泡，旧源码只复用机制，既有值不是视觉定稿。B 暂停旧候选合入。独立静态审查不代替用户认可具体变体与页面组合。
- U1 **BLOCKED_DEPENDENCY**；父任务已通知 C1 尚未实现，`848ad8bd3797b14008ba5a44e60f0737bfdf56f1` 仅阻断报告，不能当接口/fixture。未写产品代码、未造新公共 types/fixture。U2/U3 未开始，C2/C3/U1/U0 外观评审及 Shell 正式交接继续为 gate。

## 实际读取与判断记录

完整读取固定 U0–U3 计划、总索引及 v0.2 设计；读取既有 Foundation 源、CardModels.kt、ActionCards 组件结构与 README、cards runner、真实 MainActivity 页面去向/聊天/公共文档入口/阅读组件/科研及供应商入口、任务 README/REVIEW/状态/交接及 Shell 交接。/workspace 与 develop 树未发现 AGENTS.md。

Ruling：计划所称 `ui/foundation/` 实际为 `ui/system/`，文档引用实际路径，不迁移/修改原文件；若遗漏后续 owner 迁移，代价是引用需刷新，不授权另造 token。颜色逐项精确匹配当前源，bodyLarge 等未被 Foundation 覆盖的字阶不冒充已定 16sp。深色 action 为既有 #E5E5DF，仅盘点现状；W 系列对深浅色映射重新评审，未擅自改源码颜色。

只读核对原 Shell 候选 `07aeb5e45fda046446557f5083553ef2c885fc85` 报告，生产源 `d61be4b50c3f4877022008e5493ade1ba78a96ad`；未合入、未复跑其组件 fixture 或继承其“完整页面验收”。shellFinalSha 保持 pending，等待原 owner/父任务正式交接。400e206 全文规范已读，另实际核看图 02、08；未声称本轮逐图核看其余七图。

## RED / GREEN 与验证原始结果

U0 是计划规定的设计审阅 RED/GREEN，不是产品 TDD。产品行为 RED/GREEN 均 NOT_RUN。

| 项目 / 原始命令 | 实际结果 | 范围 |
| --- | --- | --- |
| 写文档前 Python Path.exists 审阅（完整脚本见下） | exit 0，列出两份文档 absent 及十族/页面验收 gaps；设计 RED | 缺口观察，不冒充失败的 Kotlin 行为测试 |
| `python3 /tmp/publicui-u0-evidence/check-docs.py` | exit 0，四条静态检查摘要 | 两 Markdown 链接/围栏/待验状态；10 palette 字段×2 模式；十族行；八页各三行。非视觉/产品 PASS |
| `git diff --check`（另含新文件暂存后再核） | 待最终暂存核验 | 源文档空白检查 |
| `bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh` | exit 127：line 8 kotlinc: command not found；**BLOCKED_TOOLCHAIN** | 未编译、未运行任何 cards 断言；不记 0 测试通过 |
| U0 具体设计 GREEN | pending，用户尚未认可本稿具体变体/页面组合 | 不填 PASS |
| U1 runner、Rust、Compose 编译、设备/TalkBack | NOT_RUN | U1 依赖未交付；本轮纯文档，无产品验收 |

设计 RED 原命令（在写入两文档前执行；原输出在 design-red.txt）：

```python
from pathlib import Path
paths = [Path('docs/design/public-services-v02') / n for n in
         ['component-variants.md', 'page-acceptance-matrix.md']]
for p in paths:
    if not p.exists():
        print(f'GAP {p}: absent; family variants/page acceptance not documented')
print('DESIGN RED: ten families lack reviewed dimensions/density/disabled/error/loading/focus/accessibility and actual public-service page entry acceptance.')
print('U0 visual approval: absent; acceptance NOT_RUN.')
```

本执行者 Library read/materialize 获授权成功后实际 view_image 核看原图 `libfile_84662ec2d4888191bc902a28cc593fa7`；它是独立组件截图，非产品。未遇 scope 拒绝，未绕过；不声称父任务已视觉核看。原图仅留 `/workspace/scratch/publicui-reference/rejected-menu-component.png`，不提交或发布。

原始日志留仓库外 `/tmp/publicui-u0-evidence/`，未提交运行日志。摘要 SHA256 在最终核验后补充。本轮静态检查脚本为仓库外一次性核验工具，不增加项目依赖或伪装公共测试。

## 本环境工具链事实

`shutil.which`：rustc/cargo/kotlinc/gradle/adb 均 ABSENT_IN_PATH；java=/usr/bin/java，python3 可用。ANDROID_HOME/ANDROID_SDK_ROOT/KOTLINC/GRADLE_HOME/JAVA_HOME 均未设；历史 `/tmp/muyon-tools/kotlin/kotlinc/bin/kotlinc`、`/workspace/ui-shell-tools` 及常见 /opt Android/Gradle 位置不存在；shared/downloads 为空。此结论来自本环境，不复制原任务缓存描述。未运行任何下载、安装或权限扩大，也不重复索批；后续工具安排交父任务。

## U1 独立测试准备（仅案例清单，尚未实施/运行）

待父任务交付正式 C1 接口/fixture 完整 SHA 后，逐项映射其 JSON 正反样本，不另建事实定义。优先序：

1. revision 精确往返 9007199254740993/u64::MAX，超界、前导零、符号、空/小数拒绝；大于 Long.MAX_VALUE 禁旧组件动作；UnixMs i64 两端及非规范输入拒绝。
2. 旧 page=1 → 公共 0，旧 page<=0 拒绝；多字节文本 UTF-8 半开区间精确，不能按字符数猜字节。
3. schema major/未知组件/action/approved 等安全字段，snapshot 修订不符、缺宿主 source 均 TextOnly；可读原答与零 dispatch 分别验证。
4. 256/257 节点、16/17 层、32/33 children、UTF-8 65536/65537 字节边界；重复 id、环、悬空节点的图校验。
5. 十族 sealed Props 一一匹配；Form keys/fieldTypes，Results 三列同位/唯一身份，claimRelation/saveStatus 白名单；模型不能自报 saved/complete 获信。
6. ValidatedPlan 只能由 validator 构造并持有不可变副本；模型与校验没有命令端口，fake command 计数恒零。

这些是既定 U1 计划的测试盘点，非冻结 C1 schema，不填 PASS。编译失败先标结构 RED；只有可编译后目标断言真实失败才是行为 RED，遵守总索引 gate。

## 审查与剩余阻断

非作者独立审查 pending，完成后记录固定源 SHA/审查人/发现与处置。未申请合入；B `01a14fbb-c8ec-7215-9b01-9c8cebf140d7` 保持唯一 develop 合入者。

剩余：U0 用户具体外观认可及 shellFinalSha；U1 C1 接口/fixture；U2 C2/C3/U1；U3 真实入口/Android 输入/设备与 TalkBack。没有拒绝或结果不明的写入，本轮缺依赖与缺工具未扩大权限。未触碰 main/develop、ChatScreen/旧卡片/Foundation/Shell、Contracts 登记文件；无真实模型、账户授权、凭据配置、付费实验、第三方程序下载执行、部署、强推或删分支。
