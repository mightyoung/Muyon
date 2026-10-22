# 新架构活动入口切换与旧 Flutter 退役 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 当前仅供父审，未获本方案实施授权；唯一合入者不变。

**Goal:** 默认开发/验证/构建入口转为原生Android/Rust，保留不可变旧证据及独立Laya门禁，不宣称完整业务/全平台替代。

**Architecture:** 先固定历史源和依赖闭包，再抽离独立门禁，然后在单独可回滚提交切换活动入口；最后分批移除已无生产/测试依赖的旧运行树。旧失败保持FAILED，不用更名、删check或baseline下降把214变绿。

**Tech Stack:** 现有Rust workspace/UniFFI、Kotlin/Compose/Gradle、GitHub Actions；Laya现有离线Python测试保留，与Office Rust引擎无关。

**Spec:** `../specs/2026-10-22-active-entrypoint-retirement.md`

## Global Constraints

- 固定审查214/develop0ab2；本方案不修改冻结214，不执行merge/main变更。
- 不改coverage baseline/阈值，不重跑被拒artifact；I04仍NOT_RUN，不能跑含它的suite。
- 无真实模型/搜索/Office运行、凭据/付费/安装/部署/权限扩大；工具恢复授权另行取得。
- 新空库可接受；不清用户文件、不卸载旧包、不自动导入旧身份或回放旧intent。
- 三个experiments Rust core path保留；Rust/Android全量门禁及模型许可/包体条件不减少。

## Review Focus

1. legacy失败使Laya未执行：抽离后测试失败必须独立挡住gate，不能因Flutter状态跳过。
2. 删除旧树破坏include_str或oracle：先固定历史fixture闭包，缺文件/hash篡改真实失败。
3. 检查脚本默认启动联网doctor/Flutter：新默认只读本地检查，不读用户key、不联系模型。
4. 回滚覆盖/删除新旧用户数据：回滚只恢复入口代码，不删库、不改包ID、不假设可跨签名覆盖。
5. 新入口被误称全平台：桌面不可用/业务未迁移明确拒绝，设备NOT_RUN不能继承编译绿灯。

---

### Task 1: 历史源与依赖清单封存（独立审查提交）

**Files:** Create `docs/architecture/active-entrypoints.json`, `docs/legacy/flutter-retirement.md`, `docs/legacy/source-manifest.json`; 保留原docs/tasks及覆盖失败记录。
**Interfaces:** manifest字段schema_version=1、legacy_source_sha=214完整SHA、active_product_sha、frozen_oracles[{source_sha,path,sha256,dependency_manifest}]、statuses[{run,source_sha,tree_sha,status}]。状态保留FAILED/NOT_RUN，历史不可算active pass。

- [ ] 用git对象构造旧Flutter依赖清单：packages全树、apps/muyon、apps/muyon_ui_preview、rootpubspec/lock、六workflow、ci/verify/doctor/打包脚本、全部Dart oracle闭包；逐文件SHA256/size，指向不可变214，保留已有更早oracle自带pin。
- [ ] 写清三条运行路径：active Android/Rust；historical Flutter明确显式选择固定SHA才可执行；Electron不可作为生产默认。旧询价/报价/桌面缺口列未迁移，不生成等价假承诺。
- [ ] 验收：manifest缺文件/错SHA反例必须失败；当前coverage失败与历史状态不得被schema标成success。无需安装SDK或构建旧应用。
- [ ] 父审历史可恢复性及已知差异后独立提交；原候选/原worktree不reset/clean。

### Task 2: Laya独立门禁（不依赖Flutter，可独立拒绝）

**Files:** Create `.github/workflows/laya-offline.yml`, `scripts/check_laya_offline.sh`, `scripts/test_laya_gate_contract.py`; Modify旧ci/verify仅在后续入口切换提交移除重复step。
**Interfaces:** `scripts/check_laya_offline.sh` 无参数，从固定repo工作目录运行四测试；任一非零返回非零。稳定必需job名`required-laya`；不得needs Flutter或依赖只有product-path触发的workflow。contents:read、固定checkout SHA、无secrets/联网业务/上传包。

