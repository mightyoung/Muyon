package com.mightyoung.muyon.study
import org.json.JSONArray
import org.json.JSONObject
import java.time.*
import java.time.format.DateTimeFormatter

private val fmt=DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
fun dateText(ms:Long):String=if(ms<=0)"" else Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(fmt)
fun parseDate(text:String):Long {
    if(text.isBlank())return 0
    val t=text.trim().replace('T',' ')
    return if(t.length==10)LocalDate.parse(t).atTime(23,59).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        else LocalDateTime.parse(t,fmt).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
}
fun fixedWindows(settings:JSONObject,days:Int=28):JSONArray {
    val result=JSONArray();val today=LocalDate.now();val zone=ZoneId.systemDefault()
    val rules=settings.optJSONArray("windows")?.objects().orEmpty()
    repeat(days){offset->val day=today.plusDays(offset.toLong())
        val override=settings.optJSONArray("overrides")?.objects()?.find{it.optString("date")==day.toString()}
        if(override!=null){
            if(!override.optBoolean("unavailable")){
                val start=day.atTime(LocalTime.parse(override.getString("start"))).atZone(zone).toInstant().toEpochMilli()
                val end=day.atTime(LocalTime.parse(override.getString("end"))).atZone(zone).toInstant().toEpochMilli()
                require(end>start){"今日可用时段结束必须晚于开始"};result.put(obj("start" to start,"end" to end))
            }
            return@repeat
        }
        rules.forEach{rule->val weekdays=rule.optJSONArray("days")?:JSONArray()
            if((0 until weekdays.length()).any{weekdays.optInt(it)==day.dayOfWeek.value}){
                val start=day.atTime(LocalTime.parse(rule.getString("start"))).atZone(zone).toInstant().toEpochMilli()
                val end=day.atTime(LocalTime.parse(rule.getString("end"))).atZone(zone).toInstant().toEpochMilli()
                require(end>start){"固定时段结束时间必须晚于开始时间"}
                result.put(obj("start" to start,"end" to end))
            }
        }
    };return result
}
fun planningRequest(state:JSONObject):JSONObject {
    val now=System.currentTimeMillis()
    val farDue=(state.items("goals")+state.items("tasks")).map{it.optLong("due")}.maxOrNull()?:0
    val days=(((farDue-now).coerceAtLeast(0)/86400000)+8).coerceIn(90,730).toInt()
    return obj("op" to "propose","now" to now,"windows" to fixedWindows(state.getJSONObject("settings")),
        "capacityWindows" to fixedWindows(state.getJSONObject("settings"),days),"detailedEnd" to now+28L*86400000,
        "offsetMinutes" to java.time.ZonedDateTime.now().offset.totalSeconds/60,"busy" to JSONArray())
}
