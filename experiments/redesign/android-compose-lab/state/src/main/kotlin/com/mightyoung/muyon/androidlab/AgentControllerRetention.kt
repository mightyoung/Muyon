package com.mightyoung.muyon.androidlab

/** The flag reports completed local handle cleanup after actual Rust Closed, never a guess. */
interface AgentRetainedLifetime:AgentControllerLifetime { val cleanupComplete:Boolean }

/** One process-root slot, reserved before construction and released only on proven cleanup. */
class AgentControllerRetention {
    class Reservation internal constructor()
    private val lock=Any()
    private var slot:Reservation?=null
    private var value:AgentRetainedLifetime?=null
    fun reserve():Reservation?=synchronized(lock) {
        if(slot!=null)null else Reservation().also{slot=it}
    }
    fun publish(reservation:Reservation,value:AgentRetainedLifetime):Boolean=synchronized(lock) {
        if(slot!==reservation || this.value!=null)false else {this.value=value;true}
    }
    fun retained():AgentRetainedLifetime?=synchronized(lock){value}
    fun failedBeforePublish(reservation:Reservation):Boolean=synchronized(lock) {
        if(slot!==reservation || value!=null)false else {slot=null;true}
    }
    fun releaseCleaned(reservation:Reservation,value:AgentRetainedLifetime):Boolean=synchronized(lock) {
        if(slot!==reservation || this.value!==value || !value.cleanupComplete)false
        else {this.value=null;slot=null;true}
    }
}

/** All generated calls enter here. Sealed cleanup is attempted once, outside the lock. */
class AgentHandleAdmission(private val onDrained:()->Unit={}) {
    private val lock=Any()
    private var active=0
    private var sealed=false
    private var attempted=false
    private var cleaned=false
    private var drainSignalled=false
    val cleanupComplete:Boolean get()=synchronized(lock){cleaned}
    fun <T> call(work:()->T):T {
        synchronized(lock){check(!sealed){"handle_unavailable"};active++}
        try{return work()}finally{
            val notify=synchronized(lock){
                active--
                if(active==0 && sealed && !attempted && !drainSignalled){drainSignalled=true;true}else false
            }
            // Only notify the existing background owner; never free a handle on this caller.
            if(notify)onDrained()
        }
    }
    fun disposeIfIdle(actualClosed:Boolean,requested:Boolean,cleanup:()->Unit):Boolean {
        synchronized(lock){
            if(cleaned)return true
            if(!actualClosed || !requested)return false
            sealed=true
            if(active!=0 || attempted)return false
            attempted=true // Failure permanently latches admission closed and cleanup incomplete.
        }
        cleanup()
        synchronized(lock){cleaned=true}
        return true
    }
}
