package com.musiciansonly.musicians_flutter

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager: NotificationManager =
                getSystemService(NOTIFICATION_SERVICE) as NotificationManager

            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            fun registerChannel(channelId: String, name: String, descriptionText: String, rawSoundName: String) {
                val soundUri = Uri.parse(
                    ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/raw/" + rawSoundName
                )
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
        }
    }
}
