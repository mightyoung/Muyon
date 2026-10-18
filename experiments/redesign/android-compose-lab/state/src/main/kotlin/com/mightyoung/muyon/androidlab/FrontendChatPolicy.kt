package com.mightyoung.muyon.androidlab

/** Presentation policy only. Admission and permission checks remain in the host. */
fun frontendCanSend(text: String, status: String): Boolean =
    text.isNotBlank() && text.toByteArray(Charsets.UTF_8).size <= 4096 &&
        status.lowercase() in setOf("idle", "completed", "cancelled", "failed", "budget_exhausted", "rejected", "not_admitted")

fun frontendCanCancel(status: String): Boolean = status.lowercase() in setOf("submitting", "queued", "running", "streaming", "accepted", "existing", "events")
fun frontendNeedsReconcile(status: String): Boolean = status.lowercase() in setOf("unknown", "outcome_unknown", "reconciling", "binder_lost", "disconnected")
fun frontendStatusLabel(status: String): String = when (status.lowercase()) {
    "idle" -> "尚未发送"
    "submitting" -> "正在提交"
    "queued", "accepted", "existing" -> "已接收 · 等待执行"
    "running", "streaming", "events" -> "执行中"
    "cancel_requested" -> "已请求取消 · 等待终态"
    "completed" -> "已完成"
    "cancelled" -> "已取消"
    "failed", "rejected", "not_admitted" -> "执行失败"
    "budget_exhausted" -> "预算已耗尽"
    "unknown", "outcome_unknown", "binder_lost", "disconnected" -> "状态未知 · 仅查询恢复，不重新发送"
    "reconciling" -> "正在查询原请求"
    else -> "未知状态：$status"
}

/** Capture the displayed conversation at the click boundary; no fallback or automatic retry. */
fun frontendSubmit(port: ChatReadPort, conversationId: String, text: String): Boolean {
    if (!frontendCanSend(text, port.snapshot.conversations[conversationId]?.status ?: "idle")) return false
    port.submit(conversationId, text)
    return true
}
