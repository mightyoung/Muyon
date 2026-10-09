# 牧羊 Rive CLI 云端探针检查点（2026-10-09）

研究基线 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`；独立分支 `task/mascot-rive-probe`，未合并 main/develop。最新实际执行提交 `79cf5f7`。本报告记录已运行结果，不代表 rig 门禁通过。

## 已执行证据

| 阶段 | Actions run | 结果 |
|---|---|---|
| 官方安装脚本下载／正文审阅 | [37957790647](https://github.com/mightyoung/Muyon/actions/runs/37957790647) | 成功，未执行脚本 |
| 稳定版 manifest 获取 | [37958097630](https://github.com/mightyoung/Muyon/actions/runs/37958097630) | 成功，版本 1.5.1 |
| 固定版本安装／命令启动 | [37958188709](https://github.com/mightyoung/Muyon/actions/runs/37958188709) | 安装成功；首个命令启动失败，exit 127 |

官方安装器 URL：`https://releases.rive.app/cli/install.sh`。
实测安装器 SHA-256：`09e1dc2b14200cb16745a38e4436ad09ab9a1c17a7954fe59009307d3fc66389`。
manifest：`https://releases.rive.app/cli/v1.5.1/manifest.json`。
官方 manifest 中 Linux x64 压缩包 SHA-256：`f1c99eadc35920f8a0a802bebe8607101e18c581c040ab0dbf98895cff368477`。
Mac Apple Silicon 压缩包 SHA-256：`471f9d6a374c95f90eea3edb9bb8b7794c0ed6787715746d2bc3ff1900332ab3`（尚未下载／运行 Mac 版本）。

安装器经正文审阅：可指定 RIVE_VERSION／RIVE_HOME／RIVE_INSTALL_DIR；固定 manifest 版本，校验压缩包 SHA-256，拒绝不安全路径和符号链接；安装至 runner 临时目录，未修改产品依赖或用户 shell 配置。安装器中的登录注释与末尾提示矛盾，不能据此认定 build 不登录可用，仍须实测。

失败原文：`rive: error while loading shared libraries: libEGL.so.1: cannot open shared object file: No such file or directory`。发生在 `rive --version`，尚未执行 help／schema／create／verify／build／inspect／screenshot。安装器声称 --once／--test 不需要相关库，但当前 Linux 二进制连启动也依赖 EGL；该说法不能替代实际证据。

## 剩余门禁与交接

按主助手最新要求，云端失败后保存检查点交回；不自动切换到 Mac、不安装系统库、不盲目重跑、不寻找非官方镜像。用户已允许 Mac 最小探针，由主助手在选定环境继续。

Mac 最小流程（仅 Apple Silicon，先确认磁盘；临时目录，不拉完整仓库／Flutter，不运行 login／publish／rev／push）：下载官方安装器到文件，验证上述固定哈希后，以 RIVE_VERSION=1.5.1 和独立临时 RIVE_HOME／RIVE_INSTALL_DIR 执行；读取 `rive --version`、`rive --help`、`rive schema --search mesh`、`rive schema --search bone`、`rive docs --list`、`rive samples --help`、`rive create --help`。先按实际 schema 写合成 checker raster／mesh／bone／number input，不能猜 RML 节点。之后逐项 verify／--once build／inspect --json／screenshot，并记录命令、exit code、文件哈希。若要求登录或付费，立即停在门禁，不自行登录或付款。

当前没有可运行的 rig RML，也没有 .riv／截图／artifact，不能将安装成功写为 rig 成功。原始日志保留在上述 Actions；仓库只记录必要结论，不复制完整日志。临时重建安装器经逐字节 hash 核验后保留在当前云端 `/tmp/muyang-probe-checkpoint/install-reviewed.sh`，不纳入仓库。

全部运行使用 public 仓库标准 Ubuntu runner、5 分钟 job timeout、contents:read，无 artifact 上传／持久缓存，无 Rive 登录、原图上传或外部项目。没有执行产品测试／应用打包；没有合并其他任务。三个 run 是不同阶段所需证据采集，没有重试同一个失败步骤。
