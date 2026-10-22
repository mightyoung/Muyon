package com.mightyoung.muyon.product.ui.documents

import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** URI is host selected, never constructed from model text or document IDs. */
data class DocumentReaderSnapshot(
    val document: ReaderDocumentRef,
    val contentUri: Uri,
    val hostEpoch: Long,
    val accessActive: Boolean,
    val annotations: List<SidecarAnnotation>,
) {
    init { require(contentUri.scheme == "content") { "Only host-controlled content URI is accepted" } }
}

/**
 * Concrete component integration seam. Host implements these closures with existing core/IPC.
 * Opening and delivery must each revalidate exact ref + epoch + grants + safety against bytes.
 * No default resolver, ambient ContentResolver access, write permission or fake Saved result.
 */
class DocumentReaderHost(
    val openCurrent: suspend (ReaderDocumentRef, Uri, Long) -> ParcelFileDescriptor,
    val isCurrent: suspend (ReaderDocumentRef, Long) -> Boolean,
    val saveSidecar: suspend (SidecarEdit, Long) -> SidecarSaveResult,
)

private data class EditorKey(val id: String, val revision: String, val anchor: String)

private class EditorState(annotation: SidecarAnnotation) {
    var draft by mutableStateOf(annotation.content.editableText())
    var submission by mutableStateOf(SidecarSubmission.READY)
    var status by mutableStateOf("")
}

private sealed class Preview {
    data object Loading : Preview()
    data class Pdf(val pageIndex: Int, val page: NativeDocumentPreview.PdfPage) : Preview()
    data class Office(val sections: List<OfficeSection>) : Preview()
    data object Failed : Preview()
}

@Composable
fun DocumentReaderScreen(snapshot: DocumentReaderSnapshot, host: DocumentReaderHost, onClose: () -> Unit) {
    // Full scope, revision, URI and authority generation fence all remembered state and old callbacks.
    key(snapshot.document, snapshot.contentUri, snapshot.hostEpoch, snapshot.accessActive) {
        if (!snapshot.accessActive) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("文档访问已失效，请返回后重新授权。")
                OutlinedButton(onClick = onClose) { Text("返回") }
            }
        } else ReaderContent(snapshot, host, onClose)
    }
}

