package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Neutral capability entry only. It neither selects an engine nor grants a business scope. */
@Composable
fun DocumentCapabilitiesScreen(onOpenExistingProjectMaterials: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("公共文档能力", style = MaterialTheme.typography.headlineSmall)
        Text("阅读与适量编辑规划覆盖 PDF、Word、PPT、Excel。公共入口尚未接线；引擎选型与权限验证进行中。")
        Text("现有项目 PDF 资料入口保留；公共能力不会扩大科研或供应商的数据范围与授权。")
        Button(onClick = onOpenExistingProjectMaterials, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("打开现有项目资料")
        }
        OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("公共文档阅读（未接线）")
        }
        OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("适量编辑（未接线）")
        }
        Text("尚未支持的格式会保留原文件并准确说明；这里不导入文档、不修改文件，也不显示已可编辑。")
    }
}
