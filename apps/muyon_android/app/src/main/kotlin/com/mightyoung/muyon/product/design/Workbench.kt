package com.mightyoung.muyon.product.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.R
import kotlinx.coroutines.launch

/** Shared neutral tokens translated from the observed reference bundles. */
@Composable
fun MuyonTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme(
        primary = Color(0xFF91BFF4), onPrimary = Color(0xFF10273F),
        background = Color(0xFF181818), surface = Color(0xFF181818),
        surfaceVariant = Color(0xFF292929), onSurface = Color(0xFFF0F0F0),
        onSurfaceVariant = Color(0xFFB7B7BB), outlineVariant = Color(0xFF3B3B3D),
        secondaryContainer = Color(0xFF303033), onSecondaryContainer = Color(0xFFF0F0F0)
    ) else lightColorScheme(
        primary = Color(0xFF254F83), onPrimary = Color.White,
        background = Color(0xFFFAFAFA), surface = Color.White,
        surfaceVariant = Color(0xFFF3F3F4), onSurface = Color(0xFF111112),
        onSurfaceVariant = Color(0xFF626469), outlineVariant = Color(0xFFE5E5E7),
        secondaryContainer = Color(0xFFEDEDF0), onSecondaryContainer = Color(0xFF111112)
    )
    MaterialTheme(colorScheme = scheme, shapes = Shapes(
        small = RoundedCornerShape(8.dp), medium = RoundedCornerShape(12.dp),
        large = RoundedCornerShape(16.dp), extraLarge = RoundedCornerShape(24.dp)
    ), content = content)
}

private data class Destination(val id: String, val label: String, val icon: Int)
private val destinations = listOf(
    Destination("chat", "助手", R.drawable.wb_chat),
    Destination("supplier", "供应商", R.drawable.wb_document),
    Destination("research", "科研工作台", R.drawable.wb_document),
    Destination("agents", "智能体", R.drawable.wb_add)
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkbenchShell(
    selected: String,
    title: String,
    status: String,
    onSelect: (String) -> Unit,
    content: @Composable () -> Unit
) {
    val drawer = rememberDrawerState(DrawerValue.Closed)
    val coroutine = rememberCoroutineScope()
    val select: (String) -> Unit = { id ->
        onSelect(id)
        coroutine.launch { drawer.close() }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        val expanded = maxWidth >= 840.dp
        val imeOpen = WindowInsets.ime.getBottom(LocalDensity.current) > 0
        val sidebar: @Composable () -> Unit = {
            Column(Modifier.width(240.dp).fillMaxHeight()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))
                .verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("muyon", Modifier.padding(12.dp, 20.dp),
                    style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                Text("个人工作空间", Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.labelMedium)
                destinations.forEach { item ->
                    NavigationDrawerItem(label = { Text(item.label) }, selected = selected == item.id,
                        icon = { Icon(painterResource(item.icon), null, Modifier.size(22.dp)) },
                        onClick = { select(item.id) }, shape = RoundedCornerShape(12.dp), modifier = Modifier.testTag("nav-${item.id}"))
                }
                Spacer(Modifier.weight(1f))
                HorizontalDivider(Modifier.padding(vertical = 12.dp))
                Text("本地工作台", Modifier.padding(horizontal = 12.dp), style = MaterialTheme.typography.labelLarge)
                Text(status, Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val body: @Composable () -> Unit = {
            Row(Modifier.fillMaxSize()) {
                if (expanded) sidebar()
                Scaffold(Modifier.weight(1f), containerColor = MaterialTheme.colorScheme.surface,
                    contentWindowInsets = WindowInsets.safeDrawing,
                    topBar = {
                        Column {
                            Row(Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = 64.dp).padding(horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                if (!expanded) IconButton(onClick = { coroutine.launch { drawer.open() } }) {
                                    Icon(painterResource(R.drawable.wb_menu), "打开工作空间导航")
                                }
                                Column(Modifier.weight(1f).padding(8.dp)) {
                                    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                    Text(status, style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Surface(shape = RoundedCornerShape(8.dp), color = MaterialTheme.colorScheme.surfaceVariant,
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                                    Text("M", Modifier.padding(12.dp, 8.dp), style = MaterialTheme.typography.labelLarge)
                                }
                            }
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        }
                    }, bottomBar = {
                        if (!expanded && !imeOpen) NavigationBar(containerColor = MaterialTheme.colorScheme.surface,
                            tonalElevation = 0.dp) {
                            destinations.forEach { item ->
                                NavigationBarItem(selected = selected == item.id, onClick = { onSelect(item.id) }, modifier = Modifier.testTag("nav-${item.id}"),
                                    icon = { Icon(painterResource(item.icon), null, Modifier.size(22.dp)) },
                                    label = { Text(item.label, maxLines = 2) },
                                    colors = NavigationBarItemDefaults.colors(
                                        indicatorColor = MaterialTheme.colorScheme.surfaceVariant))
                            }
                        }
                    }) { padding ->
                    Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding), contentAlignment = Alignment.TopCenter) {
                        Box(Modifier.widthIn(max = 1120.dp).fillMaxSize()) { content() }
                    }
                }
            }
        }
        if (expanded) body() else ModalNavigationDrawer(drawerState = drawer,
            drawerContent = {
                ModalDrawerSheet(Modifier.width(240.dp)) {
                    // Off-screen navigation must not duplicate live bottom-bar controls.
                    if (drawer.currentValue == DrawerValue.Open) sidebar()
                }
            }, content = body)
    }
}
