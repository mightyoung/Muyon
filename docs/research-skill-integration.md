# research-skill v6.8

科研工作台识别 research-skill v6.8 的可选 `research/assertions.jsonl`，以“研究者主张”展示，支持 `[assertions/id@rev]` 引用。旧项目缺少该日志仍可导入。

Assertions 仅供读取、展示和引用，不新增写回或导出。导入保留每行完整 JSON，包括 `intent`、`decisive_neighbors`、结构化 `critical_unknown` 和未知可选字段。

V1/V2 判定仍以 `schema_version == 2` 为依据；现有 claim 草稿格式及导出契约保持不变。
