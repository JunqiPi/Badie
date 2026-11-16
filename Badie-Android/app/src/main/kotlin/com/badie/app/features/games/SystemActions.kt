package com.badie.app.features.games

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import androidx.core.net.toUri
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.Game
import com.badie.app.models.Venue
import java.util.Locale

/** 交给系统的几件事：分享、导航、加入日历、复制。对应 iPhone 的 ShareLink、MapsLauncher、CalendarEventEditor、UIPasteboard */
object SystemActions {
    /** 系统的分享面板 */
    fun share(context: Context, text: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * 导航到球馆：交给装了的地图 App（geo: 链接，系统让用户选）。没有能打开的返回 false。
     * iPhone 是自己列出 Apple / Google / 高德等几个 App 让人选；安卓由系统列
     */
    fun navigate(context: Context, venue: Venue): Boolean {
        val label = android.net.Uri.encode(venue.name)
        val uri = if (venue.lat != 0.0 || venue.lon != 0.0) {
            String.format(Locale.ROOT, "geo:%.6f,%.6f?q=%.6f,%.6f(%s)", venue.lat, venue.lon, venue.lat, venue.lon, label)
        } else {
            "geo:0,0?q=" + android.net.Uri.encode("${venue.name}, ${venue.address}")
        }
        val intent = Intent(Intent.ACTION_VIEW, uri.toUri())
        return try {
            context.startActivity(Intent.createChooser(intent, tr("选择导航方式")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /**
     * 系统的新建日程页（不用日历权限）。iPhone 还带了地点坐标和开赛前 2 小时的提醒；
     * 安卓的新建日程页不收这两样，提醒按日历 App 的默认设置
     */
    fun addToCalendar(context: Context, game: Game): Boolean {
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, tr("羽毛球 · %@", game.mode.title))
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, game.slot.startTime)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, game.slot.endTime)
            .putExtra(CalendarContract.Events.EVENT_LOCATION, "${game.court.name}, ${game.court.address}")
            .putExtra(CalendarContract.Events.DESCRIPTION, game.shareText())
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        game.court.timeZoneId?.let { intent.putExtra(CalendarContract.Events.EVENT_TIMEZONE, it) }
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    fun copy(context: Context, text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Badie", text))
    }

    /** 剪贴板里的文字（粘贴房间码） */
    fun paste(context: Context): String? {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        return clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
    }
}
