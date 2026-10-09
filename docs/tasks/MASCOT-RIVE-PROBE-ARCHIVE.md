# 合成棋盘探针归档与视觉核验（2026-10-09）

本包是合成棋盘的工具链证据，**不是正式水墨牧羊吉祥物**。当前阶段只收口证据，不实现产品、不升级依赖、不改变已批准的13项资源契约。

## 已完成归档及视觉检查

原始artifact 11629977133（44,444 bytes）的直接下载在当前编辑环境受到proxy 403限制；通过现有授权GitHub Actions读取同一artifact，使用[归档run 37960085537](https://github.com/mightyoung/Muyon/actions/runs/37960085537)取回原始字节。该run只读取既有产物，probe job明确skipped，未再次安装／构建，也没有原图数据。压缩包SHA-256与原始运行上传哈希一致：`b485a7c1f7c4511ebe41ace759a87f56217795f890f537f8eb26224352965afd`。解压后全部14条SHA256SUMS逐项一致。

已用view_image实际查看pose-left.png／pose-right.png：米白背景上的蓝白棋盘清晰可见；左侧竖边在x=64固定，右侧上下角随bone.rotation姿态变化，内部棋盘格连续剪切／拉伸。结合inspect中的单一Image→Mesh→Skin、两个Tendon及4个Weight，以及仅修改headYaw默认值的复现源，变化符合局部蒙皮变形测试，不能解释为文件随机字节差异。这不是整张图片的平移或旋转。该判断不意味着正式形象表现或Flutter动态输入已获验证。

归档包包含原始zip、全部解压产物、当时成功构建的workflow快照、复现步骤、像素检查脚本及本报告。原始zip和包成员有独立校验；重新打包产生的新zip与原始artifact哈希不同是正常包装变化。PNG另作为独立附件保存。

## Flutter运行时的最小兼容建议（只读调研）

截至本次查询，Rive官方发布者的[pub.dev包页](https://pub.dev/packages/rive)显示stable 0.14.11、prerelease 0.15.0-dev.3；这不构成当前项目升级决定。固定实际runtime版本后才验证CLI资产兼容。

| 层 | 最小建议 |
|---|---|
| 业务与动作逻辑契约 | 保留既定10个number＋tap／celebrate／blink三trigger的名称、类型、范围、时序和单写入者；外层不暴露Rive SDK类 |
| 现有legacy number路径 | 0.14.11仍有`controller.stateMachine.number(name)`、`NumberInput.value`；trigger同理按固定API取句柄。启动时检查13项名称及类型，缺项走既定降级；句柄生命周期按SDK释放。这是最少资产变更路径，仍须实际Flutter探针 |
| 未来ViewModel后端 | 保留相同逻辑名字，以`ViewModelInstance.number(name).value`写number，以`ViewModelInstance.trigger(name).trigger()`发脉冲；仅适配层变化，RML内部换为同名ViewModelProperty及绑定。不得把trigger变成长期true布尔，不双写两个后端 |
| 版本差异 | stable 0.14.x使用controller.dataBind；官方0.15迁移文档改为构造时main绑定、controller.viewModelInstance读取。不要混用这两套API或为了新示例采用dev版本 |

官方[NumberInput API](https://pub.dev/documentation/rive/latest/rive/NumberInput-class.html)明确deprecated并建议Data Binding，但接口仍存在。[StateMachine API](https://pub.dev/documentation/rive/latest/rive/StateMachine-class.html)、[ViewModelInstance API](https://pub.dev/documentation/rive/latest/rive/ViewModelInstance-class.html)、[number property API](https://pub.dev/documentation/rive/latest/rive/ViewModelInstanceNumber-class.html)、[trigger property API](https://pub.dev/documentation/rive/latest/rive/ViewModelInstanceTrigger-class.html)提供上述访问与写入方式。构造绑定与实例所有权差异见[官方Flutter迁移指南](https://rive.app/docs/runtimes/flutter/migration-guide)。这些为文档核读，没有安装Flutter依赖或编译产品。

建议当前先维持legacy资产作为兼容验证目标，未来ViewModel迁移作为独立可审核资源契约版本。无论哪一后端，动作逻辑继续只写自己的gaze／头耳目标，Rive驱动独立呼吸等节点；仅适配层负责映射，不能让Dart与Rive重复advance。合成probe的0／100是私有blend端点，不是把正式headYaw外部范围改成0／100的依据。

## 正式原图阻断与本机最小交接

已再次使用当前官方Library materialization路由请求`libfile_b81596f423ac8191a8c28853b19f5a50`（muyon-04-ink.png），准备成功，但官方传输helper下载仍失败；当前云端没有该图字节。父助手此前已实际看过1254×1254白底RGB选定图，本次不能假设其本机路径存在，不能从棋盘反推图层。没有绕限制、猜存储地址，未上传原图到GitHub／Rive。

下一阶段由父任务新建本机素材制作线程，最小输入／工具需求：

1. 由官方Library路由取得这一个PNG，或使用用户已确认的本机原文件；打开核对1254×1254图像及白毛区域，不重新下载完整仓库。
2. 仅携带本设计规格／实施计划、此小probe包和已核验原图，在独立临时素材目录制作分层预览。无Flutter SDK／pub cache／大型worktree需求。
3. 先用已可用图像工具制作同源分层＋锚点预览并交用户审核；白毛保留，背景只按边界识别。若需新增工具或费用，先报告，不默认安装／购买。云端CLI已可构建rig，最初图层审核无需Mac CLI。
4. 若之后确需本机CLI，只下载官方Apple Silicon 1.5.1工具至隔离临时目录，记录下载及解压实际大小、限定清理路径；不装完整Flutter。尚未运行Mac CLI，不承诺特定占用数字。
5. 用户允许本机制作不等于允许上传Rive服务；在线目的地未明确前保留本地。继续按图层审稿→15–20秒原型→用户审后真实任务接入的门禁执行。

本轮没有制作正式图层或动作原型，没有运行项目测试。原图不可取得是下一阶段真实阻断；最小几何探针成功不能替代形象效果验收。
