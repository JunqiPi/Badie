package com.badie.app.features.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.backend.DayCandidate
import com.badie.app.backend.InviteResult
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.IconButton
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.features.matching.DateStrip
import com.badie.app.features.matching.TimeStepper
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.GameMode
import com.badie.app.models.PlayWindow
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.Room
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.UsualTimeText
import com.badie.app.models.Venue
import com.badie.app.models.WindowText
import com.badie.app.models.addingDays
import com.badie.app.models.startOfDay
import com.badie.app.models.weekdayOf
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * 约某个人打球 / 提议换个时间（半屏弹层的内容）。发现页、球友资料、聊天里改约时间都会调它，名字和参数不要改。
 * 对应 iPhone 的 Features/Home/NearbyViews.swift 里的 InviteComposeSheet。
 * counterRoomId 不为空时是“对这个邀请提议换个时间”（purpose: .counter(roomId:)）
 */
@Composable
fun InviteComposeSheet(userId: String, counterRoomId: String? = null, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val manager = env.matchManager
    if (counterRoomId == null) {
        InviteComposeContent(
            userId, counterRoom = null, partnerTimes = manager.usualTimes(userId), theirVenues = emptyList(), prefill = null,
            initialMode = manager.user(userId)?.preferredMode, onDismiss = onDismiss,
        ) { result, window -> env.appState.showToast(sentText(manager.user(userId)?.nickname ?: "", result, window), Toast.Style.Success) }
        return
    }
    var room by remember(counterRoomId) { mutableStateOf(manager.invites.firstOrNull { it.id == counterRoomId }) }
    LaunchedEffect(counterRoomId) {
        if (room == null) {
            manager.loadInvites()
            room = manager.invites.firstOrNull { it.id == counterRoomId }
        }
    }
    val current = room ?: return
    InviteComposeContent(
        userId, counterRoom = current, partnerTimes = manager.usualTimes(userId), theirVenues = emptyList(), prefill = null,
        initialMode = current.mode, onDismiss = onDismiss,
    ) { _, _ -> env.appState.showToast(L10n.tr("已发给 TA"), Toast.Style.Success) }
}

/** 发出去以后说一声：“已邀请阿杰 · 周六 19:00–21:00”，下一行“今天还能约 N 个” */
fun sentText(name: String, result: InviteResult?, window: PlayWindow): String {
    var text = L10n.tr("已邀请%@ · %@", name, "${WindowText.days(window)} ${WindowText.caption(window)}")
    if (result != null) text += "\n" + L10n.tr("今天还能约 %lld 个", result.remaining)
    return text
}

/**
 * 半屏“约<昵称>”：右滑、点卡片上的空闲时间、收到邀请后“换个时间”都用这一页。
 * 发出去的是定好的时间：哪天、几点到几点（半小时一档，1–4 小时）
 */
