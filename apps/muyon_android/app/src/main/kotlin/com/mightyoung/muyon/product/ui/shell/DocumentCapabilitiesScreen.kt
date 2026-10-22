package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Reader source is composed; access remains closed until the authoritative host bridge exists. */
@Composable
fun DocumentCapabilitiesScreen(onOpenExistingProjectMaterials: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("公共文档能力", style = MaterialTheme.typography.headlineSmall)
        Text("公共阅读尚未连接已授权文件。接通后可查看 PDF 页面和 Word、PPT、Excel 文本预览；Office 预览不保留原版式。")
        Text("现有项目 PDF 资料入口保留；公共能力不会扩大科研或供应商的数据范围与授权。")
        Button(onClick = onOpenExistingProjectMaterials, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("打开现有项目资料")
        }
        OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("公共文档阅读（等待授权接口）")
        }
        OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("批注编辑与保存（尚不可用）")
        }
        Text("批注保存尚不可用：需要核实当前文档权限、版本与保存回执。源文件编辑与排版尚不支持；原文件保持不变。")
    }
}
