package com.streetscan.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		createDefaultNotificationChannel()
	}

	private fun createDefaultNotificationChannel() {
		// The channel id is defined in res/values/strings.xml as "default_notification_channel_id"
		val channelId = getString(com.streetscan.app.R.string.default_notification_channel_id)
		val channelName = getString(com.streetscan.app.R.string.app_name)

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val importance = NotificationManager.IMPORTANCE_DEFAULT
			val channel = NotificationChannel(channelId, channelName, importance).apply {
				description = "Default channel for app notifications"
			}
			val notificationManager: NotificationManager =
				ContextCompat.getSystemService(this, NotificationManager::class.java) as NotificationManager
			notificationManager.createNotificationChannel(channel)
		}
	}
}
