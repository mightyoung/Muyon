package com.mightyoung.muyon.product.ui.configuration

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agents.setup.*
import com.mightyoung.muyon.product.ui.system.*

/** Host owns editor lifetime/scope and receipt refresh. No create, save or start callback exists. */
@Composable
fun BotConfigurationScreen(
    editor: BotConfigurationEditor,
    hostSnapshot: DraftSnapshot,
    onLeaveWithDraft: () -> Unit,
    onQueryOriginalIntent: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    // Host MUST publish a new immutable snapshot after offerChoices/creation observations.
    // An explicit value parameter prevents strong skipping with a stable editor reference.
    require(hostSnapshot.draftId == editor.draft.snapshot().draftId &&
        hostSnapshot.scope == editor.draft.snapshot().scope)
    // Local counter observes text buffers/state-machine edits on the UI thread.
    var refresh by remember(editor) { mutableIntStateOf(0) }
    @Suppress("UNUSED_VARIABLE") val observed = refresh
    val snapshot = editor.draft.snapshot()
    val choices = editor.draft.choices()
    fun update(action: () -> Unit) { action(); refresh++ }
    fun back() { if (snapshot.step == SetupStep.NAME || !editor.editable) onLeaveWithDraft()
        else update { editor.back() } }
    BackHandler(onBack = ::back)
    FoundationTheme {
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("配置 Bot", style = MaterialTheme.typography.headlineMedium)
            Text("名称 → 用途 → 建议与修改 → 最终预览", style = MaterialTheme.typography.bodyLarge)
            FoundationTag("草稿 · 仅内存保留 · 未保存")
            Text("名称不等于权限；创建不等于启动。离开后由宿主保留草稿，进程退出不能恢复。")
            if (!editor.editable) {
                val (kind, detail) = when {
                    snapshot.cancelled -> FeedbackKind.Info to "草稿已关闭；由宿主决定恢复，不会创建或启动。"
                    snapshot.creation.status == CreationStatus.CREATED -> FeedbackKind.Info to "宿主回执表示已创建；没有自动启动。"
                    snapshot.creation.status == CreationStatus.PENDING -> FeedbackKind.Loading to "创建回执待核；不编辑、不重建，只查询原意图。"
                    else -> FeedbackKind.Unknown to "创建结果未知；不编辑、不重建，只查询原意图回执。"
                }
                FoundationFeedback(kind, "创建状态：${snapshot.creation.status}", detail)
                val intent = editor.queryIntentId
                FoundationButton("查询原意图回执", if (intent != null && onQueryOriginalIntent != null)
                    ({ onQueryOriginalIntent(intent) }) else null)
            } else when (snapshot.step) {
                SetupStep.NAME -> {
                    Text("1 · 为 Bot 命名", style = MaterialTheme.typography.titleLarge)
                    FoundationTextField(editor.name, { value -> update { editor.name = value } }, "名称（最多60字符）")
                }
                SetupStep.PURPOSE -> {
                    Text("2 · 它主要帮助你做什么？", style = MaterialTheme.typography.titleLarge)
                    Text("名称：${editor.name}")
                    FoundationTextField(editor.purpose, { value -> update { editor.purpose = value } }, "用途（最多8000字符）")
                    Text("下一步提供本地模板建议；不发送模型请求，不自动启用技能。")
                }
                SetupStep.CONFIGURATION -> {
                    Text("3 · 建议与修改", style = MaterialTheme.typography.titleLarge)
                    FoundationButton("查看本地角色建议", { update { editor.suggest() } }, kind = ButtonKind.Secondary)
                    snapshot.suggestion?.let { suggestion ->
                        FoundationTag("建议 · ${suggestion.source.label} · v${suggestion.source.version}")
                        Text(suggestion.role)
                        Text("可选建议，不覆盖手工修改，不授予权限。")
                        FoundationButton("采用角色建议", if (!snapshot.role.userLocked && editor.role == snapshot.role.value)
                            ({ update { editor.useSuggestion() } }) else null, kind = ButtonKind.Secondary)
                    }
                    FoundationTextField(editor.role, { value -> update { editor.role = value } }, "角色（可修改，最多160字符）")
                    Text("技能与资料 · 宿主提供的可选范围", style = MaterialTheme.typography.titleMedium)
                    if (choices.capabilities.isEmpty()) Text("暂无已接入技能；不自动添加建议技能。")
                    choices.capabilities.forEach { capability ->
                        FoundationSelection("${capability.id} · ${capability.reason}", capability.id in choices.selectedCapabilityIds,
                            { selected -> update { editor.select(
                                if (selected) choices.selectedCapabilityIds + capability.id else choices.selectedCapabilityIds - capability.id,
                                choices.selectedMaterialIds) } }, enabled = capability.available)
                        Text("输入：${capability.inputs}；输出：${capability.outputs}；版本：${capability.version}")
                    }
                    if (choices.materials.isEmpty()) Text("暂无宿主允许的资料范围。")
                    choices.materials.forEach { material ->
                        FoundationSelection(material.id, material.id in choices.selectedMaterialIds,
                            { selected -> update { editor.select(choices.selectedCapabilityIds,
                                if (selected) choices.selectedMaterialIds + material.id else choices.selectedMaterialIds - material.id) } },
                            enabled = material.available)
                    }
                    if (choices.invalidations.isNotEmpty()) {
                        FoundationFeedback(FeedbackKind.Error, "范围已变化，请重新确认", choices.invalidations.joinToString { "${it.id}: ${it.reason}" })
                        FoundationButton("清空并确认范围变化", { update { editor.select(emptySet(), emptySet()) } }, kind = ButtonKind.Secondary)
                    }
                    Text("权限：未授予新权限\n预算：尚未配置\n停止条件：尚未配置；不能启动任务")
                }
                SetupStep.REVIEW -> {
                    Text("4 · 最终预览", style = MaterialTheme.typography.titleLarge)
                    val preview = editor.preview()
                    if (preview == null) FoundationFeedback(FeedbackKind.Error, "预览已失效", "返回检查输入、技能和资料范围。")
                    else {
                        Text("名称：${preview.name}\n用途：${preview.purpose}\n角色：${preview.role}")
                        Text("技能：${preview.capabilities.joinToString { it.id }.ifEmpty { "未选择" }}")
                        Text("资料：${preview.materialScope.joinToString().ifEmpty { "未选择" }}")
                        Text("${preview.permissionSummary}\n${preview.costSummary}")
                        Text("实际费用：${preview.actualCost ?: "未知"}\n预占费用：${preview.heldCost ?: "未知"}")
                        Text("停止条件：尚未配置；本预览不授予权限、不保存、不创建、不启动。")
                    }
                    FoundationButton("保存 / 创建（尚未接线）", null)
                    FoundationButton("启动任务（不可用）", null, kind = ButtonKind.Secondary)
                }
            }
            editor.error?.let { FoundationFeedback(FeedbackKind.Error, "请检查草稿", it) }
            if (editor.editable && snapshot.step != SetupStep.REVIEW)
                FoundationButton("下一步", { update { editor.next() } })
            FoundationButton("返回", ::back, kind = ButtonKind.Secondary)
            FoundationButton("稍后配置 · 保留内存草稿", onLeaveWithDraft, kind = ButtonKind.Quiet)
        }
    }
}
