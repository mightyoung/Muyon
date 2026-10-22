# SPIKE-01 官方工具与隔离 native 验证

状态：用户明确允许在现有云环境安装官方开发依赖；主机验证实施中，Google SDK/NDK许可证已于2026-10-14 06:27:47 UTC获用户明确接受，尚未下载或安装。
固定develop `325e798d37044cbc0617f5bddbd14ccb9adec390`；设计 `58fe9c62612d74a973614c41677e62a54332e6d6`。
唯一writer B，独占 `experiments/redesign/spike01-native-lab/` 与本文；不改产品、原fixture、M03、CI或作者旧分支。

这是throwaway实验接缝，不是产品schema。按已批准SPIKE问题与probe，先实际RED，再最小实现/完整GREEN。
一份Rust实验record同时derive Serde与UniFFI，JSON bytes与typed API进入同一规范化函数；不用expected/caseID计算actual。
验证严格未知字段/枚举、null/缺省、整数范围、UTF-16/XML/trim/NFC/长度、同语义与规范响应摘要；响应不代表业务提交。
真实Linux .so和生成Python绑定先测错误/受控panic、callback、解绑/close在途同步、显式释放及GC/native Drop。
若JDK/Kotlin/JNA供给完成，再测Linux JVM实际加载；这些都不冒称Android实际load。
Android targets/SDK/固定NDK仅在对应许可证已获用户接受后使用；交叉编译/ELF检查不等于设备运行。
无设备或可用加载runner须not_run；不自动配置新runner权限、凭据、付费资源或系统安全设置。

工具安装只在/tmp/muyon-spike01-toolchain，原/tmp8.8GB可用、workspace仅2.8GB；下载hash/版本/argv/exit及原始日志放仓库外。
Rust官方rustup-init checksum已核；installer指定minimal/no-modify-path，未改shell profile。
当前Rust1.99.0/Cargo1.99.0及aarch64-linux-android/x86_64-linux-android std目标已安装。
Crate versions从crates.io官方registry读取并精确pin/Cargo.lock；UniFFI0.32.2 MPL2，Serde/JSON/sha2/normalization/thiserror为MIT或Apache2。
OSS包未出现另行点击接受提示；Google官方SDK/NDK页面明确要求接受，已报链接与§2、3、10–12、14概要，已收到用户明确接受；尚未下载SDK/NDK。

实施顺序：工具与许可证记录→Rust真实断言RED→同源实验实现/GREEN→生成绑定并真正加载Linux库→对照/负例/回调/释放→可行Android交叉编译→独立复核/固定结果。
Unicode只接受实测有限向量结论；Dart unorm8.0与Rust新Unicode表版本差异明确记录，不能因几个NFC样本相同宣称全域等价。
SPIKE-01 Android实际加载、双传输包体/延迟/生命周期及Unicode全域证据不齐时，M03仍blocked_contract。
没有模型调用、真实用户数据/数据库、部署、main/forcepush/delete；原D01a/D03a product writer暂停保持。

## 资产交接更新

原始固定源码 `fadaeb797733ade84be2ebcfb8910c931a4ccd39` 保留。独立复核确认 H1：callback 替换 observer 后，旧 observer 析构重入 close_session 或 unsubscribe 自等待；两个真实 FFI 负probe均5秒timeout exit124。原16 Rust/10 Python GREEN不覆盖此序列，生命周期仍conditional/incomplete。此次仅发布源码和脱敏摘要，不修实现、不重跑旧审查、不合入develop。脱敏状态与工具链摘要位于实验 evidence/；CURRENT-STATUS.json与原始安装/测试日志仍在外仓 /workspace/reports/spike01-runtime-20261014，独立复核原始证据在 /workspace/reports/spike01-host-independent-20261014。JVM actual load、Dart Unicode差分、Android ELF与load尚未完成；M03继续blocked。
