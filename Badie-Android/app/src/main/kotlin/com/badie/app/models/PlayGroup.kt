package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import com.badie.app.l10n.ListText
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.ZoneId
import java.util.Locale

// MARK: - 球群（固定局）
//
// 绑定球馆的每周固定场次：一键报名、满员候补、有人退出自动递补。
// 一个群最多 5 个球馆：第一个是主球馆（venueId，旧版本只认这个），每个场次可以选在哪个球馆。
// 对外只显示近 30 天的活跃度，不显示成员总数。

@Serializable
data class PlayGroup(
    val id: String,
    val name: String,
    /** 主球馆 */
    val venueId: String,
    val ownerId: String,
    /** 组织者（含群主），可以审批、取消场次 */
    val organizerIds: List<String>,
    val memberIds: List<String>,
    /** 等待审批的人 */
    val pendingIds: List<String>,
    val summary: String,
    @Serializable(IntRangeSerializer::class) val levelRange: IntRange,
    val schedules: List<GroupSchedule>,
    val joinPolicy: JoinPolicy,
    /** 6 位群号（可以发到微信，别人在“输入房间码 / 群号”里加入） */
    val inviteCode: String,
    val createdAt: Long,
    /** 只限女生 / 男生；null = 不限 */
    val audience: Gender? = null,
    /** 教练带课：每场 1–40 人，水平范围只作提示（旧数据里没有这一项） */
    val coached: Boolean? = null,
    /** 主球馆以外的球馆（按顺序；旧数据里没有这一项） */
    val otherVenueIds: List<String>? = null,
) {
    @Serializable
    enum class JoinPolicy(val rawValue: String) {
        /** 水平符合就能直接加入 */
        @SerialName("open") Open("open"),
        /** 组织者同意后加入 */
        @SerialName("approval") Approval("approval");

        val title: String
            get() = when (this) {
                Open -> tr("直接加入")
                Approval -> tr("需要组织者同意")
            }
    }

    fun isMember(userId: String): Boolean = userId in memberIds

    fun isOrganizer(userId: String): Boolean = userId in organizerIds

    fun isPending(userId: String): Boolean = userId in pendingIds

    val levelText: String get() = "Lv.${levelRange.first}–${levelRange.last}"

    val isCoached: Boolean get() = coached ?: false

    /** 所有球馆，主球馆在前 */
    val venueIds: List<String> get() = listOf(venueId) + otherVenueIds.orEmpty().filter { it != venueId }

    /** 换一组球馆：第一个当主球馆 */
    fun withVenueIds(ids: List<String>): PlayGroup {
        val first = ids.firstOrNull() ?: return this
        val rest = ids.drop(1).filter { it != first }.distinct()
        return copy(venueId = first, otherVenueIds = rest.ifEmpty { null })
    }

    /** 收费说明：各场一样就只留一条，不一样就写明是哪一场 */
    val feeLines: List<String>
        get() {
            val notes = schedules.mapNotNull { schedule -> schedule.feeNote?.let { schedule to it } }
            if (notes.size == schedules.size && notes.map { it.second }.toSet().size == 1) return listOf(notes[0].second)
            return notes.map { (schedule, note) -> "${schedule.weekdayTitle} ${schedule.timeText}: $note" }
        }

    /** 分享到微信的文字 */
    fun inviteText(venueName: String): String {
        val times = ListText.and(schedules.map { "${it.weekdayTitle} ${it.timeText}" })
        return tr("来「%@」一起打羽毛球。%@ · %@ · %@。在 Badie App 输入群号 %@ 加入，报名、候补都在 App 里。", name, venueName, times, levelText, inviteCode) +
            "\n" + Room.joinLink(inviteCode)
    }

    companion object {
        const val MAX_SCHEDULES = 7
        const val MAX_VENUES = 5
        val NAME_LIMIT = 2..20
    }
}

