package com.badie.app.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.badie.app.backend.ProfileApi
import com.badie.app.backend.suspensionText
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.IconButton
import com.badie.app.design.InsetDivider
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.MenuRow
import com.badie.app.design.PraiseTagsView
import com.badie.app.design.ProgressBar
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.Rankings
import com.badie.app.models.ReputationScore
import com.badie.app.models.SkillTier
import com.badie.app.models.TimeSlotConstants
import com.badie.app.models.User
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

// 入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面）。
// 对应的 iPhone 源文件：Features/Profile/*.swift, Features/LevelCard/*.swift, Features/Support/*.swift

/** “我的”（第四个标签）。对应 iPhone 的 Features/Profile/ProfileView.swift */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileScreen() {
    val env = LocalEnv.current
    val router = env.router
    val appState = env.appState
    val api = rememberProfileApi()
    val context = LocalContext.current
    var showRadius by remember { mutableStateOf(false) }
    var showHelp by remember { mutableStateOf(false) }
    var showTips by remember { mutableStateOf(false) }
    var showReputation by remember { mutableStateOf(false) }
    var showsCardPreview by remember { mutableStateOf(false) }
    var showsLevelCard by remember { mutableStateOf(false) }
    val showsSupport = remember { TipJar.isAvailable(context) }
    // 空闲时间、胜率、爽约、常去球馆：进来时读一遍
    LaunchedEffect(appState.currentUser?.id) { refreshProfilePage(api) }
    val user = appState.currentUser

    RefreshEverything(Modifier.fillMaxSize(), extra = { refreshProfilePage(api) }) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.tabBarClearance),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            LargeTitleHeader(tr("我的")) {
                IconButton(Sym.gearshapeFill, tr("设置")) { router.open(Route.Settings) }
            }
            if (user != null) {
                val slots = api.recurringSlots()
                val venue = api.favoriteVenues().firstOrNull()
                Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl)) {
                    TodoPills(user, api)
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                        // 和发现页同一张卡；点了全屏看别人刷到的样子
                        MyCard(user, slots, venue, api.strikes?.recent ?: 0, Modifier.fillMaxWidth().aspectRatio(0.82f)) { showsCardPreview = true }
                        // 编辑资料 + 分享等级卡片（定过级才有卡片可分享）
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            BrutalButton(tr("编辑资料"), { router.open(Route.EditProfile) }, Modifier.weight(1f), size = ButtonSize.Medium)
                            if (user.assessment != null || user.verifiedRating != null) {
                                BrutalButton(tr("分享等级卡片"), { showsLevelCard = true }, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium)
                            }
                        }
                    }
                    CompletenessRow(user, api)
                    StatsRow(user, api.winRate)
                    MenuCard {
                        val evaluations = user.reputation.evaluationCount
                        MenuRow(Sym.starFill, tr("口碑"), tint = AppTheme.colors.lime, value = if (evaluations == 0) null else tr("%lld 次评价", evaluations)) {
                            showReputation = true
                        }
                        InsetDivider()
                        // 球友数、待处理的申请在球友那一块（FriendManager）里，这里先不写数字
                        MenuRow(Sym.person2Fill, tr("我的球友"), tint = AppTheme.colors.sky) { router.open(Route.Friends) }
                        InsetDivider()
                        MenuRow(Sym.trophyFill, tr("排行榜"), tint = AppTheme.colors.butter) { router.open(Route.Leaderboard) }
                    }
                    MenuCard {
                        MenuRow(Sym.clockArrowCirclepath, tr("历史球局"), tint = AppTheme.colors.peach) { router.open(Route.GameHistory) }
                        InsetDivider()
                        MenuRow(
                            Sym.calendarBadgeClock, tr("常用时间"), tint = AppTheme.colors.butter,
                            value = "${slots.size}/${TimeSlotConstants.MAXIMUM_RECURRING_SLOTS}",
                        ) { router.open(Route.RecurringSlots) }
                        InsetDivider()
                        MenuRow(Sym.locationCircleFill, tr("附近范围"), tint = AppTheme.colors.sky, value = DistanceFormatter.radius(api.travelRadiusKm)) {
                            showRadius = true
                        }
                        InsetDivider()
                        MenuRow(Sym.heartFill, tr("球馆与收藏"), tint = AppTheme.colors.pink, value = "${appState.backend.favoriteVenueIds.size}") {
                            router.open(Route.Courts)
                        }
                        InsetDivider()
                        MenuRow(Sym.listNumber, tr("等级对照表"), tint = AppTheme.colors.lime) { router.open(Route.LevelGuide) }
                        InsetDivider()
                        MenuRow(Sym.handRaisedFill, tr("屏蔽名单"), tint = AppTheme.colors.surfaceMuted) { router.open(Route.BlockedUsers) }
                    }
                    MenuCard {
                        MenuRow(Sym.questionmarkBubbleFill, tr("帮助与反馈"), tint = AppTheme.colors.mint) { showHelp = true }
                        if (showsSupport) {
                            InsetDivider()
                            MenuRow(Sym.cupAndSaucerFill, tr("支持 Badie"), tint = AppTheme.colors.pink) { showTips = true }
                        }
                    }
                }
            }
        }
    }

    if (showsCardPreview && user != null) {
        MyCardPreview(user, api.recurringSlots(), api.favoriteVenues().firstOrNull(), api.strikes?.recent ?: 0) { showsCardPreview = false }
    }
    if (showsLevelCard) BadieSheet(onDismiss = { showsLevelCard = false }) { dismiss -> LevelCardSheet(null, dismiss) }
    if (showRadius) BadieSheet(onDismiss = { showRadius = false }) { dismiss -> TravelRadiusSheet(api, dismiss) }
    if (showHelp) BadieSheet(onDismiss = { showHelp = false }) { dismiss -> HelpSheet(api, dismiss) }
    if (showTips) BadieSheet(onDismiss = { showTips = false }) { dismiss -> TipJarSheet(dismiss) }
    if (showReputation) BadieSheet(onDismiss = { showReputation = false }) { ReputationSheet() }
}

