package com.mightyoung.muyon.study.adapters

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

class OfflineSpeech(context: Context) : AutoCloseable {
    private val context = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var service: SpeechService? = null
    private var recognizer: Recognizer? = null
    private val session = SpeechSession()
    @Volatile private var closed = false
    @Synchronized fun start(onText: (String) -> Unit, onStatus: (String) -> Unit) {
        if(closed) return
        val ticket = session.begin()
        fun status(value: String) { main.post { if(session.current(ticket) && !closed) onStatus(value) } }
        fun finish(value: String) { main.post {
            if(session.current(ticket) && !closed) {
                onStatus(value)
                synchronized(this) {
                    if(!closed && session.current(ticket)) {
                        session.invalidate()
                        worker.execute { disposeMic() }
                    }
                }
            }
        } }
        worker.execute {
            try {
                disposeMic()
                if(!session.current(ticket) || closed) return@execute
                status("正在准备离线语音模型")
                if(model == null) model = Model(unpack().absolutePath)
                if(!session.current(ticket) || closed) return@execute
                val rec = Recognizer(model, 16000f); recognizer = rec
                val speech = SpeechService(rec, 16000f); service = speech
                val listener = object: RecognitionListener {
                    private fun deliver(value: String?, final: Boolean) {
                        val text = try { JSONObject(value ?: "{}").optString(if(final) "text" else "partial") } catch (_: Exception) { return }
                        main.post {
                            if(!closed) session.update(ticket, text, final)?.let { if(it.isNotEmpty()) onText(it) }
                        }
                    }
                    override fun onPartialResult(hypothesis: String?) { deliver(hypothesis, false) }
                    override fun onResult(hypothesis: String?) { deliver(hypothesis, true) }
                    override fun onFinalResult(hypothesis: String?) { deliver(hypothesis, true); finish("录音已结束") }
                    override fun onError(exception: Exception?) { finish("语音识别失败，请检查麦克风权限") }
                    override fun onTimeout() { finish("录音已超时") }
                }
                if(!speech.startListening(listener)) { disposeMic(); finish("麦克风启动失败") } else status("正在离线聆听")
            } catch (_: Exception) { disposeMic(); finish("离线语音不可用，请检查模型和麦克风权限") }
        }
    }
    private fun unpack(): File = synchronized(OfflineSpeech::class.java) {
        val target = File(context.filesDir, "vosk-cn-0.22")
        if(File(target, "am/final.mdl").isFile && File(target, ".ready").isFile) return@synchronized target
        val temp = File(context.filesDir, "vosk-unpack-${java.util.UUID.randomUUID()}").apply { mkdirs() }
        try {
            var total = 0L
            ZipInputStream(context.assets.open("model.zip")).use { zip ->
                while(true) {
                    val entry = zip.nextEntry ?: break
                    val output = ArchivePaths.destination(temp, entry.name) ?: continue
                    if(entry.isDirectory) output.mkdirs() else {
                        output.parentFile?.mkdirs()
                        output.outputStream().use { out -> val buffer = ByteArray(8192); while(true) { val n = zip.read(buffer); if(n < 0) break; total += n; require(total <= 512L * 1024 * 1024); out.write(buffer, 0, n) } }
                    }
                }
            }
            require(File(temp, "am/final.mdl").isFile && File(temp,"conf/model.conf").isFile)
            File(temp, ".ready").writeText("0.22")
            target.deleteRecursively(); check(temp.renameTo(target)); target
        } finally { temp.deleteRecursively() }
    }
    private fun disposeMic() {
        val oldService = service; val oldRecognizer = recognizer
        service = null; recognizer = null
        try { oldService?.stop() } finally {
            try { oldService?.shutdown() } finally { oldRecognizer?.close() }
        }
    }
    @Synchronized fun stop() {
        if(!closed) { session.invalidate(); worker.execute { disposeMic() } }
    }
    @Synchronized override fun close() {
        if(!closed) {
            closed = true; session.invalidate()
            worker.execute { try { disposeMic() } finally { model?.close(); model = null } }
            worker.shutdown()
        }
    }
}
