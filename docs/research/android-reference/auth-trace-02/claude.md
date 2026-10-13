# AUTH-TRACE-02 · Claude Android 1.261009.20（只做 base 包静态分析）

样本信息沿用：/workspace/android-ref/claude/1.261009.20/manifest.json。APK SHA-256 9807d321…122a；证书 305a1e8a…64a0，中等可信，用户已接受。
本次新增分析：apktool 2.7.0 反汇编出 smali，补上 jadx 没解出来的方法体。jadx 有 162 处反编译错误，本文用到的 eka.i、yla.b、CCRPermissionActionWorker.f 都属于 jadx 解不出、改看 smali 的情况。
标签只用四种：**包内直接证据 / 官方说明 / 推断 / 未知**。下文 evidence/ 指本目录的证据文件。

## 1. 调用链

### 1.1 手机 App 自身：本机"客户端工具"（日历等在本机执行的工具）
1. **模式设定**：每个工具有三档：NEVER / ASK / ALWAYS（v7z.java:14-19）。
   - 读取入口 k8z.g(t7z)，k8z.java:549-557：工具被开关关掉，或 SharedPreferences 里有 `paused__<key>` 时，一律按 NEVER 处理。
   - 证据：CL-01，包内直接证据。
2. **随请求传播**：e8z 只把档位为 ASK/ALWAYS 的工具放进可用工具列表（e8z.smali:75-90 调 k8z.g，再调 v7z.a()）。
   - v7z.a() 的定义是 `this==ALWAYS||this==ASK`（包内直接证据）。
   - 推断：NEVER 档在发请求之前就把工具剔除，模型看不到它。这个列表是否写进 completion 请求体，未逐行验证。
3. **自动执行还是询问**：k91.smali:2100 调 k8z.r(toolName, input)。
   - r 为真的条件：档位 == ALWAYS，并且 g6z.c(input, 权限设置) 为真（k8z.smali:1751 起）。
   - 为真时启动 de1 → yla.b，直接执行；否则走审批界面。
   - 证据：CL-01，包内直接证据。g6z.c 具体检查什么（比如允许哪些日历）未逐个工具展开，未知。
4. **用户批准**：yla.f(toolUseId, always)，yla.java:119-135。
   - 先从内存的待批表里按 tool_use_id 取出当次请求（bp2，含工具名和输入）。
   - 选了"始终允许"就调 g6z.j，把权限写成持久设置。
   - 然后启动 kv9#6 → yla.b。
   - 助手消息结束时，还没回答的请求会被清掉，日志记 "client tool ask expired"（yla.java:173-176）。
   - 证据：CL-02，包内直接证据。
5. **执行**（yla.b，只在 smali 里能读到）：
   - 第一步：`obj.b0(...)` 认领（yla.smali:359）。
   - 返回"已认领"（ice）时，调 `k8z.h(...)` 执行工具（yla.smali:482）。
   - 返回"已有记录"（hce）时不执行，回给模型一条错误结果："This tool call already ran on this device; its result is not available."（yla.smali:409-445）。
   - 证据：CL-03，包内直接证据。
6. **认领的实现**：eka.i(account, conv, toolUseId, executedAt)：
   - 用 `INSERT OR IGNORE` 写入 executed_client_tools，看返回的 rowid 是否为 -1，转成布尔值（eka.java:507-533 的 dump、kv9.java:318）。
   - zc0.smali:2887 起：插入成功，并且内存集合 eka.i.add 也返回 true，才算"已认领"（ice），否则是 hce。
   - 证据：CL-03，包内直接证据。obj.b0 → zc0 → eka.i 这一段的连接是推断：两边字段和返回类型一致，但 obj 是 R8 合并后的类。
7. **回执**：执行结果经 yla.h → faz.f 回传。抛异常时回 "An unexpected error occurred."（yla.smali:540-580，包内直接证据）。
   - faz.f 最终调用 `…/tool_result`（RecordToolResultRequest：tool_use_id, content, is_error）：推断（接口路径和请求类都在，调用点未逐行连上）。

### 1.2 Claude Code 远程会话（手机只是遥控器）
- **设模式**：手机发 `control_request`，subtype 为 `set_permission_mode`（anz.java:442-445）。
  - 可选值：default / plan / auto / acceptEdits / dontAsk / bypassPermissions（isn.java:62）。
  - 组织策略对象：PermissionModePolicy(autoPermissions, bypassPermissions)（ebo.java:41）。
  - 证据：CL-05，包内直接证据。
