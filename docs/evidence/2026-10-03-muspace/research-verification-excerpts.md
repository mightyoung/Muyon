# 验证记录（2026-10-02）

## research-skill 集成第一期（2026-10-03）

分支 `feat/research-skill-integration`，参考 research-skill v6.5（`bd9e9d8`）。

- `flutter analyze`：无问题。`flutter test`：40 项通过（含 Codex 审查后的 3 项回归测试），新增 `research_skill_test.dart`（识别、过滤、修订、绑定、引用、回写草稿、报告引用）和 `skill_ui_test.dart`（桌面尺寸下的文库修订视图、论文绑定、引用链接、阅读器绑定卡片）。夹具为手写合成数据，结构对照 v6.5，未复制上游文件。
- 端到端：复制 v6.5 `examples/v2-case/update`，为其中 `p-recent-v1`（`9999.00004v1`）补一份合成 `paper.pdf` 和 arXiv 风格 `manifest.json` 后导入。绑定到 `p-recent-v1@2`，方法 `arxiv_manifest`，哈希一致。在该 PDF 上写一条笔记并导出草稿：
  - 草稿原样追加到 `research/claims.jsonl`，`check-research.py --strict-v2` 输出 FAIL（缺 `locator_reliability`、`supports_statement`、`scope`），符合"未补全不能冒充正式证据"的设计。
  - 人工补全 `locator.page`、`locator_reliability`、`supports_statement`、`scope` 后追加，输出 PASS；保留或移除 `workbench` 溯源字段、保留 `locator.pdf_page` 均通过。
- 未验收：PDF 原生渲染、Android/macOS/Windows 上的保存对话框。再导入同一项目属于第二期。


--- 以下为同一来源后段摘录 ---



- 本机只有 Xcode Command Line Tools，`xcodebuild -version` 提示需要完整 Xcode；未完成 macOS 原生构建。Windows 原生构建需要 Windows 开发机。本轮没有提交或发布任何安装包。
- Android 构建/安装成功并不能证明原生文件选择器、PDF 渲染、导出目录写入已在设备端可用。这些仍需目标平台实机验收。
- Markdown 阅读、PDF 阅读组件、定位文字笔记及证据关联到 Markdown 提纲均已在源码实现；widget 测试覆盖 Markdown/笔记和提纲关联，PDF 真机渲染未验收。笔记存放于 SQLite，不写进 PDF；导出的报告是附来源记录的 Markdown 草稿，不是完成排版、引用样式与投稿检查的论文。
- 文件包可通过任何人工文件传输渠道送往异网设备；当前应用提供用户显式开启、短期配对、单文件的 LAN 传输；不提供后台同步、云同步或远程自动执行。任务包中的代码/数据引用是描述字段，具体文件、版本、环境、许可证和实验可重复性由执行方核验。
- 结果导入先保留为未接纳运行；“接纳为证据”是用户操作，不对科学真实性作自动判断。原始 JSONL 字段及状态保留，缺失或多义的关系不自动推断。
- 导入资料复制到应用私有目录。应用尚无用户级 ACL、加密库或协作权限模型；不要把这版当作多用户服务器。
