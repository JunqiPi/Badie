package com.badie.app.e2e

import android.app.NotificationManager
import android.content.Context
import android.util.Log
import androidx.compose.ui.test.hasContentDescription
import androidx.core.app.NotificationCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 推送（FCM，要 GitHub Secrets 里有 FCM_SERVICE_ACCOUNT，本机的 send-push 才发得出去；没有就跳过）。
 * 账号固定用 push-a / push-b（带这一轮的编号）：e2e/run.sh 在两段之间要以 B 的身份发私信
 */
abstract class PushBase : E2ETest() {
    @Before
    fun requirePush() {
        if (!Harness.pushEnabled) Log.w(TAG, "没有配 FCM_SERVICE_ACCOUNT，跳过推送测试")
        assumeTrue("没有配 FCM_SERVICE_ACCOUNT，跳过推送测试", Harness.pushEnabled)
    }

    fun shownNotifications(): List<String> {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.activeNotifications.map { status ->
            val n = status.notification
            val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(n)
            (listOfNotNull(n.extras.getCharSequence("android.title"), n.extras.getCharSequence("android.text")) +
                style?.messages.orEmpty().map { it.text ?: "" }).joinToString(" | ")
        }
    }

    /** 下拉通知栏，点含有这句话的通知 */
    fun tapNotification(textInside: String, sender: String) {
        device.openNotification()
        val item = device.wait(Until.findObject(By.textContains(textInside)), 60_000)
            ?: throw AssertionError("通知栏里没有“$textInside”。App 发出的通知：${shownNotifications()}")
        check(device.hasObject(By.text(sender))) { "通知里没有发消息的人 $sender" }
        item.click()
    }
}

@RunWith(AndroidJUnit4::class)
class PushTest : PushBase() {
    @Test
    fun notificationsInBackgroundAndQuietInOpenChat() {
        val a = Harness.createPlayer("push-a", "Avery")
        val b = Harness.createPlayer("push-b", "Brooke")
        Harness.befriend(a, b)

        launch()
        signInWithPassword(a.email)

        // 设置 → 球局提醒 → 系统的通知权限框点“允许”：马上登记这台设备
        openTab("我的")
        tap(desc(t("设置")))
        tapText("球局提醒")
        val allow = device.wait(Until.findObject(By.res("com.android.permissioncontroller:id/permission_allow_button")), 15_000)
            ?: throw AssertionError("没有弹出通知权限框")
        allow.click()
        waitFor(text(t("已开启")), what = "球局提醒：已开启")
        Harness.eventually("A 的设备登记成 fcm", 60_000) { Harness.pushDevices(a.id).any { it["kind"]?.jsonPrimitive?.content == "fcm" } }

        // 回到桌面，B 发私信：通知栏里有 B 的名字和这句话，点开就是和 B 的聊天
        pressHome()
        val ping = "Ping from Brooke ${Harness.run}"
        Harness.sendDm(b, a, ping)
        tapNotification(ping, "Brooke")
        waitFor(hasContentDescription(t("发消息…")), 30_000, "聊天的输入框")
        waitFor(text(ping), what = "聊天里的那条消息")
        waitFor(text("Brooke"), what = "聊天页顶上的对方名字")

        // 开着和 B 的聊天：B 再发，不弹通知，消息直接出现
        val quiet = "Quiet one ${Harness.run}"
        Harness.sendDm(b, a, quiet)
        waitFor(text(quiet), 40_000, "开着的聊天里的新消息")
        Thread.sleep(5_000)
        val shown = shownNotifications()
        check(shown.none { quiet in it }) { "开着这个聊天时不该弹通知：$shown" }
    }
}

/**
 * App 被杀掉以后（e2e/run.sh 打开 App、回桌面、杀进程，再以 B 的身份发 “Killed …”）：通知照样到，点开进聊天。
 * 最后退出登录，服务器上这台设备的登记要删掉
 */
@RunWith(AndroidJUnit4::class)
class PushKilledTest : PushBase() {
    @Test
    fun notificationAfterProcessKilledOpensChat() {
        val text = "Killed ${Harness.run}"
        tapNotification(text, "Brooke")
        waitFor(hasContentDescription(t("发消息…")), 40_000, "聊天的输入框")
        waitFor(text(text), what = "聊天里的那条消息")

        val a = Harness.userId(Harness.email("push-a"))!!
        check(Harness.pushDevices(a).isNotEmpty()) { "退出前应该有设备登记" }
        signOut()
        Harness.eventually("退出登录后删掉设备登记") { Harness.pushDevices(a).isEmpty() }
    }
}
