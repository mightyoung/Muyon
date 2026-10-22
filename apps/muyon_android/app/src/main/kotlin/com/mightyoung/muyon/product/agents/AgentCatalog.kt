package com.mightyoung.muyon.product.agents

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

data class AgentProfile(
    val id: String, val name: String, val role: String, val instructions: String,
    val avatar: String = "✦", val accent: String = "#7564D8", val archived: Boolean = false,
)
data class AgentGroup(val id: String, val name: String, val members: List<String>, val archived: Boolean = false)
data class CatalogSnapshot(val agents: List<AgentProfile>, val groups: List<AgentGroup>)

internal fun visibleName(value: String, fallback: String): String = value.filterNot {
    it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt()
}.trim().takeIf { name -> name.any { !it.isWhitespace() && !Character.isSpaceChar(it) } } ?: fallback

/** Local organization only. Never stores credentials, model connections or chat transcripts. */
class AgentCatalog private constructor(private val preferences: SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE))
    companion object {
        const val PREFERENCES = "muyon_agent_catalog_v1"
        const val KEY = "catalog"
        private val lock = Any()
        private const val MAX_RECORDS = 100
        private const val MAX_SERIALIZED_LENGTH = 1_200_000
    }

    fun read(): CatalogSnapshot = synchronized(lock) { readLocked() }
    fun activeAgent(id: String): AgentProfile = read().agents.single { it.id == id && !it.archived }

    private fun text(value: String, limit: Int, required: Boolean = true) {
        require(value.length <= limit && (!required || value.isNotBlank()) && value.none { it == '\u0000' }) {
            "内容为空或超过长度限制"
        }
    }
    private fun validate(snapshot: CatalogSnapshot) {
        require(snapshot.agents.size <= MAX_RECORDS && snapshot.groups.size <= MAX_RECORDS) { "目录最多保存 100 个智能体和 100 个群组（包含归档）" }
        require(snapshot.agents.map { it.id }.distinct().size == snapshot.agents.size &&
            snapshot.groups.map { it.id }.distinct().size == snapshot.groups.size) { "目录标识重复" }
        snapshot.agents.forEach {
            text(it.id, 80); text(it.name, 60); text(it.role, 160); text(it.instructions, 8000, false); text(it.avatar, 8)
            require(it.accent.matches(Regex("#[0-9a-fA-F]{6}"))) { "请选择有效头像颜色" }
        }
        val active = snapshot.agents.filterNot { it.archived }.map { it.id }.toSet()
        val all = snapshot.agents.map { it.id }.toSet()
        snapshot.groups.forEach {
            text(it.id, 80); text(it.name, 60)
            require(it.members.isNotEmpty() && it.members.size <= 20 && it.members.distinct().size == it.members.size) { "群组需要 1 至 20 位不同成员" }
            require(it.members.all { id -> id in (if (it.archived) all else active) }) { "群组成员已失效，请先调整成员" }
        }
    }
    private fun readLocked(): CatalogSnapshot {
        try {
            if (!preferences.contains(KEY)) return CatalogSnapshot(emptyList(), emptyList())
            val raw = preferences.getString(KEY, null) ?: error("missing catalog")
            require(raw.length <= MAX_SERIALIZED_LENGTH)
            val parser = JSONTokener(raw)
            val root = parser.nextValue() as? JSONObject ?: error("invalid catalog root")
            require(parser.nextClean() == '\u0000' && root.get("version") is Int && root.getInt("version") == 1)
            fun string(item: JSONObject, key: String): String = (item.get(key) as? String) ?: error("invalid string")
            fun archived(item: JSONObject): Boolean = (item.get("archived") as? Boolean) ?: error("invalid archived flag")
            val agents = root.getJSONArray("agents").let { array -> (0 until array.length()).map {
                val item = array.getJSONObject(it)
                AgentProfile(string(item, "id"), string(item, "name"), string(item, "role"), string(item, "instructions"),
                    string(item, "avatar"), string(item, "accent"), archived(item))
            } }
            val groups = root.getJSONArray("groups").let { array -> (0 until array.length()).map {
                val item = array.getJSONObject(it)
                val members = item.getJSONArray("members").let { ids -> (0 until ids.length()).map { n -> (ids.get(n) as? String) ?: error("invalid member") } }
                AgentGroup(string(item, "id"), string(item, "name"), members, archived(item))
            } }
            return CatalogSnapshot(agents, groups).also(::validate)
        } catch (failure: Exception) {
            throw IllegalStateException("智能体目录读取失败，原数据已保留。请恢复有效备份后重试。", failure)
        }
    }
    private fun mutate(change: (CatalogSnapshot) -> CatalogSnapshot) = synchronized(lock) {
        val next = change(readLocked()) // Never replace unreadable persisted data with an empty catalog.
        validate(next)
        val agents = JSONArray().also { array -> next.agents.forEach { item -> array.put(JSONObject()
            .put("id", item.id).put("name", item.name).put("role", item.role).put("instructions", item.instructions)
            .put("avatar", item.avatar).put("accent", item.accent).put("archived", item.archived)) } }
        val groups = JSONArray().also { array -> next.groups.forEach { item -> array.put(JSONObject()
            .put("id", item.id).put("name", item.name).put("members", JSONArray(item.members)).put("archived", item.archived)) } }
        val raw = JSONObject().put("version", 1).put("agents", agents).put("groups", groups).toString()
        require(raw.length <= MAX_SERIALIZED_LENGTH) { "目录容量上限已达到，请缩短指令后重试；原数据已保留" }
        check(preferences.edit().putString(KEY, raw).commit()) {
            "目录保存失败，请重试；尚未确认写入成功"
        }
    }
    fun saveAgent(agent: AgentProfile) = mutate { current -> current.copy(agents = current.agents.filterNot { it.id == agent.id } + agent) }
    fun saveGroup(group: AgentGroup) = mutate { current -> current.copy(groups = current.groups.filterNot { it.id == group.id } + group) }
    fun archiveAgent(id: String) = mutate { current ->
        require(current.agents.any { it.id == id }) { "智能体不存在" }
        require(current.groups.none { !it.archived && id in it.members }) { "请先从有效群组中移除此成员" }
        current.copy(agents = current.agents.map { if (it.id == id) it.copy(archived = true) else it })
    }
    fun archiveGroup(id: String) = mutate { current ->
        require(current.groups.any { it.id == id }) { "群组不存在" }
        current.copy(groups = current.groups.map { if (it.id == id) it.copy(archived = true) else it })
    }
}
