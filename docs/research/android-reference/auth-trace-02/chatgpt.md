# AUTH-TRACE-02 · ChatGPT Android 1.2026.272（只做 base 包静态分析）

样本信息沿用：/workspace/android-ref/chatgpt/1.2026.272/manifest.json。证书中等可信，用户已接受。
- jadx 在约 66% 时退出，但已写出约 4.9 万个 .java 文件，覆盖不全。
- 本次补充：apktool 反汇编出 smali（全量），以及 Valdi 模块的字符串（zstd 解压后）。
- 标签：包内直接证据 / 官方说明 / 推断 / 未知。

## 1. 调用链

### 1.1 Orbit 远程智能体（Codex 系的 app-server 协议）
1. **模式设定**：
   - 新建线程的参数里有 approvalPolicy、approvalsReviewer、sandbox（slj.java:32 起）。
   - 默认值：approvalPolicy="on-request"、approvalsReviewer="user"、sandbox="workspace-write"（ulj.java:86-92）。
   - 每一轮的参数里也带 approvalPolicy / approvalsReviewer / sandboxPolicy / clientUserMessageId（xsj.java）。
   - 证据：GPT-03，包内直接证据。
   - 推断：模式每轮随请求下发，切换模式影响下一轮。对正在执行的轮次有什么影响：未知。
2. **审批请求的身份**：
   - 由 roomId, messageId, threadId, turnId, requestId, method 六项组成；method 默认是 `mcpServer/elicitation/request`，也包括 `item/tool/requestUserInput`（obb0.java:25-32、mbb0）。
   - 证据：GPT-01，包内直接证据。
3. **决定和参数摘要**：
   - 决定可选 Accept / AcceptForSession / AcceptAlways / Decline / Cancel（krh）。
   - 存到本地 DataStore 的 `orbit_elicitation_responses`（acb0.java:9），每条记录是 {paramsDigest, decision, answered}，另有 saveStatus：pending / saved / failed / not_requested（hdb0.java:14）。
   - paramsDigest 的算法：先对请求参数 JSON 做规范化（o3z0.f），再取 SHA-256（o3z0.p）。
   - **复用旧决定前**，会把存下的 digest 和当前请求重新算出的 digest 比较（hdb0.smali:2028-2045、cwa0.smali:2690-2750）。
   - 证据：GPT-02，包内直接证据。也就是说，同一个 ID 但参数不同，不会沿用旧决定。
4. **谁最终执行**：Orbit 服务端或远程执行环境：未知。官方说明：Codex 文档的 approval policy；OpenAI 帮助中心"cloud browser"、"ChatGPT agent"（2026-10-13）。
5. **暂停原因**：客户端枚举里有 misalignment_monitor 和 guardian_circuit_breaker（k7c0.java:22-26）。
   - 配套文案："Auto-review did not approve some recent actions, so your dot was paused"。
   - 证据：GPT-03，包内直接证据。审查结果的完整字段（允许 / 建议确认 / 拦截 / 超时）客户端只看到暂停原因，其余未知。
6. **回执和恢复**："Reconnected. We couldn't confirm whether Orbit continued."、"Couldn't confirm this request. Check its status and try again."（包内直接证据，字符串）。具体的核对调用点：未知。

### 1.2 App 本机能力
- 本机日历工具的错误码包括 calendar_write_failed、read_only、outcome_unknown 等（pm9.java，GPT-05，包内直接证据）。
- 写入结果不确定时有显式的"未知"状态（包内直接证据）。它被谁读取、怎么核对：未知。
- 短信只走系统 SENDTO 意图，由用户自己在短信应用里发送（主报告 GPT-F08，包内直接证据）。
- 无障碍服务只能读屏幕内容（主报告 GPT-F07）。

### 1.3 生成式 UI（DIL）
- 模型写出的卡片只能触发白名单里的宿主动作。
  - 关键判定点在 dil_widgets.valdimodule 解压后的偏移 1444144（isAllowedModelWrittenDILHostActionType）和 1444277（"non-consuming actions cannot fall back to privileged actions"）。
  - URL 不可信时拒绝："untrusted URL in payload.url"（偏移 1444829）、"unsafe sandbox URL"（偏移 1444109）。
  - 证据：GPT-04，包内直接证据（字符串级；没有还原控制流）。
- **外部内容影响目标地址时，宿主在执行前拦截。**

### 1.4 连接器和云端浏览器
- 权限四档（每次询问 / 允许读 / 允许低风险 / 全部允许），"全部允许"不对托管工作区开放：官方说明（help.openai.com/en/articles/20001495，2026-10-13）。
- 客户端里有 tool_approval_once / tool_approval_session / tool_approval_always 三种审批类型（uvq0，包内直接证据）。
- 云端浏览器：首次访问新站点要授权；站点授权和"重大操作确认"是两回事；网站内容不能授权敏感操作：官方说明（20001280、20001423，2026-10-13）。客户端判定点：未知。

## 2. 六个问题
1. **自动模式**：
   - Orbit 有 approvalPolicy 和 approvalsReviewer（"user"，或由自动审查代审）（包内直接证据）。还剩哪些限制：sandbox 和暂停机制（包内直接证据），其余未知。
   - 连接器有四档：官方说明。
2. **新目标地址**：DIL 在执行前做可信 URL 规范化（包内直接证据）；云端浏览器的新站点授权只有官方说明，客户端未知；回调和重定向未知。
3. **外部内容**：DIL 有"模型写的内容"标记，并有特权动作不能回退的规则（包内直接证据）。官方说明：网站或站点工具里的指令不能授权操作。
4. **自动审查**：暂停原因两种（包内直接证据）。没有审查器时怎么办：未知。客户端没有本地风险分级器（推断：没有找到）。
5. **防重复**：
   - 审批决定绑定"请求身份 + 参数摘要"（包内直接证据）。
   - 动作执行本身是否幂等：服务端未知。客户端的 idempotencyKey 字段只在发布/分享类请求中出现（主报告 F13）。
6. **界面与真实执行**：有"无法确认 Orbit 是否继续"这一显式未知态（包内直接证据）。Stop 是否中止远程执行：未知。

## 3. 可以提出的动态实验（没有执行，需要你批准）
- **E-GPT-1**：测试账号加一个合成的 Orbit 线程。对同一个 requestId 先后给出不同参数，观察已保存的决定会不会被复用。
  - 需要：测试账号和 Orbit 访问权限。
