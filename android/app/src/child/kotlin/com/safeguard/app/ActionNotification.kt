package com.safeguard.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

private const val ACTION_CHANNEL = "approved_requests"

internal fun requireVisibleActionNotifications(context: Context): NotificationManager {
    val manager = requireNotNull(context.getSystemService(NotificationManager::class.java))
    check(manager.areNotificationsEnabled()) { "Enable SafeGuard notifications first." }
    if (Build.VERSION.SDK_INT >= 26) {
        manager.createNotificationChannel(
            NotificationChannel(ACTION_CHANNEL, "Approved requests", NotificationManager.IMPORTANCE_DEFAULT)
        )
        check(manager.getNotificationChannel(ACTION_CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE) {
            "Enable Approved requests in Android notification settings."
        }
    }
    return manager
}

internal fun showActionNotification(context: Context, title: String, text: String) {
    val manager = requireVisibleActionNotifications(context)
    val builder = if (Build.VERSION.SDK_INT >= 26) {
        Notification.Builder(context, ACTION_CHANNEL)
    } else {
        @Suppress("DEPRECATION")
        Notification.Builder(context)
    }
    val openApp = PendingIntent.getActivity(
        context,
        111,
        Intent(context, ChildActivity::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
    manager.notify(
        System.nanoTime().toInt(),
        builder.setContentTitle("RDX SafeGuard · " + title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .build()
    )
}
