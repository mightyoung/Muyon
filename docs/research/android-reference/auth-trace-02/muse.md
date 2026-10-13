# AUTH-TRACE-02 · Meta Muse 11.0.0.8.164（只做静态分析）
样本信息见 muse/11.0.0.8.164/manifest.json，签名与公开摘要一致。jadx 有 138 处反编译错误。标签：包内直接证据 / 官方说明 / 推断 / 未知。

## 1. 调用链
1. **审批的来源**：ApprovalOrigin 分 SERVER（服务端发起）和 LOCAL_HITL（本机发起）（主报告 MU-F07）。
   - 本机审批：HatchAgentPermissionsRepository.requestLocalApproval 挂起等待，completeLocalApproval 恢复；无法解析的决定直接返回失败（HatchAgentPermissionsRepository.java:5307-5323）。
   - 证据：MU-01，包内直接证据。
2. **提交决定**：decideApprovals(list, z) 的每一项是 AgentPermissionApprovalDecision(approvalId, decisionKind, alwaysScope, reason)（:535-541、:5610-5616）。
   - decideServerApprovals 没反编译出来（:5358-5363），未知。
   - 多个决定合并后可能是 Success / Failed / PartiallyApplied（:5394-5396，包内直接证据）。
   - **客户端提交的决定只带 approval_id，没有载荷摘要或版本**（包内直接证据）。服务端是否把决定绑定到具体载荷：未知。
3. **决定类型**：ALLOW_ONCE / SESSION / TODAY / ALWAYS / AUTO_ALLOW / DENY / DENY_ALWAYS / TIMED_OUT。
   - 授权生效范围：SESSION / TODAY / DURABLE。
   - 授权种类：CONNECTOR_OVERRIDE、NETWORK_RULE（网络规则）、TRANSIENT_*（临时授权）。
   - 证据：主报告 MU-F07，包内直接证据。AUTO_ALLOW 由谁、按什么规则判定：服务端，未知。
4. **云端虚拟机浏览器**：
   - noVNC 有"只看"和"可输入"两种开关（MU-F05）。
   - 接管靠租约 BrowserControlLease(taskId, takeoverId, controlOwner, controlExpiresAtMs)，包内直接证据；租约过期后怎么处理：未知。
5. **结账、发送媒体、打开本机应用**都有专用审批载荷类（包内直接证据）。官方说明：Meta 帮助中心"guidance and approval"（主报告 C2）。

## 2. 六个问题（简答）
1. 有 AUTO_ALLOW 和 ALLOW_ALWAYS（包内直接证据），具体规则未知。切换模式对进行中任务的影响：未知。
2. NETWORK_RULE / TRANSIENT_NETWORK_GRANT 说明网络目标有规则（包内直接证据）；在哪儿判定：服务端，未知。
3. 是否标记不可信内容：未找到，未知。
4. TIMED_OUT 是一种显式决定（包内直接证据）。有没有自动审查器：未知。
5. 防重复执行：客户端未找到相关逻辑，未知。审批只用 approval_id 去重（推断）。
6. 有部分生效（PartiallyApplied）这种显式结果（包内直接证据）。Stop 和撤权对进行中任务的影响：未知。
