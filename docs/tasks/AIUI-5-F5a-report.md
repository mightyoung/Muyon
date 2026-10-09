# AIUI-5 F5a 交付摘要（draft / 未采纳）

执行分支 `task/aiui-5-contract-mapping`，冻结 develop `0466f113fd7dd41f99c38cef11eca428622a6fac`。F5a有限提案/映射/夹具基础片，**不表示F5b/c实现或AIUI-5总任务验收完成**。未修改正式schema、runtime、目录、export、store、旧测试或任务书；未合develop/main、部署、模型调用或业务写入。

## 来源核对与去重

- `git fetch origin develop` 得到 FETCH_HEAD 完整0466f113 SHA；本环境remote默认只追踪main，因此未误用不存在的origin/develop。
- 两份任务书与 `82df0f29d9628d107d96d52795438e972ce5fefe` 内容diff=0；该提交及 AIUI-1 `276b29146d3eb902380cceac708209cc6ef344c0`、AIUI-2 `4e45836efcb85c86f5c8de57e6b07795aab6166a` 均通过merge-base祖先检查。
- `git ls-remote --heads origin '*aiui*'` 开工只见文档分支、AIUI-1、AIUI-2，没有AIUI-5重复分支；独立task分支开工前远端不存在。不争用F3a或AIUI-4两个旧恢复文件。
- develop CI [37971444082](https://github.com/mightyoung/Muyon/actions/runs/37971444082) 首片开工时success来自派发消息、gh API403；后续已通过只读GitHub连接独立核实该run与完整0466f113 SHA为completed/success，不能作为本修订重跑结果。
- 已读项目brief/总览现行决定、HANDOVER-LEADER、ADR-0001、REVIEW、正式stream/1、AIUI-2接口交接和生产消费源码。无AGENTS/仓库skills文件。

## 可审交付

| 内容 | 文件 | 范围 |
|---|---|---|
| 待决契约 | `docs/design/aiui-binding-adapter-contract.md` | typed bool/finite number/date/item IDs、范围/step、collection专用registry与codec/限额/身份、Compare row详情、同版本原子构造和恢复拒绝；所有增补draft |
| 全目录映射 | `docs/fixtures/aiui5/component-mapping.json` | 33项真实继承/覆盖/loop schema；逐项源码路径/行号/hash、validator、Widget参数、route/localAction/consumer、payload、restore、fixture/未来验收 |
| 复算脚本 | `scripts/aiui5/check_artifacts.py` | Python标准库；只验证产物一致性与引用、JSONL结构/未来向量标签，绝不模拟生产validator或codec |
| 最小draft向量 | `docs/fixtures/aiui5/draft-vectors.json` | 53项future-only正负数据，含数值/日期/ID、集合五维N±1生成规格、row详情、版本混搭/缓存重标、恢复拒绝 |
| 正式契约金样 | `docs/fixtures/aiui5/string-projection.library-1.jsonl` | host metadata另由Dart输入；模型行仅引用已有fact/state/computed/action；正式compiler消费，需SDK实跑 |
| 独立基础测试 | `packages/muyon_ui/test/aiui5_f5a_contract_fixture_test.dart` | 11个测试调用现行API；公开host S7→S8构造、混版本拒绝、缓存重标诊断、string dispatch无自动重算、跨snapshot accept拒绝、现行typed/collection阻断、codec/override、whole-library fallback和stream final gate |

首片提交时新增11个Dart测试**本地未运行**；随后精确b2886075afb1c56289506d5ffc8e834116ba5254的[CI37974253299](https://github.com/mightyoung/Muyon/actions/runs/37974253299)已completed/success，8/8 analyze、8/8 suites，muyon_ui由基线311pass/152skip增至322pass/152skip。日志为套件聚合摘要；这证明远端套件实际执行，不能因本地缺SDK标成远端未运行。typed/collection vector是未来可消费测试数据，没有新的生产正例；公式乘积只是公开fixture构造，不是F3a公式registry或controller重算实现。

## 关键诊断与下游决策

1. catalog 33项、render源码12case、21项无case；surface build有catalog identity gate，**library-1整个表面走snapshotFallback**。清单不称library12组件可接入。新增Widget测试锁定当前门禁，待SDK运行。
2. Toggle bool edit现行edit_input；Compare rows/detail无value现行detail_input；集合/非finite计算与workspace collection override拒绝。原有boundary断言保持。
3. inputVersion相等不能识别旧20被改标S8；现行validator会接受该scalar。host必须以S8真实输入evaluate并比对dependency fingerprint、再构造I8/P12重validate，不能只改标签。
4. local事件在state/controller消费，host router对local直接return；业务submit/confirm无正式工具mapping时仍disabled。Compare row详情需要host registry/ObjectRef resolver与Widget callback后续共同采纳。
5. 采纳推荐组合：typed spec +专用collection registry+stable row payload+显式新catalog/codec能力版本，本轮明确独立collection kind，原fact/computed/uiState解析不变；必须另提并采纳stream/2，不因仍用kind/id外形宣称v1兼容。

## 实际验证与限制

| 命令/检查 | 实际结果 |
|---|---|
| `python3 scripts/aiui5/check_artifacts.py --write` 后同脚本无参数 | PASS：33schema/12源码case/21无case/library全surface fallback/53future-only |
| `python3 -m py_compile scripts/aiui5/check_artifacts.py` | PASS（初版后另有Python修改，最终独立复核见预审记录） |
| `git diff --check` / 新文件空白核对 | PASS；提交前重新检查 |
| `bash scripts/ci.sh` | FAILED at pub get：flutter command not found；0 analyze、0 test suites运行 |
| Flutter/Dart command availability | 两者本地不存在；上述suite本地未运行；远端首片已执行成功，结果单列，不将本地限制推广到远端 |
| SQLite/CAS/browser/设备/model/4变异 | 未运行；F5b/c/F4/设备任务未来验收，不适用本提案片 |

没有原始日志入库。现有验证入口/API源码已静态核对，不替代Dart compiler。推送可以触发现有Linux CI；GitHub API访问未获成功前不报告本片CI绿。

独立非作者预审按REVIEW已进行，发现并修正目录整体gate遗漏、动作消费分叉、JSONL结构检查和Chart fixture引用。正式leader审查/契约采纳/唯一集成仍待进行；预审不能代替合入批准。完整提交SHA和远端核对结果随执行回报提供。

## 评审修订：集合解析、Choice角色与计算实例（仍draft）

本轮仅提案/验证材料增量：

- 明确新增collection kind独占collections解析，三个既有kind不隐式查registry；collectionId与任一scalar namespace重名整批拒绝，不设查询优先级。该枚举扩展必须单独采纳stream/2，stream/1继续拒绝。
- 新增`collection-binding.draft.json`：具体host envelope和模型kind/id金样，10个future-only负例（3种scalar命名冲突、错误kind/未知id、cell状态与缺值引用拒绝）。新增Dart测试由现行parser/compiler实际拒绝同一collection模型行，未修改正式解析器。
- cell旁路`(itemId,columnId) -> stateId -> FactState/missingReason/valueRef/sourceRefs`；每cell关联当前host scalar fact/computation；金样10/verified与null/notDisclosed/not_disclosed并列，空字符串/无状态/无原因不能代替缺值。
- Choice host声明parameterEdit或viewSelection。参数编辑递增draftRevision，依赖公式时版本重算；纯浏览选择只改viewValues，不增revision/不重算。角色不能与formula/business依赖矛盾。
- 计算实例ID固定`host-total-instance`，Dart断言S7/S8不变；inputVersion随真实输入版本变化。

本轮产物检查PASS：33catalog schema、66future-only vectors、10个集合金样冲突/缺值负例规格、py_compile/diff检查。Python只核对金样一致性，未运行新codec或负例变异。本轮Dart共12测试，本地无SDK；本修订精确远端CI须按推送SHA另跟踪，不能沿用首片success代替。本轮未创建/绕过Draft PR、不改正式schema/runtime或AIUI-4旧测试。
