package com.mightyoung.muyon.product.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mightyoung.muyon.product.R
import kotlinx.coroutines.launch

// Legacy source names retained for callers; glyphs come from the OS, not an
// extracted vendor font. The typography below controls readable size and rhythm.
val ClaudeSansFont = FontFamily.SansSerif
val ClaudeReplyFont = FontFamily.Serif

/** Reference-inspired spacing and colors with platform-provided typography. */
@Composable
fun MuyonTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme(
        primary = Color(0xFF8BC5FF), onPrimary = Color(0xFF111112),
        background = Color(0xFF181819), surface = Color(0xFF28292B),
        surfaceVariant = Color(0xFF28292B), onSurface = Color.White,
        surfaceContainerLow = Color(0xFF28292B), surfaceContainerHigh = Color(0xFF333437), surfaceTint = Color.Transparent,
        onSurfaceVariant = Color(0xFF999DA4), outlineVariant = Color(0x1FFFFFFF),
        secondaryContainer = Color(0xFF333437), onSecondaryContainer = Color.White
    ) else lightColorScheme(
        primary = Color(0xFF0064D4), onPrimary = Color.White,
        background = Color(0xFFFCFCFC), surface = Color.White,
        surfaceVariant = Color(0xFFF3F4F5), onSurface = Color(0xFF111112),
        surfaceContainerLow = Color(0xFFF3F4F5), surfaceContainerHigh = Color(0xFFF2F2F2), surfaceTint = Color.Transparent,
        onSurfaceVariant = Color(0xFF696B6E), outline = Color(0xFF96989C), outlineVariant = Color(0x1A000000),
        secondaryContainer = Color(0xFFF2F2F2), onSecondaryContainer = Color(0xFF111112)
    )
    fun type(size: Int, height: Int, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontFamily = ClaudeSansFont, fontSize = size.sp, lineHeight = height.sp, fontWeight = weight)
    MaterialTheme(colorScheme = scheme, shapes = Shapes(
        small = RoundedCornerShape(8.dp), medium = RoundedCornerShape(12.dp),
        large = RoundedCornerShape(16.dp), extraLarge = RoundedCornerShape(32.dp)
    ), typography = Typography(
        headlineLarge = type(32, 40, FontWeight.SemiBold), headlineMedium = type(28, 36, FontWeight.SemiBold), headlineSmall = type(24, 32, FontWeight.SemiBold),
        titleLarge = type(20, 28, FontWeight.SemiBold), titleMedium = type(16, 22, FontWeight.Medium), titleSmall = type(14, 20, FontWeight.Medium),
        bodyLarge = type(16, 24), bodyMedium = type(14, 20), bodySmall = type(13, 18),
        labelLarge = type(14, 20, FontWeight.Medium), labelMedium = type(13, 18, FontWeight.Medium), labelSmall = type(12, 16, FontWeight.Medium)
    ), content = {
        Surface(Modifier.fillMaxSize(), color = scheme.background, contentColor = scheme.onSurface) {
            content()
        }
    })
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
        val sidebar: @Composable () -> Unit = {
            Column(Modifier.width(240.dp).fillMaxHeight()
                .background(MaterialTheme.colorScheme.background)
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))
                .verticalScroll(rememberScrollState()).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("muyon", Modifier.padding(12.dp, 24.dp),
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                destinations.forEach { item ->
                    val active = selected == item.id
                    Box(Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .testTag("nav-${item.id}").semantics { this.selected = active }
                        .clickable(role = Role.Tab) { select(item.id) }, contentAlignment = Alignment.Center) {
                        Surface(Modifier.fillMaxWidth(), color = if (active) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent,
                            shape = RoundedCornerShape(12.dp)) {
                            Row(Modifier.heightIn(min = 36.dp).padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Icon(painterResource(item.icon), null, Modifier.size(18.dp))
                                Text(item.label, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                HorizontalDivider(Modifier.padding(vertical = 12.dp))
                Text("个人工作空间", Modifier.padding(12.dp), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val body: @Composable () -> Unit = {
            Row(Modifier.fillMaxSize()) {
                if (expanded) sidebar()
                if (expanded) VerticalDivider(Modifier.fillMaxHeight(), color = MaterialTheme.colorScheme.outlineVariant)
                Scaffold(Modifier.weight(1f), containerColor = MaterialTheme.colorScheme.background,
                    contentWindowInsets = WindowInsets.safeDrawing,
                    topBar = {
                        Column {
                            Row(Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = 56.dp).padding(horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                if (!expanded) IconButton(onClick = { coroutine.launch { drawer.open() } }) {
                                    Icon(painterResource(R.drawable.wb_menu), "打开工作空间导航")
                                }
                                Column(Modifier.weight(1f).padding(8.dp)) {
                                    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                }
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
