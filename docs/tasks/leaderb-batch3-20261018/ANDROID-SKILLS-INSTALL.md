# Android 官方技能安装记录

日期：2026-10-18 UTC。安装已完成，仅作用于原 checkout `/workspace/Muyon`；其他独立 worktree 未安装。

## 来源与方式

- Android 官方仓库：https://github.com/android/skills
- 固定源提交：`5bda39f154fb859a08d45e2392f3568e049f83fb`，插件声明版本 `1.0.15`。
- 已读官方 README 与插件 manifest：https://github.com/android/skills/blob/5bda39f154fb859a08d45e2392f3568e049f83fb/README.md
- Codex CLI 实际版本：`0.159.0-alpha.3`，存在 `plugin add` / `plugin marketplace add` 正式入口；默认配置目录只读。技能安装初检时 `android` CLI 尚不存在；本技能安装子任务未安装新 CLI、不写全局凭据、不改信任配置。
- 后续主任务统一安装了官方 `commandlinetools-linux-15859902_latest.zip`（主任务已核对官方 SHA256）。其中 `bin/android` 是 bootstrap；首次运行 `android --version` 实际输出 `Downloading Android CLI...` / `Unpacking embedded installation...`，随后显示版本 `1.0.16625370`，当前 CLI 已可用。证据：[android-cli-version.log](/workspace/leaderb-b3-evidence/android-cli-version.log)。其条款链接为 https://developer.android.com/studio/terms 。后续运行应加 `--no-metrics`；未运行 `android init` 或额外技能脚本。本修正不扩大安装范围，也不重新执行发现服务验证。
- 使用 OpenAI 官方 skill-installer，审阅其主脚本和 `github_utils.py` 后执行；安装器锁源为 `openai/skills@49f948faa9258a0c61caceaf225e179651397431`。官方说明：https://github.com/openai/skills/blob/49f948faa9258a0c61caceaf225e179651397431/skills/.system/skill-installer/SKILL.md
- 安装目标：`/workspace/Muyon/.agents/skills/<skill>/SKILL.md`，属于项目技能发现目录，非单纯 clone。项目此前不存在 `.agents/skills`。
- 安装器使用 `--repo android/skills --ref 5bda39f154fb859a08d45e2392f3568e049f83fb --method download --dest /workspace/Muyon/.agents/skills --path <30个官方技能路径>`。调用前从子进程环境移除 `GH_TOKEN` / `GITHUB_TOKEN`，公共下载不使用凭据，也未尝试 SSH 回退。
- 未运行 Android 仓库内任何辅助脚本。既有内置技能目录保持未修改。

## 验证与范围

- 安装器退出码 0，逐项报告 30 个技能安装成功。
- 实际读取全部 30 个 SKILL.md，确认 frontmatter、技能名称、非空正文。
- 按固定提交的 Git tree 校验安装的全部 **402 个文件**，逐文件 Git blob SHA-1 一致；源 tree 无符号链接。
- `git status --short` 为空；`git check-ignore .agents/skills/android-cli/SKILL.md` 正确命中。仅在 `.git/info/exclude` 增加本地排除行 `/.agents/skills/`，不提交技能文件、不修改产品文件。
- 当前云端 `skills.list(executor)` 未返回这些项目技能，不能据此宣称当前对话技能目录已热刷新。独立尝试 CLI app-server 的 `skills/list` 时，默认只读 CODEX_HOME 无法初始化 sqlite；仅临时 `-c sqlite_home=...` 仍遇只读初始化失败，因此未取得该 API 的名称枚举结果。没有申请扩权或更改持久配置。磁盘路径/全文读取/源哈希验证已完成；后续在此 checkout 的 Codex 会话中按相关性发现，当前会话也可直接读取对应 SKILL.md。

## 本批开发相关性

本批 SDK / API 24 / 双 ABI / APK / JNI / ELF / 16 KiB / zipalign / lint / AIDL 普通构建没有匹配的专用 Android skill。`android-cli` 仅在使用其 SDK、文档和设备工具时相关；全文已读，其缺工具时建议安装 CLI 的步骤不覆盖本批“不得运行未审阅脚本”限制。`testing-setup` 全文已读，适用于建立测试体系而非普通构建验收，不应因此安装 Hilt/Robolectric/截图框架。AGP 9 升级、R8 分析、Compose 等技能仅在对应任务实际出现时加载。

## 已安装目录（30）

