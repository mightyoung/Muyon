package com.mightyoung.muyon.androidlab

/** Product order from the approved Muyon migration baseline, not inferred WorkBuddy tabs. */
enum class Destination(val label: String) { ASSISTANT("助手"), TASKS("任务"), DATA("资料"), SETTINGS("设置") }
enum class NavigationLayout { BOTTOM_BAR, RAIL }
enum class FocusSlot { NONE, DRAFT }

/** Local view memory only. A draft is exact UTF-16 input, never a dispatched request. */
data class PageMemory(
    val draft: String = "",
    val firstVisibleItemIndex: Int = 0,
    val firstVisibleItemOffset: Int = 0,
    val focus: FocusSlot = FocusSlot.NONE,
) {
    init { require(firstVisibleItemIndex >= 0 && firstVisibleItemOffset >= 0) }
}

data class ShellState(
    val selected: Destination = Destination.ASSISTANT,
    private val assistant: PageMemory = PageMemory(),
    private val tasks: PageMemory = PageMemory(),
    private val data: PageMemory = PageMemory(),
    private val settings: PageMemory = PageMemory(),
) {
    fun memory(destination: Destination): PageMemory = when (destination) {
        Destination.ASSISTANT -> assistant
        Destination.TASKS -> tasks
        Destination.DATA -> data
        Destination.SETTINGS -> settings
    }

    fun store(destination: Destination, memory: PageMemory): ShellState = when (destination) {
        Destination.ASSISTANT -> copy(assistant = memory)
        Destination.TASKS -> copy(tasks = memory)
        Destination.DATA -> copy(data = memory)
        Destination.SETTINGS -> copy(settings = memory)
    }

    fun select(destination: Destination): ShellState = copy(selected = destination)
}

fun navigationLayout(widthDp: Float): NavigationLayout {
    require(widthDp.isFinite() && widthDp > 0f) { "Logical window width must be finite and positive" }
    return if (widthDp >= 900f) NavigationLayout.RAIL else NavigationLayout.BOTTOM_BAR
}

/** Deliberately no connected, successful, authorized or effect-receipt variant. */
enum class PortAvailability { NOT_CONNECTED }
interface RustUiPort { fun availability(): PortAvailability }
object DisconnectedRustUiPort : RustUiPort { override fun availability() = PortAvailability.NOT_CONNECTED }

/** Synthetic display vocabulary for checks; NOT a production Rust DTO or authority. */
enum class LabTaskState { QUEUED, WAITING_CONFIRMATION, RUNNING, SUCCEEDED, FAILED, CANCELLED, PAUSED, INTERRUPTED }
data class TaskSafetyCopy(val label: String, val advisory: String? = null)

fun taskSafetyCopy(state: LabTaskState, cancelling: Boolean = false, platformOwned: Boolean = false): TaskSafetyCopy {
    val terminal = state in setOf(LabTaskState.SUCCEEDED, LabTaskState.FAILED, LabTaskState.CANCELLED, LabTaskState.PAUSED, LabTaskState.INTERRUPTED)
    val pendingCancellation = cancelling && !terminal
    val label = if (pendingCancellation) "取消中…" else when (state) {
        LabTaskState.QUEUED -> "排队中"
        LabTaskState.WAITING_CONFIRMATION -> "等待你确认"
        LabTaskState.RUNNING -> "执行中"
        LabTaskState.SUCCEEDED -> "已完成"
        LabTaskState.FAILED -> "失败"
        LabTaskState.CANCELLED -> "已取消"
        LabTaskState.PAUSED -> "已暂停"
        LabTaskState.INTERRUPTED -> "已中断（结果未知）"
    }
    val advisory = when {
        platformOwned && state == LabTaskState.INTERRUPTED ->
            "结果未知，重试前请先核实。\n平台任务：在设备页面查看，不支持逐项暂停或恢复。"
        platformOwned -> "平台任务：在设备页面查看，不支持逐项暂停或恢复。"
        state == LabTaskState.INTERRUPTED -> "结果未知，重试前请先核实。"
        pendingCancellation -> "等待执行服务确认；当前不能认定已取消。"
        else -> null
    }
    return TaskSafetyCopy(label, advisory)
}
