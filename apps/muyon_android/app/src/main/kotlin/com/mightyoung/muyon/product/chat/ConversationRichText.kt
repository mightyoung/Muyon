package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mightyoung.muyon.product.design.ClaudeReplyFont
import java.net.URI

internal sealed interface ConversationBlock {
    data class Prose(val value: String, val heading: Int = 0, val quote: Boolean = false) : ConversationBlock
    data class Code(val language: String, val value: String) : ConversationBlock
    data class Table(val rows: List<List<String>>) : ConversationBlock
}

/** A deliberately small Markdown subset; unsupported syntax remains readable text. */
internal fun conversationBlocks(text: String): List<ConversationBlock> {
    val lines = text.replace("\r\n", "\n").split('\n')
    val blocks = mutableListOf<ConversationBlock>()
    var at = 0
    fun cells(line: String) = line.trim().removePrefix("|").removeSuffix("|").split('|').map(String::trim)
    while (at < lines.size) {
        val line = lines[at]
        when {
            line.isBlank() -> at++
            line.trimStart().startsWith("```") -> {
                val language = line.trim().removePrefix("```").trim()
                val body = mutableListOf<String>(); at++
                while (at < lines.size && !lines[at].trimStart().startsWith("```")) body += lines[at++]
                if (at < lines.size) at++
                blocks += ConversationBlock.Code(language, body.joinToString("\n"))
            }
            at + 1 < lines.size && line.contains('|') && cells(lines[at + 1]).all { it.matches(Regex(":?-{3,}:?")) } -> {
                val rows = mutableListOf(cells(line)); at += 2
                while (at < lines.size && lines[at].contains('|') && lines[at].isNotBlank()) rows += cells(lines[at++])
                blocks += ConversationBlock.Table(rows)
            }
            line.matches(Regex("#{1,6} .*")) -> {
                val level = line.takeWhile { it == '#' }.length
                blocks += ConversationBlock.Prose(line.drop(level + 1), heading = level); at++
            }
            line.trimStart().startsWith("> ") -> {
                blocks += ConversationBlock.Prose(line.trimStart().drop(2), quote = true); at++
            }
            line.matches(Regex("\\s*(?:[-*+] |[0-9]+[.)] ).*")) -> {
                blocks += ConversationBlock.Prose(line.replaceFirst(Regex("^\\s*[-*+] "), "• ")); at++
            }
            else -> {
                val paragraph = mutableListOf(line); at++
                while (at < lines.size && lines[at].isNotBlank() && !lines[at].matches(Regex("\\s*(?:```.*|#{1,6} .*|> .*|[-*+] .*|[0-9]+[.)] .*)")) &&
                    !(at + 1 < lines.size && lines[at].contains('|') && cells(lines[at + 1]).all { it.matches(Regex(":?-{3,}:?")) })) paragraph += lines[at++]
                blocks += ConversationBlock.Prose(paragraph.joinToString("\n"))
            }
        }
    }
    return blocks
}

internal fun safeConversationUrl(value: String): Boolean = try {
    val uri = URI(value)
    uri.scheme?.lowercase() in setOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null && value.none { it.isISOControl() }
} catch (_: Exception) { false }

