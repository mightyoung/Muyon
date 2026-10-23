# PublicUI U1：固定上游读取、测试准备与工具阻断

日期2026-10-23。分支 `task/publicui-u1-preparation-20261023`，隔离工作树 `/workspace/muyon-publicui-u1`。起点为本轮重新fetch的develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`，工作树/该树未发现AGENTS.md。未用旧main或Contracts未审候选作产品基线。

已接父任务C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`、C2 `b626c18a5dff184519e59bb866e5ed37362ac84e`、C3源码 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`、最终证据 `4d49a580cb518d9b0b80c9df3df1ff564194a639`。完整读取三份REPORT、types.rs/commands.rs/drafts.rs、三份JSON fixture、C1 public_service_types测试，以及Revision/DocumentRef身份校验和严格JSON查重入口。上游619次测试/严格Clippy是owner报告，本环境没有复跑，不称其已合develop。

## 交付

[TEST-DESIGN.md](TEST-DESIGN.md) 固定共享fixture摘要及逐例消费目标、8case/6身份向量、codec精度与严格字段规则、UIPlan后续RED顺序及缺失共享source fixture。不复制/新增公共类型或共享fixture，不定义Money/Quantity/phase新规范，不修改Contracts登记，不进入U2/U3。

依赖状态已从缺固定C1更新为C1候选已收到，当前仅测试设计可独立推进；U1产品codeStatus=absent，结构RED=NOT_RUN，行为RED/GREEN=NOT_RUN。U0 `98aed744ab1b920cea4575115a64d1e2223ade2a` 仍视觉draft，不能沿用被否决外观。

## 本环境实际验证

| 命令/动作 | 结果与范围 |
| --- | --- |
| `git fetch origin develop`；`git rev-parse FETCH_HEAD` | exit0；仍fd26dcdabcdac996bc2881e8141cac2b519966fc |
| `git fetch origin task/public-contracts-v02-20261023` | exit0；取回固定4d49a580；仅只读git show，未merge/cherry-pick |
| Python hashlib + json读取固定fixture原字节 | exit0；三个摘要匹配上游REPORT，major=1/1；types与C1原SHA逐字节一致，8cases/6vectors，正例原JSON与expected结构一致 |
| `bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh` | exit127；line8 kotlinc: command not found；未编译、未执行断言，不是行为RED |
| `shutil.which`及已知缓存路径核对 | kotlinc/cargo/rustc/gradle/adb均不在PATH；java=/usr/bin/java，Python可用；旧Kotlin路径和ui-shell-tools不存在，shared/downloads为空 |
| Markdown链接/围栏、固定fixture名称映射与diff-check | 待最终文档核验；只是静态检查 |
| U1 runner / Kotlin codec / PlanValidator / cards断言 / Rust回归 | NOT_RUN；未写无法编译验证的产品代码、未建立返回假的测试桩 |

工具链阻断的精确动作：运行原cards离线runner；目标为Kotlin编译；原因kotlinc缺失；outcome=exit127，尚未启动编译。不是审批拒绝。用户未授本线安装权限，未下载/安装、配置凭据或扩大权限，不重复索批。

原始日志留仓库外 `/tmp/publicui-u1-evidence/`，不入库：

| 文件 | SHA256 |
| --- | --- |
| fixture-inventory.log | `2008539a10172ce7ba690cba6fc4ab637d18c24df46cebbbe7fc66291be91751` |
| toolchain.log | `58eab03d70500f383731143bc07d49ac91befcd3359cb7166ba56ad7608355d4` |
| cards-toolchain.log | `826d09fafa248c16d8ec1b0e3ca191f38e8efdd2f2c75c00f2d023123502a4ed` |

Python只核验固定输入的字节/JSON元数据，不实现另一份业务codec，不证明Rust/Kotlin校验通过。原始记录中的每项测试计数来自上游或实际静态盘点，未执行的产品测试不填PASS/0失败。

## 未决项与交接

当前工具缺失阻断U1编译、行为RED/GREEN及回归；后续由父任务安排已有获授权可用工具，不能自行套用Contracts的Rust安装授权。C1缺少呈现/来源区间共享fixture的部分已列清单，向owner提出而不猜语义。Contracts候选仍待B独审/CI/合入，U1生产入口关闭；具体U0设计、C2/C3消费接线与Shell交接仍为U2/U3前置。

只交两份任务文档；没有ChatScreen、旧卡片、Foundation、Shell、services/mod.rs、core lib.rs或FFI改动。无真实模型/付费实验/Connector授权/第三方程序执行或新依赖。当前没有拒绝或结果不明的写入；独立审查pending。仅正常push独立候选，B保持唯一合入者，不创建合入/部署动作。
