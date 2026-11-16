package com.badie.app.push

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import com.badie.app.MainActivity
import com.badie.app.R
import com.badie.app.features.games.ReminderService
import com.badie.app.l10n.L10n
import com.badie.app.l10n.L10n.tr
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** 推送的内容。服务器只发数据（FCM 的 data，都是文字）：title、body、可选的 link 和 chat（JSON），见 supabase/functions/send-push/payload.ts */
data class PushContent(val title: String, val body: String, val link: String?, val chat: ChatPush?) {
    /** 聊天里显示的那句话：群聊的推送正文是“昵称: 内容”，会话通知里每句前面已经有发消息的人，去掉重复的昵称 */
    val messageText: String
        get() {
            val name = chat?.name
            val prefix = "$name: "
            return if (chat?.group != null && name != null && body.startsWith(prefix)) body.removePrefix(prefix) else body
        }

    companion object {
        fun parse(data: Map<String, String>): PushContent? {
            val title = data["title"] ?: return null
            return PushContent(title, data["body"].orEmpty(), data["link"], data["chat"]?.let(ChatPush::parse))
        }
    }
}

/** 推送里的 chat：会话、发消息的人、头像的完整地址、群名（私信为空）、会话里一共几个人。对应 iPhone 通知扩展里的 ChatPush */
@Serializable
data class ChatPush(
    val thread: String,
    val sender: String,
    val name: String? = null,
    val avatar: String? = null,
    val group: String? = null,
    val members: Int? = null,
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(text: String): ChatPush? = try {
            json.decodeFromString(serializer(), text)
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}

/**
 * 显示推送。聊天显示成带头像的会话通知（MessagingStyle，同一会话的消息归在一条里），对应 iPhone 的 BadieNotificationService；
 * 别的按标题和正文显示。点了打开 MainActivity，交给 [NotificationRouter]
 */
object PushNotifier {
    private const val MESSAGES = "messages"
    private const val OTHER = "notifications"
    private const val CHAT_TAG = "chat"
    private const val AVATAR_PIXELS = 192
    private val ids = AtomicInteger((System.currentTimeMillis() / 1000).toInt())

    private val client by lazy { OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build() }

    /** 点通知打开 App：带着 link 或 gameId；App 开着时不重建界面（交给 onNewIntent） */
    fun openIntent(context: Context, requestCode: Int, link: String? = null, gameId: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        link?.let { intent.putExtra(NotificationRouter.EXTRA_LINK, it) }
        gameId?.let { intent.putExtra(NotificationRouter.EXTRA_GAME, it) }
        return PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** 不在主线程调：聊天要下载头像（最多等 10 秒，下载不了就不带头像） */
    @SuppressLint("NotificationPermission")
    fun show(context: Context, content: PushContent) {
        if (!ReminderService.canNotify(context)) return
        L10n.attachIfNeeded(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val chat = content.chat
        val channel = if (chat != null) MESSAGES else OTHER
        manager.createNotificationChannel(NotificationChannel(channel, tr(if (chat != null) "消息" else "通知"), NotificationManager.IMPORTANCE_HIGH))
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
        if (chat == null) {
            val id = ids.incrementAndGet()
            builder.setContentTitle(content.title)
                .setContentText(content.body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(content.body))
                .setContentIntent(openIntent(context, id, link = content.link))
            manager.notify(id, builder.build())
            return
        }
        // 同一会话一条通知：接着上一条往下加
        val id = chat.thread.hashCode()
        val previous = manager.activeNotifications.firstOrNull { it.tag == CHAT_TAG && it.id == id }?.notification
        val style = previous?.let { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it) }
            ?: NotificationCompat.MessagingStyle(Person.Builder().setName(tr("我")).build())
        val sender = Person.Builder()
            .setKey(chat.sender)
            .setName(chat.name ?: content.title)
            .setIcon(chat.avatar?.let(::downloadAvatar)?.let(IconCompat::createWithBitmap))
            .build()
        style.addMessage(content.messageText, System.currentTimeMillis(), sender)
        if (chat.group != null) {
            style.conversationTitle = chat.group
            style.isGroupConversation = true
        }
        builder.setStyle(style)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(openIntent(context, id, link = content.link))
        manager.notify(CHAT_TAG, id, builder.build())
    }

    private fun downloadAvatar(url: String): Bitmap? = try {
        client.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (response.code == 200) decodeAvatar(response.body.bytes()) else null
        }
    } catch (_: IOException) {
        null
    } catch (_: IllegalArgumentException) {
        // 地址不对
        null
    }

    /** 缩到 200 像素上下，通知里用不着原图 */
    internal fun decodeAvatar(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= AVATAR_PIXELS) sample *= 2
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }
}

/** 收 FCM 的推送和新令牌。要在 AndroidManifest.xml 里登记 */
class BadieMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        runBlocking(Dispatchers.Main) { PushRegistry.didRegister(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val content = PushContent.parse(message.data) ?: return
        val shows = runBlocking(Dispatchers.Main) { NotificationRouter.willPresent(content.link) }
        if (shows) PushNotifier.show(this, content)
    }
}