/** 读“我的”页要的几样；哪样没读到不影响别的 */
private suspend fun refreshProfilePage(api: ProfileApi) {
    for (job in listOf<suspend () -> Unit>({ api.syncUsualTimes() }, { api.refreshRecord() }, { api.refreshStrikes() }, { api.refreshFavoriteVenues() })) {
        try {
            job()
        } catch (_: RemoteError) {
        }
    }
}

/** 待处理（没定级、爽约） */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TodoPills(user: User, api: ProfileApi) {
    val env = LocalEnv.current
    val strikes = api.strikes?.takeIf { it.recent > 0 || it.suspendedUntil != null }
    if (!user.needsAssessment && strikes == null) return
    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        if (user.needsAssessment) CountPill(Sym.checklist, tr("去定级"), 0) { env.router.open(Route.EditProfile) }
        if (strikes != null) {
            CountPill(Sym.exclamationmarkTriangleFill, strikes.suspensionText() ?: tr("爽约"), if (strikes.suspendedUntil == null) strikes.recent else 0) {
                env.appState.showsStrikes = true
            }
        }
    }
}

/** “资料 3/4 · 填空闲时间，更容易被约”：点了去编辑资料里缺的那一项；四项都有就不显示 */
@Composable
private fun CompletenessRow(user: User, api: ProfileApi) {
    val env = LocalEnv.current
    val missing = ProfileField.missing(user, api.recurringSlots(), hasVenue = env.appState.backend.favoriteVenueIds.isNotEmpty())
    val next = missing.firstOrNull() ?: return
    val total = ProfileField.entries.size
    val colors = AppTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .pressable {
                ProfileField.pendingFocus = next
                env.router.open(Route.EditProfile)
            }
            .defaultMinSize(minHeight = 44.dp)
            .drawBehind {
                val radius = CornerRadius(AppTheme.Radius.md.toPx())
                drawRoundRect(colors.surface, cornerRadius = radius)
                val w = 2.dp.toPx()
                drawRoundRect(
                    colors.stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), radius,
                    style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))),
                )
            }
            .padding(horizontal = AppTheme.Spacing.lg, vertical = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Text(tr("资料 %lld/%lld · %@", total - missing.size, total, next.hint), style = AppTheme.Typography.footnoteBold, color = colors.ink, modifier = Modifier.weight(1f))
        Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
    }
}

