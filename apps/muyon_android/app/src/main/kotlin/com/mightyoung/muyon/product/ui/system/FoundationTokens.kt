package com.mightyoung.muyon.product.ui.system

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class FoundationPalette(
    val background: Color, val panel: Color, val text: Color, val secondary: Color,
    val border: Color, val link: Color, val action: Color, val onAction: Color,
    val error: Color, val detail: Color
)

object FoundationTokens {
    val minimumTarget = 48.dp
    val light = FoundationPalette(
        background = Color(0xFFF5F5F3), panel = Color(0xFFFAFAF8),
        text = Color(0xFF2E2D2B), secondary = Color(0xFF646360),
        border = Color(0xFF80807C), link = Color(0xFF3F6480),
        action = Color(0xFF2E2D2B), onAction = Color(0xFFFAFAF8),
        error = Color(0xFF923B35), detail = Color(0xFF766653)
    )
    val dark = FoundationPalette(
        background = Color(0xFF252523), panel = Color(0xFF30302D),
        text = Color(0xFFF5F5F3), secondary = Color(0xFFC2C1BA),
        border = Color(0xFF999991), link = Color(0xFFA8C7DE),
        action = Color(0xFFE5E5DF), onAction = Color(0xFF2E2D2B),
        error = Color(0xFFFFB4AB), detail = Color(0xFFC2AE96)
    )
}

val LocalFoundationPalette = staticCompositionLocalOf { FoundationTokens.light }
val LocalFoundationReduceMotion = staticCompositionLocalOf { true }

/** Opt in around a screen or component; does not replace the application's theme. */
@Composable
fun FoundationTheme(
    dark: Boolean = isSystemInDarkTheme(),
    reduceMotion: Boolean = true,
    content: @Composable () -> Unit
) {
    val p = if (dark) FoundationTokens.dark else FoundationTokens.light
    val scheme = if (dark) darkColorScheme() else lightColorScheme()
    val type = Typography()
    CompositionLocalProvider(LocalFoundationPalette provides p, LocalFoundationReduceMotion provides reduceMotion, LocalContentColor provides p.text) {
        MaterialTheme(
            colorScheme = scheme.copy(
                primary = p.action, onPrimary = p.onAction,
                secondary = p.text, onSecondary = p.panel,
                background = p.background, onBackground = p.text,
                surface = p.panel, onSurface = p.text,
                surfaceVariant = p.background, onSurfaceVariant = p.secondary,
                surfaceContainer = p.panel, surfaceContainerHigh = p.panel,
                surfaceContainerHighest = p.background,
                outline = p.border, outlineVariant = p.border,
                error = p.error, onError = p.background, surfaceTint = Color.Transparent
            ),
            typography = type.copy(
                bodyMedium = type.bodyMedium.copy(fontSize = 16.sp, lineHeight = 24.sp),
                bodySmall = type.bodySmall.copy(fontSize = 16.sp, lineHeight = 24.sp),
                labelLarge = type.labelLarge.copy(fontSize = 16.sp, lineHeight = 24.sp),
                labelMedium = type.labelMedium.copy(fontSize = 16.sp, lineHeight = 24.sp),
                labelSmall = type.labelSmall.copy(fontSize = 16.sp, lineHeight = 24.sp)
            ), content = content
        )
    }
}

enum class ActionState { Ready, Disabled, Loading, Error, Unknown }
enum class ButtonKind { Primary, Secondary, Quiet }
enum class FeedbackKind { Info, Loading, Partial, Error, Unknown }

internal fun ActionState.canAct(hasCallback: Boolean): Boolean =
    hasCallback && (this == ActionState.Ready || this == ActionState.Error)
