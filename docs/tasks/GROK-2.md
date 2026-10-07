# GROK-2 能力覆盖清单初稿（科研、原型、询价）

分支 `task/grok-2-coverage-drafts` · 执行：grokbot（云端，**只做静态核对**：读代码、grep、写文档；不运行 Flutter，不改任何 `.dart` 文件）· 审查：leader 抽查 · 给谁用：REG-3（科研、原型）、REG-4（询价）

## 背景
[ADR-0004](../adr/0004-module-contract-v2.md) §8.2 要求每个模块在 `lib/src/coverage.dart` 声明「能力覆盖清单」：先列出所有业务操作面（surfaces），把每个公开成员归到恰好一个操作（operation），每个操作要么有工具承载，要么写明不开放的原因。CI 会做「操作面上的公开成员集合 = 清单里成员的并集」的双向比对，所以清单必须一个不漏。

[GROK-1](../reviews/2026-10-07-adr-0004-static-checks.md) 已经列出了科研（§4）和询价（§5）的写成员。本任务在此基础上补齐**所有公开成员**（包括只读的），按 §8.2 的格式写出初稿，供 REG-3、REG-4 直接改成 Dart 常量。

## 只做这些
产出三份 Markdown 文档，放在 `docs/reviews/coverage-drafts/`：`research.md`、`prototype.md`、`inquiry.md`。每份包括：
1. **surfaces 表**：库路径 + 类或扩展名。询价要列全 35 个 `extension … on Store` 和 `Store` 本体；科研要列 `WorkbenchStore`、`OutlineStore`、`CardStore`、`ResearchExchange` 等；原型对照 `packages/prototype_module/lib`，列出实际存在的操作面。
2. **成员清单**：每个 surface 的全部公开成员（方法、getter、setter，排除下划线开头和 `@visibleForTesting` 的），每个附 `文件:行`。同时标出成员总数，供 REG 用 `analyzer` 实测时对照。
3. **operations 表**，每行包括：
   - `id`：用 `<模块>.<动词或名词>` 形式；
   - `kind`：`query` / `write` / `external` / `internal`；
   - `members`：本操作包含的成员，每个成员恰属一个操作；
   - 承载方式（二选一）：
     - 已有工具：写真实工具 ID（科研、原型以代码里注册的为准，询价见 `apps/muyon/lib/platform/inquiry_write_tools.dart`、`business_tools.dart`）；
     - 不开放：写 `NotExposedKind` 和理由（理由 ≥ 15 字）。

   科研的导出、导入类，必须按 ADR-0004 §12.1 Q10 已确认的结论处理：
   - `exportReport`、`exportClaimDrafts` 开放；
   - 其余导出、导入，以及设备收发，记为 `deferred(REG-3)`。
4. **缺口汇总**：
   - 需要新增工具才能覆盖的操作（建议的工具 ID 与效应）；
   - 归 `internal`、`notBusiness` 的成员及理由；
   - 拿不准的归类。

## 不做
不改代码、测试或已有文档；不运行 Flutter；拿不准就写「待 REG-3/REG-4 确认」，不要猜。原始 grep 输出不进仓库。

## 回报
分支与提交哈希；三份文档路径；每个模块的 surface 数、成员数、操作数、建议新增工具数；拿不准的项。
