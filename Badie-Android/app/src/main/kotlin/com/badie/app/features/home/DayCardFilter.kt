package com.badie.app.features.home

import androidx.core.content.edit
import android.content.Context
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.backend.DayCandidate
import com.badie.app.backend.NearbyPlayer
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ChoiceChip
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TextAction
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.User
import com.badie.app.models.WindowText
import com.badie.app.models.addingDays
import com.badie.app.models.isSameDay
import com.badie.app.models.startOfDay
import com.badie.app.models.zoned
import com.badie.app.shell.LocalEnv
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.time.ZoneId

/** 按天看人的筛选：项目、球馆、等级、时间、对方性别、只看没爽约过的。记在本机，下次打开还在。对应 iPhone 的 DayCardFilter.swift */
@Serializable
data class DayCardFilter(
    val event: Event = Event.Any,
    /** 空 = 全部球馆 */
    val venueIds: Set<String> = emptySet(),
    /** 选过的球馆的名字（这天没人约那家时，也能在筛选页里看到） */
    val venueNames: Map<String, String> = emptyMap(),
    val minLevel: Int = 1,
    val maxLevel: Int = 9,
    /** 空 = 不限 */
    val times: Set<TimeOfDay> = emptySet(),
    /** null = 不限 */
    @Serializable(GenderAsRaw::class) val gender: Gender? = null,
    val reliableOnly: Boolean = false,
) {
    @Serializable
    enum class Event {
        Any, Singles, Doubles, Mixed;

        val title: String
            @Composable get() = when (this) {
                Any -> tr("全部")
                Singles -> tr("单打")
                Doubles -> tr("双打")
                Mixed -> tr("混双")
            }
    }

    @Serializable
    enum class TimeOfDay {
        Morning, Afternoon, Evening;

        val title: String
            @Composable get() = when (this) {
                Morning -> tr("上午")
                Afternoon -> tr("下午")
                Evening -> tr("晚上")
            }

        /** 一段空闲时间有没有落在这个时段里（上午 0–12 点、下午 12–18 点、晚上 18 点以后，和按开始时间分的一致） */
        fun overlaps(slot: RecurringTimeSlot): Boolean {
            val (from, to) = when (this) {
                Morning -> 0 to 12 * 60
                Afternoon -> 12 * 60 to 18 * 60
                Evening -> 18 * 60 to 24 * 60
            }
            return minOf(slot.endMinutes, to) - maxOf(slot.startMinutes, from) > 0
        }

        companion object {
            /** 按开始时间：12 点前上午，18 点前下午，之后晚上 */
            fun of(date: Long, zone: ZoneId = ZoneId.systemDefault()): TimeOfDay {
                val hour = date.zoned(zone).hour
                return if (hour < 12) Morning else if (hour < 18) Afternoon else Evening
            }
        }
    }

    /** 选了几个条件（按钮上显示） */
    val activeCount: Int
        get() = listOf(event != Event.Any, venueIds.isNotEmpty(), minLevel > 1 || maxLevel < 9, times.isNotEmpty(), gender != null, reliableOnly).count { it }

    private fun matchesPerson(user: User?): Boolean {
        if (user != null) {
            val level = user.displayLevel
            if (level < minLevel || level > maxLevel) return false
            if (gender != null && user.gender != gender) return false
        }
        return true
    }

    fun matches(card: DayCandidate, user: User?, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        when (event) {
            Event.Any -> Unit
            Event.Singles -> if (card.mode != GameMode.Singles) return false
            Event.Doubles -> if (card.mode != GameMode.Doubles || card.mixed) return false
            Event.Mixed -> if (!card.mixed) return false
        }
        if (venueIds.isNotEmpty() && card.venues.none { it.id in venueIds }) return false
        if (!matchesPerson(user)) return false
        if (times.isNotEmpty() && TimeOfDay.of(card.startsAt, zone) !in times) return false
        if (reliableOnly && card.recentNoShows > 0) return false
        return true
    }

    /** 附近的人：时间按 TA 的空闲时间（有一段落在选的时段里就算，没填的都算）；项目按 TA 常打的（没填的都算），混双算双打；球馆按 TA 常去的 */
    fun matches(card: NearbyPlayer, user: User?): Boolean {
        if (times.isNotEmpty() && card.usualTimes.isNotEmpty() && card.usualTimes.none { slot -> times.any { it.overlaps(slot) } }) return false
        val mode = card.preferredMode
        if (mode != null) {
            when (event) {
                Event.Any -> Unit
                Event.Singles -> if (mode != GameMode.Singles) return false
                Event.Doubles, Event.Mixed -> if (mode != GameMode.Doubles) return false
            }
        }
        if (venueIds.isNotEmpty() && card.venues.none { it.id in venueIds }) return false
        if (!matchesPerson(user)) return false
        if (reliableOnly && card.recentNoShows > 0) return false
        return true
    }

    /** 约在哪家：选了球馆就用选的那家，否则离我最近的 */
    fun venue(card: DayCandidate): DayCandidate.Place? {
        val sorted = card.venues.sortedBy { it.km ?: Double.POSITIVE_INFINITY }
        return sorted.firstOrNull { it.id in venueIds } ?: sorted.firstOrNull()
    }

    // MARK: 本机记住

    fun save(context: Context) {
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE).edit { putString(KEY, json.encodeToString(serializer(), this@DayCardFilter)) }
    }

    companion object {
        private const val STORE = "discover"
        private const val KEY = "BadieDayCardFilter"

        /** 以后加了新条件，老的存档也能读（缺的用默认值） */
        private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

        fun load(context: Context): DayCardFilter {
            val text = context.getSharedPreferences(STORE, Context.MODE_PRIVATE).getString(KEY, null) ?: return DayCardFilter()
            return try {
                json.decodeFromString(serializer(), text)
            } catch (_: SerializationException) {
                DayCardFilter()
            } catch (_: IllegalArgumentException) {
                DayCardFilter()
            }
        }
    }
}