// MARK: 三个数字：场次 / 到场 / 胜率

@Composable
private fun StatsRow(user: User, rate: Rankings.WinRate?) {
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        StatTile("${user.totalGames}", tr("场次"), Modifier.weight(1f))
        StatTile("${user.attendance.reliabilityPercentage}%", tr("到场"), Modifier.weight(1f))
        WinRateTile(rate ?: Rankings.WinRate(0, 0, 0, 0.0), Modifier.weight(1f))
    }
}

/** 本月胜率：场数不够时显示“–”；怎么算、赢输几局都在“?”里。服务器只给本月的，所以没有“上月” */
@Composable
private fun WinRateTile(rate: Rankings.WinRate, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Column(
        modifier
            .sticker(colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            if (rate.isPublic) "${rate.percentage}%" else "–", style = rounded(24, FontWeight.Black).copy(fontFeatureSettings = "tnum"),
            color = colors.ink, maxLines = 1,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("胜率"), style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1)
            // “?”的点击区比字高，不让它把格子撑高（iPhone 用负的边距）
            RulesButton(
                tr("本月胜率"), winRatePoints(rate),
                Modifier.layout { measurable, constraints ->
                    val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
                    val trim = 8.dp.roundToPx()
                    layout(placeable.width, (placeable.height - 2 * trim).coerceAtLeast(0)) { placeable.place(0, -trim) }
                },
            )
        }
    }
}

@Composable
private fun winRatePoints(rate: Rankings.WinRate): List<String> = buildList {
    if (rate.isPublic) {
        add(tr("赢 %lld 局 · 输 %lld 局", rate.wonRounds, rate.playedRounds - rate.wonRounds))
    } else {
        add(tr("本月已确认 %lld 场，满 %lld 场显示胜率", rate.games, Rankings.WIN_RATE_MINIMUM_GAMES))
    }
    if (rate.games > 0) add(tr("%lld 场 · %lld 位不同对手 · %@", rate.games, rate.opponents, opponentStrengthText(rate.averageGap)))
    add(tr("只算双方都确认的比赛，每月 1 日重新计算；同一对手每月最多计入 %lld 场", Rankings.MONTHLY_SAME_OPPONENT_CAP))
}

@Composable
private fun opponentStrengthText(gap: Double): String {
    val levels = String.format(Locale.ROOT, "%.1f", abs(gap))
    return when {
        gap > 0.3 -> tr("对手平均比你强 %@ 级", levels)
        gap < -0.3 -> tr("对手平均比你弱 %@ 级", levels)
        else -> tr("对手和你水平相当")
    }
}

// MARK: - 我的口碑（“我的”页的一行点进来）

