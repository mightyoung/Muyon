# Muyon Android 候选包：模型与生成字典说明

适用于源码 `708570d59ea51024ee69bb62c97f63380d490f78` 的调试产品包。
完整许可、上游模型卡和原始出处记录保留在 APK 的 `assets/notices/`，
并在待交付目录 `licenses/` 提供易读副本。此说明补充来源信息，不改变上游许可。

- 嵌入 GGUF：ggml-org 的 `embeddinggemma-2-Q8_0.gguf`，固定提交
  `58faf90940886df2d62be555c8765d00dac362c5`，309855456 字节，
  SHA256 `2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135`。
  [固定 GGUF 模型卡](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/blob/58faf90940886df2d62be555c8765d00dac362c5/README.md)
  与 [Google 固定源模型卡](https://huggingface.co/google/embeddinggemma-2/blob/914f7f89142e33e77833254d9c9b90c3cef7303b/README.md)
  均声明 Apache-2.0。
- OCR 检测与识别：PaddlePaddle PP-OCRv5 mobile，固定检测提交
  `e6f4fa85f00e168c862bc462aebca69eef9b3d3d`、识别提交
  `ed152b8b495f84de93cda5709d768548a9127622`。
  [检测模型卡](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx/blob/e6f4fa85f00e168c862bc462aebca69eef9b3d3d/README.md)
  和 [识别模型卡](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/blob/ed152b8b495f84de93cda5709d768548a9127622/README.md)
  均声明 Apache-2.0。实际模型/config 大小及 SHA256 见同批 `model-manifest.json`。
- 运行库另保留 llama.cpp MIT、ONNX Runtime MIT、PaddleOCR Apache-2.0 全文；
  运行库许可与模型许可分别记录。

## dictionary.json 是 Muyon 生成的派生文件

此文件由 Muyon 的 `apps/muyon_android/prepare-model-assets.py` 生成，
并非 PaddlePaddle 原始发布的同名 JSON 文件。来源为上述 PaddlePaddle 固定识别提交的
[inference.yml](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/blob/ed152b8b495f84de93cda5709d768548a9127622/inference.yml)
（在构建输入中命名 `rec.yml`）。

Muyon 取 `PostProcess.character_dict`，前置一个空字符串、后置一个空格，
形成18385项列表，以 UTF-8、`ensure_ascii=False`、紧凑 JSON 序列化。
这项提取、补项与格式转换由 Muyon 执行并在此标记修改；上游字符数据归属
PaddlePaddle，保留 Apache-2.0 许可与相关 NOTICE。
生成结果110788字节，SHA256：
`d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92`。

## GGUF 源 revision 的来源记录补正

APK 当前继承的旧说明中“源模型 revision 未记录”的表述，由以下固定上游记录补正：

[上游父提交 bfcd298](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/commit/bfcd298762cc34d0357ece5ebdd31791a3a374d8)
同时加入 [.src_sha](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/blob/bfcd298762cc34d0357ece5ebdd31791a3a374d8/.src_sha)、
匹配当前 GGUF 大小及 SHA256 的 LFS 指针和
[convert.log](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/blob/bfcd298762cc34d0357ece5ebdd31791a3a374d8/convert.log)。
`.src_sha` 明确记载 `PRIMARY=914f7f89142e33e77833254d9c9b90c3cef7303b`。
因此准确表述为：**上游声明此源 revision；Muyon 未独立重现转换**。
当前固定 GGUF 提交58faf909仅修改 README 使用示例，没有改变该权重。

上游日志还记录量化器版本0.6.0-dev、build11451、commit1e91a0b05；
这只是上游记录，不能据此断言完整编排工具/依赖环境可复现。
源码/指针/日志的只读证据在本批 `evidence/provenance/`；完整日志的固定 URL
及其内容 SHA256 也已记录。模型字节、校验阈值及 APK 原 NOTICE 均未修改。

本批仅完成构建、包装与组件验证，没有运行模型推理，也没有验证完整业务权限链路。