- **谁执行权限检查**：本地机器上的 Claude Code CLI，或云端执行环境。
  - 官方说明：Claude Code 文档 permission-modes / remote-control，访问日期 2026-10-13。远程端不能选 Bypass；权限提示会一直开着等回答。
  - 手机端只负责下发模式、回传决定。
- **通知栏审批**：CCRPermissionActionWorker 的参数只有 sessionId, requestId, toolUseId, accountId, organizationId, allow, comment, toolName（fk4.java:19-27）。
  - 推送里缺 tool_use_id 时会照样发出空值（CCRPermissionActionWorker.smali:532）。
  - **客户端参数里没有输入摘要或版本号**，绑定完全依赖服务端的 requestId。
  - 证据：CL-04，包内直接证据。服务端怎么校验：未知。

### 1.3 云服务
服务端的权限判断、自动审查（"Auto mode… checks each tool call for risky actions and prompt injection"，res_en:1845）都在服务端或 CLI，客户端看不到：未知。官方说明：Claude Code auto mode 用一个后台分类器审查调用（code.claude.com/docs/en/permission-modes，2026-10-13）。

## 2. 六个问题
1. **自动模式或类似模式**：
   - App 聊天：每个工具 NEVER/ASK/ALWAYS 三档。ALWAYS 只跳过"询问"，还要过 g6z.c 的输入检查，tool_use_id 认领照常执行（包内直接证据）。
   - Code：auto、bypassPermissions 等模式。不能从手机审批的请求提示 "This request can't be approved from your phone"（包内直接证据，字符串）。
   - 切换模式对排队中、执行中、恢复的任务有什么影响：App 端未发现相关代码；Code 端由 CLI 决定，未知。
2. **新目标地址**：
   - MCP App 界面的域名必须等于 `hash(connector URL)` 的前 32 位加上 `.claudemcpcontent.com`，不符就抛 DomainValidationException（qkk.java:73-94，CL-06，包内直接证据）。也就是说，嵌入界面的来源域在渲染前被绑定到连接器 URL 上。
   - 连接器给出的链接 App 不会打开："The connector sent a link that Claude won't open"（字符串，包内直接证据）；在哪儿判定、判定规则是什么：未知。
   - 模型接口地址固定为 claude.ai / api.claude.ai（主报告）。浏览器站点、回调地址的首次访问判定：App 内未发现，未知。
3. **外部内容是否标为不可信**：
   - stop_reason 里有 `prompt_injection_risk`（主报告 exec-summary 证据 04）：服务端会因此停下，客户端只负责显示。
   - 客户端没发现"外部内容影响授权"的路径，也没发现"不可信内容收紧写入权限"的逻辑：未知。
4. **自动审查**：
   - App 聊天侧没有客户端审查器；ALWAYS 档下是确定性规则（档位加 g6z.c）。
   - Code 的 auto 审查器在 CLI 或服务端：官方说明；审查结果的字段客户端看不到，未知。
   - 不同产品的审查结果枚举不能假设相同。
5. **防重复的副作用**：
   - 防重身份是 (account, conversation, tool_use_id)。**没有参数摘要**；同一个 ID、不同参数会被当成已执行而拒绝（推断）。
   - **先写入认领再执行**（包内直接证据）。保证"同一设备最多执行一次"，但不保证"执行一次以上"。
   - 发送后崩溃、回执丢失时：下次给模型返回 "already ran … result is not available"，不重跑，也不核对真实结果。**结果未知时直接按"不可用"回给模型，不做核对。**
   - 认领只在本机。跨设备是否会重复执行：未知。
   - 这张表只被这个认领流程读写，全包没有其他 SELECT（rg 检索，包内直接证据）。
6. **界面与真实执行**：
   - Stop 只取消流，stop_reason 记为 user_canceled。已经认领的本地工具不会撤销（推断）。
   - SSE 的 retract（撤回已显示内容）只影响显示，不碰 executed_client_tools（推断：retract 处理器里没有引用这张表）。
   - 通知栏审批没有绑定输入或版本，见 1.2。

## 3. 可以提出的动态实验（**没有执行，需要你批准**）
- **E-CL-1**：隔离测试机加测试账号，只用合成日历数据。在本地工具执行后、tool_result 回传前断网并结束进程，观察重启后的行为，验证"最多一次、不核对"这条结论。
  - 风险：需要登录账号和日历权限。
  - 需要你授权的事：测试账号、测试设备、日历权限。
