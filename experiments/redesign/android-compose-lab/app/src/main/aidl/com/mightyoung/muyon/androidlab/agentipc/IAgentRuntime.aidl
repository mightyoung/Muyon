package com.mightyoung.muyon.androidlab.agentipc;
import com.mightyoung.muyon.androidlab.agentipc.AgentReplyParcel;

// Private explicit methods. Liveness is a death token, never a callable UI callback.
// No root/path/private platform key, raw data, authority or native object is accepted.
interface IAgentRuntime {
    AgentReplyParcel connect(IBinder liveness);
    AgentReplyParcel start(String epoch, String lease, String requestId, int variant);
    AgentReplyParcel status(String epoch, String lease, String requestId, int variant, @nullable String runId);
    AgentReplyParcel current(String epoch, String lease);
    AgentReplyParcel lookup(String epoch, String lease, int keyKind, String key);
    AgentReplyParcel setVisibility(String epoch, String lease, long generation, boolean visible);
    AgentReplyParcel release(String epoch, String lease, long generation);
    AgentReplyParcel cancel(String epoch, String lease, String requestId, int variant, @nullable String runId);
    String submitSupplierRead(String epoch, String lease, String requestId, String text, String key, String revision);
    String supplierReadEvents(String epoch, String lease, String requestId, long after);
    AgentReplyParcel close(String epoch, String lease);
}
