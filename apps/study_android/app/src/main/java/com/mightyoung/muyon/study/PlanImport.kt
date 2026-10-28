package com.mightyoung.muyon.study

import org.json.JSONArray
import org.json.JSONObject
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

/** Import is deliberately pure: callers must show a preview before saving. */
object PlanImport {
    private const val MAX_BYTES = 64 * 1024 * 1024
    fun parse(name: String, bytes: ByteArray): JSONArray {
        require(bytes.size <= MAX_BYTES) { "文件超过64MB" }
        val rows: List<List<String>> = when (name.substringAfterLast('.', "").lowercase()) {
            "doc", "xls" -> error("不支持旧版 .doc/.xls，请另存为 .docx/.xlsx")
            "md", "markdown", "txt" -> bytes.toString(Charsets.UTF_8).lineSequence().map { listOf(it) }.toList()
            "docx" -> {
                val zip = unzip(bytes)
                val doc = xml(zip["word/document.xml"] ?: error("Word文档缺少正文"))
                val body = doc.getElementsByTagNameNS("*", "body").item(0) ?: error("Word文档缺少正文")
                val result = mutableListOf<List<String>>()
                fun textOf(element: Element): String {
                    val ts = element.getElementsByTagNameNS("*", "t")
                    return (0 until ts.length).joinToString("") { ts.item(it).textContent }
                }
                for (i in 0 until body.childNodes.length) {
                    val node = body.childNodes.item(i) as? Element ?: continue
                    when (node.localName) {
                        "p" -> result.add(listOf(textOf(node)))
                        "tbl" -> {
                            val trs = node.getElementsByTagNameNS("*", "tr")
                            for (r in 0 until trs.length) {
                                val cells = (trs.item(r) as Element).getElementsByTagNameNS("*", "tc")
                                result.add((0 until cells.length).map { textOf(cells.item(it) as Element) })
                            }
                        }
                    }
                }
                result
            }
            "xlsx" -> excel(unzip(bytes))
            "json" -> {
                val raw = bytes.toString(Charsets.UTF_8).trim()
                val array = if (raw.startsWith("[")) JSONArray(raw) else JSONObject(raw).getJSONArray("tasks")
                require(array.length() > 0) { "没有可导入任务" }
                return JSONArray().also { out -> for (i in 0 until array.length()) {
                    val src = array.getJSONObject(i); val title = src.optString("title").trim()
                    require(title.isNotEmpty()) { "任务标题为空" }
                    out.put(record(name, i, title, src.optInt("minutes", 30).coerceIn(1, 10080), src.optString("status") == "done", src.optString("due"), src.optString("notes")))
                } }
            }
            else -> error("支持Markdown、Word(.docx)、Excel(.xlsx)和JSON")
        }
        val out = JSONArray()
        var headers: List<String>? = null
        rows.forEachIndexed { index, cells ->
            if (cells.all { it.isBlank() }) return@forEachIndexed
            if (cells.size > 1 && cells.any { it.trim() in listOf("任务", "内容", "标题", "task", "title") }) { headers = cells.map { it.trim().lowercase() }; return@forEachIndexed }
            val h = headers
            if (h != null) {
                fun field(vararg names: String): String = h.indexOfFirst { it in names }.let { if (it >= 0) cells.getOrElse(it) { "" }.trim() else "" }
                val title = field("任务", "内容", "标题", "task", "title")
                if (title.isNotBlank()) out.put(record(name, index, title, duration(field("预计用时", "用时", "时长", "minutes")), field("状态", "status") in listOf("完成", "已完成", "done", "x"), field("截止日期", "日期", "due"), field("备注", "notes")))
            } else {
                val line = cells.joinToString(" ").trim()
                if (line.startsWith("#") || line.matches(Regex("[-=*]{3,}"))) return@forEachIndexed
                val check = Regex("^\\s*[-*+]\\s+\\[([ xX])](.*)$").find(line)
                val title = (check?.groupValues?.get(2) ?: line.replace(Regex("^(?:[-*+]\\s+|\\d+[.)、]\\s*)"), "")).trim()
                if (title.isNotBlank()) out.put(record(name, index, title, duration(title), check?.groupValues?.get(1)?.equals("x", true) == true, Regex("\\d{4}-\\d{1,2}-\\d{1,2}").find(title)?.value ?: "", ""))
            }
        }
        require(out.length() > 0) { "没有找到可导入任务" }
        return out
    }
    private fun duration(s: String): Int {
        val m = Regex("(\\d+(?:\\.\\d+)?)\\s*(小时|分钟|分钟数|hours?|hrs?|h|min(?:utes?)?|m)", RegexOption.IGNORE_CASE).find(s)
        val value = if (m != null) m.groupValues[1].toDouble() * (if (m.groupValues[2].lowercase() in listOf("小时", "hour", "hours", "hr", "hrs", "h")) 60 else 1) else s.toDoubleOrNull() ?: 30.0
        return value.toInt().coerceIn(1, 10080)
    }
    private fun record(source: String, row: Int, title: String, minutes: Int, done: Boolean, due: String, notes: String): JSONObject {
        val digest = MessageDigest.getInstance("SHA-256").digest("$source\u0000$row\u0000$title".toByteArray()).joinToString("") { "%02x".format(it) }
        return JSONObject().put("id", "import-${digest.take(32)}").put("title", title).put("minutes", minutes).put("remaining", if (done) 0 else minutes).put("status", if (done) "done" else "todo").also { obj ->
            val date = runCatching { LocalDate.parse(due.substringBefore('T'), java.time.format.DateTimeFormatter.ofPattern("yyyy-M-d")).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrNull()
                ?: due.toDoubleOrNull()?.let { if (it > 100000000000) it.toLong() else if (it in 1.0..2958465.0) LocalDate.of(1899,12,30).plusDays(it.toLong()).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli() else null }
            if (date != null) obj.put("due", date)
            if (notes.isNotBlank()) obj.put("notes", notes)
        }
    }
    internal fun unzip(bytes: ByteArray): Map<String, ByteArray> {
        val files = linkedMapOf<String, ByteArray>(); var total = 0
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            while (true) {
                val e = zip.nextEntry ?: break
                require(files.size < 4096 && !e.name.startsWith('/') && !e.name.contains('\\') && e.name.split('/').none { it == ".." }) { "不安全的压缩文件" }
                if (e.isDirectory) continue
                require(!files.containsKey(e.name)) { "压缩文件包含重复条目" }
                val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                while (true) { val n = zip.read(buffer); if (n < 0) break; total += n; require(total <= MAX_BYTES && out.size() + n <= 16 * 1024 * 1024) { "解压后文件过大" }; out.write(buffer, 0, n) }
                files[e.name] = out.toByteArray()
            }
        }
        require(files.isNotEmpty()) { "无效或空压缩文件" }; return files
    }
    private fun xml(bytes: ByteArray): org.w3c.dom.Document {
        // Android XML implementations do not all recognize Xerces feature names.
        // Reject DTDs before parsing as well as disabling expansion and resolution.
        require(!bytes.toString(Charsets.ISO_8859_1).replace("\u0000", "").contains("<!DOCTYPE", true)) { "不允许XML文档类型或外部实体" }
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true; isExpandEntityReferences = false
            runCatching { isXIncludeAware = false }
            runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
            runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
            runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
        }
        val builder = factory.newDocumentBuilder()
        builder.setEntityResolver { _, _ -> throw org.xml.sax.SAXException("不允许外部实体") }
        return builder.parse(ByteArrayInputStream(bytes))
    }
    private fun excel(files: Map<String, ByteArray>): List<List<String>> {
        val strings = files["xl/sharedStrings.xml"]?.let { data -> val ns = xml(data).getElementsByTagNameNS("*", "si"); (0 until ns.length).map { ns.item(it).textContent } } ?: emptyList()
        val sheets = files.keys.filter { it.matches(Regex("xl/worksheets/sheet\\d+\\.xml")) }.sorted()
        require(sheets.isNotEmpty()) { "Excel缺少工作表" }
        val date1904 = files["xl/workbook.xml"]?.let { data ->
            val props = xml(data).getElementsByTagNameNS("*", "workbookPr")
            props.length > 0 && (props.item(0) as Element).getAttribute("date1904") in listOf("1", "true")
        } ?: false
        return sheets.flatMap { path ->
            var dateColumns = emptySet<Int>()
            val rs = xml(files.getValue(path)).getElementsByTagNameNS("*", "row")
            (0 until rs.length).map { i ->
                val cs = (rs.item(i) as Element).getElementsByTagNameNS("*", "c"); val row = mutableListOf<String>()
                for (j in 0 until cs.length) {
                    val c = cs.item(j) as Element
                    val letters = c.getAttribute("r").takeWhile { it.isLetter() }; var col = 0
                    letters.forEach { col = col * 26 + (it.uppercaseChar() - 'A' + 1) }; col = (col - 1).coerceAtLeast(j)
                    require(col < 16384) { "Excel列超限" }; while (row.size <= col) row.add("")
                    val v = c.getElementsByTagNameNS("*", "v").item(0)?.textContent ?: ""
                    row[col] = when (c.getAttribute("t")) { "s" -> strings.getOrNull(v.toIntOrNull() ?: -1) ?: error("无效共享字符串"); "inlineStr" -> c.getElementsByTagNameNS("*", "is").item(0)?.textContent ?: ""; else -> v }
                }
                if (row.any { it in listOf("任务", "内容", "标题", "task", "title") }) {
                    dateColumns = row.indices.filter { row[it] in listOf("截止日期", "日期", "due") }.toSet()
                } else if (date1904) {
                    dateColumns.forEach { index -> row.getOrNull(index)?.toDoubleOrNull()?.let { value -> row[index] = (value + 1462).toString() } }
                }
                row
            }
        }
    }
}
