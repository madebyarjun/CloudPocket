package com.cloudpocket.app.cloud_pocket

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BackgroundWatchdogReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_WATCHDOG_PING = "com.cloudpocket.app.ACTION_WATCHDOG_PING"
        private const val REQUEST_CODE = 4401
        private const val WATCHDOG_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes

        fun isWatchdogScheduled(context: Context): Boolean {
            val intent = Intent(context, BackgroundWatchdogReceiver::class.java).apply {
                action = ACTION_WATCHDOG_PING
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_NO_CREATE
            }
            return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags) != null
        }

        fun scheduleWatchdog(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, BackgroundWatchdogReceiver::class.java).apply {
                action = ACTION_WATCHDOG_PING
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
            val triggerAtMs = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
                    } else {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
                }
            } catch (e: Exception) {
                Log.w("CloudPocketWatchdog", "Failed to schedule exact watchdog alarm: ${e.message}")
            }
        }

        fun cancelWatchdog(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, BackgroundWatchdogReceiver::class.java).apply {
                action = ACTION_WATCHDOG_PING
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_NO_CREATE
            }
            val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return

        // Read keepRunning preference from Flutter SharedPreferences
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val keepRunning = prefs.getBoolean("flutter.cp_setting_keep_running", true)

        if (!keepRunning) {
            cancelWatchdog(context)
            return
        }

        // Reschedule next 5-min watchdog cycle
        scheduleWatchdog(context)

        // Reschedule foreground service if terminated while Keep Running is enabled
        try {
            if (!com.pravera.flutter_foreground_task.service.ForegroundService.isRunningServiceState.value) {
                Log.i("CloudPocketWatchdog", "Watchdog triggered on action $action; service will be maintained by foreground task manager")
            }
        } catch (_: Exception) {}
    }
}
