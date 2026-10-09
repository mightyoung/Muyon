# T-3 未注册只读handler基础片集成复审

冻结 `72dcb61a9a8e09995fd1e10f5c2c2bbde201b079`，基线 develop
`c98c09274d4f903f5760f6c415801bd4be014c56`。两位非作者只读独立复审通过，
无本轮阻断/应改，仅支持未生产注册基础片归档，不宣称完整T-3。

范围3新增文件902行：handler、19项测试、任务交接；没有bootstrap/registry/resolver改变。
生产lib无外部登记调用，bootstrap保持关闭。handler公开仓储调用为SELECT/内存getter，
输出仅白名单枚举、规范UTC时间及有界计数，不暴露正文/ID/路径/端点/secret。
global范围防御、未知参数/schema拒绝、类别关闭前拒绝、取消及固定失败摘要保持。
结果数量有界，仓储物化扫描没有数据库预算上限，文档如实说明，不假称扫描有界。

19项隔离测试使用真实registrar/registry：参数/范围/类别/封存、项目/悬空排除、
脱敏/输出数量、取消/错误恢复均实断言。handler total_changes及全文件字节不变；
invoke则单列既有receipt写入，比对其余业务表不变，不把invoke称零DB写。
共享prepare最小复现仅prepare、handler0、total_changes增加，实际source逐项failed，
notifications/executions/receipts不变；不伪造业务恢复动态实测。

**生产接线仍阻断**：ToolRegistry.prepare先全局resolveScope，ScopeResolver逐source.prepare，
ModuleHost激活可写ready/failed、条件import recovery/通知及research afterActivate之后才过滤
数据moduleIds。handler纯读不代表生产全链纯度；不取消必要恢复、不自创只读写入例外。
身份感知的纯metadata resolver需另片受审接口及差分测试，本轮不扩架构/权限、不登记bootstrap。

[精确push CI37995814951](https://github.com/mightyoung/Muyon/actions/runs/37995814951)及
[PR CI37995821460](https://github.com/mightyoung/Muyon/actions/runs/37995821460)直接核对
completed/success，head72dcb61，analyze8/8、test8/8、host1366~3。
PR实际组合b29f95e40d6418ab6ac6eb7b381dfe1d88182aae双父c98基线+72任务，
本地正常组合无冲突且产品树一致。历史超时/名单失败保留，不弱化旧断言。
本机无Flutter/Dart，未冒称本地重跑；最终另跑组合/发布精确CI。原始日志不入库。

完整组合 `0e94827cb56165db2d03f825ff056b00340e24d8` 的
[CI37997331880](https://github.com/mightyoung/Muyon/actions/runs/37997331880)
completed/success：analyze8/8、test8/8、module_api68、UI323~152、host1366~3。
允许仅基础片归档，生产bootstrap仍关闭，完整T-3未完成。精确发布SHA和CI由执行回报另核。
