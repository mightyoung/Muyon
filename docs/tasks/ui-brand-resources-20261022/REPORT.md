# Android 原始品牌资源交付

分支 `task/ui-brand-resources-20261022`，基线 `f4781e16ddf4e542b983fbd77f266a0071148255`。来源固定为已核归档提交 `400e206135690c284c8402521e3135cfb7bfaee8` 的 `docs/design/2026-10-22/brand-originals/`；读取 shell 计划 `8937b3d62943351f918b4ae980f987e804427911:docs/tasks/ui-shell-20261022/HOST-ADAPTER-PATCH-PLAN.md` 第7项后，仅按父任务授权准备这组原始资源。原工作区未切分支或修改，仓库无 AGENTS.md；当前任务、交接和审查边界沿本轮已核指引。

## 供唯一 shell 接线执行者使用

| Android 资源引用 | 原文件 | 尺寸/模式 | 原字节大小 |
|---|---|---|---|
| `R.drawable.muyon_brand_mascot_front` | `1000144583(1).png` | 1254×1254，RGBA | 2089286 |
| `R.drawable.muyon_brand_mascot_views` | `1000144584(1).png` | 1536×1024，RGBA | 2851456 |
| `R.drawable.muyon_brand_icon` | `1000144624(1).png` | 1254×1254，RGB | 1489074 |

三文件在 `apps/muyon_android/app/src/main/res/drawable-nodpi/`，完整来源 Library/file ID、原版本、固定提交、源路径和 SHA-256 见 [RESOURCE-MAP.json](RESOURCE-MAP.json)。全部由 `git show` 从指定归档提取原字节并与归档来源清单核验，未重画、裁剪、缩放、改透明度或压缩；生成 UI 示例未作为正式品牌资源。三份原件已经逐张核看，分别为正面、多视角、m图标，没有可见私人聊天截图。

**尺寸限制已如实保留：** 三份 PNG 源文件合计 **6429816 字节**（约6.13 MiB），像素范围1254×1254至1536×1024。资源较大，未擅自优化。`drawable-nodpi` 不按设备密度缩放源图；接线端须约束实际显示尺寸、评估解码内存与APK体积。多视角图是完整参考图，不自动拆帧。原 m 图标含原有背景，并非此任务制作的 adaptive launcher 图标。本任务未改 launcher、Manifest 或现有 drawable；构建工具可能对打包 PNG 作处理，本次仅保证仓库源字节相同，未宣称APK内字节不变。

shell 由父任务协调使用上述稳定资源名，本分支没有 Compose/UI/Activity 接线，没有设置默认头像、替换已使用图标或启动新功能。原字体/版权问题不扩大，本映射只记录用户指定素材来源，不作额外权利结论。

## 验证与可重跑命令

复制前按三资源目标路径做存在断言，3项缺失，exit1；这是资源缺件检查，不是产品行为测试。复制后逐一完整 PNG 解码成功（Pillow12.3.0），尺寸/模式见表，文件名满足 Android 小写字母与下划线命名。

在仓库根运行下述只读核查（需要来源提交对象；本执行环境已具备）：

```sh
python3 - <<'PY'
import hashlib, json, pathlib, re, subprocess
from PIL import Image
m = json.loads(pathlib.Path('docs/tasks/ui-brand-resources-20261022/RESOURCE-MAP.json').read_text())
assert len(m['resources']) == 3
for x in m['resources']:
    p = pathlib.Path(x['resource_path'])
    assert re.fullmatch(r'muyon_brand_[a-z_]+\.png', p.name)
    b = p.read_bytes()
    old = subprocess.check_output(['git', 'show', x['source_commit'] + ':' + x['source_path']])
    assert b == old and len(b) == x['size_bytes']
    assert hashlib.sha256(b).hexdigest() == x['sha256']
    with Image.open(p) as im:
        im.load()
        assert im.format == 'PNG' and im.size == (x['width_px'], x['height_px'])
        assert im.mode == x['image_mode']
print('PASS: 3 original PNG resources, exact archive bytes, hashes, dimensions and Android names')
PY
git diff --check
```

资源原字节/哈希/尺寸/命名核查 exit0。`git diff --check` exit0；源归档和生产基线均已核远端。限定变更为三份 `drawable-nodpi/muyon_brand_*` 以及本报告/映射，未改代码、其他res、Manifest、构建或依赖。

本环境未发现 Android SDK、aapt2 或 Gradle 可执行文件，未下载SDK或触发远端构建。因此 **Android资源编译、完整APK/lint、实际显示与设备验收 NOT_RUN**；仅原件完整解码通过不等于 Android 构建通过。最终集成由唯一 shell owner/Leader B 按同候选验证。提交为纯静态资源与报告，使用 `[skip ci]`，不把跳过当通过。

## 独立复审及剩余阻断

独立只读执行者 `review_design_archive` 已按上方命令重新验证，结论通过、无确认问题：三PNG原字节/SHA-256/完整解码/尺寸/模式/命名全部PASS，映射与固定400e2061归档来源ID/版本/大小/哈希一致；暂存范围恰为5个新增文件，无既有同名资源冲突，既有res/代码/launcher/Manifest未改，`git diff --cached --check` exit0。独审未修改、提交或推送文件，不代表集成验收通过。

尺寸和构建环境缺口保留，不擅自改变原资产。没有运行真实模型/搜索、付费、配置凭据、扩大权限、部署、合 main/develop、强推或删除分支。I04拒绝及PR86依赖HOLD、旧两次unknown、预占¥0.002620未结清均不受此静态资源交付影响。