/** 性别存成 male / female */
object GenderAsRaw : com.badie.app.models.RawValueSerializer<Gender>("FilterGender", { it.rawValue }, { Gender.ofServer(it) })

/** 卡片里出现的一家球馆和人数 */
data class VenueCount(val venue: DayCandidate.Place, val count: Int)

/**
 * 筛选页。[venues] 是这天卡片里出现的球馆和人数，[count] 算按某个条件能看到几个人；
 * [day] 是现在看的哪天（null：任何时间），换了一天在点按钮时告诉外面（[onDay]）
 */
@Composable
fun DayCardFilterSheet(
    filter: DayCardFilter,
    venues: List<VenueCount>,
    count: (DayCardFilter) -> Int,
    day: Long?,
    onApply: (DayCardFilter) -> Unit,
    onDay: (Long?) -> Unit,
    /** 选了“显示：球群”：关掉筛选，发现页换成附近的球群 */
    onGroups: () -> Unit = {},
) {
    val colors = AppTheme.colors
    var draft by remember { mutableStateOf(filter) }
    var draftDay by remember { mutableStateOf(day) }
    val dayChanged = draftDay != day
    Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("筛选"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
            TextAction(tr("重置"), {
                draft = DayCardFilter()
                draftDay = null
            }, enabled = draft != DayCardFilter() || draftDay != null)
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            val padded = Modifier.padding(horizontal = AppTheme.Spacing.screen)
            Section(tr("显示"), padded) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    ChoiceChip(tr("球友"), isSelected = true) {}
                    ChoiceChip(tr("球群"), isSelected = false, onClick = onGroups)
                }
            }
            Section(tr("日期"), Modifier) {
                DayChips(draftDay) { draftDay = it }
            }
            Section(tr("项目"), padded) {
                SegmentedSticker(DayCardFilter.Event.entries, draft.event, onSelect = { draft = draft.copy(event = it) }) { it.title }
            }
            // 这天卡片里的球馆，加上以前选过、这天没人约的（人数 0，可以去掉）
            val present = venues.map { it.venue.id }.toSet()
            val saved = (filter.venueIds - present).sorted().map { VenueCount(DayCandidate.Place(it, filter.venueNames[it] ?: it), 0) }
            val all = venues + saved
            if (all.isNotEmpty()) {
                Section(tr("球馆"), padded) {
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        for (item in all) {
                            VenueRow(item, draft.venueIds.contains(item.venue.id)) { selected ->
                                draft = if (selected) {
                                    draft.copy(venueIds = draft.venueIds - item.venue.id, venueNames = draft.venueNames - item.venue.id)
                                } else {
                                    draft.copy(venueIds = draft.venueIds + item.venue.id, venueNames = draft.venueNames + (item.venue.id to item.venue.name))
                                }
                            }
                        }
                    }
                }
            }
            Section(tr("等级"), padded) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    LevelStepper(tr("从"), draft.minLevel, 1..draft.maxLevel, Modifier.weight(1f)) { draft = draft.copy(minLevel = it) }
                    LevelStepper(tr("到"), draft.maxLevel, draft.minLevel..9, Modifier.weight(1f)) { draft = draft.copy(maxLevel = it) }
                }
            }
            Section(tr("时间"), padded) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    for (time in DayCardFilter.TimeOfDay.entries) {
                        ChoiceChip(time.title, isSelected = time in draft.times) {
                            draft = draft.copy(times = if (time in draft.times) draft.times - time else draft.times + time)
                        }
                    }
                }
            }
            Section(tr("对方性别"), padded) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    ChoiceChip(tr("不限"), isSelected = draft.gender == null) { draft = draft.copy(gender = null) }
                    ChoiceChip(tr("男"), isSelected = draft.gender == Gender.Male) { draft = draft.copy(gender = Gender.Male) }
                    ChoiceChip(tr("女"), isSelected = draft.gender == Gender.Female) { draft = draft.copy(gender = Gender.Female) }
                }
            }
            Row(padded.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(tr("只看没爽约过的"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
                Switch(
                    draft.reliableOnly, { draft = draft.copy(reliableOnly = it) },
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.lime, checkedThumbColor = Color.White, checkedBorderColor = colors.stroke),
                )
            }
        }
        // 换了一天，人数要换过去才知道
        BrutalButton(
            if (dayChanged) tr("好") else tr("看 %lld 个人", count(draft)),
            {
                onApply(draft)
                if (dayChanged) onDay(draftDay)
            },
            Modifier.padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.md),
        )
    }
}

