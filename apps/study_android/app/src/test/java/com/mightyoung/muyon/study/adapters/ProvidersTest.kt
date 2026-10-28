package com.mightyoung.muyon.study.adapters

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ProvidersTest {
    @Test fun progressFixturePreservesUnitsAndFreshness() {
        val progress = Providers.parseMaimemo(JSONObject("""{"progress":{"finished":10,"total":20,"study_time":114514}}"""))
        assertEquals(10, progress.getInt("finished")); assertEquals(114514, progress.getLong("study_time")); assertTrue(progress.has("fetched_at"))
    }
    @Test fun missingOrMalformedProgressNeverMeansZero() {
        for(fixture in listOf("{}", """{"progress":{"finished":1,"total":2}}""", """{"progress":{"finished":-1,"total":2,"study_time":0}}""", """{"progress":{"finished":"1","total":2,"study_time":0}}""")) {
            try { Providers.parseMaimemo(JSONObject(fixture)); fail("Accepted invalid progress") } catch (_: ProviderException) { }
        }
    }
}
