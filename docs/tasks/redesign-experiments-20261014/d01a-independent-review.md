# D01a可执行接缝实验非作者固定SHA复审

固定提交 `ad548c35552fba74946827bc9cb5068d9ccc128d`；base develop `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`；作者branch `task/leader-b-d01a-contract-experiment-20261014`，worktree `/workspace/Muyon-leader-b-d01a-experiment-20261014`。固定终态登记输入8f8edf、设计58fe、合同99c4d与v1分类7a8128/I03为依赖，不把报告提交当受测产品实现。

**C=0，experimental-only可接收。** 本结论只接受原字节Python stdlib材料准入/模式路由接缝和当前purpose表示实验，不能作为产品分类器、权限issuer、真正扫描、派发、29wholecase/52主验收或M03冻结证明。

## 实际独立验证

以git archive固定ad548c原字节在仓库外`fixed-ad548c/`保持目录布局，读取固定v1；没有运行作者工作树文件、改作者文件或派生v2目录。未加`--derive-purpose-v2`，正常输出/日志都在本报告目录。环境CI=true、PYTHONDONTWRITEBYTECODE=1，移除MUYON_EVAL_REAL；零网络、安装、新依赖、真实数据/secret/model/Android/设备。

1. 完整unittest实际exit0，**33 tests**。正常矩阵exit0，逐case/variant/actual与提交`results/observations.json`对象完全一致：29case、77variant，**61 partial_experimental、16 not_run、0局部比较差异、whole_case_pass_count=0**。
2. 原driver `--mutate-expected`实际exit1、1比较差异；正常与负对照77个DUT actual完全一致。另独立逐行反转当前purpose expected并改变case/variant身份，全部77行actual不变；61已执行行全部检出当前资格期望反转，16明确not_run仍不伪造对照通过。对77行直接注入forbidden expected，DUT均ValueError拒绝。
3. 三语义逆变异实际在外仓临时副本执行：绕过actual-value检查、令FullAllow依赖Auto规则、降商业来源类别。三子进程均exit1，32 tests，分别1/4/1断言失败；指定test检出，非ImportError/语法错误。变异检查器exit0表示成功检出逆变异，不能误写mutant运行成功。随后原源码再次33tests exit0，恢复GREEN。
4. 原作者run-summary列出的RED/green/matrix/negative/mutation原始日志哈希全部验证。RED包括空seam20tests/24断言失败、driver26/5、未知source21/3、source规则/readOnly model23/3、变异编排1/1及谱系证明26/3；都是缺行为的实际AssertionError。非作者在实施中也读到空comparison占位后实现，不把导入失败当TDD RED。固定代码7项摘要哈希匹配。
5. 相对base仅16新增预留路径，全在experiments/redesign/d01a-contract、fixtures/redesign/classification-purpose-v2和本任务文件；diff检查通过，作者worktree干净。v1原33文件与7a/base逐字节一致，29/77原not_run、14拟定规则、52主not_run不变。v2三项SHA256SUMS实际通过。

机器proof、命令exit、mutant指定断言与日志路径见`proof.json`；逐77行反事实证据见`counterfactual-proof.json`；可复现外仓复跑脚本`independent-check.py`。旧首批M04/M05/OC测试没有重复运行，本review未写任何作者分支或产品。

## 接缝独立性与I03

`fixture_adapter.py`只深拷贝input/source/current-version/purpose/rule-coverage/actual-check/mode/prerequisites八个输入区块。DUT不读取fixture文件、expected、case_id、variant_id，嵌套oracle/身份亦拒绝。`driver.compare_variant`实际先调用DUT才读取独立v1预期，Guarded访问顺序测试与本独立预期扰动确认；没有expected拷贝进actual、按case编号查结果表或补出缺失stimulus。

v2 77记录与v1一一对应，stimulus逐对象等于allowlist拷贝，仅oracle投影该variant当前purpose资格，noncurrent为not_applicable、action_result另栏，并显式eligibility_does_not_authorize_dispatch。DUT实际输出material单current-purpose与route分轴，dispatch_performed恒false。资格可在Auto high/prohibited/unfrozen、CAS硬拒绝时eligible，而route等待/拒绝/blocked；未把材料资格当dispatch/grant。I03在本实验表达层落实，不因此冻结生产wire DTO或M03权限表示。

## C/I与产品边界

- **C=0。** 没有发现oracle依赖、预期回显、编号返回表、全案例PASS、真实credential扫描或M03冒进声明。预审的缺省/未知source_kind支持域漏洞已先实际RED后加支持集并GREEN；派生/template专属覆盖、未知继承Sensitivity/缺source版本/未知用途条款也有对应RED及闭合测试。
- **I-01：61条仅检查注入事实的组合，不能称actual classifier。** `actual_value_check.signal/state`、规则/来源/版本/权限/CAS等是host metadata assumption输入；输出sensitivity_context/attempt只表示实验路由，不证明这些事实真实。没有扫描raw credential、实际14规则、解析附件、NFC/跨端Unicode、可信source或policy issuer。字段声明与检查相结合、来源继承/禁用途、当前版本引用匹配这些逻辑已实验，但真实证明构造与覆盖/误报漏报仍缺。未来接真实host必须独立验证事实，不能直接信任renderer传入valid_assumption/evidence_current。
- **I-02：授权与效果机制未实现。** finite假期限仅做实验时间比较，未签发/消费ModeGrant、持久dispatch边界或事务、最终wire/payload/日志投影、DB/EffectReceipt/unknown恢复。FullAllow对纯风险不依Auto规则，本机最小当前用途不等全部14；必要actual-value/声明/来源/权限/CAS缺仍停。readOnly model缺独立授权为blocked_contract，未误设完全联网禁令。上述都不是实际grant或已写入，route eligible不能被集成器直接解释为生产派发许可。
- **I-03：16分支保留not_run。** 两非supplier字段、四派生转换、两模板、五裁剪/留存/重放、两新内容/新规则及一权威replay分支按input特征停，具体缺机制原因保留，不能看expected决定支持。后续新增真实接缝必须再独立验证，不能仅把expected填到actual。61执行比较也只校验当前材料布尔与有限route facet，不校验全部旧expected内容或实际全链golden。
- **I-04：M03/native gate继续blocked。** 仍需真实D01a输入证明/分类检测与能力消费/日志出站、D03a真实恢复机制及故障证据、M04/M05跨端Unicodeoracle、SPIKE-01真实Androidload/双传输/错误回调释放以及唯一schema/编码选型。当前没有产品CI覆盖新Python实验；旧CI不能升级这些实验为新架构验收。

B可在精确SHA登记本C0experimental-only与I范围，按已授权两路合同实验继续正常集成验证。无需重复原23单元盘点、首批/OC旧测试或重问用户已定四档/FullAllow决定。29wholecase与52主仍not_run，14仍proposed_unfrozen，真实模型/数据/设备边界不扩大。
