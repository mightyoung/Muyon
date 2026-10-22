package com.mightyoung.muyon.androidlab.agentipc

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.androidlab.*

/** Offline synthetic run only. Generic chat/model/business execution remain disconnected. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AgentRuntimePanel(client:AgentServiceClient,onDismiss:()->Unit) {
    val view=client.presentation
    DisposableEffect(client){client.attach();onDispose{client.detach()}}
    ModalBottomSheet(onDismissRequest=onDismiss){
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp).testTag("agent-service-panel"),verticalArrangement=Arrangement.spacedBy(12.dp)){
            Text("独立进程 · 离线合成运行",style=MaterialTheme.typography.headlineSmall)
            Text("Agent 在独立执行进程中运行，仅使用内置合成样本。通用聊天、模型与真实业务仍未接通。")
            Text(view.message,modifier=Modifier.testTag("agent-service-observation"))
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
                OutlinedButton(onClick=client::connect,enabled=!view.observationBusy,modifier=Modifier.testTag("agent-service-connect")){Text("连接与核实")}
                OutlinedButton(onClick=client::refresh,enabled=!view.observationBusy,modifier=Modifier.testTag("agent-service-current")){Text("核实当前记录")}
            }
            if(view.observationBusy)Text("状态请求尚未返回；不会排队提交新的运行。")
            val native=view.snapshot
            if(native!=null){
                Text("Rust 状态：${native.phase.name} · 修订 ${native.meta.revision}")
                native.run?.let{AgentRunDetails(it)}
            }
            val startEnabled=view.transport==UiAgentTransport.CONNECTED && view.visible && native?.phase==UiAgentServicePhase.READY &&
                !view.observationBusy && !view.startPending && (native.run==null || native.run is UiAgentRun.Terminal || native.run is UiAgentRun.SettledNoAdmission)
            Text("显式开始新的合成运行",style=MaterialTheme.typography.titleMedium)
            UiAgentVariant.entries.forEach{variant->
                OutlinedButton(onClick={client.start(variant)},enabled=startEnabled,modifier=Modifier.fillMaxWidth().testTag("agent-service-start-${variant.name}")){Text(when(variant){UiAgentVariant.EQUIPMENT->"设备样本";UiAgentVariant.RESEARCH->"研究样本";UiAgentVariant.INQUIRY->"问询样本";UiAgentVariant.SEEDED_EQUIPMENT->"固定种子设备样本"})}
            }
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){
                TextButton(onClick=client::cancel,enabled=view.transport==UiAgentTransport.CONNECTED && view.selected!=null,modifier=Modifier.testTag("agent-service-cancel")){Text("请求取消")}
                TextButton(onClick=client::closeRuntime,enabled=view.transport==UiAgentTransport.CONNECTED,modifier=Modifier.testTag("agent-service-stop")){Text("请求关闭执行进程内核")}
            }
            Text("请求取消、关闭或连接中断均不表示运行已取消；以 Rust 返回的原记录为准。离开前台会发出停止并解除绑定，重新打开不会重放运行。")
            TextButton(onClick=client::lookupOriginal,enabled=!view.observationBusy && view.selected!=null,modifier=Modifier.testTag("agent-service-lookup")){Text("核实原请求")}
            view.historical?.run?.let{Text("原请求核实",style=MaterialTheme.typography.titleMedium);AgentRunDetails(it)}
            TextButton(onClick=onDismiss,modifier=Modifier.testTag("agent-service-dismiss")){Text("关闭面板")}
            Spacer(Modifier.height(12.dp))
        }
    }
}
@Composable
private fun AgentRunDetails(run:UiAgentRun){
    Text("原请求：${run.intent.requestId}")
    val identity=when(run){is UiAgentRun.Admitted->run.identity;is UiAgentRun.Running->run.identity;is UiAgentRun.Terminal->run.summary.identity;is UiAgentRun.Unresolved->run.identity;else->null}
    Text(when(run){is UiAgentRun.Queued->"已易失排队，尚未持久接纳";is UiAgentRun.Admitted->"Rust 已持久接纳";is UiAgentRun.Running->"Rust 运行中";is UiAgentRun.Terminal->when(run.summary.terminal){UiAgentTerminal.COMPLETED->"Rust 已确认实际运行完成";UiAgentTerminal.CANCELLED->"Rust 已确认取消";UiAgentTerminal.FAILED->"Rust 已确认运行失败";UiAgentTerminal.BUDGET_EXHAUSTED->"Rust 已确认预算耗尽";UiAgentTerminal.OUTCOME_UNKNOWN->"Rust 返回结果未知"};is UiAgentRun.SettledNoAdmission->"Rust 已确认收尾且未接纳 · ${run.reason.name}";is UiAgentRun.Unresolved->"原生记录尚不确定，需要核实"},modifier=Modifier.testTag("agent-service-run-state"))
    identity?.let{value->Text("原运行：${value.runId}");value.actualTask?.let{Text("实际任务：${it.taskId}\n实际尝试：${it.attemptId}")}}
    val receipt=when(run){is UiAgentRun.Terminal->run.summary.receipt;is UiAgentRun.Unresolved->run.receipt;else->null}
    receipt?.let{Text("原读取回执：${it.outcome.name}");it.opaqueId?.let{id->Text("回执身份：$id")}}
}
