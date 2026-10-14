package muyon.rd.p04

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Source-only consumer. Host publishes each immutable state and marshals events to UI thread.
 * Compose compilation/rendering/device accessibility: NOT_RUN in this environment.
 */
@Composable
fun SupplierScreen(
    state: ScreenState,
    onSelect: (String) -> Unit,
    onEdit: () -> Unit,
    onRawChange: (String) -> Unit,
    onSave: () -> Unit,
    onConfirm: () -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("供应商名称 · MOCK 合成数据")
        Text("暂行 RustCorePort；真实 Android 加载未验证")
        Text("授权结果由 mock port 提供，未接真实授权账本")
        Text(when (state.status) {
            Status.LOADING -> "加载中"
            Status.READY -> "未提交"
            Status.SUBMITTING -> "模拟提交中，尚无已核实真实回执"
            Status.SAVED -> "模拟回执已返回；不代表真实业务已保存"
            Status.CONFLICT -> "版本冲突，保留我的修改；不能覆盖当前版本"
            Status.UNKNOWN -> "效果未知；保留原意图，待核对，禁止自动重发"
            Status.DENIED -> "可信硬约束拒绝"
            Status.CONFIRM -> "Auto 规则要求确认"
        })
        if (state.page == Page.LIST) {
            LazyColumn {
                items(state.suppliers, key = { it.id }) { supplier ->
                    Button(onClick = { onSelect(supplier.id) }) {
                        Text("${supplier.name} · ID ${supplier.id} · ${supplier.revision}")
                    }
                }
            }
        } else {
            // Scrollable, stacked fields; font/keyboard/TalkBack behavior remains device-gated.
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item { Text("ID ${state.saved?.id} · revision ${state.saved?.revision}") }
                item { Text("当前保存值：${state.saved?.name}") }
                if (state.page == Page.EDIT) {
                    item {
                        OutlinedTextField(
                            value = state.draft?.raw.orEmpty(),
                            onValueChange = onRawChange,
                            label = { Text("我的修改（原始输入交给 Rust 校验）") },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = state.status in setOf(Status.READY, Status.DENIED),
                        )
                    }
                    item { Text("intent ${state.draft?.intent} · expected revision ${state.draft?.expectedRevision}") }
                    item {
                        Button(onClick = onSave, enabled = state.status == Status.READY) {
                            Text("模拟预览并提交")
                        }
                    }
                    if (state.status == Status.SAVED) {
                        item { Button(onClick = onEdit) { Text("再次修改，建立新意图") } }
                    }
                    if (state.status == Status.CONFIRM) {
                        item { Button(onClick = onConfirm) { Text("确认当前 mock 计划") } }
                    }
                } else {
                    item { Button(onClick = onEdit) { Text("修改名称") } }
                }
                item { Button(onClick = onBack) { Text("返回列表，保留草稿") } }
            }
        }
    }
}
