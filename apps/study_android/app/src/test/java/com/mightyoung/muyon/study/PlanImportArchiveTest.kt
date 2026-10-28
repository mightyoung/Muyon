package com.mightyoung.muyon.study

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import java.time.LocalDate
import java.time.ZoneOffset

class PlanImportArchiveTest {
    private fun zip(vararg entries: Pair<String, String>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z -> entries.forEach { (name, data) -> z.putNextEntry(ZipEntry(name)); z.write(data.toByteArray()); z.closeEntry() } }
        return out.toByteArray()
    }
    @Test fun word_tables_and_paragraphs_import_actual_content() {
        val bytes = zip("word/document.xml" to """<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>阅读课本 20分钟</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>任务</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>预计用时</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>做题</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>45</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>""")
        val tasks = PlanImport.parse("course.docx", bytes)
        assertEquals(2, tasks.length()); assertEquals("做题",tasks.getJSONObject(1).getString("title")); assertEquals(45,tasks.getJSONObject(1).getInt("minutes"))
    }
    @Test fun excel_shared_inline_sparse_and_numeric_dates() {
        val bytes=zip("xl/sharedStrings.xml" to """<sst xmlns="urn:sheet"><si><t>任务</t></si><si><t>读论文</t></si></sst>""", "xl/worksheets/sheet1.xml" to """<worksheet xmlns="urn:sheet"><sheetData><row><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>预计用时</t></is></c><c r="D1" t="inlineStr"><is><t>日期</t></is></c></row><row><c r="A2" t="s"><v>1</v></c><c r="C2"><v>60</v></c><c r="D2"><v>46327</v></c></row></sheetData></worksheet>""")
        val task=PlanImport.parse("course.xlsx",bytes).getJSONObject(0)
        assertEquals("读论文",task.getString("title"));assertEquals(60,task.getInt("minutes"))
        assertEquals(LocalDate.of(1899,12,30).plusDays(46327).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(),task.getLong("due"))
    }
    @Test fun archives_reject_traversal_and_external_entities() {
        for (bytes in listOf(zip("../word/document.xml" to "bad"),zip("word/document.xml" to """<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><document>&e;</document>"""))) {
            try { PlanImport.parse("bad.docx",bytes); fail("Unsafe archive accepted") } catch (_: IllegalArgumentException) {} catch (_: org.xml.sax.SAXException) {}
        }
    }
    @Test fun old_office_formats_are_explicitly_rejected() {
        for (name in listOf("course.doc","course.xls")) {
            try { PlanImport.parse(name,byteArrayOf(1)); fail("Legacy file accepted") } catch(e:IllegalStateException) { assertTrue(e.message!!.contains("另存为")) }
        }
    }
}
