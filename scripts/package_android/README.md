# 无密钥 Android 体验包（本地）

重写自已丢失的云端脚本（原 `cfd7f7b9`）。只做内部验证用的 release APK，不嵌
`dart-define` 密钥，不自动下载 SDK/NDK，不新增凭证。

## 用法

```bash
# 需已缓存 Android SDK（ANDROID_HOME）与 Java 17+、Flutter 3.47.5
python3 scripts/package_android/package_android.py \
  --output /tmp/muyon-android-packages \
  --flutter /path/to/flutter/bin/flutter
```

产物：

- `muyon-android-<40-char-sha>-internal.apk`
- 同名 `.sha256`
- `manifest.json`（build SHA、工具版本、debug 签名摘要、空 dart_defines）

## 约束

- 禁止一切 `--dart-define` / `--dart-define-from-file`
- SDK/NDK 缺失时直接失败，不调用 sdkmanager、不联网拉工具链
- APK 路径黑名单拒绝 keys/keystore/rawlogs/`.env` 等；并用 apksigner 要求
  `CN=Android Debug`（与当前 `build.gradle.kts` release→debug 签名一致）
- 路径过滤不是内容无秘密证明；操作者仍须选用可信源码

## 测试

```bash
python3 -m unittest discover -s scripts/package_android -p 'test_*.py' -v
```

离线夹具，不跑真实 Gradle/Flutter 构建。
