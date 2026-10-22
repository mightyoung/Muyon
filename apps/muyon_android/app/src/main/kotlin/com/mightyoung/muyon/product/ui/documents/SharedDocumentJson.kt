package com.mightyoung.muyon.product.ui.documents

import org.json.JSONObject

/** Maps the frozen core serde wire shape. Caller must reject parse failures, never guess identity. */
object SharedDocumentJson {
    fun document(value: JSONObject): ReaderDocumentRef {
        val scope = value.getJSONObject("scope")
        return ReaderDocumentRef(scope.getString("workspace_id"),
            if (scope.isNull("project_id")) null else scope.getString("project_id"),
            value.getString("document_id"), wireRevision(value), when (value.getString("format")) {
                "pdf" -> DocumentFormat.PDF; "docx" -> DocumentFormat.DOCX
                "pptx" -> DocumentFormat.PPTX; "xlsx" -> DocumentFormat.XLSX
                else -> error("Unsupported document format")
            })
    }
    fun annotation(value: JSONObject): SidecarAnnotation {
        val anchor = value.getJSONObject("anchor")
        val body = value.getJSONObject("body")
        val content = when (body.getString("kind")) {
            "comment" -> AnnotationContent.Comment(body.getString("text"))
            "highlight" -> AnnotationContent.Highlight(body.getString("quote"),
                if (body.isNull("note")) null else body.getString("note"))
            else -> error("Unsupported annotation body")
        }
        val location = anchor.getJSONObject("location")
        val label = when {
            location.has("pdf") -> location.getJSONObject("pdf").let { pdf ->
                val page = if (pdf.isNull("page_index_zero_based")) null else pdf.getLong("page_index_zero_based")
                if (page == null || page !in 0..4294967295L) "PDF 位置未解析" else "第 ${page + 1} 页 · 坐标未解析"
            }
            location.has("docx") -> location.getJSONObject("docx").let { "段落 ${it.getString("paragraph_id")}" }
            location.has("pptx") -> location.getJSONObject("pptx").let { "幻灯片 ${it.getString("slide_id")} / ${it.getString("shape_id")}" }
            location.has("xlsx") -> location.getJSONObject("xlsx").let {
                "工作表 ${it.getString("sheet_id")} · R${it.getLong("first_row")}C${it.getLong("first_column")}–R${it.getLong("last_row")}C${it.getLong("last_column")}" }
            else -> error("Unsupported anchor")
        }
        val stale = when (value.getString("anchor_state")) { "current" -> false; "stale" -> true; else -> error("Unknown anchor state") }
        return SidecarAnnotation(value.getString("id"), wireRevision(value), document(anchor.getJSONObject("document")),
            anchor.toString(), label, "创建：${author(value.getJSONObject("created_by"))}；修改：${author(value.getJSONObject("modified_by"))}",
            content, stale, value.getBoolean("deleted"))
    }
    private fun wireRevision(value: JSONObject): String =
        (value.get("revision") as? String)?.also { require(validRevision(it)) }
            ?: error("Revision must be decimal wire text")

    private fun author(value: JSONObject): String = when (value.getString("kind")) {
        "human" -> "人工 ${value.getString("actor_id")}"
        "ai" -> "AI ${value.getString("agent_id")} / ${value.getString("run_id")}（预标注，非人工确认）"
        else -> error("Unknown annotation author")
    }
    fun replacementBody(edit: SidecarEdit): JSONObject = when (val body = edit.replacement) {
        is AnnotationContent.Comment -> JSONObject().put("kind", "comment").put("text", body.text)
        is AnnotationContent.Highlight -> JSONObject().put("kind", "highlight").put("quote", body.quote)
            .put("note", body.note ?: JSONObject.NULL)
    }
}