| 技能名称 | 可读取入口 |
| --- | --- |
| `adaptive` | `/workspace/Muyon/.agents/skills/adaptive/SKILL.md` |
| `agp-9-upgrade` | `/workspace/Muyon/.agents/skills/agp-9-upgrade/SKILL.md` |
| `android-cli` | `/workspace/Muyon/.agents/skills/android-cli/SKILL.md` |
| `android-for-cars-parked-apps` | `/workspace/Muyon/.agents/skills/android-for-cars-parked-apps/SKILL.md` |
| `android-intent-security` | `/workspace/Muyon/.agents/skills/android-intent-security/SKILL.md` |
| `android-permissions-security` | `/workspace/Muyon/.agents/skills/android-permissions-security/SKILL.md` |
| `android-profiler` | `/workspace/Muyon/.agents/skills/android-profiler/SKILL.md` |
| `appfunctions` | `/workspace/Muyon/.agents/skills/appfunctions/SKILL.md` |
| `camerax` | `/workspace/Muyon/.agents/skills/camerax/SKILL.md` |
| `display-glasses-with-jetpack-compose-glimmer` | `/workspace/Muyon/.agents/skills/display-glasses-with-jetpack-compose-glimmer/SKILL.md` |
| `edge-to-edge` | `/workspace/Muyon/.agents/skills/edge-to-edge/SKILL.md` |
| `engage-sdk-integration` | `/workspace/Muyon/.agents/skills/engage-sdk-integration/SKILL.md` |
| `glance-canonical-layouts` | `/workspace/Muyon/.agents/skills/glance-canonical-layouts/SKILL.md` |
| `jetpack-compose-performance` | `/workspace/Muyon/.agents/skills/jetpack-compose-performance/SKILL.md` |
| `leanback-to-compose-tv-migration` | `/workspace/Muyon/.agents/skills/leanback-to-compose-tv-migration/SKILL.md` |
| `litert-runtime` | `/workspace/Muyon/.agents/skills/litert-runtime/SKILL.md` |
| `media3-cast-integration` | `/workspace/Muyon/.agents/skills/media3-cast-integration/SKILL.md` |
| `migrate-xml-views-to-jetpack-compose` | `/workspace/Muyon/.agents/skills/migrate-xml-views-to-jetpack-compose/SKILL.md` |
| `ml-kit-genai-prompt-api` | `/workspace/Muyon/.agents/skills/ml-kit-genai-prompt-api/SKILL.md` |
| `navigation-3` | `/workspace/Muyon/.agents/skills/navigation-3/SKILL.md` |
| `navigation-event` | `/workspace/Muyon/.agents/skills/navigation-event/SKILL.md` |
| `play-billing-library-version-upgrade` | `/workspace/Muyon/.agents/skills/play-billing-library-version-upgrade/SKILL.md` |
| `play-policy-insights` | `/workspace/Muyon/.agents/skills/play-policy-insights/SKILL.md` |
| `r8-analyzer` | `/workspace/Muyon/.agents/skills/r8-analyzer/SKILL.md` |
| `restore-credentials` | `/workspace/Muyon/.agents/skills/restore-credentials/SKILL.md` |
| `styles` | `/workspace/Muyon/.agents/skills/styles/SKILL.md` |
| `testing-setup` | `/workspace/Muyon/.agents/skills/testing-setup/SKILL.md` |
| `verified-email` | `/workspace/Muyon/.agents/skills/verified-email/SKILL.md` |
| `wear-compose-m3` | `/workspace/Muyon/.agents/skills/wear-compose-m3/SKILL.md` |
| `wear-widgets` | `/workspace/Muyon/.agents/skills/wear-widgets/SKILL.md` |

## 恢复与重装

1. 如需卸载，先确认 `/workspace/Muyon/.agents/skills` 中未新增或修改用户资料；本次目录在安装前不存在，30 个目录全部由本次创建。确认后仅移除本报告表中的 30 个技能目录；目录空时移除 `.agents/skills` 和 `.agents`，不要删除父目录下其他内容。
2. 从 `/workspace/Muyon/.git/info/exclude` 仅删除本次增加的精确行 `/.agents/skills/`，保留其余行。
3. 重装时使用同一官方安装器与固定 SHA、同一 30 路径。临时审阅副本仍在 `/tmp/android-skills-installer/`；它不是永久安装依赖。验证 tree 在 `/tmp/android-skills-source-tree.json`。
4. 本报告在 `/workspace/leaderb-batch3-skills-install.md`，不属于产品仓库提交。
