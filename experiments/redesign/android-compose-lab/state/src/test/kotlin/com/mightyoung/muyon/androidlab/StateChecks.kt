package com.mightyoung.muyon.androidlab

private fun expect(value: Boolean, message: String) = check(value) { message }

fun main() {
    val checks = linkedMapOf<String, () -> Unit>(
        "default and ordered destinations" to {
            expect(Destination.entries.map { it.label } == listOf("助手", "任务", "资料", "设置"), "four product destinations")
            expect(ShellState().selected == Destination.ASSISTANT, "assistant default")
        },
        "selection changes page without modifying previous state" to {
            val original = ShellState()
            val changed = original.select(Destination.TASKS)
            expect(changed.selected == Destination.TASKS, "selection remained on assistant")
            expect(original.selected == Destination.ASSISTANT, "selection mutated prior snapshot")
        },
        "899 and 900 logical width boundary" to {
            expect(navigationLayout(899f) == NavigationLayout.BOTTOM_BAR, "899 must be bottom bar")
            expect(navigationLayout(900f) == NavigationLayout.RAIL, "900 must be rail")
            expect(navigationLayout(1280f) == NavigationLayout.RAIL, "1280 must be rail")
        },
        "invalid width rejected" to {
            for (width in listOf(-1f, 0f, Float.NaN, Float.POSITIVE_INFINITY)) {
                expect(runCatching { navigationLayout(width) }.isFailure, "invalid width $width")
            }
        },
        "raw draft survives navigation without normalization" to {
            val raw = "  e\u0301\n\uD800  "
            val state = ShellState().store(Destination.ASSISTANT, PageMemory(draft = raw))
            val returned = state.select(Destination.TASKS).select(Destination.DATA).select(Destination.SETTINGS).select(Destination.ASSISTANT)
            expect(returned.memory(Destination.ASSISTANT).draft.toCharArray().contentEquals(raw.toCharArray()), "raw UTF16 changed")
        },
        "draft focus and scroll retained together" to {
            val memory = PageMemory("未发送", 17, 43, FocusSlot.DRAFT)
            val state = ShellState().store(Destination.ASSISTANT, memory)
            val returned = state.select(Destination.TASKS).select(Destination.ASSISTANT)
            expect(returned.memory(Destination.ASSISTANT) == memory, "navigation lost memory")
        },
        "page memories and prior state remain independent" to {
            val original = ShellState()
            val changed = original.store(Destination.DATA, PageMemory("过滤输入", 2, 7))
            expect(original.memory(Destination.DATA) == PageMemory(), "mutated original")
            expect(changed.memory(Destination.ASSISTANT) == PageMemory(), "mutated sibling page")
            expect(changed.memory(Destination.DATA).draft == "过滤输入", "lost data memory")
        },
        "width changes do not own or replace state" to {
            val state = ShellState().store(Destination.ASSISTANT, PageMemory("保留", 9, 1, FocusSlot.DRAFT))
            for (width in listOf(390f, 900f, 1280f, 390f)) navigationLayout(width)
            expect(state.memory(Destination.ASSISTANT) == PageMemory("保留", 9, 1, FocusSlot.DRAFT), "layout modified state")
        },
        "negative list coordinates rejected" to {
            expect(runCatching { PageMemory(firstVisibleItemIndex = -1) }.isFailure, "negative index")
            expect(runCatching { PageMemory(firstVisibleItemOffset = -1) }.isFailure, "negative offset")
        },
        "Rust port has no connected or success default" to {
            expect(DisconnectedRustUiPort.availability() == PortAvailability.NOT_CONNECTED, "placeholder claims connectivity")
            expect(PortAvailability.entries == listOf(PortAvailability.NOT_CONNECTED), "lab must not invent successful host state")
        },
        "interrupted keeps explicit unknown warning" to {
            val copy = taskSafetyCopy(LabTaskState.INTERRUPTED)
            expect(copy.label == "已中断（结果未知）", "lost unknown label")
            expect(copy.advisory == "结果未知，重试前请先核实。", "lost verify-before-retry warning")
        },
        "cancelling never claims cancelled" to {
            val copy = taskSafetyCopy(LabTaskState.RUNNING, cancelling = true)
            expect(copy.label == "取消中…", "cancelling labelled final")
            expect(copy.advisory == "等待执行服务确认；当前不能认定已取消。", "missing pending distinction")
        },
        "platform task note takes priority" to {
            val copy = taskSafetyCopy(LabTaskState.RUNNING, cancelling = true, platformOwned = true)
            expect(copy.advisory == "平台任务：在设备页面查看，不支持逐项暂停或恢复。", "platform boundary lost")
        },
        "platform ownership cannot erase interrupted warning" to {
            val copy = taskSafetyCopy(LabTaskState.INTERRUPTED, platformOwned = true)
            expect(copy.advisory?.contains("结果未知，重试前请先核实。") == true, "platform note hid unknown outcome")
            expect(copy.advisory?.contains("平台任务：") == true, "unknown note hid platform boundary")
        },
        "ordinary queued waiting and running copy" to {
            expect(taskSafetyCopy(LabTaskState.QUEUED).label == "排队中", "queued")
            expect(taskSafetyCopy(LabTaskState.WAITING_CONFIRMATION).label == "等待你确认", "waiting")
            expect(taskSafetyCopy(LabTaskState.RUNNING).label == "执行中", "running")
        },
        "paused failed succeeded and cancelled stay distinct" to {
            expect(taskSafetyCopy(LabTaskState.PAUSED).label == "已暂停", "paused")
            expect(taskSafetyCopy(LabTaskState.FAILED).label == "失败", "failed")
            expect(taskSafetyCopy(LabTaskState.SUCCEEDED).label == "已完成", "success")
            expect(taskSafetyCopy(LabTaskState.CANCELLED).label == "已取消", "cancelled")
            expect(taskSafetyCopy(LabTaskState.SUCCEEDED, cancelling = true).label == "已完成", "stale cancelling overrode terminal")
        },
    )
    var failed = 0
    checks.forEach { (name, run) ->
        try { run(); println("PASS $name") }
        catch (error: Throwable) { failed++; println("FAIL $name: ${error.message}") }
    }
    check(failed == 0) { "$failed/${checks.size} state checks failed" }
    runLocalUiChecks()
    runDiagnosticChecks()
    runAgentServiceChecks()
    runAgentServiceWireChecks()
    println("${checks.size}/${checks.size} pure JVM state checks passed; Compose/Android runtime NOT_RUN")
}