@Composable
private fun ReaderContent(snapshot: DocumentReaderSnapshot, host: DocumentReaderHost, onClose: () -> Unit) {
    var position by remember { mutableStateOf(ReaderPosition()) }
    var pageCount by remember { mutableIntStateOf(0) }
    var pageInput by remember { mutableStateOf("1") }
    var accessLost by remember { mutableStateOf(false) }
    var readAttempt by remember { mutableIntStateOf(0) }
    val document = snapshot.document
    val saveScope = rememberCoroutineScope()
    // UI drafts and pending outcomes survive page-loading subtree removal.
    val editors = remember { mutableMapOf<EditorKey, EditorState>() }
    val preview by produceState<Preview>(Preview.Loading, position.pageIndex, readAttempt) {
        value = Preview.Loading
        val requestedPage = position.pageIndex
        var rendered: NativeDocumentPreview.PdfPage? = null
        try {
            val result = withContext(Dispatchers.IO) {
                check(host.isCurrent(document, snapshot.hostEpoch))
                val descriptor = host.openCurrent(document, snapshot.contentUri, snapshot.hostEpoch)
                val loaded = if (document.format == DocumentFormat.PDF) {
                    val page = NativeDocumentPreview.pdf(descriptor, requestedPage)
                    rendered = page
                    Preview.Pdf(requestedPage, page)
                } else {
                    val sections = ParcelFileDescriptor.AutoCloseInputStream(descriptor).use {
                        RustOfficePreview.read(it, document.format)
                    }
                    Preview.Office(sections)
                }
                ensureActive()
                check(host.isCurrent(document, snapshot.hostEpoch))
                loaded
            }
            if (result is Preview.Pdf) pageCount = result.page.pageCount
            value = result
            // Bitmap becomes Compose-owned; its bounded memory is released by GC after UI drops it.
            rendered = null
        } catch (cancelled: CancellationException) {
            rendered?.bitmap?.recycle()
            throw cancelled
        } catch (_: Exception) {
            rendered?.bitmap?.recycle()
            // Failure is not necessarily revocation; render/parser failures are honest unsupported states.
            accessLost = try { !host.isCurrent(document, snapshot.hostEpoch) } catch (_: Exception) { true }
            value = Preview.Failed
        }
    }
    val pdf = (preview as? Preview.Pdf)?.takeIf { it.pageIndex == position.pageIndex }
    val ready = !accessLost && (pdf != null || preview is Preview.Office)
    val navigation = ReaderNavigation(pageCount, when {
        accessLost -> ReaderReadStatus.ACCESS_LOST
        ready -> ReaderReadStatus.READY
        preview == Preview.Failed -> ReaderReadStatus.PAGE_FAILED
        else -> ReaderReadStatus.LOADING
    })
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("公共文档阅读", style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = onClose) { Text("关闭") }
        }
        Text("${document.documentId} · 修订 ${document.revision}")
        if (document.format == DocumentFormat.PDF) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(enabled = navigation.canNavigate && position.pageIndex > 0, onClick = {
                    position = position.goTo(position.pageIndex, pageCount); pageInput = (position.pageIndex + 1).toString()
                }) { Text("上一页") }
                Text("${position.pageIndex + 1} / ${if (pageCount == 0) "?" else pageCount}")
                OutlinedButton(enabled = navigation.canNavigate && position.pageIndex < pageCount - 1, onClick = {
                    position = position.goTo(position.pageIndex + 2, pageCount); pageInput = (position.pageIndex + 1).toString()
                }) { Text("下一页") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(pageInput, { pageInput = it.take(10) }, Modifier.weight(1f),
                    label = { Text("页码") }, singleLine = true)
                OutlinedButton(enabled = navigation.canNavigate && pageInput.toIntOrNull() != null, onClick = {
                    position = position.goTo(pageInput.toIntOrNull() ?: 1, pageCount)
                    pageInput = (position.pageIndex + 1).toString()
                }) { Text("定位") }
                TextButton(enabled = ready, onClick = { position = position.zoom(position.zoom - .25f) }) { Text("−") }
                TextButton(enabled = ready, onClick = { position = position.zoom(position.zoom + .25f) }) { Text("+ ${((position.zoom) * 100).toInt()}%") }
            }
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (accessLost) Text("访问或修订已失效；请返回重新打开。")
            else when (val shown = preview) {
                Preview.Loading -> { CircularProgressIndicator(); Text("正在本地读取原文件…") }
                Preview.Failed -> {
                    Text("本次读取失败：可能是暂时读取错误、页面损坏、加密、超过安全上限或格式不受支持。未改动原文件。")
                    if (navigation.canRetry) {
                        OutlinedButton(onClick = { readAttempt++ }) {
                            Text(if (document.format == DocumentFormat.PDF) "重试读取当前页" else "重试读取文档")
                        }
                    }
                }
                is Preview.Pdf -> if (pdf != null) {
                    val width = (LocalConfiguration.current.screenWidthDp - 32).coerceAtLeast(100).dp * position.zoom
                    Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
                        Image(pdf.page.bitmap.asImageBitmap(),
                            "文档 ${document.documentId} 第 ${position.pageIndex + 1} 页原文件渲染",
                            Modifier.width(width).aspectRatio(pdf.page.bitmap.width.toFloat() / pdf.page.bitmap.height))
                    }
                    Text("原生 PDF 页面 · 缩放后可横向移动。文字选择和嵌入式批注不支持；下方仅为 sidecar 批注。")
                } else Text("正在载入目标页…")
                is Preview.Office -> {
                    Text("${document.format} 文本预览：不保留原版式、图表、图片、合并单元格或嵌入对象；不计算公式，不执行宏。按内部部件编号列出，不代表演示/工作表顺序；不解析样式和日期格式。")
                    shown.sections.forEach { section ->
                        Text(section.title, style = MaterialTheme.typography.titleSmall)
                        Text(section.text)
                    }
                }
            }
            if (ready) {
                HorizontalDivider()
                Text("批注 sidecar", style = MaterialTheme.typography.titleMedium)
                Text("编辑只提交独立批注正文；不写入原 PDF/Office 文件。旧版本批注保留标记，不能在当前版本提交。")
                val annotations = snapshot.annotations.filter { !it.deleted && it.belongsTo(document) }
                if (annotations.isEmpty()) Text("暂无批注。文字选择与新增位置批注尚不支持。")
                annotations.forEach { annotation ->
                    key(annotation.id, annotation.revision, annotation.anchorJson) {
                        val editor = editors.getOrPut(EditorKey(annotation.id, annotation.revision, annotation.anchorJson)) {
                            EditorState(annotation)
                        }
                        AnnotationEditor(annotation, snapshot, host, editor, saveScope, onAccessLost = { accessLost = true })
                    }
                }
            }
        }
    }
}

