# REG-3b 科研只读 document searchSources 切片

执行 `/root/aiui9_cards`，分支 `task/reg-3b-research-search-20261010`，独立云工作区。
冻结基线 `c265eb13564ce8b485297fbdd3f1ddb351256e0d`。
依据 ADR-0004 §10.2/10.3、已合 REG-3a/复审/Checkpoint、GROK-6/7、NEXT-DELIVERIES-v1。

## 既有范围与交付

现 ResearchModule 已为 v2，searchSources 空；宿主 ResearchSearchAdapter 直接读取 store/hash 再用单 KnowledgeService。此片只迁 document source 声明与 actual registered 宿主消费者：按明确项目列当前版本，真实 bytes digest、nativeProject/ref身份与修改/删除/撤权前后确认；无业务写工具/模型请求/外部网络。索引依然用既有宿主知识库，不获得模块 knowledge/models facade 权限。

- 模块源通过宿主当前 runtime getter，不能持有可在撤权后继续读取的长期 runtime/resources 缓存；未绑定、已撤销、已替换或不支持来源一律失败关闭。
- 宿主 source consumer 复用 ModuleHost.scopeAuthorityRevision 与 workspace binding 身份，在异步前后 fence，取消结果不发布；只消费已登记的 document source，不绕成旧 store 全扫描。文件来源限模块管理根目录内且真实摘要一致，拒绝失效/跨范围/超预算来源。
- protected search_test 和旧接口兼容保持；实际宿主 ResearchToolsPage 的 registered 构造入口另接 module declaration/lifecycle。不得仅写未使用 helper 宣称生产接线完成。
- 新测试：真实宿主范围/来源/摘要、当前版本、磁盘变化/删除、host/module revoke与runtime替换、受控取消与异步屏障、来源路径/预算、旧搜寻行为保持（13 条新测试）。文件与项目总读取预算均 128 MiB，项目最多 1000 个当前文档，超限失败关闭。取消阻止结果发布与后续索引效果，底层已开始的只读文件 I/O 仍完成；没有宣称 Source API 支持物理取消。新增测试不改保护测试；无 sleep，原始日志不进仓库。
- shared module_api/validator/UIcore/CI 不改。新源码库存和 DA 交 coverage owner 测量独审；不自动 reset baseline、ignore、降 floor。

## 已确认后置项

ExchangeCapable 现接口使用 ExchangeEnvelope(kind/id/filePath/header)；旧宿主还有 TransferItem 和 TaskOffer 的可信接纳/操作身份、投递恢复与独立账本。映射尚未冻结，尤其 envelope.id→旧transfer identity/receipt、ResearchModuleSession 与 import intent归属、已接纳/重复/冲突状态如何保持；此片不另造桥接、不启设备收发。推荐由契约owner先给这三项逐字段/状态映射及差分夹具，之后迁实现。

REG-3-REST 已开放 research.save_note/add_outline/assess_run/accept_run，原读 objects/read_object/relations 保留。其余具名写能力（项目更新、task新修订、note-entry关联、手工run、section/cite、binding、card save）已在覆盖清单 deferred；多数对象无统一version/validator，必须按领域既有API及明确expected快照逐项冻结，不能照搬inquiry CRUD。Q10只批准 report/claimdraft 本机导出；registrar仍缺本机目标选择/允许根目录与effectIntent门面，不能伪装write或网络external。未授权 import/export任务/结果/技能实验与设备交换保持后置。

独立复审发现 parse 期间同路径新版本保留旧文件时旧 knowledge source hook 只查 id 存在：模块源同步 requirePinned 接入现 checkBeforeEffect，在 ready 提交前核 currentVersions/root/实际 digest；失败只清理对应宿主缓存索引，不清来源 taint。bootstrap 仅 research.document 的既有来源确认委托真实登记 source.confirm 与模块 lifecycle fence；其余旧 hook 不改。两条受控 parser 竞态回归同时验证生产 hook 和独立同步提交防线，以及 public knowledge.search/allowModelContent 拒绝旧证据、重新索引新版本正例。

ResearchToolsPage 旧 QA evidenceValidator 仍用绑定元数据与文件 hash，hash await 后 epoch 复核未在此片扩展；当前不是全 QA 迁移。推荐后续只把该附加确认委托 registered source/read 与既有 beforeSend 边界，需模型流程 owner 独审。

本片先完成不依赖上述领域决定的 document source 与实际宿主路径；不把约20具名建议 ID 写成已开放。exact SHA/CI/独立review在执行回报中登记，云端无SDK/Claude实际入口，不冒称本机工程师运行。
