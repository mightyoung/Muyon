# PR33 Mac golden 诊断文档复审

固定源 `5018263658950d85eddd61af6962f3617c518fdc`；集成基线
`d3deca3b3bb3ecdb45e53f5f6fb22878fcc4bec9`。本轮只采纳诊断文档，不采纳 golden 重建。

非作者 review_grok7 按 REVIEW 核范围、历史 Git 对象和证据边界，无确定阻断：
源差异仅新增 QUALITY-MACOS-GOLDEN-AB.md，79 行；生产、测试、字体、golden、
容差、skip 和 workflow 均未改变，diff --check 通过。历史 settings PNG 与 Noto
字体的 Git 字节和摘要相符；文档明确测量源为 e192，不把历史三例写成当前全量。

强制 smoothing off/on 没有提供修复；OS 升级仅为时序证据，精确 tester、旧系统
字体及机制未确定。受控基线重建是未执行提案，需要另行逐图视觉认可与基线政策
批准。合入本文不授权生成或覆盖 PNG、安装或恢复环境，也不关闭 Mac 门禁。

本云端无 Mac/Flutter/Dart、无已下载原始 Library 包。A/B 图片、遥测、安装历史
与资源数字仍为作者报告，本轮未独立复现；文档限定范围，故该限制不阻断诊断
材料合入。原始日志与图片不进仓库。

源 [push38028878646](https://github.com/mightyoung/Muyon/actions/runs/38028878646)
及 [PR38028880944](https://github.com/mightyoung/Muyon/actions/runs/38028880944)
均 success。固定源评论、review 与 inline thread 查询为空，无待裁定意见；没有
把无意见当作 bot 已审。当前组合、发布与 CI 终态见唯一集成执行者回报。

PR30 `ac0a0efa921236a765d7e9c56f3e2bf8a22acd0f` 另经非作者 review_reg3a
逐项核七文件：三个交接文档及 recomputation.dart 字节相同；publication.dart 与
测试已吸收并扩展，recomputation 测试仅删重复 import。PR21 是基线祖先，PR30
提交本身不是；没有待移植独有内容，不重复应用旧 H1 patch。本轮未关闭该 PR。
