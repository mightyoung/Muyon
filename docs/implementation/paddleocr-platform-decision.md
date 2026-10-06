# PaddleOCR 公共能力运行时选型

核实日期：2026-10-04。范围：只读依赖与官方模型核验；本次没有安装运行时、修改应用依赖或执行 OCR 推理。原始模型已在工具内存中下载、计算 SHA-256 并解析 ONNX 图接口，下载成功不等于推理通过。

## 决策

采用 **PP-OCRv5_mobile 官方 ONNX 检测＋识别模型、CPU 推理、统一前后处理**，Flutter 包精确固定 `flutter_onnxruntime: 1.8.5`。主执行通道已确认新 Miyono 宿主可以显式设 macOS 最低14，原 Folio 的旧系统目标无需带入；实施时须在安装要求、文档和设置中显示此下限。若未来恢复 macOS12/13，另做 ONNX Runtime C API 桥接构建验证，不能通过改一个Podfile数字宣称支持旧系统。

模型已经由 PaddlePaddle 发布 ONNX，不必先安装 Python PaddleOCR、Paddle2ONNX 或自行转换。完整 OCR 必须包含图像解码、检测预处理、检测推理、DB 后处理、透视裁剪、识别预处理、识别推理、CTC 解码及原图坐标映射。模型包装器本身不提供这些步骤。

## 候选比较

| 候选 | 已核实版本与维护信号 | 三端与原生依赖 | 许可 / 风险 | 建议 |
|---|---|---|---|---|
| `flutter_onnxruntime` | 1.8.5，2026-09-08 发布；Dart `^3.7.0`、Flutter `>=3.3.0`；1.8.x 持续修复 Apple 内存、打包和 AGP 问题 | 发布包 Android minSdk 21 / compileSdk 35，ORT Android 1.23.0；macOS Pod 最低14、ORT ObjC 1.23.0；Windows CMake 下载或查找原生库 | MIT；包页当前显示21.2k下载，时间口径未明，不作为稳定性证明。维护者报告1.24.x在部分Apple芯片内存回归，1.8.1回退1.23 | 首选验证对象，精确锁包和原生库 |
| `onnxruntime` Dart FFI | 1.4.1，2024-03-27 发布；Dart `>=2.17.0 <4.0.0` | 声明 Android/macOS/Windows；发布包 Android minSdk21、macOS pod10.14，Windows打包DLL | MIT；较旧发布版本，原生库更新、Android16KB页、现代Flutter兼容性均需另验；pod下限不证明库所有路径可运行 | 不以它自动解决旧mac兼容；仅作受控备选 |
| 自有 ONNX Runtime C API 桥接 | 可固定 Microsoft ORT 1.23.0 | 自管三端库、ABI、生命周期和C/C++构建 | ORT MIT；控制较强，但维护绑定与原生构建成本更高 | 当最低系统或包装器限制确实阻塞时采用 |

