package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import android.os.Process
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import com.mightyoung.muyon.androidbridge.*
import java.io.File

/** One trusted in-process authority per dedicated ledger; no UI or Binder installation surface. */
internal class ServiceAdmissionProcessOwner(private val authority:ServiceAdmissionAuthority) {
    private var owner:DurableServiceHostOwner?=null
    private var ledgerPath:String?=null
    @Synchronized fun acquire(context:Context,budget:ServiceOwnerCallBudget,
        onReady:(GeneratedAgentController)->Unit={},onCleaned:()->Unit={}):ServiceHostLease {
        check(owner==null){"admission_owner_retained"}
        val file=File(privateAdmissionRoot(context),DurableServiceHostOwner.DATABASE_NAME)
        check(ledgerPath==null || ledgerPath==file.absolutePath){"admission_owner_path_changed"}
        ledgerPath=file.absolutePath
        val value=DurableServiceHostOwner(file,authority)
        owner=value
        return ServiceHostLease(ServiceHostBinding.Installed(value,ServiceOwnerMode.CONFIGURED_CHAT,budget),release={
            synchronized(this){check(owner===value);value.close();owner=null}
        },onReady=onReady,onCleaned=onCleaned)
    }
    companion object {
        /** Production configuration has no approval/provider/credential facts. */
        fun unconfigured()=ServiceAdmissionProcessOwner(ServiceAdmissionAuthority(
            ServiceAdmissionAuthority.State(null,null,{_,_->false},{_,_,_->null})))
    }
}

/** Actual Service Context only; never repairs/replaces existing entries or follows a symlink. */
internal fun privateAdmissionRoot(context:Context):File {
    val parent=context.filesDir.canonicalFile
    val expected=File(parent,"agent-admission-root")
    val stat=try{Os.lstat(expected.absolutePath)}catch(error:ErrnoException){
        if(error.errno!=OsConstants.ENOENT)throw error
        try{Os.mkdir(expected.absolutePath,448)}catch(race:ErrnoException){if(race.errno!=OsConstants.EEXIST)throw race}
        Os.lstat(expected.absolutePath)
    }
    check((stat.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFDIR &&
        (stat.st_mode and 4095)==448 && stat.st_uid==Process.myUid()){"admission_root_unavailable"}
    val root=expected.canonicalFile
    check(root==expected && root.parentFile==parent){"admission_root_unavailable"}
    // Reject existing symlink/non-private database/lock/sidecar files before SQLite opens any.
    root.listFiles()?.forEach { file ->
        val entry=Os.lstat(file.absolutePath)
        check((entry.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFREG && entry.st_uid==Process.myUid() &&
            (entry.st_mode and 63)==0 && file.canonicalFile==file){"admission_entry_unavailable"}
    }
    return root
}
