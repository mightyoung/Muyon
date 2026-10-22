package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import android.os.Process
import android.system.Os
import android.system.OsConstants
import java.io.File

/** Fixed trusted round only. Never a UI/IPC path, epoch-derived directory or recovery reset. */
internal object OrdinaryChatAuthorizedSession {
    const val ROOT_NAME="agent-service-authorized-followup-20261020"
    fun allowed(context:Context,live:OrdinaryChatLiveInstallation):Boolean {
        check(live.budget.batchIdentity=="muyon-ordinary-chat-20261020-authorized-followup")
        val snapshot=live.budget.snapshot() // Validates pinned prior ledger and one-time grant under parent lock.
        check(!snapshot.stopped){"authorized_round_stopped"}
        validateExisting(context.filesDir,snapshot.attempts>0)
        return true
    }
    /** Once admitted, neither namespace nor index may be recreated by the native constructor. */
    fun validateExisting(filesParent:File,hasAttempt:Boolean) {
        if(!hasAttempt)return
        val parent=filesParent.canonicalFile
        val root=File(parent,ROOT_NAME)
        fun validate(file:File,directory:Boolean) {
            val stat=Os.lstat(file.path)
            check(file.canonicalFile==file && stat.st_uid==Process.myUid())
            check((stat.st_mode and OsConstants.S_IFMT)==if(directory)OsConstants.S_IFDIR else OsConstants.S_IFREG)
            check((stat.st_mode and 4095)==if(directory)448 else 384)
        }
        validate(root,true)
        val namespace=File(root,"native-agent-service-v1");validate(namespace,true)
        validate(File(namespace,"index.db"),false)
    }
}
