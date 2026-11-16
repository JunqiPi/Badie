package com.badie.app.features.venues

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.badie.app.backend.VenueIssue
import com.badie.app.backend.VenuePeople
import com.badie.app.backend.reportVenue
import com.badie.app.backend.venuePeople
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.IconButton
import com.badie.app.design.InfoRow
import com.badie.app.design.InsetDivider
import com.badie.app.design.PersonBubble
import com.badie.app.design.SectionTitle
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.SymbolId
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.User
import com.badie.app.models.Venue
import com.badie.app.models.VenueSource
import com.badie.app.models.VenueStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.launch

/**
 * 球馆详情。iPhone 是弹窗（从链接进来时是整页，CourtDetailSheet）；安卓都是整页（Route.Venue）。
 * 没有小地图（要 Google 地图的 key），“导航”跳到地图 App
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun VenueDetailView(court: Venue) {
    val env = LocalEnv.current
    val appState = env.appState
    val router = env.router
    val locationManager = env.locationManager
    val matchVenues = env.matchManager.draftVenueIds
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    // 最新数据（确认后状态会变）
    val venue = locationManager.court(court.id) ?: court
    val isFavorite = locationManager.isFavorite(venue.id)
    var regularsCount by remember { mutableStateOf<Int?>(null) }
    var people by remember { mutableStateOf(VenuePeople()) }
    var showNavigation by remember { mutableStateOf(false) }
    var showReport by remember { mutableStateOf(false) }

    // 收藏或取消后人数会变
    LaunchedEffect(venue.id, isFavorite) {
        regularsCount = locationManager.fetchRegularsCount(venue.id)
        try {
            people = appState.backend.venuePeople(venue.id)
        } catch (_: RemoteError) {
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        // 名称、又名、可信度、常去
        Row(Modifier.padding(top = AppTheme.Spacing.sm), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Text(venue.name, style = AppTheme.Typography.title2, color = colors.ink)
                if (!venue.aliases.isNullOrEmpty()) {
                    Text(tr("又名 %@", venue.aliases.joinToString(" · ")), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                    VenueStatusBadge(venue.status)
                    venue.facility?.let { TagPill(it.title, icon = Sym.building2Fill, fill = colors.lavender) }
                }
            }
            IconButton(
                if (isFavorite) Sym.heartFill else Sym.heart,
                if (isFavorite) tr("取消常去") else tr("设为常去"),
                accent = if (isFavorite) colors.pink else null,
            ) {
                haptics.selection()
                locationManager.toggleFavorite(venue.id)
            }
        }

        // 地址、入口说明
        Column(
            Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            // TODO(地图)：iPhone 这里有 160 高的小地图（VenueMapPreview）。要等 Google 地图的 key
            VenueAddressBlock(venue.postalAddress)
            venue.entranceNote?.let { note ->
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.Top) {
                    Symbol(Sym.doorLeftHandOpen, size = 13, tint = colors.ink, modifier = Modifier.padding(top = 2.dp))
                    Text(note, style = AppTheme.Typography.footnote, color = colors.ink)
                }
            }
        }

        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            StatTile(venue.formattedDistance(locationManager.coordinate), tr("距离"), Modifier.weight(1f).fillMaxHeight())
            StatTile(venue.courtCount?.toString() ?: "–", tr("场地数"), Modifier.weight(1f).fillMaxHeight())
            StatTile(regularsCount?.toString() ?: "–", tr("人常去"), Modifier.weight(1f).fillMaxHeight())
        }

        PeopleRow(tr("最近在这打过"), people.recent) { appState.showPlayer(it) }
        PeopleRow(tr("常客"), people.regulars) { appState.showPlayer(it) }

        // 价格、开放时间、电话、官网
        Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.lg)) {
            InfoRow(
                currencyIcon(venue.currency), venue.pricingText, tint = colors.butter,
                subtitle = venue.pricingNote ?: if (venue.pricing.isKnown) tr("以球馆实际收费为准") else null,
            )
            InsetDivider()
            val playTimes = venue.playTimes
            if (playTimes != null) {
                InfoRow(Sym.clockFill, tr("羽毛球开放时段"), tint = colors.peach, subtitle = playTimes)
            } else {
                val suffix = venue.timeZoneAbbreviation()?.let { tr(" · 当地时间（%@）", it) }.orEmpty()
                InfoRow(Sym.clockFill, venue.hoursText, tint = colors.peach, subtitle = venue.operatingHours?.let { it.formattedDaysOpen + suffix })
            }
            venue.phone?.let { phone ->
                InsetDivider()
                InfoRow(
                    Sym.phoneFill, phone, Modifier.pressable(scale = 0.98f, onClickLabel = tr("致电球馆预订场地")) { MapsLauncher.call(context, phone) },
                    tint = colors.mint,
                )
            }
            venue.website?.let { website ->
                val host = runCatching { java.net.URI(website).host }.getOrNull() ?: website
                InsetDivider()
                InfoRow(
                    Sym.safariFill, host, Modifier.pressable(scale = 0.98f) { MapsLauncher.openWebsite(context, website) },
                    tint = colors.sky, subtitle = tr("官网 / 预订页面"),
                )
            }
        }

        TrustSection(venue) { showReport = true }

        // 这里的固定局
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            SectionTitle(tr("这里的固定局"), actionTitle = tr("建一个")) { router.open(Route.CreateGroup(venue.id)) }
            // TODO(球群)：iPhone 在这里列出这家球馆的球群（groupManager.groups(atVenue:)），没有时写“还没有球群”。
            // 球群那一块（features/groups）搬好以后接上；现在只放“建一个”
        }

        // 本馆排行
        InfoRow(
            Sym.trophyFill, tr("本馆排行"),
            Modifier.pressable(scale = 0.98f) { router.open(Route.VenueLeaderboard(venue.id)) }
                .sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none)
                .padding(horizontal = AppTheme.Spacing.lg),
            tint = colors.butter, subtitle = tr("本月场次最多 · 分水平段"),
        ) { Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary) }

        if (venue.amenities.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                for (amenity in venue.amenities) TagPill(amenity.title, icon = amenity.icon, fill = colors.sky)
            }
        }

        val selected = venue.id in matchVenues
        BrutalButton(
            {
                when {
                    selected -> matchVenues.remove(venue.id)
                    matchVenues.size < MAX_MATCH_VENUES -> matchVenues.add(venue.id)
                    else -> {
                        appState.showToast(L10n.tr("快速匹配最多选择 %lld 个球馆", MAX_MATCH_VENUES))
                        return@BrutalButton
                    }
                }
                haptics.selection()
            },
            Modifier.semantics { this.selected = selected },
            kind = if (selected) ButtonKind.Secondary else ButtonKind.Primary,
            size = ButtonSize.Medium,
        ) {
            Symbol(if (selected) Sym.checkmarkCircleFill else Sym.plusCircleFill, size = 15)
            Text(if (selected) tr("移出匹配") else tr("加入匹配"), Modifier.padding(start = AppTheme.Spacing.sm))
        }
        BrutalButton({ showNavigation = true }, kind = ButtonKind.Inverse, size = ButtonSize.Medium) {
            Symbol(Sym.locationNorthLineFill, size = 15)
            Text(tr("导航"), Modifier.padding(start = AppTheme.Spacing.sm))
        }
    }

    if (showNavigation) {
        ChoiceSheet(tr("选择导航方式"), null, MapsLauncher.apps(venue).map { it.title }, onDismiss = { showNavigation = false }) { index ->
            val app = MapsLauncher.apps(venue)[index]
            if (!MapsLauncher.open(context, venue, app)) appState.showToast(L10n.tr("未安装%@", app.title), Toast.Style.Error)
        }
    }
    if (showReport) {
        ChoiceSheet(
            tr("这个球馆有什么问题？"), tr("一个人的报告不会让球馆下架；多位球友报告后会进入人工核实。"),
            VenueIssue.entries.map { it.title }, onDismiss = { showReport = false },
        ) { index ->
            scope.launch {
                try {
                    appState.backend.reportVenue(venue.id, VenueIssue.entries[index])
                    appState.showToast(L10n.tr("谢谢，我们会尽快核实"), Toast.Style.Success)
                } catch (error: RemoteError) {
                    appState.showError(error)
                }
            }
        }
    }
}

// MARK: - 最近在这打过、常客

/** 一排头像，点一个看 TA 的资料；没人就不显示 */
@Composable
private fun PeopleRow(title: String, users: List<User>, onShow: (String) -> Unit) {
    if (users.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        SectionTitle(title, detail = users.size.toString())
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            verticalAlignment = Alignment.Top,
        ) {
            for (user in users) PersonBubble(user, size = 48.dp) { onShow(user.id) }
        }
    }
}

