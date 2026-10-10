# REG-4c 固定源复审与集成

固定源 `cb93c740718390ac5d54d8d193bc90095ea79178`；基线
`ef114b3ac620d6de135d4146847898776475b5fe`。非作者 review_reg3a 按 REVIEW.md
复审全部生产 diff、测试与变异脚本，无确定代码阻断；云端无 Flutter，本地仅静态核对。

- 范围：21 文件；四个通用写工具、覆盖清单、hosted Folio 入口限制及已分配目录修复；
  未夹带 F5b core、预算或历史污点实现，与其余八个待审 PR 无直接文件重叠。
- `inquiry_record_tools.dart` 保留类型专属 preflight、保护字段/quotation 价格白名单，
  事务内核当前选择/版本/引用，在效果前检查授权，并原子写业务回执。
- 目录仅在发现层筛 scope kind；显式空 authority 的 global 元数据仍可发现。
  prepare/invoke 范围、混合 selectedModules、null 模块回退、manual 路径及 MCP 来源绑定保留。
- Hosted 助手、palette、快捷入口与权限控件受限；库存 fixture 原样保留，
  新四项 CRUD 单独精确检查。没有 skip、失败豁免或门禁改动。

用户本轮明确回复“允许”，批准 REG-4c 精确库存 19→23 的限定例外及门禁通过后合 develop；
不将此前仅 REG-3a 的例外泛化到其他测试。

[源 CI](https://github.com/mightyoung/Muyon/actions/runs/38033992072)、
[PR CI](https://github.com/mightyoung/Muyon/actions/runs/38033994597)、
[专用验证](https://github.com/mightyoung/Muyon/actions/runs/38033991636) 均成功，日志独立读取。
专用五项安全变异与 scope 目录变异均由指定行为断言检出，恢复源码后 GREEN。
[固定源机器人复审](https://github.com/mightyoung/Muyon/pull/31#issuecomment-6095286014)
已终结且无主要问题；合前重读评论、review body、inline threads 无未裁定意见。

主动建立当前 develop 组合 `5f48b7b6a21b5ae625a506cd6d312f637d1d42d6`，
[CI38035359692](https://github.com/mightyoung/Muyon/actions/runs/38035359692) 成功：
analyze/test 各 8/8，host1512/3skip，doctor23，Laya29。
正常 no-ff 集成 `409c1616526d13e71352960c45951782fc85a5cb`，整树等于已测组合。
原始日志不入库；Mac goldens、真机及真实模型仍未验证。发布 SHA 与 CI 终态见执行回报。
