# AIUI 隔离稿与坏 codec 页面复审

集成基线 `079f1bc350f5cef784e265bc398acd03b0812a3b`；最终源
`308e119c772b4ad7399b5649357dc2baf81075f0`；生产主体源
`57ef4b6e9f1a9270e8382d9b27df42c4425f00ee`，测试生命周期初次收口源
`d0ae72cb37d6687abf26ff6d59133cf816bdf896`。用户授权仅修显式恢复/丢弃与实际
页面可读退路，不改变旧 codec、缓存架构、权限或业务工具。

非作者 review_reg3a、review_grok7 独立复审：旧 schema1 漏存剩余隔离字段的
阻断已封闭，schema1 保持只读可读且不重写；仅兼容 schema2 开放逐字段操作。
候选在 shadow session 按当前 spec 验证，CAS 成功后才安装；无效值和 CAS 输家
不活化、不分派业务。坏 codec 的有/无 plan 页面共用身份、字节限额退路；只读
退出位仅针对 unreadable checkpoint，普通保存失败仍传播，加载后的关闭也重核。

CAS/存储失败保留原持久字节；CAS 已成功但 await 后内存 fence 失效时，旧合法
投影可能已写盘，只保证不安装过期活动层、保持只读并要求重开按新 spec 验证。
本片不宣称 SQL 与内存跨对象事务回滚。已有 operationRef 与 unknown 回执保留，
不重放业务操作。

14 项新增行为回归包含真实页面点击、SQLite 关闭重开、schema1 双字段字节保留、
schema2 逐项剩余稿、CAS 输家/存储异常、撤权/结构变化、坏 codec 有/无 plan、
身份/字节拒绝、加载中关闭及真实 applyPatch 保存期间变化后新 spec 重开隔离。
它们不是未来14场景完整验收。旧断言未弱化，无 skip/容差/等待预算例外。

d0 精确 PR CI `38045035482` 实际失败：既有坏 codec 文案兼容与新增测试重复
dispose。308 最小修复保留原坏 codec 无 salvage 文案/回答和 controller，只在
该路径使用原 fallback；有 salvage 仍只读。测试避免第二次 dispose，行为断言保留。

生命周期修正：卸载/排空后 workspaceOperation 关闭 SQLite，两类 barrier
finally 释放。没有吞清理错误；取消且无完整日志的旧 CI 不是 RED/GREEN 证据。
本云端无 SDK；官方 Linux SDK archive 读取被网络 403 阻挡，没有安装替代版。
新源 PR CI [38045801243](https://github.com/mightyoung/Muyon/actions/runs/38045801243)
与最终组合 `75cd9da4f21e014fc30360f95df0bd1ad7dd4cf3`
CI [38045820980](https://github.com/mightyoung/Muyon/actions/runs/38045820980) 均成功；
全库 analyze 8/8、test 8/8，host 1542 pass / 3 skip，doctor 23、Laya 29。
这两次 fresh CI 已关闭上述两项实际失败；发布与远端读回见执行回报。
完整 F4c、全部集合类型、未来14场景、设备/golden/真实模型仍各自待验。
原始日志和大产物不入仓库。
