# ANDROID-REFERENCE-01 Phase 1：样本核验与工具环境（2026-10-13 Asia/Shanghai）
## 应用身份（C=官方/商店页面）
| 应用 | 官方名/开发者 | 包名 | 当前版本 | 可信来源 | 同名排除 |
|---|---|---|---|---|---|
| WorkBuddy | WorkBuddy／腾讯（商店署名不一致：魅族=腾讯云计算(北京)有限责任公司；应用汇=深圳市腾讯计算机系统有限公司） | com.tencent.workbuddy.app | 2.6.1（2026-10-09，280MB，Android 7.0+） | 官网 workbuddy.cn / codebuddy.cn/work 只给桌面包，移动端指向“官方应用商店”；腾讯应用宝 sj.qq.com/appdetail/com.tencent.workbuddy.app | 排除 Google Play com.workbuddy.apps（新加坡共享办公，WORK-SPHERE VENTURE） |
| Meta Muse | Muse from Meta／Meta Platforms, Inc. | com.facebook.aura | 11.0.0.8.164（2026-10-09起；minSdk 29, target 36） | 仅 Google Play（美/加区，邀请制）；Meta 无官方 APK 直链 | 排除 muse.ai 等同名；APKMirror 有镜像但不在本轮可信来源内 |
| Claude | Claude by Anthropic／Anthropic PBC | com.anthropic.claude | Play 2026-10-12 更新，版本号页面未显示 | Google Play | — |
| ChatGPT | ChatGPT／OpenAI Opco, LLC | com.openai.chatgpt | Play 2026-10-11 更新，版本号页面未显示 | Google Play | — |
## 样本：四个均未取得（盒内全盘仅有 Muyon 自身 internal APK）
## 工具：见报告
| 工具 | 版本/来源 | 状态 |
|---|---|---|
| rea | 6.4.0 | inspect-android-package / class / method / search / trace-references（JADX）、decode-android-resources（apktool，跳过smali）、identify-flutter-build、ADB 系列（需设备，盒内无）。用 Muyon internal APK 冒烟通过 |
| OpenJDK | 21.0.12.1（Debian apt） | OK |
| jadx-headless-mcp | 0.7.1 all.jar（GitHub 1013503897/jadx-headless-mcp），SHA256 6e5eacf5…ff75 与 REA 内置审计值一致 | OK，REA_JADX_MCP_JAR 已写入 ~/.bashrc |
| jadx CLI | 1.5.3（skylot GitHub release）~/.local/opt/jadx | OK |
| apktool | 2.7.0-dirty（Debian apt） | OK（REA 要求≥2.7.0） |
| apksigner | 0.9（Debian build-tools 35.0.2） | OK |
| aapt | v0.2-debian（aapt1；无 aapt2） | 可用，aapt2 未装 |
| rea doctor | 不健康：Debian 13 非官方支持；skill/cursor MCP 注册 missing（不影响 CLI） | 记录 |

## 更新 2026-10-13 13:04：WorkBuddy 2.6.1 已取得（应用汇官方下载链）
SHA-256 5ce90433…34e3；versionCode 852；arm64-v8a 单APK；签名 v2，证书 SHA-256 2b450095…6f14（DN Tencent，自签，腾讯归属中等可信）。详见 workbuddy/2.6.1/manifest.json。

## 更新 2026-10-13 16:32：用户 Drive 文件夹
- Muse 11.0.0.8.164：已取得，签名与公开 Meta 摘要一致（muse/11.0.0.8.164/）
- Claude 1.261009.20、ChatGPT 1.2026.272：只有 base，缺必需的 abi/density split；签名是 Google Play 应用签名形式，没有公开参照；用户已接受中等可信后完成静态分析（claude/1.261009.20/、chatgpt/1.2026.272/）

## 更新 2026-10-13 22:38：MEMORY-LIFECYCLE-04
- 记忆/偏好/身份/压缩对照与 Muyon 建议已落地：memory-lifecycle-04/（muse.md、claude.md、chatgpt.md、muyon.md、evidence/、manifest.json、report.docx）
- 仍为静态分析；未登录、未调用真实模型
