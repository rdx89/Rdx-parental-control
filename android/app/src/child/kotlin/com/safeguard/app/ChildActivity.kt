package com.safeguard.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class ChildActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val admin by lazy { ComponentName(this, SafeGuardAdminReceiver::class.java) }
    private val policy by lazy { getSystemService(DevicePolicyManager::class.java) }
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safeguard/child")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "activateAdmin" -> {
                            if (!policy.isAdminActive(admin)) {
                                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                    .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                                startActivity(intent)
                            }
                            result.success(null)
                        }
                        "execute" -> {
                            val command = requireNotNull(call.argument<String>("command"))
                            execute(command, call.argument<String>("message"))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (failure: Exception) {
                    result.error("action_failed", failure.message ?: "Action failed.", null)
                }
            }
    }

    private fun execute(command: String, message: String?) {
        val label = when (command) {
            "lock" -> "Lock device"
            "vibrate" -> "Vibrate"
            "sound" -> "Play sound"
            "flashlight" -> "Flashlight"
            "message" -> "Parent message"
            else -> error("This request is unavailable.")
        }
        if (command == "lock") check(policy.isAdminActive(admin)) { "Enable Device Admin first." }
        showNotification(label, message ?: "Approved on this device.")
        when (command) {
            "lock" -> policy.lockNow()
            "vibrate" -> {
                val vibrator = getSystemService(Vibrator::class.java)
                check(vibrator.hasVibrator()) { "This device has no vibrator." }
                if (Build.VERSION.SDK_INT >= 26) {
                    vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(500)
                }
            }
            "sound" -> {
                val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 70)
                handler.postDelayed({ tone.release() }, 1200)
                check(tone.startTone(ToneGenerator.TONE_PROP_ACK, 800)) { "Cannot play a tone." }
            }
            "flashlight" -> {
                val camera = getSystemService(CameraManager::class.java)
                val torch = camera.cameraIdList.firstOrNull { id ->
                    camera.getCameraCharacteristics(id)
                        .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                } ?: error("This device has no flashlight.")
                camera.setTorchMode(torch, true)
                handler.postDelayed({
                    runCatching { camera.setTorchMode(torch, false) }
                }, 2000)
            }
        }
    }

    private fun showNotification(title: String, text: String) {
        check(notifications.areNotificationsEnabled()) { "Enable SafeGuard notifications first." }
        val channel = "approved_requests"
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(
                NotificationChannel(channel, "Approved requests", NotificationManager.IMPORTANCE_DEFAULT)
            )
            check(notifications.getNotificationChannel(channel).importance != NotificationManager.IMPORTANCE_NONE) {
                "Enable Approved requests in Android notification settings."
            }
            Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        notifications.notify(
            System.nanoTime().toInt(),
            builder.setContentTitle("SafeGuard · " + title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setAutoCancel(true)
                .build()
        )
    }
}
