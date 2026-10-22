# SDK许可偏差审计记录 — 2026-10-14

新增接受/额外安装已停止。执行者误使用批量 `--licenses`，超出新条款须先上报的授权。

执行时间依据原始日志 filesystem birth/mtime：06:54:46.927056621–06:54:49.538906676 UTC。不是采集到的进程起止时间。流水线退出1；SDK manager完成接受，yes因SIGPIPE退出。

```bash
set -o pipefail
export ANDROID_USER_HOME=/workspace/spike01-tools/android-user
mkdir -p "$ANDROID_USER_HOME"
yes | /workspace/spike01-tools/android/cmdline-tools/19.0/bin/sdkmanager --sdk_root=/workspace/spike01-tools/android --licenses > /workspace/spike01-evidence/android-licenses.log 2>&1
```

| 额外条款名称及官方完整来源 | 本地文件写入时间 UTC |
|---|---|
| [Google TV Add-on for Android SDK License Agreement / android-googletv-license](https://dl.google.com/android/repository/addon2-1.xml#android-googletv-license) | 2026-10-14 06:54:49.515119 |
| [Android XR Emulator System Image SDK License Agreement / android-googlexr-license](https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml#android-googlexr-license) | 2026-10-14 06:54:49.519119 |
| [Android SDK License Agreement (ARM DBT license ID) / android-sdk-arm-dbt-license](https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml#android-sdk-arm-dbt-license) | 2026-10-14 06:54:49.523119 |
| [Android SDK Preview License Agreement / android-sdk-preview-license](https://dl.google.com/android/repository/repository2-1.xml#android-sdk-preview-license) | 2026-10-14 06:54:49.532899 |
| [Glass Development Kit License Agreement / google-gdk-license](https://dl.google.com/android/repository/addon2-1.xml#google-gdk-license) | 2026-10-14 06:54:49.536462 |
| [microXR Emulator System Image SDK License Agreement / microxr-sysimage-license](https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml#microxr-sysimage-license) | 2026-10-14 06:54:49.537263 |
| [MIPS Internal Evaluation License Agreement for MIPS Android System Images / mips-android-sysimage-license](https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml#mips-android-sysimage-license) | 2026-10-14 06:54:49.538907 |

官方 XML 的片段标识对应 license ID，不保证浏览器自动滚动；以 ID 查找完整文本。

UNKNOWN. No packet capture or request-level network trace was retained. Local files prove local acceptance; tool did fetch official Google metadata and subsequently download approved components. No evidence establishes an acceptance POST to Google, and absence of log is not proof it did not occur. No login/account/new credentials configured.

实际Android组件：command-line19.0、platform-tools37.0.1、platform35、build-tools35.0.0、NDK28.2.13676358/r28c。未下载/使用额外七组件；上述标准安装包的package.xml使用android-sdk-license。其余已授权依赖为Rust1.99及Android std、Kotlin2.2.20、JNA5.19.1、coroutines1.10.2与锁定Rust crates；未新增Gradle、JDK17。

额外接受文件于约07:04:28 UTC移出生效缓存并保留。此举不构成法律接受撤销。无新账号、凭据、网络/安全权限配置。

精确来源：原日志 `evidence/android-licenses.log` 与额外文件 `evidence/extra-license-records/` 保存在交接包；完整精度时间、来源链接和文件摘要见 `license-exception.json`。
- android-licenses.log SHA256 `41e7766102ce0b4eb4b251e4462b337bdfda3c8cffebd1ed0eefd1c4c06d1328`
- downloads/repository.xml SHA256 `9c6014fd13f460b2eff2a241f1fa4f8881a8a2c4ed8c2a6a2886697c660b4af8`
