package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.ServiceOwnerCredentialCapability
import java.util.UUID

/** Agent-process memory only. Never stringify, save state, persist, log or transport this store. */
internal class OrdinaryChatTemporaryCredential {
    private var key:CharArray?=null
    private var capability:ServiceOwnerCredentialCapability?=null
    class Prepared internal constructor(internal val expected:ServiceOwnerCredentialCapability?,val capability:ServiceOwnerCredentialCapability,internal val value:CharArray) {
        internal var committed=false
        fun discard(){if(!committed)value.fill('\u0000')}
    }
    @Synchronized fun prepare(input:CharArray):Prepared {
        require(input.size in 16..512 && input.all { it.code in 33..126 })
        val generation=Math.addExact(capability?.generation?.toLong() ?: 0L,1L)
        return Prepared(capability,ServiceOwnerCredentialCapability(UUID.randomUUID().toString(),generation.toULong()),input.copyOf())
    }
    @Synchronized fun commit(prepared:Prepared) {
        check(!prepared.committed && prepared.expected==capability)
        key?.fill('\u0000');key=prepared.value;capability=prepared.capability;prepared.committed=true
    }
    @Synchronized fun install(input:CharArray):ServiceOwnerCredentialCapability {
        val prepared=prepare(input)
        return try{commit(prepared);prepared.capability}finally{prepared.discard()}
    }
    @Synchronized fun current()=capability
    fun <T> withCopy(expected:ServiceOwnerCredentialCapability,block:(CharArray)->T):T {
        val copy=synchronized(this){check(capability==expected);checkNotNull(key).copyOf()}
        return try {block(copy)} finally {copy.fill('\u0000')}
    }
    @Synchronized fun clear(){key?.fill('\u0000');key=null;capability=null}
}
