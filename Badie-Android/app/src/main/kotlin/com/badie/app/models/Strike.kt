package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import java.time.ZoneId

/** 我的爽约记录（近 180 天）：180 天内第 1 次警告、第 2 次 7 天不能约球、第 3 次永久；48 小时内可以申诉 */
data class MyStrikes(
    /** 不能约球到什么时候；永久是 [DISTANT_FUTURE] */
    val suspendedUntil: Long?,
    /** 近 180 天算数的次数（申诉中和撤销的不算） */
    val recent: Int,
    val strikes: List<Strike>,
) {
    enum class Status(val rawValue: String) {
        Active("active"), Appealed("appealed"), Upheld("upheld"), Overturned("overturned");

        companion object {
            fun of(rawValue: String): Status? = entries.firstOrNull { it.rawValue == rawValue }
        }
    }

    data class Strike(
        val id: Int,
        val level: Int,
        val status: Status,
        val createdAt: Long,
        val seen: Boolean,
        val canAppeal: Boolean,
        /** 那场球的开始时间（按球馆时区显示）和球馆 */
        val gameStartsAt: Long,
        val timeZone: ZoneId?,
        val venue: String?,
    )

    companion object {
        /** “暂停约球至 11月2日 19:00” / “已暂停约球” */
        fun suspensionText(until: Long, zone: ZoneId = ZoneId.systemDefault()): String =
            if (until == DISTANT_FUTURE) tr("已暂停约球") else tr("暂停约球至 %@", DateText.dayAndTime(until, zone))
    }
}