// MARK: - 可信度

@Composable
private fun TrustSection(venue: Venue, onReport: () -> Unit) {
    val env = LocalEnv.current
    val appState = env.appState
    val locationManager = env.locationManager
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val hasConfirmed = locationManager.hasConfirmed(venue.id)
    Column(
        Modifier.fillMaxWidth().sticker(colors.surfaceMuted, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Text(sourceText(venue), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            if (venue.status != VenueStatus.Verified) {
                BrutalButton(
                    {
                        scope.launch {
                            try {
                                locationManager.confirmVenue(venue.id)
                                haptics.success()
                                appState.showToast(L10n.tr("谢谢确认。"), Toast.Style.Success)
                            } catch (error: RemoteError) {
                                appState.showError(error)
                            }
                        }
                    },
                    Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small, enabled = !hasConfirmed,
                ) {
                    Symbol(Sym.checkmarkCircleFill, size = 13)
                    Text(if (hasConfirmed) tr("已确认") else tr("确认地址"), Modifier.padding(start = AppTheme.Spacing.xs))
                }
            }
            BrutalButton(
                onReport,
                if (venue.status != VenueStatus.Verified) Modifier.weight(1f) else Modifier,
                kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = venue.status != VenueStatus.Verified,
            ) {
                Symbol(Sym.exclamationmarkBubbleFill, size = 13)
                Text(tr("信息有误"), Modifier.padding(start = AppTheme.Spacing.xs))
            }
        }
    }
}

/** 来源说明：谁加的、谁确认过、最近什么时候确认的 */
fun sourceText(venue: Venue, now: Long = System.currentTimeMillis()): String {
    val freshness = venue.lastConfirmedAt?.let { L10n.tr(" · 最近确认 %@", DateText.relative(it, now)) }.orEmpty()
    val attribution = venue.attribution
    if (venue.source == VenueSource.OpenData && attribution != null) {
        return L10n.tr("来自当地政府开放数据 · %@%@", attribution, freshness)
    }
    return when (venue.status) {
        VenueStatus.Verified -> venue.checkedOn?.let { L10n.tr("平台于 %@ 核实%@", yearMonth(it), freshness) } ?: L10n.tr("平台已核实地址%@", freshness)
        VenueStatus.Confirmed -> L10n.tr("%lld 位球友确认过地址%@", venue.confirmedBy.size, freshness)
        VenueStatus.Unconfirmed -> {
            val origin = when (venue.source) {
                VenueSource.AppleMaps -> L10n.tr("来自 Apple 地图，由球友加入")
                VenueSource.OpenStreetMap -> L10n.tr("来自 © OpenStreetMap 贡献者")
                else -> L10n.tr("由球友添加")
            }
            L10n.tr("%@ · %lld/%lld 位确认%@", origin, venue.confirmedBy.size, Venue.CONFIRMATIONS_NEEDED, freshness)
        }
    }
}

/** “2026年10月”（按 App 的语言） */
private fun yearMonth(millis: Long): String = try {
    android.icu.text.DateFormat.getInstanceForSkeleton("yMMM", java.util.Locale.getDefault()).format(java.util.Date(millis))
} catch (_: RuntimeException) {
    java.text.SimpleDateFormat("yyyy-MM", java.util.Locale.ROOT).format(java.util.Date(millis))
}

/** 价格那一行的图标：iPhone 按币种（美元、人民币、英镑…）；安卓的图标库还没有这几个，先用钞票 */
private fun currencyIcon(@Suppress("UNUSED_PARAMETER") currency: String): SymbolId = Sym.banknote

// MARK: - 选项弹层（iPhone 的 confirmationDialog）

@Composable
fun ChoiceSheet(title: String, message: String?, options: List<String>, onDismiss: () -> Unit, onChoose: (Int) -> Unit) {
    val colors = AppTheme.colors
    SheetScaffold(onDismiss = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            Text(title, style = AppTheme.Typography.title3, color = colors.ink)
            if (message != null) Text(message, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            Spacer(Modifier.padding(top = AppTheme.Spacing.xs))
            options.forEachIndexed { index, option ->
                BrutalButton(option, {
                    onDismiss()
                    onChoose(index)
                }, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
            }
        }
    }
}
