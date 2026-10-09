# F5a 草案归档集成复审（未采纳）

冻结 `f0203bf5030410f23e056bf8c6eeb6956c0593f2`，基线 develop
`0466f113fd7dd41f99c38cef11eca428622a6fac`。非作者独立只读复核完整9新增文件，
范围为draft/manifest/fixture/checker/独立新测试；无确定阻断或应改，建议组合门禁。
无正式schema、runtime、目录、store、export或旧测试改动。

四澄清闭合：collection独占registry且必须另行采纳stream/2，scalar同名全拒；
Choice参数编辑/视图选择分层；stable computationId跨S7/S8不变；cell状态、missingReason
及值/来源引用一致，真实10和null示例不混淆。所有新能力向量future-only。
12个Dart测试调用生产validate/state/codec/compiler，library1金样经过end后finalPlan；
同一collection夹具模型行由现行v1拒绝。旧缓存重标scalar被接受作为明确诊断缺口，
不冒称F3a公式/runtime重算已实现。library整体fallback事实保留。

独立隔离/tmp重跑Python checker及py_compile通过：33schema、12源码case、21无case、
library整surface fallback、66future-only；另核33项引用/符号、fixture、版本/来源bounds/
状态/future-only标签通过。集成者合并树另重跑checker通过。Python不等于codec执行。
[精确源 CI 37979546165](https://github.com/mightyoung/Muyon/actions/runs/37979546165)
直接核对completed/success：analyze8/8、test8/8、muyon_ui +323 ~152、host +1284 ~3。
本机Flutter/Dart缺失，Dart运行依精确CI及本轮组合门禁，不引用旧CI冒充本修订验证。

合入仅归档已审草案与验证材料，不批准stream/2、typed/collection正式schema或F5b/c实施，
不接正式runtime。未来能力须正式决议、同runtime接线及端到端行为验收。日志不入库。