internal fun conversationInline(value: String, linkStyle: SpanStyle): AnnotatedString = buildAnnotatedString {
    val link = Regex("\\[([^]\\n]+)]\\(([^\\s)]+)\\)")
    fun appendInline(source: String, depth: Int) {
        if (depth >= 8) { append(source); return }
        var at = 0
        while (at < source.length) {
            val match = if (source[at] == '[') link.find(source, at)?.takeIf { it.range.first == at } else null
            if (match != null) {
                val target = match.groupValues[2]
                if (safeConversationUrl(target)) {
                    pushStringAnnotation("URL", target)
                    pushLink(LinkAnnotation.Url(target, TextLinkStyles(style = linkStyle)))
                    appendInline(match.groupValues[1], depth + 1); pop(); pop()
                } else append(match.value)
                at = match.range.last + 1
                continue
            }
            val delimiter = when {
                source[at] == '`' -> "`"
                source.startsWith("**", at) -> "**"
                source[at] == '*' -> "*"
                source[at] == '_' && (at == 0 || !source[at - 1].isLetterOrDigit()) -> "_"
                else -> null
            }
            if (delimiter == null) { append(source[at++]); continue }
            val start = at + delimiter.length
            var end = source.indexOf(delimiter, start)
            // Single-star runs are not parsed as part of an incomplete bold marker.
            while (end >= 0 && delimiter == "*" &&
                ((end > 0 && source[end - 1] == '*') || source.getOrNull(end + 1) == '*')) end = source.indexOf(delimiter, end + 1)
            val valid = end > start && !source.substring(start, end).contains('\n') &&
                source.substring(start, end).isNotBlank() &&
                (delimiter != "_" || source.getOrNull(end + 1)?.isLetterOrDigit() != true)
            if (!valid) { append(delimiter); at = start; continue }
            val style = when (delimiter) {
                "`" -> SpanStyle(fontFamily = FontFamily.Monospace, background = Color(0x14696969))
                "**" -> SpanStyle(fontWeight = FontWeight.Bold)
                else -> SpanStyle(fontStyle = FontStyle.Italic)
            }
            pushStyle(style)
            if (delimiter == "`") append(source.substring(start, end)) else appendInline(source.substring(start, end), depth + 1)
            pop()
            at = end + delimiter.length
        }
    }
    appendInline(value, 0)
}

@Suppress("DEPRECATION")
@Composable
internal fun ConversationRichText(text: String, modifier: Modifier = Modifier) {
    val blocks = remember(text) { conversationBlocks(text) }
    val clipboard = LocalClipboardManager.current
    val ink = MaterialTheme.colorScheme.onSurface
    val linkStyle = SpanStyle(color = MaterialTheme.colorScheme.primary)
    SelectionContainer(modifier.widthIn(max = 680.dp).fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            blocks.forEachIndexed { index, block ->
                when (block) {
                    is ConversationBlock.Prose -> {
                        val body = remember(block.value, linkStyle) { conversationInline(block.value, linkStyle) }
                        Text(body, Modifier.fillMaxWidth().then(if (block.quote) Modifier.background(MaterialTheme.colorScheme.surfaceVariant).padding(12.dp) else Modifier),
                            style = TextStyle(fontFamily = ClaudeReplyFont, color = ink, fontSize = if (block.heading > 0) 20.sp else 16.sp,
                                lineHeight = if (block.heading > 0) 28.sp else 24.sp,
                                fontWeight = if (block.heading > 0) FontWeight.SemiBold else FontWeight.Normal))
                    }
                    is ConversationBlock.Code -> Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceVariant) {
                        Column(Modifier.fillMaxWidth().testTag("conversation-code-$index").padding(12.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(block.language.ifBlank { "代码" }, style = MaterialTheme.typography.labelMedium)
                                TextButton(onClick = { clipboard.setText(AnnotatedString(block.value)) }, modifier = Modifier.testTag("conversation-copy-$index")) { Text("复制代码") }
                            }
                            Text(block.value, Modifier.horizontalScroll(rememberScrollState()), fontFamily = FontFamily.Monospace,
                                fontSize = 14.sp, lineHeight = 22.sp)
                        }
                    }
                    is ConversationBlock.Table -> Column(Modifier.testTag("conversation-table-$index").horizontalScroll(rememberScrollState())) {
                        val columns = block.rows.maxOfOrNull { it.size } ?: 0
                        block.rows.forEachIndexed { rowIndex, row ->
                            Row(Modifier.background(if (rowIndex == 0) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.background)) {
                                repeat(columns) { column -> Text(row.getOrElse(column) { "" }, Modifier.width(180.dp).padding(12.dp),
                                    style = MaterialTheme.typography.bodyMedium, fontWeight = if (rowIndex == 0) FontWeight.SemiBold else FontWeight.Normal) }
                            }
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}
