# AUTH-1b B12 固定修复独立复审

目标 review/auth-1b-b12-boundaries@202bd2707bc1976b9c5d5c12517b1159c5800351；base af352970d8477f29e6b0ee04ebcbd4fde7539c34。工作区 /Users/muyi/Downloads/dev/muspace/.claude/worktrees/auth-1b-b12-review。只读源码/测试；无提交/push/merge。六个变更文件逐字节等于固定提交，未包含 B3 6c05bdf 或取消 WIP。

结论：原 B12 两个阻断关闭，未发现新增阻断/应改，建议接纳该边界修复提交，最终 exact-head CI 仍由父核验。不代表 B3/C 或生产自动调用完成。先前 af35297 的失败 gate 不追溯改写为通过；B3 取消阻断继续未接纳。

| 判据 | 结果/位置 |
|---|---|
| 正数 onProgress 返回后、chunk delivery 前再 guard | 满足：packages/supplier_core/lib/src/lan.dart:1013-1021 |
| 拒绝 chunk 不计 bytes | 满足：sent/count 移至 guard 之后；新真实 TLS 到期与真实 Registry availability 撤销均 failed、bytes_sent=0、inbox空 |
| 首次 namespace pin 不懒信祖先链接 | 满足：host_scope_authority.dart:175-195，完整词法祖先链检查在 pin 前 |
| 重开 owner/producer 后已有祖先链接仍unknown | 满足：新增scope测试实际重开SQLite并重构producer，返回null |
| macOS系统别名兼容与用户链接拒绝 | 满足：仅/tmp->/private/tmp、/var->/private/var精确目标；独立/tmp driver 实际验证两别名子目录可证明，用户leaf/ancestor链接均unknown |
| 旧正常发送/源证明/状态/聊天边界 | 满足此次31条定向验证；未跑full |

亲跑命令（全部unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy）：
- root flutter pub get 成功。
- apps/muyon flutter analyze --no-pub --fatal-infos --fatal-warnings：No issues found! (ran in 7.4s)
- apps/muyon flutter test --no-pub test/assistant_scope_authority_test.dart test/assistant_transfer_progress_boundary_test.dart test/assistant_transfer_capability_boundary_test.dart test/assistant_transfer_peer_identity_test.dart test/assistant_transfer_authorization_test.dart test/transfer_states_test.dart test/transfer_chat_backend_test.dart：00:10 +31: All tests passed!
- 独立/tmp/auth1b-b12-alias-driver_test.dart --plain-name 'independent macOS aliases'：00:00 +1: All tests passed!
- git diff --check base HEAD 无输出。

未运行full/变异/CI，作者1013/变异不算独立证据。新行为测试无sleep，真实SQLite和loopback paired TLS，不是真机/模型。SQLite仅复用经SHA649fdf22050829816ebec7dbeab5e7b974bd72487f84cbcf3529f3bd7b756430核对的官方dylib缓存，未复制测试产物。原始logs: /tmp/auth1b-b12-review-{pub,analyze,focused}.log；额外driver及log: /tmp/auth1b-b12-alias-driver_test.dart、/tmp/auth1b-b12-alias-driver.log。

pub get 自动生成两个macOS xcconfig修改和未跟踪apps/muyon/macos/Podfile；未主动清理或修改源树，交父处理生成物。固定六个提交文件未改变。

记录者仅保存非作者核实结论；目标代码 SHA 不变。最终文档 HEAD 的远端 SHA 与 CI 由执行回报提供。尚未合 develop/main/release。
