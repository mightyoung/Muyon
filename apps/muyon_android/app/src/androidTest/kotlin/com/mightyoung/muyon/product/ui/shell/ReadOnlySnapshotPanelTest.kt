package com.mightyoung.muyon.product.ui.shell

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ReadOnlySnapshotPanelTest {
    @get:Rule val compose = createComposeRule()
    @Test fun unknownCostsAndUnavailableCapabilitiesRemainExplicit() {
        var reads = 0
        val snapshot = ReadOnlySnapshot("original", "native-child", "unknown", "unknown", "2620", "0", "intent_recorded_outcome_unknown")
        compose.setContent { MaterialTheme { ReadOnlySnapshotPanel(snapshot, "", false, { reads++ }) } }
        compose.onNodeWithText("实际费用：未知").assertExists()
        compose.onNodeWithText("已记录取消意图；尚未确认取消；不代表回滚。").assertExists()
        compose.onNodeWithText("任务、来源与可操作卡片：缺完整可信事实，暂不可用。").assertExists()
        compose.onNodeWithText("查询只读候选与状态").performClick()
        assertEquals(1, reads)
        compose.onNodeWithText("确认本次外发").assertDoesNotExist()
    }

    @Test fun refreshRetainsObservedContentAndCanBeUnavailable() {
        val snapshot = ReadOnlySnapshot("original", "native-child", "completed", "completed", null, null, "unavailable")
        compose.setContent { MaterialTheme { ReadOnlySnapshotPanel(snapshot, "当前只读来源不可用", true, null) } }
        compose.onNodeWithText("原请求状态：completed").assertExists()
        compose.onNodeWithText("当前只读来源不可用").assertExists()
        compose.onNodeWithText("查询只读候选与状态").assertIsNotEnabled()
    }
}
