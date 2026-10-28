package com.mightyoung.muyon.study
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONArray
class SuggestionsTest {
    @Test(expected=IllegalArgumentException::class) fun unknown_id_is_rejected_before_ui_callback(){taskSuggestions(obj("tasks" to JSONArray(),"goals" to JSONArray()),JSONArray().put(obj("id" to "imaginary","title" to "bad")))}
    @Test fun progress_update_preserves_existing_links(){val old=obj("id" to "t","title" to "课程","minutes" to 60,"remaining" to 60,"resources" to JSONArray().put(obj("id" to "r")),"status" to "todo");val base=obj("tasks" to JSONArray().put(old),"goals" to JSONArray());val out=taskSuggestions(base,JSONArray().put(obj("id" to "t","remaining" to 20)));assertEquals(20,out.getJSONObject(0).getInt("remaining"));assertEquals("r",out.getJSONObject(0).getJSONArray("resources").getJSONObject(0).getString("id"))}
}