证据：[包注册表](https://pub.dev/packages/flutter_onnxruntime)、[精确发布包API](https://pub.dev/api/packages/flutter_onnxruntime/versions/1.8.5)、[1.8.5源码归档](https://pub.dev/api/archives/flutter_onnxruntime-1.8.5.tar.gz)、[变更记录](https://pub.dev/packages/flutter_onnxruntime/changelog)、[FFI包](https://pub.dev/packages/onnxruntime)、[FFI发布包](https://pub.dev/api/archives/onnxruntime-1.4.1.tar.gz)、[ORT许可](https://github.com/microsoft/onnxruntime/blob/v1.23.0/LICENSE)。未进行完整安全公告审计，不作“无已知漏洞”声明；没有可靠下载周期或响应时间数据，不虚构采用率和维护SLA。

## 官方模型固定清单

全部来自 `PaddlePaddle` 官方 Hugging Face 组织；模型卡声明 Apache-2.0，分发保留许可证及来源。[检测模型](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx)、[识别模型](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx)。

| 文件 | 固定revision | 字节 | SHA-256 |
|---|---|---:|---|
| det `inference.onnx` | `e6f4fa85f00e168c862bc462aebca69eef9b3d3d` | 4,826,518 | `a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d` |
| det `inference.yml` | 同上 | 903 | `98069072e1b6b37d727fd9d9f11725faa46d6ea0de012f2ed26caea011c37699` |
| rec `inference.onnx` | `ed152b8b495f84de93cda5709d768548a9127622` | 16,534,782 | `da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092` |
| rec `inference.yml`（含字典） | 同上 | 148,345 | `5dfeb2777f6d0db8177d8128a8acfcf6e6276dc4ac73ea3bf0dc06d6a5e85d8e` |

精确下载模板：`https://huggingface.co/PaddlePaddle/<model>/resolve/<revision>/<file>`；模型名分别为 `PP-OCRv5_mobile_det_onnx`、`PP-OCRv5_mobile_rec_onnx`。两模型权重合计21,361,300字节，约20.37MiB；这不含原生运行时、图像库、峰值内存或APK多ABI开销。表内哈希由本次下载内容计算，亦与Hub的ONNX LFS对象SHA一致。发行时仍须本地重算，且字典必须与权重一起固定。

## 推理契约与实现边界

本次解析实际 protobuf 图获得：

| 模型 | 输入 | 输出 | 格式 |
|---|---|---|---|
| det | `x`，float32，`[N,3,H,W]`，动态N/H/W | `fetch_name_0`，float32，动态4维；按实际运行shape读取概率图 | ONNX IR6 / opset11 |
| rec | `x`，float32，`[N,3,48,W]`，动态N/W | `fetch_name_0`，float32，`[N,T,18385]` | ONNX IR3 / opset7 |

这是文件接口证据，尚未验证实际运行shape和数值。不得把任意输出维度直接硬编码成输入像素尺寸。来源：[固定det权重](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx/blob/e6f4fa85f00e168c862bc462aebca69eef9b3d3d/inference.onnx)、[固定rec权重](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/blob/ed152b8b495f84de93cda5709d768548a9127622/inference.onnx)。

执行交接：

1. 对解码后像素设上限，读取/规范化EXIF方向；保留原文件哈希、页号、规范化后尺寸及回原图变换。扫描PDF先逐页栅格化再OCR，文字PDF提取文本单独标记来源。
2. det按固定YAML的BGR、`resize_long:960`及对应PaddleX尺寸规则预处理，记录x/y缩放比例；按通道执行 `(pixel/255-mean)/std`，mean `[.485,.456,.406]`、std `[.229,.224,.225]`，转换NCHW float32。
3. DB后处理基线：thresh `.3`、box_thresh `.6`、max_candidates `1000`、unclip_ratio `1.5`。需要轮廓、旋转最小矩形、概率图内框评分、基于面积/周长的polygon offset/unclip，再映射到原图并排序。用轴对齐框或固定加宽近似时必须标明算法偏差并测质量，不能称与官方一致。
4. 透视裁剪四边形文本行；竖长行可参考官方宽高比1.5的90度旋转逻辑。这不覆盖任意倒置文字方向分类，缺少方向分类时明确能力边界。
5. rec固定高48，按宽高比缩放、必要时右侧零填充；NCHW float32、`pixel/127.5-1`。使用固定模型的颜色约定和字典。**当前新版Android示例有RGB转换，而冻结v5模型YAML是BGR**，不可直接混用；以冻结YAML＋PaddleX原始流水线作为数值对照基线，彩色样本必须验证。
6. CTC逐时间步argmax，删除blank0和连续重复项（blank隔开的相同字符应保留），拼接对应字典字符，分数为保留字符概率均值。PaddleX默认字典追加空格、再前置blank；必须断言最终类别数18385，避免多/少加空格或UTF-16拆分字符。YAML解析器必须真正解析引号和转义，不能按行前缀直接截字符。
7. 返回文本、原图四点坐标、检测/识别置信度、页号、源哈希、模型版本和处理参数版本。置信度不证明报价表格结构、金额或供应商实体正确。

官方参考：[固定det配置](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx/blob/e6f4fa85f00e168c862bc462aebca69eef9b3d3d/inference.yml)、[固定rec配置](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/blob/ed152b8b495f84de93cda5709d768548a9127622/inference.yml)、[PaddleX检测前后处理](https://github.com/PaddlePaddle/PaddleX/blob/develop/paddlex/inference/models/text_detection/processors.py)、[PaddleX识别前后处理](https://github.com/PaddlePaddle/PaddleX/blob/develop/paddlex/inference/models/text_recognition/processors.py)、[固定官方Android SDK参考](https://github.com/PaddlePaddle/PaddleOCR/tree/dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf/deploy/ppocr-android/ppocr-sdk/src/main/java/com/paddle/ocr)。PaddleX develop引用仅供行为核实，实施时还须固定实际采用的commit与比较样本。

## Flutter API与构建注意事项

1.8.5提供 `OnnxRuntime().createSession(...)` / `createSessionFromAsset(...)`、`OrtValue.fromList(Float32List, shape)`、`session.run({'x': input})`、输出 `asList()`、`OrtValue.dispose()`、`session.close()`。实现使用finally释放输入/输出值、按服务生命周期复用session，限制并发与最大张量内存；推理接口不会自动获得OCR语义。[维护者API指南](https://github.com/masicai/flutter_onnxruntime/blob/main/doc/api_usage.md)、[精确1.8.5源码](https://pub.dev/api/archives/flutter_onnxruntime-1.8.5.tar.gz)。

可交给执行者的API示例（静态核实签名，未运行；`nchw`必须由上述预处理生成，不能传空白张量后宣称OCR通过）：

```dart
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

Future<(List<int>, List<double>)> inferOnce(
  String verifiedModelPath,
  Float32List nchw,
  List<int> inputShape,
) async {
  final session = await OnnxRuntime().createSession(verifiedModelPath);
  OrtValue? input;
  Map<String, OrtValue> outputs = {};
  try {
    input = await OrtValue.fromList(nchw, inputShape);
    outputs = await session.run({'x': input});
    final result = outputs['fetch_name_0'];
    if (result == null) throw StateError('Missing model output');
    final flat = await result.asFlattenedList();
    return (
      List<int>.of(result.shape),
      flat.map((value) => (value as num).toDouble()).toList(),
    );
  } finally {
    for (final output in outputs.values) {
      await output.dispose();
    }
    await input?.dispose();
    await session.close();
  }
}
```

`asList()`返回按shape嵌套的数组，`asFlattenedList()`返回一维值；两者不要混用索引。示例每次关闭session用于说明所有权，生产服务应缓存两个已验证session，关闭服务时统一释放；释放失败处理也要避免阻断其余资源释放。

### 图像依赖复用

2026-10-04定点读取当前workspace lock：已有传递依赖 `image 4.10.1`，来自现有PDF链路，`supplier_core`直接声明 `pdf:^3.12.0`。公共OCR包要显式声明精确 `image:4.10.1` 才可直接import，保留当前解析结果即可，无需升级整个PDF/archive链。其MIT许可、Dart跨平台能力见[包页](https://pub.dev/packages/image)、[许可](https://pub.dev/packages/image/license)、[精确源码](https://pub.dev/api/archives/image-4.10.1.tar.gz)。

可复用解码、EXIF orientation烘焙、resize、像素访问、编码；**不要假设`image`已经提供完整DB轮廓／旋转矩形／polygon offset实现**。四边形变换也须验证为所需透视homography，不能仅凭`copyRectify`名称替代官方OpenCV `getPerspectiveTransform/warpPerspective`。先用纯Dart实现并与固定官方结果对照，可避免为整套OpenCV再引入三端原生构建；这是实施建议，性能需实测。

- Android：依赖ORT1.23.0并保留 `-keep class ai.onnxruntime.** { *; }`；包方声明1.5.1起支持16KB页，仍需在实际发布产物与目标设备核验。minSdk21仅为插件Gradle声明，最终有效下限由全部AAR清单和应用决定。
- macOS：CocoaPods指定ORT ObjC1.23.0、最低14；SwiftPM路径使用维护者fork提供1.23.0，应同时固定原生二进制来源。仅有CommandLineTools不足以验证Flutter macOS应用构建；需要完整Xcode，不能从当前macOS26宿主版本推导最低系统兼容。
- Windows：**发布包CMake与README有差异**：`USE_SYSTEM_ONNXRUNTIME`默认ON，回退下载版本仍为1.22.0；父工程须在插件加载前固定 `USE_SYSTEM_ONNXRUNTIME=OFF`、`ONNXRUNTIME_VERSION=1.23.0`。发布包按指针宽度选x64/x86，没有可靠Windows ARM64选择，首轮验收限定x64；不得宣称ARM64完成。还要固定下载库哈希，实际验证DLL随包分发。
- Apple模型元数据/输入输出信息API未全部支持，不能把运行时metadata查询作为所有平台启动前置条件；使用已固定manifest并在输出处做shape校验。

以上native值来自下载的1.8.5发布tarball，优先级高于主分支README。ORT各版opset支持可对照[官方兼容表](https://onnxruntime.ai/docs/reference/compatibility.html)。未知问题是实际原生推理、资源峰值与端侧质量，不是ONNX模型能否取得。

## 验证与停止条件

执行阶段先做同一组真实图片上的det＋rec端到端CPU样本，覆盖中文、英文、数字金额、彩色字、旋转行、空白和超大输入；与固定官方PaddleX基准比较文字、框和分数，再接公共文件服务。保留原图与结果回放。分别验证取消后结果不提交、损坏模型哈希拒绝、缺少模型可见错误、离线完整执行、低内存及重复调用释放。

当前可确认：官方模型可获取，哈希与接口已核实，三端运行时存在可实施路线。当前不可确认：该Flutter应用已运行OCR、Android实机性能、macOS构建/最低系统、Windows构建和扫描PDF/报价图质量。完成条件必须包含真实推理结果；只注册能力、下载模型、运行mock或提取PDF原文本都不满足。

本次只新增本选型文档；实现、平台最低版本决策和验收由主执行通道继续。
