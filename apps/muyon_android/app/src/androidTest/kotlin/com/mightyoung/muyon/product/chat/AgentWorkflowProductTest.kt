package com.mightyoung.muyon.product.chat

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.MainActivity
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real Activity → Binder Service → serialized runtime → Rust durable workflow ledger. */
class AgentWorkflowProductTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var client: ProductClient
    private val clients = mutableListOf<ProductClient>()
    private val conversation = UUID.randomUUID().toString()

    private fun connectClient(): ProductClient {
        val connected = CountDownLatch(1)
        lateinit var connectedClient: ProductClient
        instrumentation.runOnMainSync {
            connectedClient = ProductClient(context) { if (it) connected.countDown() }
            connectedClient.bind()
        }
        clients += connectedClient
        assertTrue("real Binder connection", connected.await(15, TimeUnit.SECONDS))
        return connectedClient
    }

    @Before fun connect() {
        client = connectClient()
        val health = call("health")
        val database = File(context.filesDir, "muyon-product-v2/business-v2.sqlite")
        val ready = if (health.optString("status") != "ok" && !database.isFile) call("initialize") else health
        assertEquals(ready.toString(), "ok", ready.getString("status"))
        scope(null)
    }

    @After fun close() { instrumentation.runOnMainSync { clients.forEach { it.close() } } }

    private fun call(method: String, payload: JSONObject = JSONObject(), target: ProductClient = client): JSONObject {
        val done = CountDownLatch(1)
        var reply: JSONObject? = null
        instrumentation.runOnMainSync { target.call(method, payload) { reply = it; done.countDown() } }
        assertTrue("real $method callback", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(reply)
    }

    private fun success(reply: JSONObject): JSONObject {
        assertEquals(reply.toString(), "ok", reply.getString("status"))
        val data = reply.getJSONObject("data")
        assertFalse("nested operation failure: $data", data.has("error"))
        assertNotEquals(data.toString(), "unavailable", data.optString("status"))
        return data
    }

    private fun scope(project: String?, target: ProductClient = client) {
        success(call("chat_scope", JSONObject().put("project_id", project ?: JSONObject.NULL), target))
    }

    private fun action(action: String) = JSONObject().put("action", action)
    private fun workflow(operation: JSONObject, target: ProductClient = client, chat: String = conversation): JSONObject =
        success(call("agent_workflow", JSONObject().put("conversation_id", chat).put("operation", operation), target))
    private fun denied(operation: JSONObject, expected: String, target: ProductClient = client, chat: String = conversation) {
        val reply = call("agent_workflow", JSONObject().put("conversation_id", chat).put("operation", operation), target)
        assertEquals(reply.toString(), "ok", reply.getString("status"))
        val failure = reply.getJSONObject("data")
        assertEquals(failure.toString(), "unavailable", failure.getString("status"))
        assertEquals(failure.toString(), expected, failure.getString("error"))
        assertFalse(failure.has("result"))
    }

    private fun root(title: String = "真实任务 ${UUID.randomUUID()}") = workflow(action("create_root")
        .put("title", title).put("task", "读取本地测试记录，保留来源，不外发。"))
    private fun child(root: JSONObject, executor: String = "local_read", offset: Int = 0) = workflow(childAction(root, executor, offset))
    private fun childAction(root: JSONObject, executor: String = "local_read", offset: Int = 0) = action("create_child")
        .put("root_id", root.getString("id")).put("skill_id", "supplier-overview")
        .put("task", "读取本地供应商记录，不联网。拥有明确且足够长的任务要求。")
        .put("executor", executor).put("arguments", JSONObject().put("limit", 50).put("offset", offset))
    private fun snapshot(root: JSONObject) = workflow(action("snapshot").put("root_id", root.getString("id")).put("after_seq", 0))
    private fun objects(rows: JSONArray) = (0 until rows.length()).map { rows.getJSONObject(it) }

    private fun commit(operation: JSONObject): JSONObject {
        val plan = success(call("prepare", JSONObject().put("operation", operation).put("expected_revision", "0")))
        val committed = success(call("confirm", JSONObject().put("plan_id", plan.getString("plan_id"))))
        assertEquals(committed.toString(), "committed", committed.getString("status"))
        assertEquals(plan.getString("intent_id"), committed.getJSONObject("receipt").getString("intent_id"))
        assertEquals("ok", call("discard", JSONObject().put("plan_id", plan.getString("plan_id"))).getString("status"))
        return committed
    }

    @Test fun selectedSkillReadsCommittedBusinessAndPublishesOrderedToolFacts() {
        val supplierId = UUID.randomUUID().toString()
        val name = "Workflow fixture $supplierId"
        commit(JSONObject().put("operation", "supplier_create").put("supplier_id", supplierId).put("payload", JSONObject()
            .put("name", name).put("aliases", JSONArray()).put("categories", JSONArray())
            .put("address", JSONObject.NULL).put("notes", "Local workflow fixture").put("merged_into", JSONObject.NULL)))
        var offset = 0
        while (true) {
            val reply = call("suppliers", JSONObject().put("limit", 50).put("offset", offset))
            assertEquals(reply.toString(), "ok", reply.getString("status"))
            val page = reply.getJSONArray("data")
            if (objects(page).any { it.getString("id") == supplierId }) break
            assertEquals("fixture must exist in real source", 50, page.length())
            offset += 50
            assertTrue("bounded source pagination", offset <= 10000)
        }
        val parent = root()
        assertTrue(parent.getBoolean("can_control"))
        val run = child(parent, offset = offset)
        assertEquals(parent.getString("id"), run.getString("parent_id"))
        assertEquals("queued", run.getString("status"))
        assertTrue(run.isNull("result"))
        val executed = workflow(action("execute_local").put("run_id", run.getString("id")))
        assertEquals(executed.toString(), "completed", executed.getString("status"))
        val result = executed.getJSONObject("result")
        assertEquals("current_local_business", result.getString("source"))
        assertFalse(result.getBoolean("synthetic"))
        assertFalse(result.getBoolean("outbound_authorized"))
        val record = objects(result.getJSONArray("records")).single { it.getString("id") == supplierId }
        assertEquals(name, record.getJSONObject("payload").getString("name"))
        val snap = snapshot(parent)
        assertEquals("completed", snap.getJSONObject("root").getString("status"))
        val events = objects(snap.getJSONArray("events"))
        assertEquals(listOf("run_created", "child_spawned", "skill_loaded", "tool_started", "tool_completed", "completed"), events.map { it.getString("kind") })
        assertTrue(events.zipWithNext().all { (a, b) -> a.getLong("seq") < b.getLong("seq") })
        assertEquals("tool_result", events.single { it.getString("kind") == "tool_completed" }.getString("origin"))
        denied(action("execute_local").put("run_id", run.getString("id")), "workflow_execution_denied")
    }

    @Test fun metadataLoadsBodyOnDemandAndDisabledSkillCannotCreateOrExecute() {
        val metadata = objects(workflow(action("skills")).getJSONArray("skills")).single { it.getString("id") == "supplier-overview" }
        assertFalse(metadata.has("body"))
        assertFalse(metadata.has("content"))
        val loaded = workflow(action("load_skill").put("skill_id", "supplier-overview"))
        assertTrue(loaded.getString("body").contains("supplier_list"))
        val digest = MessageDigest.getInstance("SHA-256").digest(loaded.getString("body").toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        assertEquals(digest, metadata.getString("digest"))
        assertEquals(digest, loaded.getString("digest"))
        val parent = root()
        val run = child(parent)
        try {
            assertFalse(workflow(action("set_skill").put("skill_id", "supplier-overview").put("enabled", false)).getBoolean("enabled"))
            denied(childAction(parent), "workflow_skill_disabled")
            denied(action("execute_local").put("run_id", run.getString("id")), "workflow_skill_disabled")
            val unchanged = objects(snapshot(parent).getJSONArray("runs")).single { it.getString("id") == run.getString("id") }
            assertEquals("queued", unchanged.getString("status"))
            assertTrue(unchanged.isNull("result"))
        } finally { workflow(action("set_skill").put("skill_id", "supplier-overview").put("enabled", true)) }
        assertEquals("completed", workflow(action("execute_local").put("run_id", run.getString("id"))).getString("status"))
    }

    @Test fun conversationProjectAndBinderSessionIsolateAuthority() {
        val parent = root()
        denied(action("snapshot").put("root_id", parent.getString("id")), "workflow_run_not_found", chat = UUID.randomUUID().toString())
        val other = connectClient()
        scope(null, other)
        val previous = workflow(action("snapshot").put("root_id", parent.getString("id")), other).getJSONObject("root")
        assertFalse(previous.getBoolean("can_control"))
        denied(action("cancel").put("run_id", parent.getString("id")), "workflow_previous_session_read_only", other)
        val project = UUID.randomUUID().toString()
        commit(JSONObject().put("operation", "project_create").put("project_id", project).put("name", "Workflow isolation $project"))
        scope(project)
        denied(action("snapshot").put("root_id", parent.getString("id")), "workflow_run_not_found")
        val projectRoot = root()
        assertEquals(project, projectRoot.getString("project_id"))
        scope(null)
        denied(action("snapshot").put("root_id", projectRoot.getString("id")), "workflow_run_not_found")
        assertTrue(snapshot(parent).getJSONObject("root").getBoolean("can_control"))
    }

    @Test fun remoteChildCannotPretendToExecuteAndRootCancellationStopsQueuedWork() {
        val parent = root()
        val remote = child(parent, "remote_chat")
        assertNotEquals(conversation, remote.getString("conversation_id"))
        assertTrue(remote.getString("conversation_id").startsWith("child-"))
        assertTrue(remote.getBoolean("can_control"))
        assertTrue(remote.isNull("remote_request_id"))
        denied(action("execute_local").put("run_id", remote.getString("id")), "workflow_execution_denied")
        // No provider is configured or credential installed by this fixture. Preparation alone must never claim execution.
        val preview = call("workflow_prepare", JSONObject().put("conversation_id", conversation).put("run_id", remote.getString("id")))
        assertEquals(preview.toString(), "ok", preview.getString("status"))
        val rejected = preview.getJSONObject("data")
        assertEquals(rejected.toString(), "unavailable", rejected.getString("status"))
        assertTrue(rejected.getString("error").isNotBlank())
        assertFalse(rejected.has("request_id"))
        val local = child(parent)
        val stopped = workflow(action("cancel").put("run_id", parent.getString("id"))).getJSONObject("snapshot")
        assertEquals("cancelled", stopped.getJSONObject("root").getString("status"))
        objects(stopped.getJSONArray("runs")).forEach {
            assertEquals(it.toString(), "cancelled", it.getString("status"))
            assertTrue(it.isNull("result"))
            assertTrue(it.isNull("remote_request_id"))
        }
        denied(action("execute_local").put("run_id", local.getString("id")), "workflow_execution_denied")
        denied(childAction(parent), "workflow_parent_invalid")
        assertFalse(objects(snapshot(parent).getJSONArray("events")).any { it.getString("kind") == "tool_completed" })
    }

    @Test fun activityMenuCreatesAndExecutesLocalChildWithCollapsibleFacts() {
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("chat-more").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("任务与技能").assertDoesNotExist()
        compose.onNodeWithTag("chat-more").performClick()
        compose.onNodeWithText("任务与技能").performClick()
        waitFor("workflow-manager")
        val title = "本地工作流 UI ${UUID.randomUUID()}"
        compose.onNodeWithTag("workflow-title").performScrollTo().performTextInput(title)
        compose.onNodeWithTag("workflow-task").performScrollTo().performTextInput("读取本地供应商并核对来源，不外发。")
        compose.onNodeWithTag("workflow-create-root").performScrollTo().performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("workflow-title").fetchSemanticsNodes().singleOrNull()
                ?.config?.get(SemanticsProperties.EditableText)?.text == ""
        }
        waitFor("workflow-child-task")
        compose.onNodeWithTag("workflow-skill-supplier-overview").performScrollTo().performClick()
        compose.onNodeWithTag("workflow-child-task").performScrollTo().performTextInput("执行供应商概览技能，显示真实读取过程。")
        compose.onNodeWithTag("workflow-create-child").performScrollTo().performClick()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("workflow-child-task").fetchSemanticsNodes().singleOrNull()
                ?.config?.get(SemanticsProperties.EditableText)?.text == ""
        }
        compose.onNodeWithTag("workflow-show-activity").performScrollTo().performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("执行本地工具").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("执行本地工具").performScrollTo().performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("本地读取完成").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("查看结果").performScrollTo().performClick()
        compose.onNode(hasText("current_local_business", substring = true)).assertExists()
        capture("01-local-child-result")
        compose.onNodeWithTag("workflow-expand").performScrollTo().performClick()
        compose.onNodeWithText("本地读取完成").assertDoesNotExist()
        compose.onNodeWithText("任务与技能").assertDoesNotExist()
        capture("02-collapsed-chat")
    }

    private fun waitFor(tag: String) { compose.waitUntil(15_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() } }
    private fun capture(name: String) {
        compose.waitForIdle()
        instrumentation.uiAutomation.waitForIdle(300, 5_000)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        val folder = File(context.getExternalFilesDir(null), "workflow-proof").also { check(it.mkdirs() || it.isDirectory) }
        File(folder, "$name.png").outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        bitmap.recycle()
    }
}
