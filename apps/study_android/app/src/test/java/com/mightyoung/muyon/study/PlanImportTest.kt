package com.mightyoung.muyon.study
import org.junit.Assert.*
import org.junit.Test
class PlanImportTest {
    @Test fun markdown_import_preserves_steps_and_deterministic_identity() {
        val text="# 控制基础\n- [ ] 看第三章 30分钟 2026-11-01\n- [x] 跑例程 45分钟"
        val a=PlanImport.parse("plan.md",text.toByteArray())
        val b=PlanImport.parse("plan.md",text.toByteArray())
        assertEquals(2,a.length());assertEquals(a.getJSONObject(0).getString("id"),b.getJSONObject(0).getString("id"))
        assertEquals(30,a.getJSONObject(0).getInt("minutes"));assertEquals("done",a.getJSONObject(1).getString("status"))
    }
    @Test fun invalid_file_is_rejected_without_silent_empty_import() {
        try { PlanImport.parse("file.xlsx",byteArrayOf(1,2));fail("invalid archive accepted") } catch (_:Exception) { }
    }
}
