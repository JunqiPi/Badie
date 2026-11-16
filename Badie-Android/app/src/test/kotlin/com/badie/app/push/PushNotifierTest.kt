package com.badie.app.push

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import androidx.core.app.NotificationCompat
import com.badie.app.l10n.L10n
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayOutputStream

/** 推送怎么显示：聊天是带发消息的人的会话通知，同一会话归在一条里；别的按标题和正文。跑在 Robolectric 上 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class PushNotifierTest {
    private val app: Application get() = RuntimeEnvironment.getApplication()
    private val manager get() = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @Before
    fun setUp() {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    @After
    fun tearDown() {
        L10n.detach()
    }

    private fun chat(body: String, name: String, group: String? = null) = PushContent(
        title = group ?: name, body = if (group != null) "$name: $body" else body, link = "/messages/group/p-1/",
        chat = ChatPush(thread = "group:p-1", sender = "u-$name", name = name, group = group, members = 6),
    )

    @Test
    fun chatMessagesStackInOneConversation() {
        PushNotifier.show(app, chat("我带球", "Sam", group = "周六球局"))
        PushNotifier.show(app, chat("我晚 10 分钟", "Lee", group = "周六球局"))
        val shown = manager.activeNotifications.filter { it.tag == "chat" }
        assertEquals(1, shown.size)
        val notification = shown.single().notification
        assertEquals("messages", notification.channelId)
        val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(notification)!!
        assertEquals(listOf("我带球", "我晚 10 分钟"), style.messages.map { it.text.toString() })
        assertEquals(listOf("Sam", "Lee"), style.messages.map { it.person?.name.toString() })
        assertEquals("周六球局", style.conversationTitle)
        assertTrue(style.isGroupConversation)
        assertEquals("没有界面时也用 App 的文字表（测试里系统语言是英文）", "Messages", manager.getNotificationChannel("messages").name)
    }

    @Test
    fun otherPushesShowTitleAndBodyAndOpenTheLink() {
        PushNotifier.show(app, PushContent("配上了", "周六 10:00 · LABC", "/app/games/g-1/", null))
        val notification = manager.activeNotifications.single().notification
        assertEquals("notifications", notification.channelId)
        assertEquals("配上了", notification.extras.getString(NotificationCompat.EXTRA_TITLE))
        val intent = shadowOf(notification.contentIntent).savedIntent
        assertEquals("/app/games/g-1/", intent.getStringExtra(NotificationRouter.EXTRA_LINK))
    }

    @Test
    fun nothingShownWithoutPermission() {
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        PushNotifier.show(app, PushContent("配上了", "x", null, null))
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test
    fun avatarIsScaledDown() {
        val photo = Bitmap.createBitmap(1024, 768, Bitmap.Config.ARGB_8888)
        val bytes = ByteArrayOutputStream().also { photo.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        val avatar = PushNotifier.decodeAvatar(bytes)
        assertNotNull(avatar)
        assertTrue(avatar!!.width in 192..383)
        assertNull("不是图片", PushNotifier.decodeAvatar("oops".toByteArray()))
    }
}
