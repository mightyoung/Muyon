# Independent review: second followup / kind / migration rowid

结论：在冻结的三源码及专属 case 文件范围，未发现未闭合的具体阻断。三项原反例均已在固定 88c 源复现 RED，并以相同断言在当前源码通过。仅写本目录与 /tmp；未改生产或原生 tests，无真实 provider 请求。Synthetic newly-created fixture 的 claim/settle 只在内存/本地数据库构造实际 Owner 事实。

## 实际执行与计数

- 独立额外 7 测试：当前 7 PASS / 0 FAIL（independent-current-7.log），与原生新增覆盖分开计数。
- 固定 base 三原反例逐项运行：0 PASS / 3 FAIL，三条 EXIT101（independent-base-three-original-counterexamples.log）。base 的 tools/origin/workflow 为精确 git show；owner/agent 仅重定向模块路径，资源为 base 原字节，来源文件另存。
- base 全部 7 控制的原始记录为 3 PASS / 4 FAIL（independent-base-7-RED-complete.log）。额外第4失败是 logical_in_wire 负向严格要求 tool_history_invalid，旧版实际返回 agent_origin_chain_invalid；它没有作为第四项新产品缺陷或正常成功声称。当前该负向能在编码前拒绝，相关三表完整不变。
- 独立重跑原生 7 target：group_request_binding67 + group_runtime_bridge53 + group_runtime_store65 + agent_tools7 + agent_workflow16 + agent_owner11 + agent_child_tools3 = 222 PASS / 0 FAIL（independent-native-regression.log）。67 包含引入/历史覆盖，并非67新增。
- git diff --check PASS。父提供的 core373、固定 B326 属父验证，不计入本独审执行数。Clippy 仍 NOT_RUN（工具缺失，不安装、不加 allow）。

## 三项复核

1. 合法第二轮：真正 Owner settle/read review 后，以两个不同真实 call_ref 生成两个 followup。独立比较每轮整个 outbound envelope 及最终持久 payload 字符串（全部历史前缀、工具清单、wire name、IDs、arguments、review 内容），3 request chain 为 tool_consumed/tool_consumed/prepared，父链/root/Group 元数据一致；实际 charged132、used_calls2、最后 request 未 attempted。当前成功，旧版实际 tool_history_invalid。当前 adapter 仅把已发布且已选择的 exact registered wire name 逆映射为 logical，再交原 encoder。未改 encoder/validator/实验目录。

2. 不弱化负向：unknown wire、registered but unselected wire、把 logical 混入持久 wire history、unpaired response 四变体，在校准 synthetic payload/origin digest 后仍 tool_history_invalid，requests/origins/tool_steps 三表完整不变。真实重复 call_ref 仍拒绝，链保持2、无新身份。旧88c“第二轮拒绝”的历史证据不删；它不能再作为合法 distinct-ref 第二轮的限制，新真正向已实际通过。

3. kind/rowid：kind 仅改 local_read、workflow、unknown_kind 三变体均 attribution Err + HOLD；旧版 local_read 为 attribution None + group_hold false。真正执行 local_read 的合法 root/child、普通 standalone 和 workflow root 对话 Direct 控制不被误判，且不产生 execution authority。migration 用3个实际 completed 请求、AFTER meta UPDATE 的 INSERT OR REPLACE（17列相同，仅首 rowid1→4），旧版迁移 Ok，当前拒绝并完整 rollback：rowid/全列、version3、origin表不存在。正常迁移保留 rowids，后续 Fourth prompt 精确为 First/Answer First/Second/Answer Second/Third/Answer Third/Fourth。

## 限定源码结论与权限边界

workflow 在 kind 过滤之前验证 nonremote 全部 remote/current/list refs 和 kind 对应真实 root/parent/depth/conversation；损坏保持 error/HOLD。origin 仅两处 SELECT 增加 rowid，以现有事务尾读比较拒绝重排。tools 在 append 新 logical call 之前对历史使用 get_mut，未插入 null 字段、未作 underscore 猜测或 fallback。专属原生 tests 保留旧负向语义并加入真正向、正常迁移及合法 local_read 控制。

Group 最后仍 HOLD，execution_authority=false、cross_owner_atomic=false，读取映射 canonical first original 及当前链，并非 Gateway permit。FFI/lib/Host/gateway/claim/allowed 未改，无网络发送；不宣称跨库原子执行闭合。

## 可复跑命令与证据

工作目录 /workspace/mig20/crates，固定环境 PATH=/tmp/mig20-rust/bin:$PATH CARGO_HOME=/tmp/mig20-cargo CARGO_TARGET_DIR=/tmp/mig20-target RUSTFLAGS='-L native=/tmp/mig20-native-libs'。

```sh
cargo test --offline --manifest-path /tmp/mig20-second-history-independent-review/Cargo.toml --test current independent_ -- --nocapture
cargo test --offline --manifest-path /tmp/mig20-second-history-independent-review/Cargo.toml --test base independent_ -- --nocapture
cargo test --offline -p muyon-core --test group_request_binding --test group_runtime_bridge --test group_runtime_store --test agent_tools --test agent_workflow --test agent_owner --test agent_child_tools
```

/tmp 原 harness 源及 Cargo 文件均复制在 evidence/independent-*；绝对生产路径 import 在 base/current 相同。base 初次缺 include_str 资源的编译失败保留于 independent-base-7-RED.log，不当产品 RED。补充负向夹具首次 SHA LowerHex 编译错误仅修 /tmp 为逐字节 hex；最终通过版本已保存。父 probe01 IndexMut null 插入失败与 probe02 corrected get_mut 成功如实区分，不将01声称成功。

## 冻结 SHA256

```
973cdf3d9f9e7a85e95d3f72a59dc7b0b7bdb5ad92c5d10472a44fb528ed2f69  crates/muyon-core/src/agent/origin.rs
0c9212adc163dcd3d02cc2167b4d057430038dfc4331fdeb59c0dcf67b63a786  crates/muyon-core/src/agent/tools.rs
d2a9a2ab780ad9d4ccc90fb77dbe1ac4980fa17609f6dccf72aa4ae64b1f0476  crates/muyon-core/src/agent/workflow.rs
d164974d6c4ec9c7bde8eb63f18cbf41780b5f381b57f66bcce94630abab4989  crates/muyon-core/tests/support/group_origin_gate_cases.rs
```
