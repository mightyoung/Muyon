# 可操作供应商实验页面

这是 v1.3.2 D01.1 的隔离合成入口：供应商列表、原始名称编辑、Rust 校验、真实 SQLite CAS、原业务回执与重启核对。S1/S2 是同名合成对象，按稳定 ID 区分。列表由两个 read 组成，不是原子集合快照。正式权限、生产迁移与 M03 未接入；不要选择真实业务目录。

## 当前云端工作区启动

已有 Node、Linux SQLite 和与本片匹配的 P07 二进制才可运行；不需要 npm 安装。当前工作区已有二进制 `/tmp/rd-p07-independent-target/debug/rd-p07-atomic`，SHA256 `62232d1bdec9f923058dd9446b644781737caef9e111dc4dbb5658afe54c674c`。普通源码克隆不保证有该二进制或离线依赖缓存，不把本启动说明当作新环境安装指南。

在仓库根目录执行：

```sh
cd experiments/redesign/device-deferred/operable-supplier-flow
lab_dir="$(mktemp -d /tmp/muyon-p08.XXXXXX)"
node host/server.mjs --data "$lab_dir" --port 0
```

打开终端输出的 `url`，仅绑定本机 loopback。选 S1 或 S2 → 编辑 → 输入原始名称 → 预览 → 保存。新标签页独立编辑同一个 S1：第一个保存后，第二个旧版本保存应显示冲突，原草稿保留。返回列表仍定位原 ID，不按名称合并。

停止宿主后，在原终端复用同一个 `lab_dir` 重启；不要再次执行 mktemp 或清理目录。可沿用第一次 URL 的端口：

```sh
node host/server.mjs --data "$lab_dir" --port <第一次URL中的端口>
```

页面恢复原会话，或显式选择“恢复原草稿”。已派发/结果未知只核对原回执，不自动重提，不创建替代意图。当前记录与原历史回执分别显示；“已保存”来自核验后的真实回执。取消不能丢弃 saving/unknown 原绑定。参考 [共享宿主投影](host/PROJECTION.md) 和 [实验合同](CONTRACT.md)。

## 证据边界

真实 Chromium 网页操作与物理 SQLite 计数由组合非作者 QA 单独记录，不以 mocked-host DOM 用例替代。桌面网页运行不等于 Electron 壳已运行；手机 viewport 不等于 Android/Compose 已运行。Android 交付为 Compose 页面源和纯 JVM 投影/动作检查，native transport、TalkBack、设备与 Compose runtime 未验。正式 M03 保持 blocked_contract；本页不授予生产权限，也不验证真实模型或外部端点。
