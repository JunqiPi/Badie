package com.badie.app.features.games

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import com.badie.app.MainActivity
import com.badie.app.R
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Game

/**
 * 球局本地提醒：开赛前 1 天、2 小时、15 分钟（多次提醒能显著降低爽约率）。对应 iPhone 的 Services/ReminderService.swift。
 * 用不精确的闹钟（AlarmManager.set，不要精确闹钟权限），到点由 [GameReminderReceiver] 发通知。
 *
 * 通知权限和 [GameReminderReceiver] 登记在 AndroidManifest.xml。手机重启后闹钟会丢（要 RECEIVE_BOOT_COMPLETED 再排一次），iPhone 没有这个问题
 */
object ReminderService {
    private class Offset(val id: String, val millis: Long, val titleKey: String)

    private val offsets = listOf(
        Offset("1d", 24 * 3_600_000L, "明天有球局"),
        Offset("2h", 2 * 3_600_000L, "2 小时后开打"),
        Offset("15m", 15 * 60_000L, "快到了，记得签到"),
    )

    /** 提醒的时间点（开赛前 1 天、2 小时、15 分钟里还没过的），测试用 */
    fun fireTimes(game: Game, now: Long): List<Long> =
        offsets.map { game.slot.startTime - it.millis }.filter { it - now > 5_000 }

    private const val CHANNEL = "game_reminders"
    private const val PREFS = "game_reminders"
    private const val SCHEDULED = "scheduled"

    /** 能不能发通知：Android 13 起要用户同意，也可能在系统设置里关了 */
    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    }

    /** 为球局安排提醒，返回实际安排的条数（不能发通知时是 0） */
    fun schedule(context: Context, game: Game, now: Long = System.currentTimeMillis()): Int {
        if (!canNotify(context)) return 0
        cancel(context, game.id)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        var count = 0
        val body = "${game.slot.formattedFull(now)} · ${game.court.name}"
        for (offset in offsets) {
            val fireAt = game.slot.startTime - offset.millis
            if (fireAt - now <= 5_000) continue
            alarms.set(AlarmManager.RTC_WAKEUP, fireAt, pending(context, game.id, offset.id, tr(offset.titleKey), body))
            count += 1
        }
        if (count > 0) remember(context, game.id, true)
        return count
    }

    /** 开始时间变了（没定时间的球局定好了）：之前开着提醒的按新时间重排；没开过的不动 */
    fun rescheduleIfPending(context: Context, game: Game) {
        if (game.id in scheduled(context)) schedule(context, game)
    }

    fun cancel(context: Context, gameId: String) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (offset in offsets) alarms.cancel(pending(context, gameId, offset.id, "", ""))
        remember(context, gameId, false)
    }

    private fun pending(context: Context, gameId: String, suffix: String, title: String, body: String): PendingIntent {
        val intent = Intent(context, GameReminderReceiver::class.java)
            .setAction("com.badie.app.GAME_REMINDER")
            .setData("badie-reminder://game/$gameId/$suffix".toUri())
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body)
            .putExtra(EXTRA_GAME, gameId)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun scheduled(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(SCHEDULED, emptySet()).orEmpty()

    private fun remember(context: Context, gameId: String, on: Boolean) {
        val ids = scheduled(context).toMutableSet()
        if (if (on) ids.add(gameId) else ids.remove(gameId)) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { putStringSet(SCHEDULED, ids) }
        }
    }

    /** 到点发一条通知；点开进 App。发之前查过 canNotify */
    @SuppressLint("NotificationPermission")
    internal fun post(context: Context, gameId: String, title: String, body: String) {
        if (!canNotify(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL, tr("球局提醒"), NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(
            context, gameId.hashCode(),
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        manager.notify("game-$gameId".hashCode() + title.hashCode(), notification)
    }

    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_GAME = "gameId"
}

/** 闹钟到点：发提醒通知。要在 AndroidManifest.xml 里登记（见 [ReminderService] 的说明） */
class GameReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val gameId = intent.getStringExtra(ReminderService.EXTRA_GAME) ?: return
        ReminderService.post(
            context, gameId,
            intent.getStringExtra(ReminderService.EXTRA_TITLE).orEmpty(),
            intent.getStringExtra(ReminderService.EXTRA_BODY).orEmpty(),
        )
    }
}
