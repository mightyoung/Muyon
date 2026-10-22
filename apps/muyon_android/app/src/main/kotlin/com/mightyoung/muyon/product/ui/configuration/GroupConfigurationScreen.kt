package com.mightyoung.muyon.product.ui.configuration

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.ui.system.*

/** Read-only display projection of Rust GroupConfig/HostSnapshot, resolved by trusted host.
 * Null means unknown; display strings are never a second permission/budget ledger. */
data class GroupGovernanceDisplay(
    val humanAdministrators: String?, val permissionIntersection: String?,
    val budgetCeiling: String?, val knownActual: String?, val reserved: String?,
    val stopConditions: String?, val originalRequestIds: List<String>,
)

/** Controlled local preview only; no FFI, persistence, grant or execution action. */
@Composable
fun GroupConfigurationScreen(
    display: GroupGovernanceDisplay,
    selectedMode: String?, onModeChange: ((String) -> Unit)?,
    coordinatorId: String, onCoordinatorChange: ((String) -> Unit)?,
    onLeaveWithDraft: () -> Unit,
    modifier: Modifier = Modifier,
    onQueryOriginalRequest: ((String) -> Unit)? = null,
) {
    FoundationTheme {
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("群组协作方式", style = MaterialTheme.typography.headlineMedium)
            FoundationTag("离线配置预览 · 未保存 · 未运行")
            Text("人类管理员管理成员与权限，不自动成为任务协调 leader。")
            Text("人类管理员：${display.humanAdministrators ?: "未知"}")
            listOf(
                Triple("host_only", "不设协调者", "宿主按明确成员/依赖/顺序校验；仅离线校验已实现。"),
                Triple("fixed", "固定协调者", "配置可预览；底座执行返回 UnsupportedMode，尚未实现。"),
                Triple("per_task", "每项任务选择", "开始任务时指定协调者；执行尚未实现。"),
            ).forEach { (wire, label, detail) ->
                FoundationSelection("$label · $wire", selectedMode == wire,
                    onModeChange?.let { callback -> { selected -> if (selected) callback(wire) } })
                Text(detail)
            }
            if (selectedMode == null) Text("请选择协作方式；没有默认选择。")
            if (selectedMode != null && selectedMode !in setOf("host_only", "fixed", "per_task"))
                FoundationFeedback(FeedbackKind.Error, "不支持的配置模式", "保留原配置，由宿主核对；禁止执行。")
            if (selectedMode == "fixed") {
                FoundationTextField(coordinatorId, onCoordinatorChange, "协调成员 ID（仅草稿）")
                if (coordinatorId.isBlank()) Text("fixed 配置须指定协调成员；人类管理员身份不替代成员身份。")
            }
            if (selectedMode == "host_only") Text("host_only 的 coordinator_id 必须为空；宿主转换时须清空旧协调者。")
            Text("权限与预算", style = MaterialTheme.typography.titleLarge)
            Text("权限交集：${display.permissionIntersection ?: "未知；没有授予权限"}")
            Text("根预算上限：${display.budgetCeiling ?: "未知"}\n实际费用：${display.knownActual ?: "未知"}\n预占：${display.reserved ?: "未知"}")
            Text("停止条件：${display.stopConditions ?: "尚未配置；不可运行"}")
            Text("离线底座约束：深度1、同时活跃最多2、累计子任务最多8；轮次须由宿主设置非零上限。失败/取消不重置累计数。")
            Text("无协调者仍受宿主规则、四层权限交集、成员能力、根预算和停止条件约束。")
            if (display.originalRequestIds.isNotEmpty()) {
                FoundationFeedback(FeedbackKind.Unknown, "存在待核原请求", "保留原预占，禁止新派发；只能查询原请求回执。")
                display.originalRequestIds.forEach { requestId ->
                    FoundationButton("查询原请求：$requestId", onQueryOriginalRequest?.let { callback -> { callback(requestId) } }, kind = ButtonKind.Secondary)
                }
            }
            FoundationFeedback(FeedbackKind.Info, "生产接线尚未完成", "可信完整快照、持久恢复、网关、费用证明和协调者移交均待接线。离线校验不是执行授权。")
            FoundationButton("保存设置（尚未接线）", null)
            FoundationButton("运行群组（不可用）", null, kind = ButtonKind.Secondary)
            FoundationButton("返回 · 保留宿主草稿", onLeaveWithDraft, kind = ButtonKind.Quiet)
        }
    }
}
