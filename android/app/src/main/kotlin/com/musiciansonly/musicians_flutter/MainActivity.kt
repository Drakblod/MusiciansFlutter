package com.musiciansonly.musicians_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle

class MainActivity: FlutterActivity() {
    private val soundChannelsV2 = listOf(
        Triple("gig_request_channel_v2", "Gig Requests", "notification_gig_request_v2"),
        Triple("gig_response_channel_v2", "Gig Responses", "notification_gig_response_v2"),
        Triple("rsvp_reminder_channel_v2", "RSVP Reminders", "notification_event_rsvp_v2"),
        Triple("finalized_gig_channel_v2", "Finalized Gigs", "notification_gig_confirmed_v2"),
        Triple("chat_notifications_v2", "Band Section Messages", null)
    )
    private var soundProfile: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "musicians/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "clearDelivered" -> {
                        getSystemService(NotificationManager::class.java).cancelAll()
                        result.success(null)
                    }
                    "getSoundProfile" -> result.success(soundProfile)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        val resourcesReady = soundChannelsV2.all { (_, _, sound) ->
            sound == null || resources.getIdentifier(sound, "raw", packageName) != 0
        }
        val channelsReady = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            soundChannelsV2.all { (id, _, _) ->
                getSystemService(NotificationManager::class.java).getNotificationChannel(id) != null
            }
        if (resourcesReady && channelsReady) soundProfile = "android-v2"
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager: NotificationManager =
                getSystemService(NOTIFICATION_SERVICE) as NotificationManager

            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            fun registerChannel(channelId: String, name: String, descriptionText: String, rawSoundName: String?) {
                val soundUri = if (rawSoundName == null) {
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                } else {
                    Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/raw/" + rawSoundName)
                }
                val channel = NotificationChannel(channelId, name, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = descriptionText
                    setSound(soundUri, audioAttributes)
                }
                notificationManager.createNotificationChannel(channel)
            }

            // Existing channel (backward compatibility)
            registerChannel(
                "event_notifications",
                "Event Invites",
                "Notifications for new events and band updates",
                "guitarsound"
            )

            // 1. Gig Requests (New substitute / musician request broadcasts)
            registerChannel(
                "gig_request_channel",
                "Gig Requests",
                "Notifications for new gig and substitute requests",
                "gig_rquest"
            )

            // 2. Gig Responses & Applications
            registerChannel(
                "gig_response_channel",
                "Gig Responses",
                "Notifications for gig applications and responses",
                "gig_rquest_response"
            )

            // 3. RSVP Reminders
            registerChannel(
                "rsvp_reminder_channel",
                "RSVP Reminders",
                "Reminders to RSVP for upcoming events",
                "reminder_rsvp"
            )

            // 4. Finalized Gigs
            registerChannel(
                "finalized_gig_channel",
                "Finalized Gigs",
                "Notifications when gigs and substitute spots are finalized",
                "finalized_gig"
            )

            soundChannelsV2.forEach { (id, name, sound) ->
                registerChannel(id, name, name, sound)
            }
        }
    }
}
