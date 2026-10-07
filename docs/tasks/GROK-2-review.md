# GROK-2 审查

审查分支 `review/GROK-2` @ `9a76462`（grokbot）· 审查：leader 自审，不派子代理 · 2026-10-07

## 范围
只新增 `docs/reviews/coverage-drafts/` 下的三份文档：科研、原型、询价。

## 核对
| 项 | 结论 |
|---|---|
| 格式 | 按 ADR-0004 §8.2：surfaces、成员（附 `文件:行`）、operations（kind、members、工具或不开放理由）、缺口汇总 |
| 询价成员 | leader 按缩进规则重扫全部 35 个 `extension … on Store`，只漏了一个真实成员：`Inquiries.inquiriesOf`（`inquiries.dart:129`）。另有两处命中是函数类型的参数，属于误报 |
| Q10 | 科研的导出、导入按已确认的结论处理 |
| 数字 | surface、成员、操作数均为初稿；REG-3、REG-4 用 `analyzer` 实测，并做双向比对，以实测为准 |

## 结论
**合入。** 可选：REG-4 把 `inquiriesOf` 归入询价的只读查询操作。