/** 每周固定场次 */
@Serializable
data class GroupSchedule(
    val id: String,
    /** 星期：1 = 周日 … 7 = 周六 */
    val weekday: Int,
    /** 从 0 点起的分钟数 */
    val startMinutes: Int,
    val endMinutes: Int,
    /** 名额（满了进候补） */
    val capacity: Int,
    /** 费用说明，如“每人 $15” */
    val feeNote: String? = null,
    /** 在哪个球馆（群里的球馆之一）；null = 主球馆 */
    val venueId: String? = null,
) {
    /** 这个场次实际在哪个球馆：不是群里的球馆（比如被删掉了）就回到主球馆 */
    fun effectiveVenueId(group: PlayGroup): String = venueId?.takeIf { it in group.venueIds } ?: group.venueId

    val weekdayTitle: String
        get() {
            val day = RecurringTimeSlot.weekdayNames[((weekday - 1) % 7 + 7) % 7]
            return tr("每%@", day)
        }

    val timeText: String
        get() = String.format(Locale.ROOT, "%02d:%02d–%02d:%02d", startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)

    /** 某天的这一场（这天不是这个星期几时返回 null） */
    fun slot(day: Long, zone: ZoneId = ZoneId.systemDefault()): TimeSlot? {
        if (weekdayOf(day, zone) != weekday) return null
        return TimeSlot.on(day, startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60, zone)
    }

    companion object {
        const val FEE_NOTE_LIMIT = 120

        /** 名额 4–40；教练带课的群 1–40（教练不报名，人数指学员） */
        fun capacityRange(coached: Boolean): IntRange = if (coached) 1..40 else 4..40

        /** 1–7 个；每个 1–12 小时、当天结束，名额和收费说明的长度（和服务器的 valid_schedules 一致） */
        fun areValid(schedules: List<GroupSchedule>, coached: Boolean = false): Boolean =
            schedules.isNotEmpty() && schedules.size <= PlayGroup.MAX_SCHEDULES && schedules.all {
                (it.endMinutes - it.startMinutes) in 60..720 && it.endMinutes <= 24 * 60 &&
                    it.capacity in capacityRange(coached) && it.weekday in 1..7
            } && schedules.all { (it.feeNote?.characterCount ?: 0) <= FEE_NOTE_LIMIT }
    }
}

/** 某一场固定局（按需生成） */
@Serializable
data class GroupSession(
    /** groupId|scheduleId|yyyyMMdd */
    val id: String,
    val groupId: String,
    val scheduleId: String,
    val slot: TimeSlot,
    val capacity: Int,
    /** 报名顺序 */
    val signedUp: List<String>,
    val waitlist: List<String>,
    val isCancelled: Boolean = false,
    /** 在哪个球馆；null = 球群的主球馆 */
    val venueId: String? = null,
) {
    fun effectiveVenueId(group: PlayGroup): String = venueId ?: group.venueId

    sealed interface Status {
        data object SignedUp : Status
        data class Waitlisted(val position: Int) : Status
        data object None : Status
    }

    val isFull: Boolean get() = signedUp.size >= capacity

    fun status(userId: String): Status {
        if (userId in signedUp) return Status.SignedUp
        val index = waitlist.indexOf(userId)
        if (index >= 0) return Status.Waitlisted(index + 1)
        return Status.None
    }

    fun isUpcoming(now: Long = System.currentTimeMillis()): Boolean = !isCancelled && slot.endTime > now

    companion object {
        /** 开场前多久内退出算临时取消（与球局规则一致，毫秒） */
        const val LATE_CANCELLATION_WINDOW = 2 * 3_600_000L
        /** 能看到并报名未来几天的场次 */
        const val DAYS_AHEAD = 14

        fun makeId(groupId: String, scheduleId: String, day: Long, zone: ZoneId = ZoneId.systemDefault()): String {
            val date = day.zoned(zone).toLocalDate()
            val stamp = String.format(Locale.ROOT, "%04d%02d%02d", date.year, date.monthValue, date.dayOfMonth)
            return "$groupId|$scheduleId|$stamp"
        }
    }
}

/** 球群的真实活跃度（对外展示用，不显示成员总数） */
data class GroupActivity(
    /** 近 30 天开了几场 */
    val sessionsLast30Days: Int,
    /** 平均每场报名人数 */
    val averageTurnout: Double,
) {
    val text: String
        get() = if (sessionsLast30Days == 0) {
            tr("近 30 天还没开过场")
        } else {
            tr("近 30 天 %lld 场 · 平均每场 %lld 人", sessionsLast30Days, roundHalfAway(averageTurnout).toInt())
        }
}
