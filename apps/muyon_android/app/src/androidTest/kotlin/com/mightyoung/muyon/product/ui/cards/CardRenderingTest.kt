package com.mightyoung.muyon.product.ui.cards

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.ui.system.FoundationTheme
import com.mightyoung.muyon.product.ui.system.LocalFoundationPalette
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File

/** OFFLINE FIXTURES ONLY. Captures are evidence only when this test actually runs on Android. */
class CardRenderingTest {
    @get:Rule val compose = createComposeRule()
    private val binding = CardBinding(CardScope("fixture", "conversation", "project", "agent", 1), "message", "card", 1, 2, "attempt", "fixture-digest")
    private fun render(dark: Boolean, scale: Float) {
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, scale)) {
                FoundationTheme(dark = dark, reduceMotion = true) {
                    Column(Modifier.width(320.dp).fillMaxHeight().background(LocalFoundationPalette.current.background)
                        .testTag("card-gallery").verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        AttachmentCard(AttachmentCardModel(binding, "fixture-source", "测试材料.pdf", "v1", AttachmentAvailability.Partial,
                            listOf(AttachmentStage("本地保存", StageStatus.Complete, "已保存"), AttachmentStage("提取", StageStatus.Partial, "3 / 5页"),
                                AttachmentStage("索引", StageStatus.Partial, "仅第1–3页可检索")), "测试夹具：第4–5页失败"))
                        EvidenceCard(EvidenceCardModel(binding, "测试主张", "测试原文片段", SourceRelation.Cited, "fixture-source",
                            "测试材料.pdf", "v1", "第3页", "p3", "同源测试材料，不是独立证据"))
                        ChoiceCard(ChoiceCardModel(binding, "测试选择", SelectionMode.Single,
                            listOf(ChoiceOption("todo", "待核对"), ChoiceOption("read", "已读完")), setOf("todo")))
                        DraftCard(DraftCardModel(binding, "fixture-draft", "测试草稿", DraftSaveStatus.Unsaved,
                            listOf(DraftField("note", "备注", "仅测试数据", multiline = true)), canSubmit = true))
                        ConfirmationCard(ConfirmationCardModel(binding, "fixture-intent", "测试确认", "测试记录", "待核对 → 已读完", "r1", "r2",
                            "本地测试库", "仅本地写入", ConfirmationKind.Modification))
                        ReceiptCard(ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "fixture-intent"), ReceiptStatus.Unknown,
                            "测试夹具：结果未知", reservedCost = null, actualCost = null, cancelRequested = true))
                        ProjectCards(ProjectCardsModel(binding, "测试项目", "仅测试项目 · 本地资料", listOf(ProjectMaterial("fixture-source", "测试材料.pdf", "v1")),
                            listOf(ReportVersion("v2", "测试报告", ReportVersionStatus.Conflict, "fixture-source-v1"))))
                    }
                }
            }
        }
        val folder = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "card-rendering")
        assertTrue(folder.isDirectory || folder.mkdirs())
        fun capture(name: String) {
            val bitmap = compose.onNodeWithTag("card-gallery").captureToImage().asAndroidBitmap()
            File(folder, "${if (dark) "dark" else "light"}-$scale-$name.png").outputStream().use {
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
        }
        capture("attachment-top")
        listOf("card-locate-source", "card-choice-read", "card-submit-draft", "card-approve", "card-query-receipt", "card-compare-v2").forEach { tag ->
            compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
            capture(tag)
        }
    }
    @Test fun lightNormal() = render(false, 1f)
    @Test fun lightLarge() = render(false, 2f)
    @Test fun darkNormal() = render(true, 1f)
    @Test fun darkLarge() = render(true, 2f)
}
