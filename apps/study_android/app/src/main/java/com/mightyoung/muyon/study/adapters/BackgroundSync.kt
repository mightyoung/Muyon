package com.mightyoung.muyon.study.adapters

import android.app.job.*
import android.content.*
import com.google.android.gms.auth.api.identity.*
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Tasks
import com.mightyoung.muyon.study.*
import org.json.JSONObject
import java.util.concurrent.*

object BackgroundSync {
    fun enable(context:Context){
        context.getSharedPreferences("background_sync",0).edit().putBoolean("enabled",true).apply()
        context.getSystemService(JobScheduler::class.java).schedule(JobInfo.Builder(28001,ComponentName(context,StudySyncJob::class.java)).setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).setPeriodic(3600000).build())
    }
    fun disable(context:Context){context.getSharedPreferences("background_sync",0).edit().putBoolean("enabled",false).putBoolean("google",false).apply();context.getSystemService(JobScheduler::class.java).cancel(28001)}
    fun googleConnected(context:Context){context.getSharedPreferences("background_sync",0).edit().putBoolean("google",true).apply();enable(context)}
}
/** Read-only provider refresh. No calendar publication, AI calls or uncertain-write replay. */
class StudySyncJob:JobService(){
    private val worker=Executors.newSingleThreadExecutor()
    @Volatile private var stopped=false
    override fun onStartJob(params:JobParameters):Boolean{
        stopped=false
        worker.execute{
            val prefs=getSharedPreferences("background_sync",0)
            fun active()=!stopped&&prefs.getBoolean("enabled",false)
            fun call(c:JSONObject):JSONObject?{
                if(!active())return null
                val latch=CountDownLatch(1);var result:JSONObject?=null
                StudyRepository.get(this).request(c){v,_->result=v;latch.countDown()}
                return if(latch.await(30,TimeUnit.SECONDS))result else null
            }
            fun failure(provider:String){call(obj("op" to "sync_error","provider" to provider,"error" to "后台刷新未完成，请打开应用检查网络与授权"))}
            try{
                if(active()&&prefs.getBoolean("google",false))try{
                    val request=AuthorizationRequest.builder().setRequestedScopes(listOf(Scope("https://www.googleapis.com/auth/calendar.readonly"),Scope("https://www.googleapis.com/auth/drive.file"))).build()
                    val authorization=Tasks.await(Identity.getAuthorizationClient(this).authorize(request),30,TimeUnit.SECONDS)
                    if(authorization.hasResolution()||authorization.accessToken.isNullOrBlank())error("需要重新授权")
                    val now=System.currentTimeMillis();val events=Providers.calendar(authorization.accessToken!!,now-86400000,now+120L*86400000)
                    call(obj("op" to "calendar_sync","events" to events,"now" to now))
                }catch(_:Exception){failure("calendar")}
                if(active())try{val token=SecureKeys.get(this,"maimemo");if(token.isNotBlank())call(obj("op" to "maimemo_sync","progress" to Providers.maimemo(token),"now" to System.currentTimeMillis()))}catch(_:Exception){failure("maimemo")}
                val snapshot=call(obj("op" to "snapshot"));if(snapshot!=null&&snapshot.items("tasks").isNotEmpty())call(planningRequest(snapshot))
            }finally{jobFinished(params,false)}
        };return true
    }
    override fun onStopJob(params:JobParameters):Boolean{stopped=true;return true}
    override fun onDestroy(){stopped=true;worker.shutdown();super.onDestroy()}
}
