package com.bunny.afa.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM trigger receiver — lets EXTERNAL AI agents (ChatGPT Custom Actions,
 * Make/Zapier webhooks → FCM) fire saved skills on this device.
 *
 * Message contract:
 *   data.skillId   → skill to run (replays via accessibility engine)
 *   data.prompt    → ad-hoc prompt to send to the overlay assistant
 */
class FcmTriggerService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val skillId = message.data["skillId"]
        val prompt = message.data["prompt"]

        val intent = android.content.Intent("com.bunny.afa.FCM_TRIGGER").apply {
            setPackage(packageName)
            putExtra("skillId", skillId)
            putExtra("prompt", prompt)
        }
        sendBroadcast(intent)
    }

    override fun onNewToken(token: String) {
        // Persist device token (needed so your server / Custom GPT can address
        // this device). Store it locally + sync to your licensing backend.
        super.onNewToken(token)
    }
}
