package com.torikdammam.buklin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.media.Ringtone
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

class MainActivity : FlutterActivity() {
    private var incomingTone: Ringtone? = null

    private fun stopAlert() {
        incomingTone?.stop()
        incomingTone = null
        @Suppress("DEPRECATION")
        val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
        vibrator.cancel()
    }

    override fun onDestroy() {
        stopAlert()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val pattern = longArrayOf(0, 400, 200, 400)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("buklin_work_v1", "Incoming work requests",
                NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Sound and vibration for new work while you are online"
                setSound(sound, audio)
                enableVibration(true)
                vibrationPattern = pattern
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "buklin/work_alerts")
            .setMethodCallHandler { call, result ->
                if (call.method == "stop") {
                    stopAlert()
                    result.success(null)
                } else if (call.method != "play") {
                    result.notImplemented()
                } else {
                    try {
                        incomingTone?.stop()
                        incomingTone = RingtoneManager.getRingtone(this, sound)?.apply {
                            audioAttributes = audio
                            play()
                        }
                        @Suppress("DEPRECATION")
                        val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1), audio)
                        } else {
                            @Suppress("DEPRECATION")
                            vibrator.vibrate(pattern, -1, audio)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("alert_failed", error.message, null)
                    }
                }
            }
    }
}
