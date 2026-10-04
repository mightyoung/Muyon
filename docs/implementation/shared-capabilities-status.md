# 公共能力当前状态

2026-10-04，依据当前代码核对。结论：公共能力尚未完整构建；OCR 未实现，基于关键词检索的 RAG 已有初版并接入科研界面，但尚未成为各业务模块统一调用的公共服务。

| 能力 | 当前实现 | 已接入范围与限制 |
|---|---|---|
| OCR | 未构建独立 OCR 服务，也未集成本地 OCR 引擎/模型 | 当前 DocumentParser 读取 PDF 已有文本层和纯文本；无可提取文本时明确报 OCR unavailable。扫描 PDF / 图片识别不属于已完成能力，不把文本提取或原助手图片请求算作公共 OCR |
| 文档解析 | 已有 PDF 文本提取、页码及文件摘要校验 | 科研文档索引使用；尚未通过统一公共接口接入 Folio |
| 离线检索 | 已有 SQLite FTS5、BM25、中文双字分词、英文 token、工作区/所选文档范围与过期检测 | 科研工具界面已接入；目前依据科研 WorkbenchStore 读取文档，没有通用模块文档提供者 |
| RAG 问答 | 已有检索→冻结证据→模型请求→引用校验→保存答案流程 | 科研界面已接入；支持页码引用、授权、取消与源失效拦截。检索采用关键词，不含 embedding、向量索引、混合检索或 reranker。真实模型及真实文档质量评测未验收 |
| 模型网关 | 已有 OpenAI-compatible 网关、显式 profile/endpoint、凭据引用、超时取消及授权边界 | 科研问答使用。Folio 仍走迁入的 supplier_core LLM 客户端，尚未统一调用宿主模型网关 |
| 公共能力注册/授权接口 | CapabilityRegistry / ModuleCapabilities 接口与契约测试已有 | bootstrap 创建 registry，但没有注册 OCR/RAG/模型 provider；科研 runtime 获得的 allowed 集合为空。不能宣称插件公共能力中心已经运行 |
| 数据/文件/凭据基础设施 | 已有宿主数据库所有权与迁移、私有文件根、文件冻结、凭据适配及生命周期 | 迁入模块已使用相关宿主适配；平台安全存储与实机文件行为仍需设备验收 |

## 直接代码依据

- `apps/muspace/lib/services/documents/document_parser.dart`：PDF loadText / fullText；无文本时报 `No extractable text; OCR is unavailable`。
- `apps/muspace/lib/services/search/search_service.dart`：FTS5、bm25、cjk-bigram-latin-v1；绑定科研文档与 workspace 范围。
- `apps/muspace/lib/assistant/qa_service.dart`：证据冻结、请求授权、引用 ID / digest / scope 校验、取消和执行记录。
- `apps/muspace/lib/app/research_tools_page.dart`：直接实例化 SearchService 与 QaService，完成科研入口的调用接线。
- `apps/muspace/lib/app/bootstrap.dart`、`packages/muspace_module_api/lib/src/capabilities.dart`：公共注册与授权框架已存在，实际 provider 注册尚缺。
- `packages/supplier_core/lib/src/llm.dart`、`packages/inquiry_module/lib/src/app/app_state.dart`：Folio 使用原模块自己的模型调用实现。

此前宿主回归 29 项通过，包括检索范围、索引失效、问答引用校验和取消；这次核对只读代码，没有重新运行测试，也没有实际请求模型。Android APK 构建通过不构成 OCR、检索质量或跨模块共享能力验收。

## 后续开发顺序建议

1. 将现有文档解析、检索与模型调用变成宿主注册的公共 provider，定义模块提供文档、传入 ContextRef 和授权范围的契约；先把 Folio 与科研接入同一条实际调用链。
2. 构建独立 OCR provider，支持图片/扫描 PDF，返回文本、页码/区域、置信度及来源摘要；输出继续受模块范围和文件授权约束。具体引擎与目标平台仍需选择与验证，当前没有安装或确定新的依赖。
3. 用真实中文报价单、供应商资料和科研 PDF 验证 OCR 与检索命中、引用正确性、性能及设备行为；按结果决定是否增加 embedding、混合检索和 reranker。

本次问题是状态核对，上述为建议，未执行新的 OCR/RAG 扩展开发。
