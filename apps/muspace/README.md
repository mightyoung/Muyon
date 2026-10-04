# MuSpace 本地开发

MuSpace 使用 Flutter workspace，默认进入从 software-cost-calculator 迁入的 Folio 供应商模块。科研模块入口保留，后续验收仍按修订 4 计划推进。

在仓库根目录执行 `flutter pub get`，然后进入 `apps/muspace`：

```sh
flutter run -d macos
flutter run -d windows
flutter run -d <android-device-id>
flutter test --no-pub
flutter build apk --release --no-pub
```

运行桌面目标需对应平台开发工具；macOS 需完整 Xcode。Android 生成包目前使用开发签名，只用于本地验证。

默认数据目录为系统应用支持目录下的 `muspace/data`；开发时可在 `flutter run` 后加 `--dart-define=MUSPACE_DATA_DIR=/absolute/private/path` 指定隔离目录。宿主保存工作区、模块注册及配置，业务库位于 `modules/inquiry` 和 `modules/research`。不会自动读取原 Folio 数据、密钥或自动启动局域网服务；原供应商数据通过原有导入/恢复入口显式迁入。

Folio 目前是随应用编译的内置模块，采用宿主数据库和生命周期适配。统一公共插件协议与动态安装不在本次迁入验收范围。

各包可分别运行测试：`packages/muspace_module_api`、`packages/supplier_core`、`packages/inquiry_module`、`packages/research_module`。本机代理若影响 Flutter 测试的 localhost WebSocket，运行测试时去掉 HTTP_PROXY/HTTPS_PROXY/ALL_PROXY 及小写同名变量，并设置 `NO_PROXY=localhost,127.0.0.1,::1`。

源码依据、功能清单及验收缺口见仓库 `docs/implementation` 和各迁入包的 `MIGRATION_STATUS.md` / `MIGRATION_VALIDATION.md`。