- [ ] 先写runner契约测试：第一/中间/最后测试退出非零均失败；无Flutter可用仍执行；不读取用户env；不静默吞失败。fixture只用临时目录假工具。
- [ ] 提取原四项顺序和原测试源不改断言：`test_stage1_contract.py`、`test_stage2_data.py`、`test_stage2_threshold.py`、`test_kaggle_submit.py`（cwd scripts/laya）。不调用stage1真实询问/训练/submit。
- [ ] 无path过滤导致required永久缺席；PR develop及默认集成push正常产出明确required状态。若采用selector，则always汇总并校验真实测试结果，不能把skip转success。
- [ ] 验收：四项真实离线结果逐一留日志，synthetic失败注入证明required-laya红；Flutter job红/未运行时仍有独立Laya结果。原run跳过不补写成功。
- [ ] 审查后只在新固定head验证；branch required check登记是显式门禁契约变更，需父批准，不能靠同名替换当前红灯。

### Task 3: Dart oracle从活动树解耦（先于删除）

**Files:** Modify `experiments/redesign/rust-agent-host-lab/core/tests/supplier_store.rs`；Create该core下`tests/fixtures/legacy-schema12/{store.dart,entities.dart,manifest.json}`；调整`experiments/redesign/device-deferred/rust-domain/tests/differential.py`、`scripts/redesign/supplier-name-reference/{oracle.dart,README.md}`、`experiments/redesign/core-agent-lab/host-checks/host_inverses.py`的历史运行入口及文档；检查plugin-contract-lab/checks/ci_evidence.py/reg4c脚本消费者。
**Interfaces:** schema fixture保留原字节+source SHA/path/hash，仍做schema12真实结构断言；historical oracle读取明确固定源码，不引用活动packages。不可用工具输出NOT_RUN，不编造Dart pass。

- [ ] 保留supplier_store现有所有断言，先加入fixture hash/缺失失败控制；include_str从活动packages切到封存fixture，不删除测试模块/公共API。
- [ ] differential.py保持PRODUCT=`01e56cc2d729dab70e1b1def05c3aa93b28f421a`、FIXTURE=`8c5995515fa14ca3592a1c33c71afb4e4c1e5def`与unorm_dart0.3.1依赖lib指纹，改为在临时历史checkout执行；历史脚本硬编码SDK/tmp路径改显式既有工具输入，禁止自动安装。保留32配对仅30相等/2预期rawguard差异及全Unicode未证结论。
- [ ] host_inverses完整Dart协议/process/oracle闭包按214封存，不只拷测试入口漏pub/asset/source；历史任务需显式标记，不混入新默认产品必需运行。
- [ ] `ct01_eight_fields_normalize_with_dart_rules`本身是纯Rust断言，无Dart执行依赖，保留，不按名称删除。plugin Dart证据解释器保历史能力，不当作运行时依赖。
- [ ] 验收：完整Rust生产workspace及其三个path core真实tests能在活动Flutter目录不可见的隔离副本编译运行；fixture篡改必红。绝不通过删除tests绕过。历史oracle可复现工具未获恢复时保持NOT_RUN、历史结果仍原样。

### Task 4: 默认入口切换（独立可回滚，待父审批准）

**Files:** Modify `scripts/{ci,verify,doctor}.sh`, `scripts/test_verification_gates.py`, `scripts/test_doctor.sh`；Create `scripts/product/{ci,verify,doctor}.sh`及对应入口契约测试；更新six workflow活动/历史触发与使用说明；旧打包器保留historical显式入口。
**Interfaces:** 现有通用入口默认delegate product本地验证；legacy只在显式历史SHA模式运行。product doctor只报告工具绝对路径/版本、固定输入缺项，本地只读，不联系/models或读取key。缺工具/资产失败明确，不能返回伪pass。

