# AIUI-5 F5b 切片 1c：collection RED

基线 `a60b352`。契约依据：leader 技术采纳记录（非用户逐条审定）；docs 仍 proposed 为历史。
**本轮只写 RED，未运行任何测试/analyze，不宣称 PASS。** 调用者运行后以真实输出为准。

## 改动文件
- `module_api/lib/src/ui/{snapshot,collection,plan,state}.dart`：仅可编译 scaffold（均标 NOT READY）
  - `UiComputedEvidence`、`DataSnapshot.computedEvidence` + `copyWith(computedEvidence:)`
  - `UiCollectionShape{table,series,timeline,options,items}.accepts` 恒 false
  - `UiComponentSchema.collections / allowedValues / childComponents`（不可变，校验未读取）
  - `UiLocalAction.openRow`（dispatch 先 `invalid`）、`UiSessionState.rowObject` 恒 null
- `module_api/test/ui_collection_test.dart`（新）
- 未改：validator 接受 gate、`resolve`、apps、旧 fixture/UI 测试；无第二 validator/router；exports 无需变更。

## 预期 RED（未运行）
所有 collection 正例（`ok(...)`）因 validator 仍对 `BindingKind.collection` 一律报 `unknown_collection:` 而在**行为断言**失败；
`openRow`/`rowObject`/`accepts` 正例同理；allowedValues 非法（Heading.level、Chart.kind）、readonly typed binding 坏 metadata/initial 的**拒绝**用例目前真实失败（validator 未读元数据，当前接受）。
每个负例先断言对应正例，故不会空转通过。预期现在已通过的控制：schema 元数据不可变、`computedEvidence`/`copyWith` 声明、旧 catalog 拒绝（该项配对正例仍 RED）。

## 覆盖
table 单/多列；rows 199/200/201、columns 31/32/33；collection/column/item id 127/128/129 字节及多字节；
label 255/256/257 及多字节；64KiB 元数据 65535/65536 ok、65537 拒；fact 值大小不计入；重复列/行、缺/多 cell、cell 非法 kind/未知 fact、
row.object 与 cell fact object 不一致；computed 缺 evidence/坏 source/过期 generation/digest 变；null 事实不补 0；
requiredBindings/mandatoryStates 经 collection cells 计 shown；provenance 零复制（identity）；旧 catalog 拒；
series 数值/decimalString/合法缺值/非法串/非有限、pie 负值整集合拒、非 series 形状拒；shape.accepts 列要求；
openRow 正例（可信 fact object）与伪造/未知/无 object/非 string 载荷 invalid 且无 draft 变化、重排 itemId 稳定；stream2 端到端。

## 待父审的执行澄清（不改 proposed 采纳状态）
1. **64KiB 度量**：暂按“结构引用元数据整体 JSON UTF-8”，测试 helper `_metaBytes`：
   `jsonEncode({id, columns:[{id,label}], rows:[{itemId, cells:[{kind,id}…按列序], object?(ObjectRef.toJson)}]})`，
   不含 fact/computed 值、无第二 codec 版本。测试按此构造 N±1（helper 自检不符会抛 StateError）；因未运行，精确性尚未实测。
   **这是唯一待父审的澄清。**

以下为实现细节/假设，不是新提案：
- `allowedValues` 按设计 §2 为 `Map<String, Set<Object>>`，用真实值：`Heading.level {1,2,3}`（整数）、`Chart.kind {'bar','line','pie'}`；已修正此前误写的 `Set<String>`/字符串化比较。
- series 只要求列集合为 `label`、`value`，不要求列序（按 columnId 取数）；shape 正例含反转列序 `[value,label]`。
- 错误码：测试只要求集合级前缀 `collection:<id>:`（`mandatory_state:`/`required_binding:` 沿用），属性值错误只要求含属性名。
- `verified`+null 不在本轮断言。
- 旧 catalog 判定假设沿用 `usesTypedEdits`（`library-2`）。
- 修复：测试文件多余的末尾 `}`（编译错误，非 RED）。

## 接口归属
validator/resolve/openRow 分派/`rowObject`/`accepts` 实现属 F5b 后续 GREEN；workspace/restore/schema2 publication 属 F5c，formula adapter 属 F3b，shell 导航 patch 属 F4c，均未触碰。

## 调用者实际RED与归属
真实Claude CLI2.1.295/init claude-sonnet-5-5，sonnet/low/24000/acceptEdits，新session f92460c9-b44f-4e5d-86a5-058e41c86046，首次30turns/400893ms/result success/end_turn/exit0。首跑多余brace导致编译错误，不能计RED；调用者还指出allowedValues必须Set<Object>及series按列ID集合不限定顺序。原Claude修复回合14turns/38853ms/result success/end_turn/exit0，不是Codex代写实现。

修复后实际专项2PASS/38FAIL/exit1，无编译/NoSuchMethod/StateError。失败主要是同一collection拒绝门的正例前置，也有allowedValues与readonly typed binding未校验的实际缺口；不冒称38独立缺陷。64KiB helper构造未异常，真正接受/拒绝仍待GREEN。缓存Flutter3.47.5/Dart3.13.4/no-pub；日志/tmp/aiui-f5b-logs不入仓。仅Scaffold+RED，没有collection绑定GREEN、没有UI/33适配。
