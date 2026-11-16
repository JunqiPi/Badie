package com.badie.app.features.onboarding

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.SectionTitle
import com.badie.app.design.StickerTextField
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.models.Coordinate
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.Venue
import kotlinx.coroutines.delay

/**
 * 选常去球馆（最多 3 家）：上面是已选的，下面是附近的；打字就按名字搜（服务器的 search_venues，不认街道地址）。
 * 对应 iPhone 的 VenuePickerView 的多选模式。iPhone 上找不到时可以自己加球馆，安卓要等球馆那一步（地图）做好
 */
@Composable
fun VenuePicker(model: OnboardingModel, onDone: () -> Unit) {
    val colors = AppTheme.colors
    var query by remember { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<Venue>?>(null) }
    // 打字时等一下再搜（连续输入只搜最后一次）
    LaunchedEffect(query) {
        if (query.isBlank()) {
            hits = null
            return@LaunchedEffect
        }
        delay(300)
        hits = model.searchVenues(query)
    }
    val center = model.location ?: Coordinate.fallbackCenter
    val selected = model.favoriteVenueIds.mapNotNull(model::venue)
    val radius = tr("%@内", DistanceFormatter.radius(Venue.DEFAULT_TRAVEL_RADIUS_KM))

    Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(tr("选择球馆"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.semantics { heading() })
                Text(tr("已选 %lld/%lld", selected.size, MAX_FAVORITE_VENUES), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
            BrutalButton(tr("完成"), onDone, size = ButtonSize.Small, fullWidth = false)
        }
        StickerTextField(
            query, { query = it }, tr("搜索球馆"),
            modifier = Modifier.padding(horizontal = AppTheme.Spacing.screen),
            style = AppTheme.Typography.body,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
            trailing = if (query.isEmpty()) null else {
                {
                    val label = tr("清除搜索")
                    Box(
                        Modifier.size(44.dp).clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { query = "" }
                            .semantics { contentDescription = label },
                        contentAlignment = Alignment.Center,
                    ) { Symbol(Sym.xmarkCircleFill, size = 17, tint = colors.inkTertiary) }
                }
            },
        )
        LazyColumn(
            Modifier.fillMaxWidth(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(AppTheme.Spacing.screen),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            val found = hits
            if (found != null) {
                item {
                    if (found.isEmpty()) {
                        EmptyStateView(Sym.magnifyingglass, tr("没有找到“%@”", query.trim()))
                    } else {
                        VenueSection(null, null, found, model, center)
                    }
                }
            } else {
                if (selected.isNotEmpty()) item { VenueSection(tr("已选"), null, selected, model, center) }
                val nearby = model.nearbyVenues.filter { it.id !in model.favoriteVenueIds }
                item {
                    if (nearby.isNotEmpty()) {
                        VenueSection(tr("附近"), radius, nearby, model, center)
                    } else if (selected.isEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                            Symbol(Sym.mappinSlash, size = 13, tint = colors.inkSecondary)
                            Text(tr("%@还没有收录的球馆", radius), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VenueSection(title: String?, detail: String?, venues: List<Venue>, model: OnboardingModel, center: Coordinate) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        if (title != null) SectionTitle(title, detail = detail)
        Column(Modifier.fillMaxWidth().sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md)) {
            venues.forEachIndexed { index, venue ->
                if (index > 0) InsetDivider()
                VenueRow(venue, DistanceFormatter.string(venue.distanceKm(center)), isOn = venue.id in model.favoriteVenueIds) { model.toggleVenue(venue.id) }
            }
        }
    }
}

/** 一家球馆：名字、距离、地址（用来确认是不是这一家），右边是勾选框 */
@Composable
fun VenueRow(venue: Venue, distance: String, isOn: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    Row(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 64.dp)
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Checkbox) {
                haptics.selection()
                onClick()
            }
            .semantics(mergeDescendants = true) { selected = isOn }
            .padding(vertical = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.figureBadminton, fill = if (isOn) colors.lime else colors.surfaceMuted, size = 42.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(venue.name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
                Spacer(Modifier.size(AppTheme.Spacing.sm))
                Text(distance, style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = colors.inkSecondary)
            }
            if (venue.compactAddress.isNotEmpty()) {
                Text(venue.compactAddress, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
        }
        Symbol(if (isOn) Sym.checkmarkSquareFill else Sym.square, size = 22, tint = if (isOn) colors.ink else colors.inkTertiary)
    }
}
