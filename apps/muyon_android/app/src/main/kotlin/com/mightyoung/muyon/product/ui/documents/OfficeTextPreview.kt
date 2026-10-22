package com.mightyoung.muyon.product.ui.documents

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.ext.DefaultHandler2

/** Native bounded OOXML text preview. No drawing, formula calculation or embedded payloads. */
data class OfficeSection(val title: String, val text: String)

object OfficeTextPreview {
    private const val MAX_ARCHIVE = 16 * 1024 * 1024
    private const val MAX_EXPANDED = 32 * 1024 * 1024
    private const val MAX_PART = 4 * 1024 * 1024
    private const val MAX_TEXT = 200000
    private const val MAX_SECTIONS = 64

    fun read(input: InputStream, format: DocumentFormat): List<OfficeSection> {
        require(format != DocumentFormat.PDF) { "PDF requires PdfRenderer" }
        // Bound compressed bytes too; no staging to user paths or ZIP extraction to disk.
        val archive = boundedBytes(input, MAX_ARCHIVE)
        val parts = linkedMapOf<String, ByteArray>()
        var total = 0
        var count = 0
        ZipInputStream(ByteArrayInputStream(archive)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                require(++count <= 1024) { "Office ZIP entry limit" }
                require(!entry.name.startsWith('/') && !entry.name.contains('\\') &&
                    entry.name.split('/').none { it == ".." || it == "." }) { "Unsafe ZIP part" }
                val selected = selected(entry.name, format)
                val output = if (selected) ByteArrayOutputStream() else null
                var partSize = 0
                val buffer = ByteArray(8192)
                while (true) {
                    val read = zip.read(buffer)
                    if (read < 0) break
                    total += read; partSize += read
                    require(total <= MAX_EXPANDED && (!selected || partSize <= MAX_PART)) { "Office expansion limit" }
                    output?.write(buffer, 0, read)
                }
                if (output != null) {
                    require(!parts.containsKey(entry.name)) { "Duplicate Office part" }
                    require(parts.size < MAX_SECTIONS + 1) { "Office part limit" }
                    parts[entry.name] = output.toByteArray()
                }
                zip.closeEntry()
            }
        }
        val strings = parts["xl/sharedStrings.xml"]?.let { parse(it, Mode.STRINGS).strings }.orEmpty()
        val sections = parts.filterKeys { it != "xl/sharedStrings.xml" }.entries
            .sortedBy { Regex("[0-9]+(?=\\.xml$)").find(it.key)?.value?.toIntOrNull() ?: 0 }
        require(sections.isNotEmpty() && sections.size <= MAX_SECTIONS) { "Unsupported or missing Office content" }
        var textSize = 0
        return sections.map { (name, data) ->
            val parsed = parse(data, if (format == DocumentFormat.XLSX) Mode.SHEET else Mode.TEXT, strings)
            textSize += parsed.text.length
            require(textSize <= MAX_TEXT) { "Office text limit" }
            OfficeSection(name, parsed.text.ifBlank { "此部分没有可预览文本" })
        }
    }

    private fun selected(name: String, format: DocumentFormat): Boolean = when (format) {
        DocumentFormat.DOCX -> name == "word/document.xml"
        DocumentFormat.PPTX -> name.matches(Regex("ppt/slides/slide[1-9][0-9]{0,5}\\.xml"))
        DocumentFormat.XLSX -> name == "xl/sharedStrings.xml" || name.matches(Regex("xl/worksheets/sheet[1-9][0-9]{0,5}\\.xml"))
        DocumentFormat.PDF -> false
    }

    private fun boundedBytes(input: InputStream, limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            require(out.size() + read <= limit) { "Office archive limit" }
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    private enum class Mode { TEXT, STRINGS, SHEET }
    private class TextHandler(val mode: Mode, val shared: List<String>) : DefaultHandler2() {
        val text = StringBuilder()
        val strings = mutableListOf<String>()
        private val value = StringBuilder()
        private val sharedValue = StringBuilder()
        private var capture = false
        private var phoneticDepth = 0
        private var cell = ""
        private var cellType = ""
        private var formula = false
        private var depth = 0
        override fun startDTD(name: String?, publicId: String?, systemId: String?) { throw SAXException("DTD unsupported") }
        override fun resolveEntity(publicId: String?, systemId: String?): InputSource { throw SAXException("External entity unsupported") }
        override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes) {
            require(++depth <= 128) { "XML depth limit" }
            val tag = localName?.takeIf { it.isNotEmpty() } ?: qName.orEmpty().substringAfter(':')
            // Spreadsheet rPh text is a pronunciation hint, never the base cell/string value.
            if (mode != Mode.TEXT && tag == "rPh") phoneticDepth++
            if (tag == "si") sharedValue.setLength(0)
            if (tag == "c") {
                cell = attributes.getValue("r").orEmpty(); cellType = attributes.getValue("t").orEmpty()
                value.setLength(0); formula = false
            }
            if (tag == "f") formula = true
            capture = phoneticDepth == 0 && (tag == "t" || (mode == Mode.SHEET && tag == "v"))
        }
        override fun characters(ch: CharArray, start: Int, length: Int) {
            if (!capture) return
            val target = when (mode) { Mode.TEXT -> text; Mode.STRINGS -> sharedValue; Mode.SHEET -> value }
            require(target.length + length <= MAX_TEXT) { "Office text limit" }
            target.append(ch, start, length)
        }
        override fun endElement(uri: String?, localName: String?, qName: String?) {
            val tag = localName?.takeIf { it.isNotEmpty() } ?: qName.orEmpty().substringAfter(':')
            if (tag == "t" || tag == "v") capture = false
            if (mode != Mode.TEXT && tag == "rPh") phoneticDepth--
            if (mode == Mode.STRINGS && tag == "si") {
                require(strings.size < 10000 && strings.sumOf { it.length } + sharedValue.length <= MAX_TEXT) { "Shared string limit" }
                strings.add(sharedValue.toString())
            }
            if (mode == Mode.SHEET && tag == "c") {
                val raw = value.toString()
                val display = if (cellType == "s") shared.getOrNull(raw.toIntOrNull() ?: -1)
                    ?: throw SAXException("Missing shared string") else raw
                text.append(cell).append(": ").append(display)
                if (formula) text.append(" [公式缓存值]")
                text.append('\n')
            }
            if (mode == Mode.TEXT && (tag == "p" || tag == "br")) text.append('\n')
            require(text.length <= MAX_TEXT) { "Office text limit" }
            depth--
        }
    }
    private data class Parsed(val text: String, val strings: List<String>)
    private fun parse(bytes: ByteArray, mode: Mode, shared: List<String> = emptyList()): Parsed {
        val reader = SAXParserFactory.newInstance().apply { isNamespaceAware = true }.newSAXParser().xmlReader
        val handler = TextHandler(mode, shared)
        // Fail closed if the platform cannot enforce these controls.
        reader.setFeature("http://xml.org/sax/features/external-general-entities", false)
        reader.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        reader.setProperty("http://xml.org/sax/properties/lexical-handler", handler)
        reader.contentHandler = handler
        reader.entityResolver = handler
        reader.errorHandler = handler
        reader.parse(InputSource(ByteArrayInputStream(bytes)))
        return Parsed(handler.text.toString(), handler.strings)
    }
}
