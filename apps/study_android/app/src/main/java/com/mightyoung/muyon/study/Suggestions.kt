package com.mightyoung.muyon.study
import org.json.JSONArray
import org.json.JSONObject
/** Validates a model's candidate on the worker; no UI or storage side effects. */
fun taskSuggestions(base:JSONObject,proposed:JSONArray):JSONArray {
    require(proposed.length()<=200){"AI 建议过多，未应用修改"}
    val result=JSONArray()
    proposed.objects().forEach{p->
        val id=p.optString("id");val old=base.items("tasks").find{it.optString("id")==id}
        require(id.isBlank()||old!=null){"AI 返回了未知任务ID，未修改数据"}
        val t=if(old!=null)JSONObject(old.toString())else obj("id" to newId(),"minutes" to 30,"remaining" to 30,"status" to "todo")
        listOf("title","minutes","remaining","due","goal","priority","status","notes","location").forEach{k->if(p.has(k))t.put(k,p.get(k))}
        require(t.optString("title").isNotBlank()){ "AI 建议缺少任务内容" }
        for(k in listOf("minutes","remaining"))require(t.optInt(k,-1) in 0..100000){"AI 建议时长无效"}
        require(t.optString("status") in listOf("todo","doing","done","blocked","paused")){"AI 建议状态无效"}
        if(!t.isNull("goal")&&t.optString("goal").isNotBlank())require(base.items("goals").any{it.optString("id")==t.getString("goal")}){"AI 建议目标不存在"}
        result.put(t)
    };return result
}
