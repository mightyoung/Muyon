# v1.3.2 设备验证后置：四路可逆研发计划

状态：用户授权的开发顺序调整，四路实施中；派发不算交付或验收。唯一集成人 Leader B。
用户依据：2026-10-14 `Sentinel_b1d5319501b88191895d8130a270f3c2`「先不纠结真机，先继续做开发」；
`Sentinel_4f760d0b7ed8819191307ae2602debb8`「持续推进四个研发任务」。

## 与原计划的关系

本文是[原 v1.3.2 计划](../design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md)
M03/M06/M12/M15/M18 依赖顺序的实施补充；保留已核设计包原字节与 checksum。
取代此前「缺 Android runner 即暂停所有 Rust 与前端 writer」的实施限制。
正式 M03 全部出口仍未通过：状态 **blocked_contract**；Android actual load **NOT_RUN**。
缺设备不阻塞隔离纯领域、恢复单元和双端界面/mock 开发；设备/发布验收门不取消。

SPIKE 候选 `b17ac548f7a8d2d6151cbdaf6af527722c67ee50`（原交付 `206af7c41361a470ab241e9058d31b9bc9e1a931`，
固定实现 `bdbe0ed34fa48f9170436d3c3e44d870118ee381`）本轮 Rust18/Python10/8H1/JVM21paired 已复跑；
[候选回归 CI](https://github.com/mightyoung/Muyon/actions/runs/38528169445)登记时仍 in_progress。
只有终态通过且远端 develop 未改变才合入；失败则暂缓。四路本地工作可先从候选启动，
不会因分支基线存在 SPIKE 而称其已合入。既有有效测试复用，不重跑 OC 等旧审查。

## 实际任务、分支与所有权

以下目录均以 `experiments/redesign/device-deferred/` 为前缀。
工作区均为 `/workspace/Muyon-device-deferred-<lane>-20261014`，从精确候选 SHA 建立。

| 任务 / writer | lane / 任务分支 | 独占目录 | 独占任务文档 | 当前实施 |
| --- | --- | --- | --- | --- |
| RD-P01 / device_deferred_rust_domain | rust-domain / task/device-deferred-rust-domain-20261014 | rust-domain/ | REDESIGN-RD-P01-20261014.md | Rust 纯领域 normalization/read/edit candidate，無產品库/授权/FFI |
| RD-P02 / device_deferred_rust_recovery | rust-recovery / task/device-deferred-rust-recovery-20261014 | rust-recovery/ | REDESIGN-RD-P02-20261014.md | 同域游标与有界缺口、展示 epoch 与真实 receipt 分轴、unknown 零自动重派 |
| RD-P03 / device_deferred_desktop_mock | desktop-mock / task/device-deferred-desktop-mock-20261014 | desktop-mock/ | REDESIGN-RD-P03-20261014.md | Electron 适配源码与可运行桌面 DOM 界面、可替换 mock port、意图/冲突/未知状态 |
| RD-P04 / device_deferred_android_mock | android-mock / task/device-deferred-android-mock-20261014 | android-mock/ | REDESIGN-RD-P04-20261014.md | Kotlin screen-state/presenter JVM 验证、Compose 首片源码及 mock port |
| B | plan / task/device-deferred-plan-20261014 | 本文、原实验任务的顺序补充 | 本文 | 边界登记、固定 SHA 审查组织、唯一合入 |

四路不得写别人的目录，不共享 target/build 输出，不动 apps/packages/root 依赖、CI、旧 fixture/oracle、原设计包。
当前 agent 列表核无其他活动 writer；原工作区全部保留。后续新增 writer 必须核范围后登记。

## 可逆临时接缝与待冻结项

- Rust crate 均 unpublished、独立构建；纯函数/reducer 不持有生产数据库或授权签发权。
- 两端临时 `RustCorePort` 只由各路显式 mock 实现供开发，raw 原值送端口，不先 trim/NFC。
  前端状态可保留；未来正式生成合同仅通过 adapter 替换临时类型，不将当前端口注册为产品 DTO。
- 临时模式/范围/intent/receipt 输入必须是显式合成事实；DUT 不读取 expected/caseID 结果表。
  unknown 只能查账，不能自动重派；按钮点击或 mock 接收不等于真实业务提交。
- 待冻结：单一 schema 与编码/摘要版本、Unicode8/17实现等价、wire framing/类型映射、真实权限/事务/回执接口，
  Android ABI/4KB/16KB运行、原生加载/回调/释放、Compose进程生命周期、Electron可信桥接与正式包分发。
- 不改 M03 状态，不将 RD-P01/02/03/04 算成原 M06/M12/M15/M18 完整验收；52主用例、29/77分类与19/72恢复历史保留。

## 执行与独立门禁

1. 四路先真实 RED，再完成最小可实施代码与 GREEN。Rust/kernel 和 presenter/model 测试可无设备执行。
2. 领域/恢复采用有意义语义负例与必要逆变异；UI/mock 核 raw 完整传递、双击同意图一次、冲突保草稿、unknown 不重派、旧展示不抹真实 receipt。
3. 编译、模型/状态测试、真实渲染、原生加载、设备生命周期分开报告。没有 Electron/Compose运行依赖时明确 NOT_RUN，
   不因此不写可实施界面源码，也不把 Node/JVM 成功称桌面/Android运行完成。
4. 作者仅提交自己任务分支；非作者核精确 SHA、范围与验证后由 B 组合回归。安装、许可、账号、付费、模型、部署权限不扩大。
5. SPIKE 已有许可偏差原文与隔离记录继续保留；本批不接受任何新条款。原始新测试日志留仓库外，只脱敏摘要入仓库。
6. 设备可用后仍须真实双 ABI加载、错误/回调/释放、4KB/16KB与系统生命周期证据；发布门不能用 mock 或交叉 ELF 代替。

## 停止条件

重要行为失败、共写冲突、DUT借 oracle 造实际值、私密数据进日志、产品 schema 冒充冻结或需要新增许可/账号/资源时，
暂停受影响路线并回报；其他不依赖该问题的路线继续。未核事实维持 not_run/partial，不把剩余缺口整体标可跳过。