@Composable
fun InviteComposeContent(
    userId: String,
    /** 换个时间：在回的这个邀请；新邀请是 null */
    counterRoom: Room?,
    /** TA 的空闲时间：选的那天 TA 有空，时间上面写一句“<TA> 周五晚上有空” */
    partnerTimes: List<RecurringTimeSlot>,
    /** TA 常去的球馆（卡片上的），近的在前 */
    theirVenues: List<DayCandidate.Place>,
    /** 点卡片上的空闲时间进来：按那一段填好 */
    prefill: RecurringTimeSlot?,
    /** 默认的项目：TA 常打的；换个时间是现在的项目 */
    initialMode: GameMode?,
    onDismiss: () -> Unit,
    /** 发出去了（新邀请带结果；换个时间是 null） */
    onSent: (InviteResult?, PlayWindow) -> Unit,
) {
    val env = LocalEnv.current
    val manager = env.matchManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val partner = manager.user(userId)
    val currentVenue = counterRoom?.court
    val favorites = env.appState.backend.favoriteVenueIds

    var mode by remember { mutableStateOf(GameMode.Singles) }
    var day by remember { mutableLongStateOf(startOfDay(System.currentTimeMillis())) }
    var startMinutes by remember { mutableIntStateOf(19 * 60) }
    var endMinutes by remember { mutableIntStateOf(21 * 60) }
    var venueId by remember { mutableStateOf<String?>(null) }
    var suggestedVenueName by remember { mutableStateOf<String?>(null) }
    var showsDatePicker by remember { mutableStateOf(false) }
    var showsVenuePicker by remember { mutableStateOf(false) }
    var isWorking by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }

    // 定好的时间：整个窗口就是一场
    val window = PlayWindow.on(day, startMinutes, endMinutes)?.copy(durationMinutes = endMinutes - startMinutes)
    val possible = window?.isPossible() ?: false

    /** 一段时间（TA 的空闲时间、两人的交集）填成：那天，从开头打 2 小时 */
    fun apply(next: PlayWindow) {
        val start = (PlayWindow.clockMinutes(next.start) + 29) / 30 * 30
        if (start !in 6 * 60..23 * 60) return
        day = startOfDay(next.start)
        startMinutes = start
        endMinutes = minOf(24 * 60, start + 120)
    }

    // 项目：TA 常打的。时间：点了空闲时间就用那一段；否则用两人空闲时间的交集（服务器给）；都没有就 19:00–21:00（今天来不及就明天）。
    // 球馆：建议的那家，否则两人都常去的、我常去的、TA 常去的
    LaunchedEffect(Unit) {
        if (initialMode != null) mode = initialMode
        if (currentVenue != null) venueId = currentVenue.id
        val next = prefill?.let { PlayWindow.nextOccurrence(it) }
        if (next != null) {
            apply(next)
        } else if (PlayWindow.on(day, startMinutes, endMinutes)?.isPossible() != true) {
            day = addingDays(day, 1)
        }
        val before = Triple(day, startMinutes, endMinutes)
        val suggestion = manager.nearbyApi.suggestInvite(userId, currentVenue?.id)
        // 等建议的时候已经自己改了时间，就不再覆盖
        val suggested = suggestion?.window
        if (prefill == null && suggested != null && Triple(day, startMinutes, endMinutes) == before) apply(suggested)
        if (venueId == null) {
            val id = suggestion?.venueId
            if (id != null) {
                venueId = id
                suggestedVenueName = suggestion.venueName
            } else {
                venueId = theirVenues.firstOrNull { it.id in favorites }?.id ?: favorites.firstOrNull() ?: theirVenues.firstOrNull()?.id
            }
        }
    }

    val today = startOfDay(System.currentTimeMillis())
    // 日期条：今天起 14 天；用日历选了更远的那天也放进来
    val days = (0 until 14).map { addingDays(today, it) }.let { if (day in it) it else it + day }
    // 选的那天 TA 有空的那段：“周五晚上”（和选的时间重叠的优先）
    val sameDay = partnerTimes.filter { it.dayOfWeek == weekdayOf(day) }.sortedBy { it.startMinutes }
    val partnerFree = (sameDay.firstOrNull { it.startMinutes < endMinutes && it.endMinutes > startMinutes } ?: sameDay.firstOrNull())?.let(UsualTimeText::chip)
    val venueName = venueId?.let { id ->
        manager.court(id)?.name ?: theirVenues.firstOrNull { it.id == id }?.name ?: currentVenue?.takeIf { it.id == id }?.name ?: suggestedVenueName
    }
    val isShared = venueId?.let { id -> id in favorites && theirVenues.any { it.id == id } } ?: false

    fun send() {
        val target = window ?: return
        val venue = venueId ?: return
        if (isWorking || !target.isPossible()) return
        isWorking = true
        errorText = null
        scope.launch {
            try {
                if (counterRoom == null) {
                    val result = manager.nearbyApi.invitePlayer(userId, venue, target, mode)
                    haptics.success()
                    onSent(result, target)
                } else {
                    manager.nearbyApi.counterInvite(counterRoom.id, venue.takeIf { it != currentVenue?.id }, target, mode)
                    haptics.success()
                    onSent(null, target)
                }
                manager.loadInvites()
                onDismiss()
            } catch (error: RemoteError) {
                errorText = InviteText.error(error)
            } finally {
                isWorking = false
            }
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        val padded = Modifier.padding(horizontal = AppTheme.Spacing.screen)
        Text(
            if (counterRoom == null) tr("约%@", partner?.nickname ?: "") else tr("换个时间"),
            style = AppTheme.Typography.title2, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = padded.padding(top = AppTheme.Spacing.xl).semantics { heading() },
        )
        Field(tr("项目"), padded) {
            SegmentedSticker(GameMode.entries, mode, onSelect = {
                mode = it
                errorText = null
            }) { it.title }
        }
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Row(padded.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                FieldTitle(tr("日期"))
                Spacer(Modifier.weight(1f))
                IconButton(Sym.calendar, tr("选日期")) { showsDatePicker = true }
            }
            DateStrip(days, day, onSelect = {
                day = it
                errorText = null
            })
        }
        Field(tr("时间"), padded) {
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                val name = partner?.nickname
                if (partnerFree != null && name != null) {
                    Text(tr("%@ %@有空", name, partnerFree), style = AppTheme.Typography.footnote, color = colors.inkSecondary, maxLines = 1)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    // 改开始：时长不变，结束跟着挪（最晚 24:00）
                    TimeStepper(tr("开始"), startMinutes, 6 * 60..23 * 60, Modifier.weight(1f)) { start ->
                        val length = endMinutes - startMinutes
                        startMinutes = start
                        endMinutes = minOf(24 * 60, start + length)
                        errorText = null
                    }
                    Symbol(Sym.arrowRight, size = 14, tint = colors.inkTertiary)
                    // 改结束：一场保持 1–4 小时，不够或太长就挪开始
                    TimeStepper(tr("结束"), endMinutes, 7 * 60..24 * 60, Modifier.weight(1f)) { end ->
                        endMinutes = end
                        startMinutes = minOf(maxOf(startMinutes, end - LONGEST), end - SHORTEST)
                        errorText = null
                    }
                }
                if (!possible) Text(tr("这个时间来不及了"), style = AppTheme.Typography.footnoteBold, color = colors.danger)
            }
        }
        Field(tr("球馆"), padded) {
            Row(
                Modifier.fillMaxWidth().pressable(scale = 0.98f) { showsVenuePicker = true }
                    .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(venueName ?: tr("选球馆"), style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (isShared) Text(tr("你们都常去"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                }
                Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
            }
        }
        errorText?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = colors.danger, modifier = padded) }
        BrutalButton(
            if (counterRoom == null) tr("发出邀请") else tr("发出"), ::send, padded,
            enabled = !isWorking && venueId != null && possible,
        )
    }

    if (showsDatePicker) {
        SheetScaffold(onDismiss = { showsDatePicker = false }) {
            InviteDatePicker(day) {
                day = it
                errorText = null
                showsDatePicker = false
            }
        }
    }
    if (showsVenuePicker) {
        SheetScaffold(onDismiss = { showsVenuePicker = false }, fullHeight = true) {
            InviteVenuePicker(theirVenues, favorites, currentVenue, venueId) {
                venueId = it
                showsVenuePicker = false
            }
        }
    }
}

