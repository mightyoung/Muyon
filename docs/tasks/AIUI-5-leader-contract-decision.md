# F5 leader 技术采纳记录

2026-10-10，父任务明确技术采纳 PR19 head `36d0ba881b5e3e54d8a5e60867d869f168e00135` 的六项接口方向，独立复审判实质缺口闭合。采纳主体是父任务 leader；**不表述为用户逐条审定**。采纳范围为实现契约，不是运行验收、生产启用或合入许可。

新契约基线＝上述 head 加本记录同提交的两项收尾：F5c切片1采用全部显示computed真实重算且保extracted；dispatch内部检查readOnly/recomputing/pending，而非仅禁按钮。旧proposed与future-only历史保留。版本、nullable与render capture、严格publish、qty拒绝、extracted/adopt、公式非view守卫、H3最终admission以修订正文为准。

父任务授权继续 **F5b**：另建 `task/aiui-5-f5b-contract-adapters` 隔离分支，由真实Claude实现核心契约与组件适配，Codex核查整合。先RED契约/typed/collection/v1拒绝，再GREEN；33组件分小可审切片，精确SHA与测试摘要单列。F5b此阶段拥有surface/state；F5c暂未并行写。F5c接口与F3b消费由父任务另调度。旧目录拒绝、单runtime/validator/router保持。

禁止：污染原docs PR/主工作树/其他任务，生产切换、合develop/main、付费业务模型/部署、SDK大型下载。验证优先既有Actions；原始Claude日志本地，实际模型/参数/终态须记录。PR18验收owner同步本契约，F5b不改其文件。

首片计划：使用当前正式入口的正向typed/集合拒绝行为取得RED（缺新类型的编译错误不计有效RED），再交纯契约/spec、collection与stream2显式门槛、旧行为回归。组件目录与renderer以之后切片接入，不开启应用生产目录。后续启动基线以F5b报告记录的最新develop与本契约提交组合SHA为准。
