package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidlab.*
import org.json.JSONObject

/** Bounded presentation decoder; JSON labels never confer authority. */
internal fun registeredToolProjection(payload:JSONObject):ChatToolResult {
    require(payload.keys().asSequence().toSet()==setOf("tool","result") && payload.get("tool") is String)
    val p=payload.getJSONObject("result")
    require(p.keys().asSequence().toSet()==setOf("provider","connection","request","sources","tainted","instruction_authority","currency","cost_micros","billing"))
    require(p.get("tainted")==true && p.get("instruction_authority")==false && p.get("provider") is String && p.get("currency") is String && p.get("billing") is String && (p.get("cost_micros") is Int||p.get("cost_micros") is Long))
    val connection=p.getJSONObject("connection");require(connection.keys().asSequence().toSet()==setOf("module_id","type","key","revision","schema_version") && connection.get("module_id")=="web_search" && connection.get("type")=="connection" && connection.get("schema_version")==1 && connection.get("key") is String && connection.get("revision") is String)
    val request=p.getJSONObject("request");require(request.keys().asSequence().toSet()==setOf("task","attempt","call") && listOf("task","attempt","call").all{request.get(it) is String && request.getString(it).length in 1..256})
    val rows=p.getJSONArray("sources");require(rows.length()<=50)
    val sources=(0 until rows.length()).map {i->val row=rows.getJSONObject(i)
        val required=setOf("title","url","snippet","summary","content","rerank_score","authority","rank")
        require(row.keys().asSequence().toSet().let{it.containsAll(required) && (it-required).all{k->k in setOf("site_name","site_icon","date")}})
        require(row.keys().asSequence().filter{it !in setOf("authority","rank")}.all{row.get(it) is String && row.getString(it).toByteArray().size<=4096})
        require(row.get("authority") is Int && row.getInt("authority") in -1..4 && row.get("rank") is Int && row.getInt("rank")==i+1)
        ChatSource(row.getString("title"),row.getString("url"),row.getInt("rank"))
    }
    val billing=p.getString("billing");require(billing==if(sources.isEmpty())"empty_success" else "nonempty_success")
    val cost=p.getLong("cost_micros");require(if(sources.isEmpty())cost==0L else cost>0)
    return ChatToolResult(payload.getString("tool"),p.getString("provider"),sources,p.getString("currency"),cost,sources.isEmpty())
}
