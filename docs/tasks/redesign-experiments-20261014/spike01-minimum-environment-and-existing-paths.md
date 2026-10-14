# SPIKE-01 最小环境需求与现有执行路径（只读追加）

2026-10-14 UTC。固定原盘点基线`1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`、设计`58fe9c62612d74a973614c41677e62a54332e6d6`。另读取已获用户正常合入授权的候选`6a6664b1094c94c8db45f4ed274a170570c0cbb7`的现成隔离Python实验说明，**本报告不执行/证明其develop合入**。原`inventory.md`/`inventory.safe.json`逐字节未改，哈希分别仍`e28aaf6c97da053cf4f9f4a352c14286c82eff0ad9e0beeef703d69898149096`与`18afc0dc16bae0a6fa7c6b544668ccca24972b71b223fb1d0ab7cc0311dabbd0`。

结论：当前有Python与缓存Dart参考工具，可承接已供给的离线合同实验；**Android/Rust native执行环境仍未就绪，不能冻结M03**。当前工具、已有源码/配置候选与尚缺原生资源分别如下。

## 当前可调用与已有离线实验

本次实际命令 `command -v python3 && python3 --version && /workspace/flutter-sdk/bin/cache/dart-sdk/bin/dart --version`，exit0：Python路径`/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3`、版本`3.12.14`；缓存Dart为`3.13.4 stable linux_x64`。另外只读确认`/workspace/pub-cache/hosted/pub.dev/unorm_dart-0.3.1/lib`存在。仅运行版本查询，没有本轮重跑下表实验、native build或设备操作。

| 路径/固定SHA | 已有执行机制 | 当前能支持什么、不能证明什么 |
| --- | --- | --- |
| 6a候选`experiments/redesign/d01a-contract/` README L1–50 | Python stdlib；既有unittest/driver/expected-only负控/变异命令 | 当前Python可启动，源码已在Git对象；既有源报告33实验tests和61partial/16not_run，不能等同真实分类器/hostgrant/dispatch或Android加载。本轮不复跑或重新计pass |
| 6a候选`experiments/redesign/d03a-contract/` README L1–64 | Python stdlib、独立lab SQLite及子进程故障实验 | 既有源报告24tests、63partial/9not_run及有限lab原子边界；不证明Rust权威回执、native生命周期或产品恢复。本轮未启动子进程实验 |
| 1dc `scripts/redesign/supplier-name-reference/README.md` L1–42 | 缓存Dart直接调用固定01产品`normalizeText`/`Supplier.fromJson`，Python只作输入/比对；缓存unorm | 缓存工具已存在，可在准确隔离source checkout按既有命令承接参考；既有47次真实函数调用不等于tool/controller/权限/CAS/receipt成功，也不证明Rust Unicode等价。无需pub/安装；本轮未重跑 |

这三条路径的固定Git对象可读取；当前检查工作树仍bc5b2c3，上述run_reference.py与两实验目录均**未在这个工作树物化**。必须使用对应既有隔离checkout或由B按准确source建立允许范围，不在他人工作树直接落文件。Interpreter版本查询只证明启动，不冒称本轮suite已通过。已有6a组合源报告的独立复验/CI属于其准确提交和实验范围，不为native实验背书。原52主验收、29分类case、14规则状态不因追加盘点改变。

## 真正native实验的最小工具与证明

这是SPIKE-01执行前的需求清单，**不是安装命令、版本冻结或产品设备矩阵**。原盘点已证明PATH无rustc/cargo/rustup、adb/SDK工具、gradle/kotlin/javac等，Java21只有runtime；没有native构建/加载结果。本轮不再安装或重复全面扫描。

| 必要层 | 最小需求及范围 | 当前状态与负责闭合的任务 |
| --- | --- | --- |
| Rust编译与依赖 | 已供给并版本锁定的rustc/Cargo、host工具链、离线可解析的Cargo锁定依赖；native crate/生成器需要同版本验证。rustup可作盘点/管理工具，但不是缺工具时授权下载的理由 | 当前缺Rust/Cargo及其标准缓存；由B指定SPIKE-01 native实验owner记录准确版本/缓存证据，不自动rustup install/update |
| Android Rust targets | 候选arm64-v8a→`aarch64-linux-android`，测试x86_64→`x86_64-linux-android`，核已安装std目标与NDK目标/API、linker/sysroot实际对应 | 两项只是待验证候选映射，本机无rustup/target证明；不得自动target add或冻结支持矩阵 |
| Android SDK/NDK | 已供给SDK platforms/build-tools、对应API与**固定NDK**的Clang/LLD/sysroot；记录包版本、路径、hash与离线可用性。sdkmanager若已提供可用于只读元数据，缺工具不能自动安装 | 当前标准SDK/NDK路径缺失；设计58要求锁定，现有Flutter配置`compileSdk/ndkVersion`由Flutter选取，不足以宣称新native版本已锁。native owner与提供环境者先闭合 |
| Java/Gradle/Kotlin | 真正JDK（含编译器）与兼容的离线Gradle distribution、Android/Kotlin插件和依赖缓存；Gradle集成Kotlin编译器可满足构建，不额外强制独立kotlinc，但其实际依赖要可解析 | 当前只有Java21 runtime、无javac/Gradle/Kotlin CLI；Flutter缓存只有wrapper而无distribution可用证明。旧source声明Java17/AGP8.11.1/Kotlin2.2.20/Gradle9.3.1-all仅作旧路径参考，兼容性与新版本取舍由实验核验，不直接移植冻结 |
| UniFFI与绑定依赖 | 两候选：统一JSON bytes经UniFFI薄载体 vs 同源schema生成类型化绑定；同版Rust库、生成器与Kotlin绑定、JNA/AAR及所有native依赖必须一起验证。cargo-ndk可选辅助，不要求凭空再安装一个工具 | 当前无新crate/UniFFI/JNA加载证据。按设计58 L574–592 Kotlin候选走JNA，不称“自动JNI”；窄JNI退出方案须有实际证据与维护范围，不能静态拍板 |
| 真实执行路径 | 准确source/build SHA、实际库+生成绑定+依赖hash、ABI/API/运行环境、native load/错误/回调/释放/退出观察，独立复验 | 当前无adb/可查询设备/server、无新native runner结果；必须由B派发明确native executor/非作者审查者后，在已授权且可用的设备/runner执行；不由本report或旧FlutterAPK替代 |

