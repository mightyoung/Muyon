package com.mightyoung.muyon.product.agentipc

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.*
import org.json.JSONObject
import java.util.UUID

/** No write is automatically retried on timeout, process death or reconnection. */
class ProductClient(context: Context, private val onConnection: (Boolean) -> Unit) : AutoCloseable {
    private val context = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var service: Messenger? = null
    private var session: String? = null
    private var epoch: String? = null
    private var bound = false
    private var closed = false
    var workspaceExists: Boolean = false
        private set
    private val pending = mutableMapOf<String, (JSONObject) -> Unit>()
    private val receiver = Messenger(object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(message: Message) {
            val raw = message.data.getString("response") ?: return
            if (closed || raw.length > 1_048_576) return
            try {
                val reply = JSONObject(raw)
                pending.remove(reply.getString("request_id"))?.invoke(reply)
            } catch (_: Exception) { /* An invalid reply cannot establish success. */ }
        }
    })
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            if (closed) return
            service = Messenger(binder)
            call("connect", JSONObject()) { result ->
                val data = result.optJSONObject("data")
                if (result.optString("status") == "ok" && data != null) {
                    session = data.getString("session"); epoch = data.getString("epoch")
                    workspaceExists = data.optBoolean("initialized")
                    onConnection(true)
                } else onConnection(false)
            }
        }
        override fun onServiceDisconnected(name: ComponentName) { disconnected() }
        override fun onBindingDied(name: ComponentName) {
            disconnected()
            if (bound) context.unbindService(this)
            bound = false
            if (!closed) handler.post { bind() }
        }
    }
    fun bind() {
        if (!closed && !bound) bound = context.bindService(Intent(context, ProductService::class.java), connection, Context.BIND_AUTO_CREATE)
    }
    private fun failure(code: String) = JSONObject().put("status", "unknown")
        .put("error", code).put("recovery_action", "query_original")
    private fun disconnected() {
        service = null; session = null; epoch = null
        val callbacks = pending.values.toList(); pending.clear()
        callbacks.forEach { it(failure("service_disconnected")) }
        if (!closed) onConnection(false)
    }
    fun call(method: String, payload: JSONObject = JSONObject(), callback: (JSONObject) -> Unit) = request(method, payload, null, callback)
    fun configureChat(settings: JSONObject, credential: CharArray, callback: (JSONObject) -> Unit) = request("chat_configure", settings, credential, callback)
    private fun request(method: String, payload: JSONObject, credential: CharArray?, callback: (JSONObject) -> Unit) {
        val target = service
        if (closed || target == null || (method != "connect" && session == null)) {
            credential?.fill('\u0000'); callback(failure("service_unavailable")); return
        }
        if (pending.size >= 128) { credential?.fill('\u0000'); callback(failure("request_limit")); return }
        if (!validWireJson(payload)) {
            credential?.fill('\u0000')
            callback(failure("invalid_unicode").put("status", "rejected").put("recovery_action", "none")); return
        }
        val raw = payload.toString()
        if (raw.toByteArray(Charsets.UTF_8).size > 1_048_576 || (credential != null && credential.size !in 16..512)) {
            credential?.fill('\u0000'); callback(failure("request_limit")); return
        }
        val request = UUID.randomUUID().toString()
        pending[request] = callback
        try {
            target.send(Message.obtain(null, 1).apply {
                replyTo = receiver
                data = Bundle().apply {
                    putString("request_id", request); putString("method", method); putString("payload", raw)
                    putString("session", session); putString("epoch", epoch)
                    credential?.let { putCharArray("credential", it) }
                }
            })
            handler.postDelayed({ pending.remove(request)?.invoke(failure("response_unknown")) }, 30_000)
        } catch (_: RemoteException) {
            pending.remove(request)?.invoke(failure("response_unknown"))
        } finally { credential?.fill('\u0000') }
    }
    override fun close() {
        if (closed) return
        closed = true
        // Control revocation must not depend on pending capacity or a connect
        // reply. Binder parcels preserve this client's connect/disconnect order.
        try {
            service?.send(Message.obtain(null, 1).apply {
                replyTo = receiver
                data = Bundle().apply {
                    putString("request_id", UUID.randomUUID().toString())
                    putString("method", "disconnect"); putString("payload", "{}")
                    putString("session", session); putString("epoch", epoch)
                }
            })
        } catch (_: RemoteException) { /* owner death also revokes the lease */ }
        if (bound) context.unbindService(connection)
        bound = false
        disconnected()
        handler.removeCallbacksAndMessages(null)
    }
}