- [ ] 先写契约反例：默认环境无Flutter仍不调用Flutter；Rust/Gradle缺失、任一子检查失败保持非零；doctor不联系网络或读取用户凭据；非Android平台明确unsupported/NOT_READY而非造包。
- [ ] product ci/verify复用当前muyon-product.yml真实命令集合（offline locked workspace alltargets、strict、checker tests；真实双ABI/native/bindingcmp；online provision后clean offline assembleDebug/AndroidTest/lint），明确本地不自动安装/下载或启动设备。完整CI网络provision权限仍按原路线，不在doctor隐式触发。
- [ ] 六旧workflow处置：ci自动Flutter变为显式historical运行入口；verify保macOS历史manual；ui-preview/reg4c取消旧task分支自动活动触发、保固定历史manual；android-min26保旧Fluttershipping历史manual；package-artifacts保旧三端历史手动和存储审批，不转发到新假桌面包。不删既有结果/测试，不称当前红CI被修复。
- [ ] 新产品workflow正常PR/push触发必须保留其三个Rust path sources和模型/native/checker路径；入口/门禁自身改动也要触发真正product检查，不能仅selector skip。required-product继续always needs真实Rust+Android并严格success；required-laya独立必需。
- [ ] 验收：在新精确head跑完整原生产品+独立Laya并到终态，故障注入证明两个真实gate任一失败都挡住；记录checkout与tree，PRmerge/head区别明示。Android编译不称设备/视觉测试。
- [ ] 合入讨论必须明确审查新gate contract、旧失败处置、平台能力缺口；父指定固定SHA后唯一集成者才执行。当前214仍红，不通过branch rule删ci check单独放行它。

### Task 5: 原生包装约束、无损回滚与可选源码清理

**Files:** 修改新Android发布说明/活动入口manifest；旧`scripts/package_artifacts/{package.py,README.md}`只标historical，后续另写/审原生包装命令，不把Flutter路径替换成存在检查即success；最后独立清理commit才考虑旧apps/packages路径。
**Interfaces:** 原生内部包manifest至少source/workflow/toolchain SHA、ABI、APK大小+hash、native/binding/model+notice hashes、debug签名标识、构建/设备/许可状态；无发布授权时只保日志，不上传APK。新签名及存储/许可/包体预算缺项必须拒绝发布，不伪造费用或大小限额。

- [ ] 保持verifyModelAssets/verifyProductNativeInputs、package_gate.py/model_package_gate.py全部原断言，五固定文件共331366004字节(另加生成dictionary与notices)不是总APK上限。notice包含GGUF/base模型card及MIT/Apache记录；hash正确不代分发许可审批。
- [ ] 双ABI arm64-v8a/x86_64、ELF machine/16KiB load和ZIP STORED对齐、JNI hash、generatedbinding逐字节cmp及真实APK inspect均保留；禁止-x跳过门禁或上传模型包宣称内部私密。
- [ ] 无损回滚验收用纯synthetic文件哨兵：旧包与新包数据分开；入口切换/revert不删除任一哨兵，不卸载旧包，不回放旧intent，不让legacy库被新owner自动打开。需设备时另行授权，不在本计划文档阶段运行。
- [ ] 新默认入口稳定+oracles解耦+闭包搜索无消费者后，才单独提旧源码删除PR；删除列表独审、完整Rust/Android/Laya回归，三个experiments生产core及历史fixtures不删。用户文件和历史Git对象/证据不在删除范围。
- [ ] 回滚只revert入口切换提交并恢复上一manifest/工作流配置，代码还原不自动运行历史失败suite，不回滚数据库或清目录；若包签名/版本阻止覆盖安装，明确保留两包并停止，不卸载解决。

## 审查交接与当前状态

文档自审已覆盖六workflow、ci/verify/doctor/打包、Dartoracle、Laya独立门禁、三Rustpath依赖、模型许可/包体、用户文件与回滚、桌面/询价缺口。未执行以上checkbox。父先审Task1-4的入口契约及required状态设计，再指定隔离实施分支；不询问重复合入许可、不创建并发集成者。当前PR101失败不是被本计划清除。
