# M04 供应商名称语义向量 v1

这是一套离线 **fixture harness format**，只描述测试输入构造、调用层和源事实预期，不是第二套业务DTO、Rust struct、M03 wire/schema或授权对象。产品固定源 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`，设计固定源 `58fe9c62612d74a973614c41677e62a54332e6d6`，M02限定领域决定提交 `2fd91b03a7b5f0888c1e11ab0ba559a580e970d0`；编制起点 `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a`。

| 文件 | 数量与状态 | 调用层 |
| --- | --- | --- |
| `name-domain-vectors.json` | 32 `not_run` | 真实Dart `normalizeText(input, 'name', 200, required: true)`，只测名称规范器，不推导完整API/权限/效果成功 |
| `entry-comparisons.json` | 16 `not_run` | 真实既有完整Supplier payload、工具guard/schema或旧form source差异；各层预期分别列出，不把一个层的结果外推其他层 |
| `planned-state-semantics.json` | 6 `planned` | 可信同值新意图+1、同意图不二次写、CAS、scope、只读回执与unknown；未附造grant、classification、credentialcheck或执行证据 |

总计54个本地语义记录，不新增/重计52主验收或29分类子case。14分类规则仍拟定。三个JSON的 `golden` 与每case `golden` 均为 null，`golden_status=pending_independent_dart_reference`；`proposed_semantics`/`proposed_semantics_by_entry` 是待真实参考检验的源事实预期，不是已运行golden、跨端通过或产品默认。

## 输入构造（仅解码，不实现验证）

每个 `input_recipe` 恰取以下一种构造；M05的adapter只负责构造输入，必须调用固定Dart实际函数/validator，不得在adapter复制trim/NFC/XML/200码点逻辑来冒oracle：

- `{"literal": value}`：JSON原值，包括完整既有Supplier payload样本、string、false/0/null等；是否存在某key是结构事实，不能把缺省转null。
- `{"repeat": {"literal": "甲", "count": 200}}`：按次数连接原文字串，不先规范化。
- `{"concat": [recipe, ...]}`：依次连接子recipe的String结果。
- `{"utf16_code_units": [55296]}`：以Dart `String.fromCharCodes`等输入构造方式保留原UTF-16单元，包括孤立surrogate；`[55357,56832]`为合法emoji pair。不得先用Unicode replacement修复坏surrogate；若传输无法表达或入口先拒绝，分别报告该边界和规范器结果，不谎称一样已测。

JSON采用ASCII escape保证文本文件本身为合法UTF-8；这里 `\u000b` 等是数据，实际解码后才是输入字符。JSON重复配方避免粘贴2000字正文；源字节hash由本目录SHA256SUMS核验。数据重建不等同领域算法，Python编制过程未调用任何规范化库，也未产生Dart运行结果。

## 实际调用层与 M05 接口

每JSON附准确fullSHA、path/line的 `source_references`；case用 `source_refs`绑定已读的guard。名称32case不含typed false/0/null/omitted，避免把直接normalizeText冒完整API验证。typed输入仅在entry文件既有完整Supplier payload中：`Supplier.fromJson`先exactKeys再name校验；null可过旧tool preflight而完整Supplier仍required text，false/0/数组/对象被实际ontology text guard拒绝；缺name的完整payload是缺key错误，和非空合法patch缺name保留旧值不同。旧TextEditingController.text是String，typed输入不装作旧表单输入。

M05可真实调用 `Supplier.fromJson`，须明确它是validatePayload的实际supplier分支；未调用`validatePayload`dispatch整体不可记该整条已执行。`_validateArguments`是private宿主注册preflight，旧catalog_form是真UI的预处理；不能真实调用者保持对应lane `not_run`/source-only，不用复制controller处理冒已跑UI。工具schema类型校验、size guard、领域校验是独立阶段；pass_raw_size_guard不是API成功。M05运行证据可在其任务允许路径落独立report，不需修改本fixture输入或填造golden；最终golden采纳另由真实reference证据与非作者review确认。

raw护栏为完整原输入 **UTF-16 code units≤2000**，BMP字符1单元、补充字符2单元；所有新端完整raw入Rust，禁止新UI预trim绕XML。规范链为XML合法字符检查→trim→NFC→非空且≤200码点。原Dart领域函数本身没有tool raw2000护栏，所以raw2001可trim合法；旧工具和新版目标入口应拒绝超限。raw2000/2001均有BMP和补充字符配方，不能把UTF-8 bytes、scalar count或规范后长度替代raw计数。

旧catalog_form先trim，VT/FF边缘可先被剥掉后保存甲；原raw直接规范器/旧工具和新端核心均拒XML非法字符。内部VT/FF仍非法，内部TAB/LF/CR保留。empty旧form转null后expected text与直接规范器required分别记层，不整齐改成同错误。精确Dart trim空白域、NFC数据版本、Rust等价仍待M05固定oracle及M03冻结前证据；两库都叫NFC不证明等价。

## 状态/权限/分类界限

6个planned记录只保留M02已定语义和未来runner所需事实，不构造业务DTO/ScopeGrant/credential结果或宣称交易成功。同规范名可信新intent仍revision+1及独立receipt；同intent重投递不二次写；旧snapshot重入主handler可能先scope_changed，恢复用独立readonly回执路径，不弱化selection guard。当前scope/purpose最小投影仍必要；notFound/unreadable不证明没执行，不自动换key重发unknown。

本机name动作按当前用途仍须实际新值credential检查、可信字段声明、来源/继承限制、权限/模式/业务/CAS与真实能力；这些向量不提供或替代该证据。unreviewed禁模型或业务**外发**不泛化为所有本机写入；credential原文禁正文，最小检查缺失局部拒绝/blocked_contract；不等待14广域规则全实现。未知分类不合成host grant，name=none不是授权；所有确定性名称动作保持0模型目标，本次没有模型/设备/外发运行。

所有内容为合成文字，未含真实秘密或credential canary。未来若添加合成canary，只能受控input，受阻正文不得原样echo进日志/差分/回执；reference报告记录case ID、允许的最小原因与摘要，不默认复制输入正文。源CLI错误也不可直接输出敏感正文。

## 验证及后续

本任务仅验证JSON可解析、case命名唯一、recipe结构、declared raw UTF-16边界、输入文件hash与固定源码路径/行范围，未执行Dart、产品、UI、状态fixture或新52验收。`SHA256SUMS`覆盖本README与三个JSON，不自覆盖，也不包含目录外任务文件；后续修改输入应重算hash并追溯版本，不因oracle失败改预期掩盖差异。

M05固定参考runner输出实际原Dart版本/依赖/调用点/结果/安全诊断并明示未跑lane；M03仍须D01a/D03a/SPIKE-01、实际Android库加载与Unicode等价证据，本文不冻结编码或跨端能力。
