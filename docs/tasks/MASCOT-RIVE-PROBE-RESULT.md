# 牧羊 Rive CLI 最小合成 rig 验证结果（2026-10-09）

后续收口：原始artifact已在云端保存并逐项校验，已实际view_image检查两PNG；当前视觉核验、Flutter只读接口建议及原图阻断见 [MASCOT-RIVE-PROBE-ARCHIVE.md](MASCOT-RIVE-PROBE-ARCHIVE.md)。下文中的“尚未直接目视”是本次成功构建当时的历史状态。

结论：Ubuntu 云端路径可用。官方 CLI 1.5.1 在无 Rive 登录、无原图、无产品依赖的情况下，实际完成 raster image + mesh + skin + bones + number input 的 verify／.riv 编译／inspect／headless 截图。此前 libEGL 缺失已修复；不需要转移到 Mac。此结论只通过最小工具链门禁，不代表水墨牧羊素材、Flutter 运行时接入或15–20秒角色表现验收完成。

## 固定来源与范围

基线 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`；独立分支 `task/mascot-rive-probe`。最终执行提交 `7bed149`，[成功运行 37959412806](https://github.com/mightyoung/Muyon/actions/runs/37959412806)。未合并 main／develop，不修改产品代码，不上传原图，不登录 Rive，不运行 publish／rev／push，不创建外部项目。

官方安装器 `https://releases.rive.app/cli/install.sh` 下载到文件后审阅，执行前 SHA-256 固定为 `09e1dc2b14200cb16745a38e4436ad09ab9a1c17a7954fe59009307d3fc66389`。版本固定 1.5.1，官方版本 manifest 的 Linux tar SHA-256 固定 `f1c99eadc35920f8a0a802bebe8607101e18c581c040ab0dbf98895cff368477`，安装器实际校验通过。安装仅在 runner 临时目录。

## Ubuntu 最小运行库

根据实际 `ldd` 缺失项和 Ubuntu 24.04 官方 apt 元数据，使用 `apt-get install --no-install-recommends libegl1 libgles2 libx11-6`。日志证明 libx11-6 已存在；新增运行包为 libegl1、libgles2、libglvnd0，三者版本 `1.7.0-1build1`，下载163kB，额外占用609kB。已有 Mesa EGL vendor 库不需要另装，未安装桌面／X server／Flutter／SDK。

官方参考：[libegl1](https://packages.ubuntu.com/noble/libegl1)、[libgles2](https://packages.ubuntu.com/noble/libgles2)、[libx11-6](https://packages.ubuntu.com/noble/libx11-6)。安装日志记录实际 apt policy／show 与 dpkg 版本，不凭网页版本替代运行环境。

安装包 docs 实际位于 `RIVE_HOME/versions/1.5.1/docs`；临时 bin 是安装器 muxer 入口，需显式 RIVE_DOCS_DIR 才能读取。遵循生成项目 AGENTS.md 的要求，依据实际 `schema` 和 `docs rigging／assets／format／easing／state-machines` 编写 RML，未猜类型。

## 逐项实测

| 检查 | 证据 |
|---|---|
| CLI启动 | `rive 1.5.1` |
| PNG素材 | Python标准库生成64×64 RGBA棋盘纹理，无第三方依赖 |
| verify | 两个输入默认值分别验证成功，0 errors／0 warnings |
| .riv编译 | 左姿态849 bytes；右姿态855 bytes |
| inspect | 左姿态 problems=[]，断言1 ImageAsset／Image／Mesh／Skin／RootBone／Bone／StateMachineNumber／BlendState1DInput，2 Tendon，4 Weight；右姿态独立 inspect 文件保留 |
| mesh连接 | 4个UV顶点、两三角形[0,1,2]／[0,2,3]、两个绑定矩阵、每顶点255权重且tendon索引1或2 |
| number连接 | headYaw经BlendState1DInput连接0／100两姿态，两姿态分别key同一Deform bone.rotation（−0.4／+0.4弧度） |
| headless截图 | 官方 `--screenshot --advance=1` 生成两张256×256 PNG；日志为EGL_PLATFORM_DEVICE_EXT；depthStencil／4x MSAA回退，不依赖桌面显示 |
| PNG像素解码 | 标准库inflate＋PNG filter反解成功，13,919像素不同；棋盘像素左12,857／右12,931；bbox左[64,44,210,191]、右[64,65,211,210]，左边界保持64 |

number 输入验证方式为改变默认值后分别编译和执行两个姿态，不能把它称为同一个 `.riv` 的 Flutter 实时输入验证。PNG解码和内容检查证明不是空白截图；当前编辑环境对connector提供的artifact下载URL返回proxy 403，尚未直接目视审核截图。可由主助手／用户从下面小artifact下载审核。不要声称已通过水墨形象或动画审美验收。

## 产物

[成功运行artifact 11629977133](https://github.com/mightyoung/Muyon/actions/runs/37959412806/artifacts/11629977133)，44,444 bytes，留存1天。包含左右 `.riv`／PNG、左右RML、checker.png、rive.yaml、verify JSON、左右inspect JSON、pixel-check.json及SHA256SUMS。打包 SHA-256：`b485a7c1f7c4511ebe41ace759a87f56217795f890f537f8eb26224352965afd`。

| 文件 | SHA-256 |
|---|---|
| pose-left.riv | `31cd13841dc15accfac1ce13a344eacd06182032e6a9df3973582ce1f2268495` |
| synthetic-rig.riv（右） | `b502faf260238244951363d28a6f335571849559ac1cbbb10361b6496c4ba7ed` |
| pose-left.png | `3248f19f38d5530d870cd2fe3526b0074c3f63adebb4c4148904a0cf0f0454ba` |
| pose-right.png | `fc6390463c6e8c075ebd692cab4257d33db52b9c555dc7d3fac12b79520ba0f9` |

仅public仓库标准Ubuntu runner、5分钟timeout、contents:read，无持久cache、付费／larger runner。artifact只保留必要合成证据，不含CLI二进制或官方原始日志。设计执行预算仍为0；未调用付费服务。

## 对后续设计的影响

1. CLI生成mesh rig资产这一技术缺口已有实测路径，Mac无需安装或保存工具缓存。
2. CLI 1.5.1 bundled docs将StateMachineNumber／Bool／Trigger标为deprecated，并推荐ViewModelProperty数据绑定；本probe刻意验证既定legacy number契约，它仍实际可编译和渲染。正式角色需在固定Flutter runtime版本后选择兼容legacy输入或迁移view-model，明确更新设计接口；不能静默更换13输入契约。
3. 未验证Flutter runtime是否接受该unsigned `.riv`、骨骼实际复杂动画混合、Dart gaze单时钟、真任务state/stage、reduced motion／后台／尺寸／主题。这些仍按实施计划独立门禁。
4. 原始图像materialization及同源分层仍待推进；这个合成纹理probe不使用、替代或破坏白毛。完整原型仍须用户审核。

未运行项目测试／应用打包。验证发生在独立GitHub Actions云端探针，没有触碰AIUI协议、冻结插件页或其他任务。旧CHECKPOINT为此前失败时的历史记录，以本报告为当前结果。
