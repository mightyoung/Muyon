package com.mightyoung.muyon.androidlab

/** The flag reports completed local handle cleanup after actual Rust Closed, never a guess. */
interface AgentRetainedLifetime:AgentControllerLifetime { val cleanupComplete:Boolean }

/** Bounded process-root ownership seam. Refusing baseline for remote TDD; not app-wired. */
class AgentControllerRetention {
    class Reservation internal constructor()
    fun reserve():Reservation?=Reservation()
    fun publish(reservation:Reservation,value:AgentRetainedLifetime):Boolean=true
    fun retained():AgentRetainedLifetime?=null
    fun failedBeforePublish(reservation:Reservation):Boolean=false
    fun releaseCleaned(reservation:Reservation,value:AgentRetainedLifetime):Boolean=false
}


/** Refusing baseline: actual wrapper admission/disposal sealing is implemented after RED. */
class AgentHandleAdmission(private val onDrained:()->Unit={}) {
    val cleanupComplete:Boolean get()=false
    fun <T> call(work:()->T):T=work()
    fun disposeIfIdle(actualClosed:Boolean,requested:Boolean,cleanup:()->Unit):Boolean {
        if(actualClosed && requested)cleanup()
        return false
    }
}
