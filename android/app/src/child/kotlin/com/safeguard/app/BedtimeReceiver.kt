package com.safeguard.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar

class BedtimeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val schedule = BedtimeSchedule(context)
        try {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED,
                Intent.ACTION_MY_PACKAGE_REPLACED -> schedule.reschedule()
                BedtimeSchedule.ACTION_BEDTIME -> schedule.onAlarm()
            }
        } catch (failure: RuntimeException) {
            Log.w("RDXBedtime", "Could not process the bedtime schedule", failure)
        }
    }
}

internal class BedtimeSchedule(private val context: Context) {
    companion object {
        const val ACTION_BEDTIME = "com.safeguard.app.child.BEDTIME_LOCK"
        private const val MINUTES = "minutes"
        private const val EXPECTED = "expected"
        private const val MAX_DELAY_MILLIS = 60 * 60 * 1000L

        internal fun nextTime(minutes: Int, now: Long): Long =
            Calendar.getInstance().apply {
                timeInMillis = now
                set(Calendar.HOUR_OF_DAY, minutes / 60)
                set(Calendar.MINUTE, minutes % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= now) add(Calendar.DAY_OF_YEAR, 1)
            }.timeInMillis
    }

    private val settings = context.getSharedPreferences("bedtime", Context.MODE_PRIVATE)
    private val alarm get() = requireNotNull(context.getSystemService(AlarmManager::class.java))
    private val policy get() = requireNotNull(context.getSystemService(DevicePolicyManager::class.java))
    private val admin get() = ComponentName(context, SafeGuardAdminReceiver::class.java)
    private val operation get() = PendingIntent.getBroadcast(
        context,
        110,
        Intent(context, BedtimeReceiver::class.java).setAction(ACTION_BEDTIME),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun configuredMinutes(): Int? = settings.getInt(MINUTES, -1).takeIf { it in 0..1439 }

    fun enable(minutes: Int) {
        require(minutes in 0..1439) { "Choose a valid time." }
        check(policy.isAdminActive(admin)) { "Enable Device Admin for screen locking first." }
        requireVisibleActionNotifications(context)
        val next = nextTime(minutes, System.currentTimeMillis())
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, operation)
        if (!settings.edit().putInt(MINUTES, minutes).putLong(EXPECTED, next).commit()) {
            alarm.cancel(operation)
            error("Could not save bedtime on this device.")
        }
    }

    fun disable() {
        check(settings.edit().remove(MINUTES).remove(EXPECTED).commit()) {
            "Could not disable bedtime on this device."
        }
        alarm.cancel(operation)
    }

    fun reschedule() {
        val minutes = configuredMinutes() ?: return
        val next = nextTime(minutes, System.currentTimeMillis())
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, operation)
        if (!settings.edit().putLong(EXPECTED, next).commit()) alarm.cancel(operation)
    }

    fun onAlarm() {
        if (configuredMinutes() == null) return
        val now = System.currentTimeMillis()
        val expected = settings.getLong(EXPECTED, 0)
        val isCurrent = expected > 0 && now - expected in 0..MAX_DELAY_MILLIS
        reschedule()
        if (!isCurrent || !policy.isAdminActive(admin)) return
        showActionNotification(context, "Bedtime screen lock", "Daily schedule set on this device.")
        policy.lockNow()
    }
}
