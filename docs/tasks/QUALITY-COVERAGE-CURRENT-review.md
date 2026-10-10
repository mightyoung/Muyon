# 当前覆盖率集成复审

候选 `21308deba8a3c77a3e4f14b5254297a3b1fd8dc7`；集成基线
`60b1efdbb2e38ea760c8f49077599fb5ea994602`。原 PR23 源
`30439f7c0a22d5d1ed9646120c65d6e190ec1f85` 不是本候选祖先；新 PR34
承接其门禁实现，修正已不符合当前契约的 schema1 正控。原 PR23 与分支保留，
没有为 PR 状态重接旧非法正控、手动关闭或删除。

非作者 review_reg3a 复审全部12文件，并独立运行9 checker、5 DA、10 gate
离线测试。生产 lib 无候选自行修改；八套各一次，失败出口保留。新增 codec
四项与 bool/date 运行时四项回归不弱化旧断言。

基线来自测量源 `bf09261ed57a69f49e60475c63e6ed1d619164e8`：
push CI38045851196、PR CI38045853186 的八套测试均通过，仅旧 API 分母漂移。
候选 JSON 严格等于 push 快照；除 source SHA/run ID 外，全部 summary/DA相同。
非作者逐 blob 重算401个源码 SHA256，核八包库存及43个 gate 的 DA集合/命中。
相对旧测量源633858b21ef1afcf8d5cfe6d0839f662f97b0b0a，11个 API变化文件
都有真实源码变化；31个相同源码 gate 的 DA不变、命中不降，旧逐文件 floor
无降低。model/transfer 源字节与门禁数据不变；edit_spec 两次均84/84。

19个未加载文件仍未知，不能推算全库覆盖率。自动门禁检查源码库存、DA身份及
命中数量，不比较内容 hash，也不能发现相同数量下命中行互换；本次人工全源
诊断补充这些检查，不把它描述成自动保证。测量契约、checker及门禁范围未改变。

临时普通组合 `0e7ea3197e7504ed7390465c7d0d1adee357f58e` 与新 PR checkout
`cdf4942beddca1b98178d3702de989f40cf66e0c` 父提交同为上述 develop与候选，
完整 tree 同为 `420aa8935a049a7de1f42ab5ad1dc0e62c9d1685`，差异为空。
新源 [push38046970607](https://github.com/mightyoung/Muyon/actions/runs/38046970607)
与当前组合 [PR38046974874](https://github.com/mightyoung/Muyon/actions/runs/38046974874)
均成功：analyze/test各8/8、API198、host1542/3skip、coverage门禁及Laya29通过。
PR全部401条记录同已审测量；新push仅transfer_service.dart:1203既有catch多命中，
DA与源码不变、无命中下降或等数量交换。四次命中全集并非恒定，保留已审floor，
不据正向波动重置基线。发布与远端读回见执行回报；原始日志、逐行诊断快照
与大产物不入仓库。