@Composable
private fun AnnotationEditor(
    annotation: SidecarAnnotation,
    snapshot: DocumentReaderSnapshot,
    host: DocumentReaderHost,
    editor: EditorState,
    scope: CoroutineScope,
    onAccessLost: () -> Unit,
) {
    val draft = editor.draft
    val status = editor.status
    val saving = editor.submission == SidecarSubmission.SAVING
    val locked = !editor.submission.canSubmit
    val stale = annotation.stale || annotation.document != snapshot.document
    val edit = annotation.edit(snapshot.document, draft)
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${annotation.locationLabel} · 批注修订 ${annotation.revision}")
            Text(annotation.authorLabel)
            if (stale) Text("旧版本批注，仅供预览，无法编辑。")
            if (annotation.content is AnnotationContent.Highlight) Text("原引用：${annotation.content.quote}")
            OutlinedTextField(draft, { editor.draft = it }, Modifier.fillMaxWidth(), label = { Text("批注正文") },
                enabled = !stale && !saving && !locked, minLines = 2)
            Button(enabled = !stale && !saving && !locked && edit != null && edit.replacement != annotation.content, onClick = {
                if (!editor.submission.canSubmit) return@Button
                val submitted = edit ?: return@Button
                editor.submission = SidecarSubmission.SAVING
                scope.launch {
                    try {
                        if (!host.isCurrent(snapshot.document, snapshot.hostEpoch)) {
                            onAccessLost(); return@launch
                        }
                        val result = host.saveSidecar(submitted, snapshot.hostEpoch)
                        if (!host.isCurrent(snapshot.document, snapshot.hostEpoch)) {
                            onAccessLost(); return@launch
                        }
                        editor.submission = editor.submission.finished(result)
                        editor.status = when (result) {
                            SidecarSaveResult.Saved -> "已由宿主确认保存；等待更新批注快照。"
                            is SidecarSaveResult.Rejected -> "保存被拒绝；请刷新权限/修订后核对，草稿已保留。"
                            SidecarSaveResult.Unknown -> "保存结果未知；请由宿主查询原回执，禁止重复提交。"
                        }
                    } catch (cancelled: CancellationException) {
                        editor.submission = SidecarSubmission.UNKNOWN
                        // Host must retain durable intent and resolve ambiguous cancellation on re-entry.
                        throw cancelled
                    } catch (_: Exception) {
                        editor.submission = SidecarSubmission.UNKNOWN
                        editor.status = "保存结果未知；请由宿主查询原回执，禁止重复提交。"
                    }
                }
            }) { Text(if (saving) "保存中…" else "保存 sidecar 批注") }
            if (status.isNotEmpty()) Text(status)
        }
    }
}
