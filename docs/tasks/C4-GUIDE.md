# C4-GUIDE 交互模式与组件指南交接稿

## 目标、依赖与归属

云数据线程负责从训练/开发数据提炼交互模式、组件使用指南；本任务只预留统一接口、交接文档和验收。数据稿依赖 UI-3a目录/契约版本锁定；运行检索适配在UI-4b提供接口后接入，不依赖模型训练胜出；UI-4b无指南可返回空继续。测试封存，不能为提炼指南读测试答案。

## 文件、接口与复用

拟新增 `docs/superpowers/specs/2026-10-08-ai-native-architecture/ui-interaction-guides-draft.md` 与 `apps/muyon/lib/assistant/ui_guide_lookup.dart`（数据检索薄适配，数据稿由云线程交）；接口 `packages/muyon_module_api/lib/src/ui/guides.dart` 和空实现由UI-4b先定义；本任务测试 `apps/muyon/test/ui_guide_lookup_test.dart`，不重复建接口。复用云数据线程已有分割/来源/许可/审阅记录，不把 scripts/laya 工具调用题直接当智能UI指南 gold。

复用 `Future<List<UiGuideEntry>> UiGuideSource.lookup(UiGuideQuery query)`。Query含purpose/组件目录版本/数据画像；Entry含guideId/revision、适用条件、反例、案例证据ID、验证状态(proposed/evaluated)、来源split(train/dev)、catalogVersion。指南是软建议，不发权限、不扩组件/动作，不把启发式称成熟规则；真实样例未审也保留候选状态。

## 验收与步骤

- [ ] `sealed_test_cannot_generate_guide`与`guide_cannot_override_required_conflict`先失败；test来源条目拒绝进入正式指南，建议隐藏冲突仍被 UI-3a validator拒。
- [ ] 云数据稿每条登记条件/反例/证据/验证/版本，实际未知不补造；为harness和两种Provider使用同一查询接口。
- [ ] 接口可空/超时软降级，既有业务与文字继续；不能把指南当组件能力硬判据。
- [ ] 单测合同及 train/dev来源检查，文档review、各模式小样本对照单列；测试集只用于冻结评测，不反馈改指南。
- [ ] leader复核稿与数据来源后分别派文档/接口接入，不把本草案写成已部署的检索服务。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