@Composable
private fun Section(title: String, modifier: Modifier, content: @Composable () -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(
            title, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary,
            modifier = Modifier.padding(horizontal = if (modifier == Modifier) AppTheme.Spacing.screen else 0.dp).semantics { heading() },
        )
        content()
    }
}

/** 任何时间（附近的人）、今天、明天……后面是这天有几个人有空 */
@Composable
private fun DayChips(selected: Long?, onSelect: (Long?) -> Unit) {
    val manager = LocalEnv.current.matchManager
    val today = startOfDay(System.currentTimeMillis())
    Row(
        Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        ChoiceChip(tr("任何时间"), isSelected = selected == null) { onSelect(null) }
        for (offset in 0 until 7) {
            val date = addingDays(today, offset)
            val count = manager.availableCount(date)
            val name = WindowText.dayName(date)
            ChoiceChip(if (count > 0) "$name · $count" else name, isSelected = selected?.let { isSameDay(it, date) } ?: false) { onSelect(date) }
        }
    }
}

@Composable
private fun VenueRow(item: VenueCount, selected: Boolean, onToggle: (Boolean) -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val foreground = if (selected) colors.onAccent else colors.ink
    Row(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .pressable(scale = 1f) {
                haptics.selection()
                onToggle(selected)
            }
            .semantics(mergeDescendants = true) { this.selected = selected }
            .sticker(if (selected) colors.lime else colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(if (selected) Sym.checkmarkCircleFill else Sym.circle, size = 18, tint = foreground)
        Text(item.venue.name, style = AppTheme.Typography.subheadlineBold, color = foreground, maxLines = 2, modifier = Modifier.weight(1f).padding(vertical = AppTheme.Spacing.sm))
        Text(item.count.toString(), style = AppTheme.Typography.footnoteBold, color = foreground)
    }
}

@Composable
private fun LevelStepper(title: String, value: Int, range: IntRange, modifier: Modifier, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    Row(
        modifier.sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs, Alignment.CenterHorizontally),
    ) {
        Text(title, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
        StepIcon(Sym.minus, tr("降低"), value > range.first) { onChange(maxOf(range.first, value - 1)) }
        Text("Lv.$value", style = AppTheme.Typography.headline, color = colors.ink)
        StepIcon(Sym.plus, tr("提高"), value < range.last) { onChange(minOf(range.last, value + 1)) }
    }
}

@Composable
private fun StepIcon(icon: com.badie.app.design.SymbolId, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(36.dp, 40.dp).pressable(scale = 0.85f, enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Symbol(icon, size = 15, tint = if (enabled) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
    }
}
