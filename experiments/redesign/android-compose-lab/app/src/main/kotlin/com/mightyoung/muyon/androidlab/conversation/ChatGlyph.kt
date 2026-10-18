package com.mightyoung.muyon.androidlab.conversation

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme

internal enum class ChatGlyphKind { ADD, UP, DOWN, CHEVRON, TOOL, STOP, SIDE_PANEL, CHAT, TASKS, FILES, SETTINGS }

/** Shared, original outline glyphs; no Muse or mascot artwork is bundled. */
@Composable
internal fun ChatGlyph(kind: ChatGlyphKind, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.onSurface) {
    Canvas(modifier.size(20.dp)) {
        val s = size.minDimension / 24f
        fun line(x1: Float, y1: Float, x2: Float, y2: Float) = drawLine(color, Offset(x1*s,y1*s), Offset(x2*s,y2*s), 1.7f*s, StrokeCap.Round)
        when (kind) {
            ChatGlyphKind.CHAT -> {
                val p = Path().apply { moveTo(5f*s,4f*s); lineTo(19f*s,4f*s); quadraticTo(21f*s,4f*s,21f*s,6f*s); lineTo(21f*s,15f*s); quadraticTo(21f*s,17f*s,19f*s,17f*s); lineTo(10f*s,17f*s); lineTo(4f*s,21f*s); lineTo(4f*s,6f*s); quadraticTo(4f*s,4f*s,5f*s,4f*s) }
                drawPath(p,color,style=Stroke(1.7f*s)); line(8f,9f,17f,9f); line(8f,12f,14f,12f)
            }
            ChatGlyphKind.TASKS -> {
                drawRoundRect(color,Offset(4f*s,3f*s),androidx.compose.ui.geometry.Size(16f*s,18f*s),CornerRadius(3f*s),style=Stroke(1.7f*s))
                line(7f,9f,9f,11f); line(9f,11f,13f,7f); line(8f,16f,16f,16f)
            }
            ChatGlyphKind.FILES -> {
                val p = Path().apply { moveTo(4f*s,5f*s); lineTo(10f*s,5f*s); lineTo(12f*s,8f*s); lineTo(21f*s,8f*s); lineTo(21f*s,20f*s); lineTo(3f*s,20f*s); lineTo(3f*s,5f*s); close() }
                drawPath(p,color,style=Stroke(1.7f*s))
            }
            ChatGlyphKind.SETTINGS -> {
                line(4f,7f,20f,7f); line(4f,17f,20f,17f)
                drawCircle(color,3f*s,Offset(9f*s,7f*s)); drawCircle(color,3f*s,Offset(16f*s,17f*s))
            }
            ChatGlyphKind.SIDE_PANEL -> {
                drawRoundRect(color, Offset(3f*s,4f*s), androidx.compose.ui.geometry.Size(18f*s,16f*s), CornerRadius(3f*s), style=Stroke(1.7f*s))
                line(9f,4f,9f,20f)
                line(5.5f,8f,6.5f,8f)
                line(5.5f,11f,6.5f,11f)
            }
            ChatGlyphKind.ADD -> { line(5f,12f,19f,12f); line(12f,5f,12f,19f) }
            ChatGlyphKind.UP -> { line(12f,19f,12f,5f); line(6f,11f,12f,5f); line(12f,5f,18f,11f) }
            ChatGlyphKind.DOWN -> { line(12f,5f,12f,19f); line(6f,13f,12f,19f); line(12f,19f,18f,13f) }
            ChatGlyphKind.CHEVRON -> { line(9f,6f,15f,12f); line(15f,12f,9f,18f) }
            ChatGlyphKind.TOOL -> {
                drawRoundRect(color, Offset(4f*s,7f*s), androidx.compose.ui.geometry.Size(16f*s,13f*s), CornerRadius(3f*s), style=Stroke(1.6f*s))
                val path = Path().apply { moveTo(9f*s,7f*s); lineTo(9f*s,4f*s); lineTo(15f*s,4f*s); lineTo(15f*s,7f*s) }
                drawPath(path,color,style=Stroke(1.6f*s)); line(4f,12f,20f,12f)
            }
            ChatGlyphKind.STOP -> drawRoundRect(color, Offset(6f*s,6f*s), androidx.compose.ui.geometry.Size(12f*s,12f*s), CornerRadius(2f*s))
        }
    }
}