private const val SHORTEST = 60
private const val LONGEST = 240

@Composable
private fun FieldTitle(title: String) {
    Text(title, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary, modifier = Modifier.semantics { heading() })
}

@Composable
private fun Field(title: String, modifier: Modifier, content: @Composable () -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        FieldTitle(title)
        content()
    }
}

/** 日历：今天起 30 天内 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InviteDatePicker(day: Long, onPick: (Long) -> Unit) {
    val colors = AppTheme.colors
    val zone = ZoneId.systemDefault()
    val first = LocalDate.now(zone)
    val last = first.plusDays(TimeSlotConstants.MAXIMUM_DAYS_AHEAD.toLong())
    // 日历按 UTC 的 0 点记日期
    fun utc(date: LocalDate) = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val state = rememberDatePickerState(
        initialSelectedDateMillis = utc(Instant.ofEpochMilli(day).atZone(zone).toLocalDate()),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean = utcTimeMillis in utc(first)..utc(last)
            override fun isSelectableYear(year: Int): Boolean = year in first.year..last.year
        },
    )
    Column(Modifier.fillMaxWidth().padding(AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        DatePicker(
            state, title = null, headline = null, showModeToggle = false,
            colors = DatePickerDefaults.colors(
                containerColor = colors.canvas, selectedDayContainerColor = colors.ink, selectedDayContentColor = colors.canvas,
                todayDateBorderColor = colors.ink, todayContentColor = colors.ink, dayContentColor = colors.ink,
            ),
        )
        BrutalButton(tr("好"), {
            val picked = state.selectedDateMillis ?: return@BrutalButton
            val date = Instant.ofEpochMilli(picked).atZone(ZoneOffset.UTC).toLocalDate()
            onPick(date.atStartOfDay(zone).toInstant().toEpochMilli())
        })
    }
}

/**
 * 选一家球馆：TA 常去的、我常去的、附近的。
 * iPhone 用的是球馆库的选择页（VenuePickerView 单选）；安卓的球馆页做好以后换过去
 */
@Composable
private fun InviteVenuePicker(theirVenues: List<DayCandidate.Place>, favorites: List<String>, currentVenue: Venue?, selected: String?, onPick: (String) -> Unit) {
    val manager = LocalEnv.current.matchManager
    val colors = AppTheme.colors
    LaunchedEffect(favorites) { manager.loadVenues(favorites) }
    val options = buildList {
        currentVenue?.let { add(it.id to it.name) }
        theirVenues.forEach { add(it.id to it.name) }
        favorites.forEach { id -> manager.court(id)?.let { add(id to it.name) } }
        manager.nearbyCourts.forEach { add(it.id to it.name) }
    }.distinctBy { it.first }
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Text(tr("选球馆"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.sm).semantics { heading() })
        for ((id, name) in options) {
            val isSelected = id == selected
            val shared = id in favorites && theirVenues.any { it.id == id }
            Row(
                Modifier.fillMaxWidth().pressable(scale = 0.98f) { onPick(id) }
                    .sticker(if (isSelected) colors.lime else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.md),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                val ink = if (isSelected) colors.onAccent else colors.ink
                Symbol(if (isSelected) Sym.checkmarkCircleFill else Sym.circle, size = 18, tint = ink)
                Column(Modifier.weight(1f)) {
                    Text(name, style = AppTheme.Typography.headline, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (shared) Text(tr("你们都常去"), style = AppTheme.Typography.footnote, color = if (isSelected) colors.onAccent else colors.inkSecondary)
                }
            }
        }
    }
}