Rust pure-domain或桌面侧进程实验需要同样的host rustc/Cargo与已供给缓存，即使无需Android也**当前不能实际编译**。Python接缝/缓存Dart参考可帮助固定输入与反例，但不能比较真正UniFFI吞吐/包体/生命周期，也不能在缺Rust时用Python模拟结果替代选型。

## 现有GitHub路径：只有配置候选

1dc `.github/workflows/ci.yml:28–40`声明ubuntu-latest、Flutter3.47.5及scripts/ci.sh，属于既有回归。1dc `package-artifacts.yml:26,65–84,107`声明Android用ubuntu-24.04、setup-java17、Flutter3.47.5、Flutter APK build及artifact3天。既有workflow没有Rust/UniFFI/native load或设备验证步骤；原盘点固定tree/grep无这些入口。没有查询当前hosted runner镜像、可用容量或preinstalled工具清单，没有dispatch本轮CI。

现有Android包装workflow会setup工具和resolve依赖，不能在本轮“禁止安装/下载、配置新凭据/安全权限、付费resources”的范围内擅自启动。旧Flutter debug签名APK、sourceCI或package manifest都不是新库实际加载证据；本机wrapper存在也不允许执行以触发Gradle下载。

如B后续选择已有runner作为实验路径，仍需**对应native实验owner**与准确隔离写范围、可用预装/缓存Rust+targets/SDK固定NDK/JDK/Gradle/UniFFI依赖证据、明确ABI/API、实际可用设备或runner执行机制及准确run/build/source记录、非作者复验。所需职责应分清：Rust/UniFFI实验writer负责候选库、生成器和Cargo/target缓存；Android实验宿主writer负责SDK/固定NDK/JDK/Gradle/JNA、ABI打包与实际加载/生命周期；B负责准确writer预留、允许的runner执行及来源登记；非作者负责同SHA/库hash、反例与未执行范围复验。这些是待派发职责，未据此指派现有agent或恢复M03产品writer。仅改runs-on或复用旧Flutter打包步骤不会自动满足这些条件。环境提供/runner路径需在已有授权范围内解决，不在本轮安装、修改workflow/权限或配置凭据。

## ABI/页面条件与停止线

设计58 L985、L1162–1166、L1733–1738保留候选arm64-v8a及测试x86_64；4KB/16KB环境须核**所有**原生依赖的对齐、安装和实际加载，不能只检查主Rust库。这里不冻结最低/目标API、设备型号、NDK/Rust/UniFFI/JNA版本或完整支持矩阵。原盘点`/dev/kvm`缺失且adb不可查询，只能记设备状态unknown，不能声明无设备或启动模拟器补证。

明确停止条件：

- 需要任一未供给编译器/target/SDK/NDK/Gradle依赖时停止对应构建；不运行下载/安装命令、不通过改系统包、安全权限、签名凭据或付费资源补齐。
- 缺实际设备/runner环境事实时停止native load；不启动adb server/模拟器、安装APK或dispatch现有包装workflow。
- 新库与匹配绑定、回调/释放/错误、双传输语义/摘要、包体/延迟及退出方案缺真实证据时，SPIKE-01保持未完成，不替代M03 gate。
- 当前之后**M03产品writer暂停**；本报告只提供环境/路径需求，不恢复writer、不创建schema/产品代码、不占用已存在writer文件。后续SPIKE实验与M03正式冻结由B按对应准确所有权和证据另行推进。

实际只读命令/exit、固定source路径hash、缓存存在性与未执行项见`minimum-environment-and-existing-paths.safe.json`。读取6a/1dc/58指定源码对象均exit0；一次尝试定位不存在的`REDESIGN-SPIKE01-20261014.md`为git-show exit128，随后按树定位真实`REDESIGN-CONTRACT-EXPERIMENTS-20261014.md`，未造文件或推定任务已完成。未改仓库/原报告，未build/dispatch/device操作、安装、配置凭据、真实模型或成本动作；没有新增产品SHA或合入动作。
