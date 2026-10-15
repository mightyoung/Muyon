package com.mightyoung.muyon.androidlab

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/** Independent local diagnostic. Closing invalidates observation, never native execution. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DiagnosticPanel(coordinator: RustDiagnosticCoordinator, onDismiss: () -> Unit) {
    var snapshot by remember(coordinator) { mutableStateOf(DiagnosticSnapshot()) }
    var lease by remember(coordinator) { mutableStateOf<DiagnosticLease?>(null) }
    DisposableEffect(coordinator) {
        val attached = coordinator.attach { snapshot = it }
        lease = attached
        onDispose { coordinator.detach(attached) }
    }
    val presentation = snapshot.presentation
    LaunchedEffect(coordinator, lease, presentation) {
        if (presentation is DiagnosticPresentation.Running) {
            delay(15_000)
            lease?.let { coordinator.expire(it, presentation.token) }
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp).testTag("rust-diagnostic-panel"),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("本地 Rust 检查", style = MaterialTheme.typography.headlineSmall)
            Text("仅检查随包声明。执行服务未连接，模型、附件与业务执行仍不可用。")
            when (val availability = snapshot.availability) {
                DiagnosticAvailability.NotChecked -> Text("尚未检查本地 Rust")
                is DiagnosticAvailability.Ready -> Text("本地 Rust 检查可用", modifier = Modifier.testTag("rust-diagnostic-ready"))
                is DiagnosticAvailability.Unavailable -> Text("本地 Rust 检查不可用 · ${diagnosticErrorLabel(availability.code)}", modifier = Modifier.testTag("rust-diagnostic-unavailable"))
            }
            if (snapshot.nativeBusy) Text("本地检查仍在运行；关闭或停止等待不会取消 Rust 调用。", modifier = Modifier.testTag("rust-diagnostic-busy"))
            Button(onClick = { lease?.let(coordinator::startHandshake) }, enabled = lease != null && !snapshot.nativeBusy,
                modifier = Modifier.testTag("rust-diagnostic-handshake")) { Text("检查本地 Rust") }
            Text("随包声明变体", style = MaterialTheme.typography.titleMedium)
            UiDiagnosticVariant.entries.forEach { variant ->
                OutlinedButton(onClick = { lease?.let { coordinator.startValidation(it, variant) } },
                    enabled = lease != null && !snapshot.nativeBusy && snapshot.availability is DiagnosticAvailability.Ready,
                    modifier = Modifier.fillMaxWidth().testTag("rust-variant-${variant.name}")) { Text(diagnosticVariantLabel(variant)) }
            }
            when (presentation) {
                DiagnosticPresentation.Idle -> Unit
                is DiagnosticPresentation.Running -> Text("正在检查本地 Rust…")
                is DiagnosticPresentation.LocallyTimedOut -> Text("已停止等待展示；Rust 调用返回前不能开始下一次检查。", modifier = Modifier.testTag("rust-local-timeout"))
                is DiagnosticPresentation.Failed -> Text("检查未通过 · ${diagnosticErrorLabel(presentation.code)}", modifier = Modifier.testTag("rust-diagnostic-failed"))
                is DiagnosticPresentation.Complete -> {
                    val report = presentation.report
                    Text("Rust 离线声明检查完成", modifier = Modifier.testTag("rust-diagnostic-result"))
                    Text("${diagnosticVariantLabel(report.variant)} · ${report.namespace}")
                    Text("声明：数据 ${report.dataCount} · 操作 ${report.operationCount} · 关系 ${report.relationCount} · 视图 ${report.viewCount}")
                    Text("目录代次 ${report.catalogGeneration}；声明数量不表示业务操作可执行。")
                }
            }
            if (presentation is DiagnosticPresentation.Running) TextButton(onClick = { lease?.let { coordinator.expire(it, presentation.token) } },
                modifier = Modifier.testTag("rust-stop-waiting")) { Text("停止等待展示") }
            TextButton(onClick = onDismiss, modifier = Modifier.testTag("rust-diagnostic-close")) { Text("关闭") }
            Spacer(Modifier.height(12.dp))
        }
    }
}

private fun diagnosticVariantLabel(value: UiDiagnosticVariant) = when (value) {
    UiDiagnosticVariant.EQUIPMENT -> "设备声明"
    UiDiagnosticVariant.RESEARCH -> "研究声明"
    UiDiagnosticVariant.INQUIRY -> "问询声明"
    UiDiagnosticVariant.SEEDED_EQUIPMENT -> "固定种子设备声明"
}
private fun diagnosticErrorLabel(value: DiagnosticError) = when (value) {
    DiagnosticError.NATIVE_LOAD -> "库缺失或加载失败"
    DiagnosticError.UNSUPPORTED_PROTOCOL, DiagnosticError.PROTOCOL_MISMATCH -> "协议或构建不兼容"
    DiagnosticError.INVALID_REQUEST_ID, DiagnosticError.REQUEST_MISMATCH -> "请求关联不一致"
    DiagnosticError.DECLARATION_REJECTED -> "声明被拒绝"
    DiagnosticError.INTERNAL_FAILURE, DiagnosticError.NATIVE_FAILURE -> "本地检查失败"
}
