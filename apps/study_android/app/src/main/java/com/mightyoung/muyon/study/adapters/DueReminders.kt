package com.mightyoung.muyon.study.adapters

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import org.json.*

object DueReminders {
    private const val PREF = "due_reminders"
    private const val CHANNEL = "study_deadlines"
    private fun pending(context: Context, id: String) = PendingIntent.getBroadcast(context, 0, Intent(context, DueReceiver::class.java).setData(Uri.parse("study://due/${Uri.encode(id)}")).putExtra("id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun active(task: JSONObject) = task.optString("status") != "done" && !task.optBoolean("deleted")
    @Synchronized fun reconcile(context: Context, tasks: JSONArray): String {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val alarm = context.getSystemService(AlarmManager::class.java)
        val old = try { JSONArray(prefs.getString("tasks", "[]")) } catch (_: Exception) { JSONArray() }
        val notifications = context.getSystemService(NotificationManager::class.java)
        for(i in 0 until old.length()) { val id = old.getJSONObject(i).optString("id"); alarm.cancel(pending(context, id)); notifications.cancel(id, 0) }
        if(!prefs.edit().putString("tasks", tasks.toString()).commit()) return "提醒保存失败"
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "任务截止提醒", NotificationManager.IMPORTANCE_DEFAULT))
        if(Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return "提醒已保存；请授予通知权限后重新同步提醒"
        if(!notifications.areNotificationsEnabled()) return "提醒已保存；系统通知已关闭"
        var count = 0; var approximate = false
        for(i in 0 until tasks.length()) {
            val task = tasks.getJSONObject(i); val deadline = task.optLong("due")
            if(!active(task) || deadline <= System.currentTimeMillis() || task.optString("id").isBlank()) continue
            val intent = pending(context, task.getString("id"))
            try {
                if(Build.VERSION.SDK_INT >= 31 && !alarm.canScheduleExactAlarms()) { alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, intent); approximate = true }
                else alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, intent)
            } catch (_: SecurityException) { try { alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, intent); approximate = true } catch (_: Exception) { return "系统拒绝安排提醒，请检查权限" } }
            count++
        }
        return "已安排 $count 条截止提醒" + if(approximate) "（系统未允许精确闹钟，可能延迟）" else ""
    }
    internal fun deliver(context: Context, id: String) {
        val tasks = try { JSONArray(context.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("tasks", "[]")) } catch (_: Exception) { return }
        val task = (0 until tasks.length()).map { tasks.getJSONObject(it) }.find { it.optString("id") == id } ?: return
        if(!active(task) || task.optLong("due") > System.currentTimeMillis() || task.optLong("due") <= 0) return
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val content = launch?.let { PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val notification = Notification.Builder(context, CHANNEL).setSmallIcon(com.mightyoung.muyon.study.R.drawable.gpt_reminder).setContentTitle("任务已到截止时间").setContentText(task.optString("title", "学习任务")).setAutoCancel(true).setContentIntent(content).build()
        try { context.getSystemService(NotificationManager::class.java).notify(id, 0, notification) } catch (_: SecurityException) { }
    }
    internal fun restore(context: Context) { val tasks = try { JSONArray(context.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("tasks", "[]")) } catch (_: Exception) { return }; reconcile(context, tasks) }
}
class DueReceiver : BroadcastReceiver() { override fun onReceive(context: Context, intent: Intent) { intent.getStringExtra("id")?.let { DueReminders.deliver(context, it) } } }
class RestoreRemindersReceiver : BroadcastReceiver() { override fun onReceive(context: Context, intent: Intent) { if(intent.action in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)) DueReminders.restore(context) } }
