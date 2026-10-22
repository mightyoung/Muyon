# D01 — 搜索发送终态超时修复证据

运行源码固定为 `7039175c8d6706b9bc75106b150510ae38c397ee`；生产修复提交为 `944e18b0d78ca0b92e63724fc91ff7dc0650c997`。2026-10-20，原两个真实私有 Service/Rust 搜索用例在 API26 arm64 模拟器通过，`OK (2 tests)`，6.645 秒。34 项专属 Rust 检查通过，双 ABI 原生库、APK 和 Android lint 通过。没有调用真实模型、网络搜索或付费服务。

## 原始故障与复现

原 CI：<https://github.com/mightyoung/Muyon/actions/runs/39279706227>，源码 `590fbc026b2fc5d200236d1877482b03752d0d8f`。2 tests / 1 failure；`settingsSaveThenOrdinarySendShowsSourceEmptyAndControlledError` 第45行首个 `send("find fixture","completed")`，第33行等待60000ms超时。无连接用例通过。原始日志为 [ci-original-instrumentation.log](ci-original-instrumentation.log)。

从该次运行的 `search-package-device` artifact 下载原双 APK，在临时只读 API36 arm64 模拟器真实运行同一类测试，重现相同的首个搜索发送超时；该环境另有无连接用例超时，不能把它当成 API26 结果。没有改变原 APK、等待条件或超时。检查该合成 fixture 自己的私有目录发现：

- `source.db` 已有 answer_delta、tool_projection、tool_receipt、terminal 四个事件；`registered-result.db` 的 state 为 completed。
- UI 持久化记录已得到 run/epoch，未得到 receipt，source synthetic 标记为 false。
- 因此失败发生在受理/结果轮询投影之间，不能归因于 IME，也不是没有执行搜索。

可控 Rust 复现见 `experiments/redesign/web-search-lab/core/tests/service_send.rs:136`。通过执行时 settings 检查上的 Condvar 暂停真实 ConfiguredToolRoute；Service、Agent、工具注册、结果生成和恢复检查均使用原实现。先取得执行中轮询，再释放执行并验证真实终态。

## 根因与最小修复

1. `experiments/redesign/rust-agent-host-lab/core/src/supplier_business.rs:616` 原来对进行中的 registered metadata 无条件调用 disclose。共享业务副本此时没有 dir 和结果事件；`service_tools.rs:299` 要求结果目录/账本，检查失败后 reply 被变为 `unknown / terminal=true / DISCLOSURE_UNAVAILABLE`。`AgentChatReadSession.kt:75` 只对 accepted/existing/events 继续查询，因此停止轮询，尽管 worker 随后正常完成。
2. `supplier_business.rs:705` 原来从 `mode.is_none()` 推导 registered synthetic 标记；ConfiguredChat 下的离线搜索被错误标成 false。`chat_route.rs:326` 现在从既有可信 `self.synthetic` 冻结 route 字段，make 要求其为布尔值，execute/restore 校验与实际路由一致。false 路由仍返回 transport unavailable，不能伪装成合成成功。
3. `service_controller.rs:648` 的受理回复保留冻结源身份，仅返回无 dir、无结果事件的 metadata。`supplier_business.rs:619` 只允许这种无结果 metadata 保持非终态；真实结果的 restore/disclose、权限/配置/回执验证保持执行。重复发送和变更配置的既有拒绝测试继续通过。

第二个独立 RED 回归见 `service_send.rs:168`，同时检查合成与非合成路由的受理/终态源标记。修复前合成终态误为 false，修复后两种标记均与可信路由一致。

修复超时后，API26 第一轮实际运行在费用文字断言处失败，耗时6.48秒；完整失败见 [api26-first-instrumentation.log](api26-first-instrumentation.log)。实际文字正确，但原 `assertTextContains("非真实计费")` 默认不是子串匹配。最终提交将它改为更严格的完整文字 `assertTextEquals("USD 750/1,000,000 · 合成账本估值，非真实计费")`，没有删除断言或降低成功条件。

`SearchSendServiceLoopTest.kt:34` 仍等待60000ms；只增加固定状态、cursor、run/receipt/tool存在标志的超时诊断，不输出业务内容或秘密。原 UI 点击、Service、Rust、来源、费用、空结果、受控错误和无连接断言均保留。

## RED → GREEN 与验证命令

在仓库根目录，macOS 本地测试使用 `TMPDIR=/private/tmp` 避免临时目录路径中的符号链接触发真实 InvalidRoot；`RUSTFLAGS='-l sqlite3'` 链接已存在的系统 SQLite，不修改 Cargo 或源码。

```sh
env TMPDIR=/private/tmp RUSTFLAGS='-l sqlite3' cargo test --locked --offline --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test service_send admitted_registered_send_stays_pollable_until_real_result_is_available -- --exact --test-threads=1
env TMPDIR=/private/tmp RUSTFLAGS='-l sqlite3' cargo test --locked --offline --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test service_send registered_source_label_is_frozen_from_trusted_route_not_host_mode -- --exact --test-threads=1
```

前一回归修复前 exit101：expected events，actual unknown / terminal=true / DISCLOSURE_UNAVAILABLE；后一回归修复前 exit101：expected synthetic=true，actual false。相应修复后均通过。

完整专属检查：先构建本地插件目录二进制，移到 `/private/tmp/muyon-d01-plugin-target` 后在最终源码再次运行以下命令，exit0：contract 5、agent_search 20、service_send 9（保留原7项，新增2项）。原始输出见 [rust-final.log](rust-final.log)，未在源码目录保留插件 target。

