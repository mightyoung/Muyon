package com.mightyoung.muyon.androidlab

import android.app.Application
import android.os.Handler
import android.os.Looper

/** Process ownership is intentional: UI recreation must not release or replace a blocked native slot. */
class MuyonLabApplication : Application() {
    val diagnostics: RustDiagnosticCoordinator by lazy {
        val main = Handler(Looper.getMainLooper())
        createRustDiagnosticCoordinator(GeneratedDiagnosticPort(BuildConfig.MUYON_BRIDGE_PROTOCOL.toUInt(), BuildConfig.MUYON_BRIDGE_SOURCE_SHA)) { deliver ->
            if (Looper.myLooper() == Looper.getMainLooper()) deliver() else main.post { deliver() }
        }
    }
}