/** 本人看到客观记录（准时、水平校准、履约）和别人看到的印象；球品分对任何人都不显示 */
@Composable
private fun ReputationSheet() {
    val user = LocalEnv.current.appState.currentUser ?: return
    val reputation = user.reputation
    val record = user.attendance
    val colors = AppTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = AppTheme.Spacing.screen)
            .padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("我的口碑"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(tr("口碑怎么算"), reputationPoints(user))
            androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
            Text(
                if (reputation.evaluationCount == 0) tr("还没有评价") else tr("%lld 次匿名评价", reputation.evaluationCount),
                style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary,
            )
        }
        if (reputation.evaluationCount > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                StatTile(reputation.punctualityText, tr("准时到场"), Modifier.weight(1f))
                StatTile(reputation.deviationText, tr("等级偏差"), Modifier.weight(1f))
            }
        }
        Column(Modifier.card(shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Text(tr("球友眼中的你"), style = AppTheme.Typography.subheadlineBold, color = colors.ink)
            PraiseTagsView(reputation.publicTags, emptyText = tr("暂无印象"))
        }
        Column(Modifier.card(shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            if (user.isNewPlayer) {
                Text(tr("水平校准中 %lld/%lld", reputation.evaluationCount, ReputationScore.NEW_PLAYER_THRESHOLD), style = AppTheme.Typography.subheadlineBold, color = colors.ink)
                ProgressBar(reputation.evaluationCount.toFloat() / ReputationScore.NEW_PLAYER_THRESHOLD)
            } else {
                Text(tr("综合等级 %@", user.displayTier.text), style = AppTheme.Typography.subheadlineBold, color = colors.ink)
                ProgressBar((user.displayTier.index + 1).toFloat() / SkillTier.COUNT)
            }
        }
        Column(Modifier.card(shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("履约记录 · %@", record.standing.title), style = AppTheme.Typography.subheadlineBold, color = colors.ink)
            Text(
                tr("完成 %lld 场 · 爽约 %lld 次 · 临时取消 %lld 次", record.gamesPlayed, record.noShows, record.lateCancellations),
                style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary,
            )
        }
    }
}

/** 原来写在卡片上的说明都收到这里 */
@Composable
private fun reputationPoints(user: User): List<String> {
    val reputation = user.reputation
    val selfPercent = ((1 - user.peerWeight) * 100).roundToInt()
    val points = mutableListOf(tr("球友印象在 5 位以上球友评价后显示，每月更新一次"))
    if (user.isNewPlayer) {
        points += tr(
            "再打 %lld 场并获得评价后，等级将按“问卷 %lld%% + 球友评价 %lld%%”计算",
            ReputationScore.NEW_PLAYER_THRESHOLD - reputation.evaluationCount, selfPercent, 100 - selfPercent,
        ) + if (user.peerWeight > User.PEER_EVALUATION_WEIGHT) tr("（你的等级待校准，球友评价占比更高）") else ""
    } else {
        val source = if (user.verifiedRating == null) tr("问卷") else tr("认证")
        points += tr(
            "%@ %@ × %lld%% + 球友评价 %@ × %lld%%",
            source, SkillTier.ofRating(user.baseRating).text, selfPercent, SkillTier.ofRating(reputation.peerLevelAverage).text, 100 - selfPercent,
        ) + if (user.verifiedRating == null) "" else tr("，不超过认证档位")
    }
    points += user.attendance.standing.message
    points += tr("球品评分只用于匹配排序，任何人（包括你自己）都看不到分数")
    return points
}

// MARK: - 推进去的页面

@Composable
fun EditProfileScreen() = EditProfileView()

@Composable
fun RecurringSlotsScreen() = RecurringSlotsView()

/** 等级（“我的”里的等级对照表）：右上角分享等级卡片（定过级才有） */
@Composable
fun LevelGuideScreen() {
    val env = LocalEnv.current
    val user = env.appState.currentUser
    var showsLevelCard by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("等级"), onBack = { env.router.pop() }) {
            if (user != null && (user.assessment != null || user.verifiedRating != null)) {
                IconButton(Sym.squareAndArrowUp, tr("分享等级卡片")) { showsLevelCard = true }
            }
        }
        SkillLevelGuideView(user?.displayTier, Modifier.weight(1f))
    }
    if (showsLevelCard) BadieSheet(onDismiss = { showsLevelCard = false }) { dismiss -> LevelCardSheet(null, dismiss) }
}

@Composable
fun VerificationScreen() = VerificationView()