```sh
env TMPDIR=/private/tmp RUSTFLAGS='-l sqlite3' MUYON_PLUGIN_CONTRACT_BIN=/private/tmp/muyon-d01-plugin-target/debug/muyon-plugin-contract-lab cargo test --locked --offline --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test contract --test agent_search --test service_send -- --test-threads=1
env TMPDIR=/private/tmp RUSTFLAGS='-l sqlite3' cargo clippy --locked --offline --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test service_send
```

Clippy 普通模式 exit0；`-D warnings` 因既有 `reopen(p: &PathBuf)` 的 ptr_arg 警告 exit101（现 `service_send.rs:359`），未关闭警告，也未扩大到风格清理。`git diff --check` exit0。

双 ABI 构建均 exit0：`MUYON_BRIDGE_BUILD_ID=7039175c8d6706b9bc75106b150510ae38c397ee`，`CARGO_TARGET_DIR=/private/tmp/muyon-d01-native`，NDK `28.2.13676358`，相应 `CC_<target>`、`AR_<target>` 和 `CARGO_TARGET_<TARGET>_LINKER` 指向本地 NDK 的26-clang与llvm-ar，RUSTFLAGS仅设置16384字节max/common-page-size。分别执行：

```sh
cargo build --locked --offline --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --target aarch64-linux-android --lib
cargo build --locked --offline --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --target x86_64-linux-android --lib
```

输入身份及双库 SHA256 见 [bridge-inputs.json](bridge-inputs.json)。打包使用同一输入副本 `/private/tmp/muyon-d01-bridge-inputs`，Gradle 原 verifyBridgeInputs 检查实际通过。没有手改生成绑定。

```sh
env JAVA_HOME=/private/tmp/muyon-jdk17/amazon-corretto-17.jdk/Contents/Home GRADLE_USER_HOME=/private/tmp/muyon-d01-gradle GRADLE_RO_DEP_CACHE=/private/tmp/muyon-refactor-read-cache ANDROID_HOME=/Users/muyi/Library/Android/sdk /Users/muyi/.gradle/wrapper/dists/gradle-8.13-all/54h0s9kvb6g2sinako7ub77ku/gradle-8.13/bin/gradle --offline --no-daemon --console=plain -p experiments/redesign/android-compose-lab -PmuyonSearchInstrumentation=true -PmuyonBridgeInputs=/private/tmp/muyon-d01-bridge-inputs -PmuyonBridgeSourceSha=7039175c8d6706b9bc75106b150510ae38c397ee :app:assembleSearchFixture :app:assembleSearchFixtureAndroidTest :app:lintSearchFixture
```

最终构建/lint exit0，44秒。使用独立 Gradle cache 和只读依赖快照，未删除或修复用户现有损坏的 cache。原配置的 Kotlin exposed return type/SDK XML 警告仍存在。

## API26 实际结果与结果门禁

设备 `emulator-5556`：`ro.build.version.sdk=26`，`ro.product.cpu.abi=arm64-v8a`，default系统镜像。仅清理本任务合成 searchFixture 数据后，安装最终双 APK，两个 install 均 exit0。未使用 API36 代替该结果。

```sh
/Users/muyi/Library/Android/sdk/platform-tools/adb -s emulator-5556 shell am instrument -w -r -e class com.mightyoung.muyon.androidlab.SearchSendServiceLoopTest com.mightyoung.muyon.androidlab.searchFixture.test/androidx.test.runner.AndroidJUnitRunner
```

最终 adb exit0；两个具名用例各自 `INSTRUMENTATION_STATUS_CODE: 0`，`numtests=2`，`OK (2 tests)`，Time 6.645。完整原始输出见 [api26-final-instrumentation.log](api26-final-instrumentation.log)。APK SHA256：

- app-searchFixture.apk：`81e5eefe6a5f2ca21f8fbbc623b5899511cf576d1eab0824e5b8157a5dafd551`
- app-searchFixture-androidTest.apk：`226f3282c501b65cf362b503c85c7a609360f31b00ebf189ce97a5a778d8f3cb`

原 search_send_device.sh 的结果门禁（要求 OK (2 tests)，拒绝 FAILURES/INSTRUMENTATION_FAILED/Process crashed）应用于实际原CI失败日志和第一轮API26失败日志均 exit1；应用于最终日志 exit0。第一轮API26中 adb 自身 exit0，内容门禁仍拒绝，因此未把 adb exit0误报成功。

## 范围与整合边界

源码只改6个文件：三个原 Rust Service 文件、chat_route.rs、service_send.rs、SearchSendServiceLoopTest.kt。检查相同模式时，ordinary_chat.rs:44 已只在有 answer_delta 时核验结果，未改其实现。原配置变更、账本/回执篡改、被动恢复和禁止重发的7项回归继续通过。

最终 API26 是本地 arm64 验证；没有声称新的 GitHub CI/x86_64 设备通过，也没有真实模型/真实 SearchHost/付费验收。没有执行旧聚合、I04、403产物重试，也没有修改预算、凭据、TLS、Cargo/Gradle或生成绑定。

route 新要求冻结 synthetic 布尔字段；旧无该字段的 registered 账本不做迁移、保持拒绝恢复，符合已确认的“不要求历史数据兼容”。P02提取/接入新产品路径时应保留本提交的 metadata非终态、可信源身份和结果披露检查；新产品业务整合与总验收仍由父任务负责，不能将本次原实验 Service 通过升级为整个产品交付通过。
