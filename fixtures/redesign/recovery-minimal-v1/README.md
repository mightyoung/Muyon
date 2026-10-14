# D03a 最小恢复合成 fixture 输入目录

状态：**72子场景全部 `not_run`，无恢复runtime、无执行golden，待非作者审查**。依据已审合同 `40f3cddb6e62baa2374bde288120d2385cb14c3f` §8 的19组 D03A 标签；本目录将各组的正负/故障分支展开，没有新增第20组或主验收编号。

产品来源固定 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`；两册设计固定 `58fe9c62612d74a973614c41677e62a54332e6d6`。`recovery-scenarios.json` 顶层固定来源，group携带contract/two-book引用与既有验收映射，case含synthetic input facts/stimuli、expected required/forbidden observations、execution_status=not_run、actual=null、golden=null。

这里的JSON是**离线测试输入表达**，不是产品DTO、协议schema、可信证据格式或新状态机。事实字段、动作/期望标签只描述合同语义；M03单源仍须冻结具体字段/enum、数字范围、编码、摘要域、可信关联、错误和平台映射。未来实际runner需将输入映射至真实受测实现，并独立验证输出；不能把本文件的expected原样回显就计pass。

## 19组覆盖与边界

| group | 子场景数 | 覆盖 |
| --- | --- | --- |
| D03A-01 | 4 | 同域推进；错store/scope/stream大seq不混入 |
| D03A-02 | 3 | 重启seq保全；新stream合法bootstrap；拒旧流，不重铸intent/key |
| D03A-03 | 3 | 快照/缓冲覆盖、迟到旧快照、同水位分叉、独立草稿 |
| D03A-04 | 8 | 七崩溃边界及两事务原地内容/头指针反例；投影/durablecursor一致 |
| D03A-05 | 3 | 重复零二次应用、同身份异payload、缺口有界修复 |
| D03A-06 | 3 | 核心合法推进证据、无证据跳跃、权限收窄先清投影 |
| D03A-07 | 6 | 补拉失败/过期、快照残缺/环/摘要错/schema不兼容 |
| D03A-08 | 2 | 小测试buffer预算超限/未超限；事实先落盘与可解释resync |
| D03A-09 | 3 | 旧epoch展示/retract、真回执独立核对、renderer伪造拒绝 |
| D03A-10 | 1 | 已撤读权与当前新版本，旧真实效果仍保留 |
| D03A-11 | 2 | PendingInput独立身份与允许/不允许正文持久；不新设留存策略 |
| D03A-12 | 2 | 送达有/无可信受理证据；原消息与重复不创建第二消息/intent |
| D03A-13 | 3 | 响应丢失只读查回执、同intent重复、同key异参数/scope冲突 |
| D03A-14 | 2 | 真实新intent同规范名revision+1；换key不能冒充新意图 |
| D03A-15 | 2 | 提交前取消/提交后取消和导航关闭不回滚业务 |
| D03A-16 | 5 | 可证未派发/claim或未知/查不到/不可读；零自动重发 |
| D03A-17 | 8 | 真用户新意图关联与七伪发起对照；oldunknown保留 |
| D03A-18 | 10 | 五绑定变化重验、FullAllow纯风险零问、四硬前提拒绝 |
| D03A-19 | 2 | 历史prepared换stream与保全账本/账本缺失，不能推断零派发 |

72子场景不是新增72主case。既有52主case不增，A00 29分类子case继续not_run；这里每个局部场景也未执行。D03A-19仍为既有D03/D06/P3后续边界输入，不扩大首片实际恢复实现或真实数据测试范围。

## 合成证据、隐私与计数

所有store/scope/stream、用户指令、权限、能力、schema、策略、摘要、回执和正文均为metadata placeholder。正文不物化，没有真实user body、credentials、canary或外部地址。`trusted_issuer_fixture`/`evidence_valid`等仅说明未来可信测试注入前提，不能成为renderer自填approved的生产证据；实际runner必须通过真实核心/可信宿主入口构造或核验证据。

每个seq字符串只属于已授权投影流。没有原审计序号、隐含受限类型或隐藏计数输入；推进差值不表示隐藏审计数量。history complete也仅指许可覆盖完整。测试用buffer=2事件/64bytes只为可展开的小合成预算，不是产品默认；阈值测量/冻结仍归M03/M12。

D03A-12成功核对仅确认原消息一次，失败核对保持送达未知；额外重复确认消息计数为0。D03A-17新的合法独立效果可成功，原unknown不因新成功变已知；合成FullAllow仍核对scope/用途/真实能力/业务/CAS，纯风险零额外问。过程取消、导航关闭、旧epoch或历史缺口不消除已知效果与真实回执。

## 静态核查与未满足项

可在本目录执行 `sha256sum -c SHA256SUMS`。JSON解析、19组/72唯一ID、来源引用、完整cursor域与十进制seq、所有actual/golden=null、全部not_run及SHA256核验，只证明fixture材料结构与完整性，**不是实际恢复测试**。本次没有runner，没有模拟产品状态机，没有pass/fail运行数据。

D03a fixture非作者审查及真实合成恢复执行未完成；M03/M12 runtime、SPIKE-01实际加载与跨端协议证据等依赖保持。旧合同和旧证据保留；不安装/pub/Android/真实模型或模型服务，不设置MUYON_EVAL_REAL，不push/merge/main/deploy。
