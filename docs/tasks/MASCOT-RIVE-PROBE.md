# MASCOT-RIVE-PROBE：隔离 Actions 合成素材探针

当前已完成官方CLI 1.5.1＋Ubuntu最小运行库的合成mesh／bones／number-input无登录编译、inspect及headless截图，完整证据与剩余门禁见 [MASCOT-RIVE-PROBE-RESULT.md](MASCOT-RIVE-PROBE-RESULT.md)。以下为原始任务授权与阶段安排。

用户授权：2026-10-09 `Sentinel_5585bfb2bcdc8191aaaeed1f4a1b502b`，允许新增并运行独立测试工作流，费用0，不登录Rive，不上传原图，与应用打包是两项任务。

分支 `task/mascot-rive-probe`，基线 `01404ae472451f55af5baa6ce76c95af72b0cbfc`。设计分支及其他工作区不动，不合并develop/main。仓库官方元数据确认visibility=public、default_branch=main，按GitHub官方计费说明标准hosted Ubuntu计算免费；不使用larger runner、缓存或付费服务。

仅此分支push + `[run-mascot-probe]`提交消息 + 工作流／探针脚本路径变更触发；无schedule、无PR事件、无自动重跑、无默认分支workflow_dispatch依赖。通用ci仅在本分支副本中排除这一个探针分支，避免无关全量Flutter任务；其他分支触发规则保留。

执行分阶段：先官方安装器下载、实际hash与内容审查（首轮不执行）；后续固定已审hash／精确版本才安装。然后查真实schema，创建合成checker raster mesh／bones／number input并实际verify／build／inspect／screenshot，逐项记证据。安装成功不等于rig成功；失败就报告具体阶段，不绕访问限制／换镜像。必要产物目标≤10MiB、留存1天；原始日志不入仓库。

当前首提交只获取安装器核读，5分钟timeout，无原图／账号／产品依赖／外部项目。首轮不上传artifact，hash与安装器正文只在Actions日志供核读。之后实际执行结果另补摘要，不能把待执行步骤写成PASS。
