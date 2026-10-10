# AIUI-5 F5b 切片 1 报告：stream/2 RED 测试

状态：**测试已写，NOT RUN（由调用者运行并补实际输出）**。执行者无 Flutter/Dart 运行权限，本报告不含任何运行结果。基线 `77e708040737eb07825a2067b488da7328d2ba31`。

## 新增文件
- `packages/muyon_module_api/test/ui_stream_v2_test.dart`
- 本报告
未改生产、旧 `ui_stream_test.dart`、F5a/旧 library 测试、旧 fixture/checker。

## 测试范围（全经真实 `UiStreamSession` / `UiStreamCompiler` / `validateUiPlan`，无 fake validator）
测试只用当前已存在的类型：`library-2` 由测试内以 `UiCatalog(version:'library-2', 复用 fixture 组件)` 构造（host catalog version），collection 绑定以原始 JSON 行 `{"kind":"collection"}` 传入，不引用 `BindingKind.collection` / `DataSnapshot.collections`，故在当前代码可编译。

## 预期真实 RED（行为断言失败，非编译/环境错误）
| 测试 | 当前行为 → 失败断言 |
|---|---|
| `aiui-stream/2 session with host catalog library-2 constructs` | 构造抛 `ArgumentError`（stream_protocol.dart:41）→ `returnsNormally` 失败 |
| `library-2 with aiui-stream/1 is rejected at construction` | 当前构造成功不抛 → `throwsA(ArgumentError ∋ catalog_requires_stream_2)` 失败 |
| `library-2 + stream/2 compiles a plain plan…` | `/2` 构造抛错 → 测试以异常失败（同一根因；GREEN 后断言 badLines 0、complete == batch、`catalogVersion=='library-2'`） |
| `stream/2 accepts collection bind syntax; pre-collection catalog rejects…` | 同上；GREEN 后断言 badLines 0、节点 placeholder 而非坏行 |

注意：后三者的 RED 根因与第一项相同（/2 session 不能构造），属同一缺口，不是三个独立缺陷；若要独立 RED，须待 GREEN 先放行 /2 构造后再看各自断言。

## 预期现在即通过的对照（必须保持，M2 守卫）
- v1 四 kind 正例解析无误；v1 session 下 `collection` → `badLines==1`、节点不存在、`end` 后 `finalPlan==null`、含 `malformedStream`。
- minimal-1/dynamic-1/library-1 + v1 下 collection 仍被拒。
- 非法版本（`/0 /3 "/2 " 大小写 /02 无后缀 空串`）含 library-2 目录均 `throwsArgumentError`。

## 与旧测试的冲突（GREEN 时由调用者/授权方处理）
旧 `ui_stream_test.dart` 第 28–37 行断言 `protocolVersion:'aiui-stream/2'` 构造 `throwsArgumentError`（minimal-1 目录）。GREEN 放行 /2 后该断言会失败；本片按指示不改它。建议 GREEN 时让 /2 + 非 library-2 目录仍允许（任务书 §1.1 矩阵：语法放行），该旧断言须由有权方改为 `aiui-stream/3`，须在 GREEN 提交里单独说明。

## 后续检查点（顺序最短）
1. GREEN-1：`UiStreamSession` 接受 `/2`，`library-2`+`/1` 抛 `catalog_requires_stream_2`。预期本文件全绿。
2. 加 `BindingKind.collection`、v1 解析显式拒绝、v2 放行；此时对照 v1 负例是 M2 真实守卫（变异：v1 放行 → `badLines==1` 失败）。
3. 追加类型声明后的真实测试（先 RED 再 GREEN）：
   - `DataSnapshot.collections` + library-2 槽位：用真实 `validateUiPlan` 与 stream/2 `end` 对 `CompareTable.rows` collection 接受（语法接受后最终 validate 通过）；缺 cell/超限整体拒绝，N−1/N/N+1。
   - `editSpecs`：`UiSessionState.dispatch` 对 `UiNumberEdit/UiDateEdit/UiItemIdsEdit` 越界/NaN/off-grid/2026-02-30/重复 itemId 返回 `invalid` 且 `draftRevision` 不变；`nullableDispatch`、`strictQtyString`（M1）。
   - `openRow`：`rowObject` 与 `dispatch`，未知/伪造 itemId 零回调。
   这些放 `ui_edit_spec_test.dart` / `ui_collection_test.dart`，不是本文件。
4. Widget 切片（muyon_ui）及 `staleWidgetCapture`、library-2 目录渲染在后片。

## 调用者待补
- `cd packages/muyon_module_api && flutter test test/ui_stream_v2_test.dart` 的实际输出与各失败断言；确认 4 个 RED 均为行为失败而非编译错误。
- 同目录 `flutter test test/ui_stream_test.dart` 确认旧测试当前仍绿。

## 调用者实际 RED（2026-10-10）

组合基线77e708040737eb07825a2067b488da7328d2ba31，真实Claude CLI2.1.295/init claude-sonnet-5-5，low/24000，session c440f713-f643-41ac-861c-98d2fa72fe0b，result success/end_turn/exit0；Claude只新增测试/报告，Codex执行。缓存Flutter3.47.5/Dart3.13.4、现有165包路径复用，直接flutter_tools.snapshot，no-pub/no-version-check，无SDK/依赖下载。初始package config路径问题已纠正，不计RED。

旧ui_stream_test.dart单独30/30 PASS。新增ui_stream_v2_test.dart实际3 PASS/4 FAIL，exit1：/2构造returnsNormally失败；library2+/1预期抛catalog_requires_stream_2但未抛；完整v2计划与collection语法在当前/2构造处失败。全API运行包含新增RED：71 PASS/4 FAIL，失败恰为上述4项，无其他失败。没有编译错误；前三个v2正面路径同一缺口，不计独立三缺陷。

日志在/tmp/aiui-f5b-logs/，不入仓。Green需将旧ui_stream_test.dart中未知协议拒绝例从/2改测/3（仅此未知版本例），旧v1/旧目录拒绝不得削弱。首片a先protocol2/显式v1kind gate及枚举穷举；首片b随后metadata/spec/collection实际validate/dispatch行为RED→GREEN；Widget/render capture/33项下一切片。本RED提交不是实现完成，也不启用production目录。
