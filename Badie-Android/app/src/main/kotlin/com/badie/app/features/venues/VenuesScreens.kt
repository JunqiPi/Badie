package com.badie.app.features.venues

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.LoadingDots
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SectionTitle
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.pressable
import com.badie.app.design.rounded
import com.badie.app.l10n.tr
import com.badie.app.models.UserPreferences
import com.badie.app.models.Venue
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RefreshEverything
import com.badie.app.shell.Route
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

// 球馆这一块的页面。入口的名字和参数不要改（shell/MainTabView.kt 按这些名字接页面）。
// 对应的 iPhone 源文件：Features/Venues/*.swift, Features/Courts/CourtsView.swift

/** 附近球馆：列表（每行带地址），可搜索、添加、收藏、看详情、导航。iPhone 上面还有一张地图 */
@Composable
fun CourtsScreen() {
    val env = LocalEnv.current
    val router = env.router
    val locationManager = env.locationManager
    var showRadius by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    StartLocation()

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("附近球馆"), onBack = { router.pop() }) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                IconButton(Sym.magnifyingglass, tr("搜索球馆")) { showSearch = true }
                IconButton(Sym.sliderHorizontal3, tr("附近范围")) { showRadius = true }
            }
        }
        // TODO(地图)：iPhone 这里是 260 高的地图（球馆图钉、我的位置、范围圆），点列表行时地图移过去。要等 Google 地图的 key
        RefreshEverything(Modifier.weight(1f)) {
            CourtsList(
                locationManager.nearbyCourts,
                onSearch = { showSearch = true },
                onOpen = { router.open(Route.Venue(it.id)) },
                onAdd = { router.open(Route.AddVenue) },
            )
        }
    }
    if (showRadius) {
        SheetScaffold(onDismiss = { showRadius = false }) { TravelRadiusSheet { showRadius = false } }
    }
    if (showSearch) {
        VenuePickerSheet(VenuePickerMode.Browse, emptyList(), {}, onDismiss = { showSearch = false })
    }
}

@Composable
internal fun CourtsList(courts: List<Venue>, onSearch: () -> Unit, onOpen: (Venue) -> Unit, onAdd: () -> Unit) {
    val locationManager = LocalEnv.current.locationManager
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        SectionTitle(tr("%lld 家球馆", courts.size), detail = locationManager.radiusText)
        if (courts.isEmpty()) {
            EmptyStateView(
                Sym.mappinSlash, tr("%@还没有收录的球馆", locationManager.radiusText),
                actionTitle = tr("搜索球馆"), action = onSearch,
            )
        } else {
            VenueSection(null, null, courts) { court ->
                VenueRow(
                    court, court.formattedDistance(locationManager.coordinate),
                    Modifier.pressable(scale = 0.98f) { onOpen(court) },
                    regulars = locationManager.regularsCount(court.id),
                    isFavorite = locationManager.isFavorite(court.id),
                )
            }
        }
        AddVenueButton(Modifier.padding(top = AppTheme.Spacing.sm), onClick = onAdd)
    }
}

/** 球馆页（详情） */
@Composable
fun VenueScreen(id: String) {
    val env = LocalEnv.current
    val router = env.router
    val locationManager = env.locationManager
    val cached = locationManager.court(id)
    var loaded by remember(id) { mutableStateOf(cached) }
    var finished by remember(id) { mutableStateOf(cached != null) }
    LaunchedEffect(id) {
        if (loaded == null) {
            loaded = try {
                locationManager.loadCourt(id)
            } catch (_: RemoteError) {
                null
            }
            finished = true
        }
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("", onBack = { router.pop() })
        val venue = cached ?: loaded
        when {
            venue != null -> VenueDetailView(venue)
            !finished -> Box(Modifier.fillMaxWidth().padding(AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) { LoadingDots() }
            else -> EmptyStateView(Sym.mappinSlash, tr("没有找到这个球馆"))
        }
    }
}

/** 快速匹配选球馆（最多 3 家）：直接改 MatchManager 的 draftVenueIds */
@Composable
fun MatchVenuesScreen(query: String?) {
    val env = LocalEnv.current
    val router = env.router
    val selection = env.matchManager.draftVenueIds
    VenuePickerView(
        VenuePickerMode.Multiple(MAX_MATCH_VENUES),
        selection = selection.toList(),
        onSelectionChange = { ids ->
            selection.retainAll(ids.toSet())
            for (id in ids) if (id !in selection) selection.add(id)
        },
        onDismiss = { router.pop() },
        modifier = Modifier.fillMaxSize(),
        initialQuery = query.orEmpty(),
        onOpen = { router.open(Route.Venue(it.id)) },
    )
}

/** 添加球馆（整页）：加好以后换成这家球馆的球馆页 */
@Composable
fun AddVenueScreen() {
    val env = LocalEnv.current
    val router = env.router
    val draft = remember { AddVenueDraft("", env.locationManager.coordinate) }
    AddVenueContent(draft, onClose = { router.pop() }) { venue ->
        router.pop()
        router.open(Route.Venue(venue.id))
    }
}

// MARK: - 附近范围（公里/英里跟着设备的地区）：只管“附近”显示多远，不影响匹配

@Composable
fun TravelRadiusSheet(onDone: () -> Unit) {
    val locationManager = LocalEnv.current.locationManager
    val colors = AppTheme.colors
    val unit = locationManager.distanceUnit
    val low = maxOf(1f, ceil(unit.value(UserPreferences.MINIMUM_TRAVEL_RADIUS)).toFloat())
    val high = floor(unit.value(UserPreferences.MAXIMUM_TRAVEL_RADIUS)).toFloat()
    var value by remember {
        mutableFloatStateOf(unit.value(locationManager.preferences.travelRadiusKm).roundToInt().toFloat().coerceIn(low, high))
    }
    val label = tr("附近范围")
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(label, listOf(tr("附近的球馆、球局和球群按这个范围显示。"), tr("匹配只看你选的球馆，搜索也不受范围限制。")))
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${value.roundToInt()}", style = rounded(48, FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = colors.ink, modifier = Modifier.alignByBaseline())
            Text(tr("%@内", unit.title), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.alignByBaseline())
        }
        val valueText = "${value.roundToInt()} ${unit.title}"
        Slider(
            value, { value = it.roundToInt().toFloat() },
            Modifier.semantics { contentDescription = label; stateDescription = valueText },
            valueRange = low..high,
            steps = (high - low).toInt() - 1,
            colors = SliderDefaults.colors(
                thumbColor = colors.ink, activeTrackColor = colors.ink, inactiveTrackColor = colors.surfaceMuted,
                activeTickColor = colors.ink.copy(alpha = 0f), inactiveTickColor = colors.ink.copy(alpha = 0f),
            ),
        )
        BrutalButton(tr("完成"), {
            val km = unit.km(value.toDouble()).coerceIn(UserPreferences.MINIMUM_TRAVEL_RADIUS, UserPreferences.MAXIMUM_TRAVEL_RADIUS)
            locationManager.updateTravelRadius(km)
            onDone()
        })
    }
}
