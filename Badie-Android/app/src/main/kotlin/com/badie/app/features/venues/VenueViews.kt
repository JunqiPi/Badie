package com.badie.app.features.venues

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.badie.app.backend.VenueDuplicate
import com.badie.app.design.AppTheme
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.LoadingDots
import com.badie.app.design.SectionTitle
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.tr
import com.badie.app.location.LocationProvider
import com.badie.app.models.DistanceFormatter
import com.badie.app.models.PostalAddress
import com.badie.app.models.Venue
import com.badie.app.models.VenueStatus
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv

// 球馆的小部件：可信度标记、球馆行、地址块、“是不是这一家？”。对应 iPhone 的 Features/Venues/VenueViews.swift

// MARK: - 打开球馆页时取位置

/** 第一次打开时问定位权限（问过就不再问，和 iPhone 的 start() 一样），然后取位置、拉附近的球馆 */
@Composable
fun StartLocation() {
    val locationManager = LocalEnv.current.locationManager
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        locationManager.permissionAnswered(result.values.any { it })
    }
    LaunchedEffect(Unit) {
        if (locationManager.canLocate && !locationManager.isAuthorized && !locationManager.hasAskedPermission) {
            launcher.launch(LocationProvider.PERMISSIONS)
        }
        try {
            locationManager.start()
        } catch (_: RemoteError) {
        }
    }
}

// MARK: - 可信度标记

@Composable
fun VenueStatusBadge(status: VenueStatus) {
    val colors = AppTheme.colors
    val fill = when (status) {
        VenueStatus.Verified -> colors.mint
        VenueStatus.Confirmed -> colors.sky
        VenueStatus.Unconfirmed -> colors.butter
    }
    val label = when (status) {
        VenueStatus.Verified -> tr("平台已核实地址")
        VenueStatus.Confirmed -> tr("多位球友确认过地址")
        VenueStatus.Unconfirmed -> tr("新添加，地址待确认")
    }
    TagPill(status.title, Modifier.semantics { contentDescription = label }, icon = status.icon, fill = fill)
}

// MARK: - 高亮搜索词

/** 名称中和搜索词对上的部分加粗、加柠檬底色，一眼能核对 */
@Composable
fun highlighted(text: String, query: String): AnnotatedString {
    val range = VenueSearch.matchRange(text, query) ?: return AnnotatedString(text)
    val colors = AppTheme.colors
    return buildAnnotatedString {
        append(text.substring(0, range.first))
        withStyle(SpanStyle(background = colors.lime.copy(alpha = 0.55f), color = colors.ink)) { append(text.substring(range.first, range.last + 1)) }
        append(text.substring(range.last + 1))
    }
}

// MARK: - 球馆行：名称 + 完整地址 + 距离/场地数/常去人数

sealed interface VenueAccessory {
    data object None : VenueAccessory
    data object Chevron : VenueAccessory
    data class Checkbox(val isOn: Boolean) : VenueAccessory
    data class Radio(val isOn: Boolean) : VenueAccessory
}

@Composable
fun VenueRow(
    venue: Venue,
    distance: String,
    modifier: Modifier = Modifier,
    regulars: Int = 0,
    isFavorite: Boolean = false,
    query: String = "",
    accessory: VenueAccessory = VenueAccessory.Chevron,
    isClosedForSlot: Boolean = false,
    trailingOverlay: (@Composable () -> Unit)? = null,
) {
    val colors = AppTheme.colors
    val isOn = (accessory as? VenueAccessory.Checkbox)?.isOn == true || (accessory as? VenueAccessory.Radio)?.isOn == true
    Row(
        modifier.fillMaxWidth().padding(vertical = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.figureBadminton, fill = if (isOn) colors.lime else colors.sky, size = 42.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(highlighted(venue.name, query), style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f, fill = false))
                    if (isFavorite) {
                        val label = tr("常去")
                        Box(Modifier.semantics { contentDescription = label }) { Symbol(Sym.heartFill, size = 11, tint = colors.dangerFill) }
                    }
                }
                Spacer(Modifier.width(AppTheme.Spacing.sm))
                Text(distance, style = AppTheme.Typography.footnoteBold.copy(fontFeatureSettings = "tnum"), color = colors.inkSecondary, maxLines = 1)
            }
            VenueSearch.matchedAlias(venue, query)?.let { alias ->
                Text(tr("又名 %@", alias), style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Bold), color = colors.inkSecondary)
            }
            // 完整地址，用来确认“是不是这一家”
            if (venue.compactAddress.isNotEmpty()) {
                Text(highlighted(venue.compactAddress, query), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                VenueStatusBadge(venue.status)
                val meta = listOfNotNull(
                    venue.courtCount?.let { tr("%lld 片场地", it) },
                    regulars.takeIf { it > 0 }?.let { tr("%lld 人常去", it) },
                ).joinToString(" · ")
                if (meta.isNotEmpty()) {
                    Text(meta, style = AppTheme.Typography.caption, color = colors.inkTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (isClosedForSlot) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Symbol(Sym.moonZzzFill, size = 11, tint = colors.danger)
                    Text(tr("所选时段不营业"), style = AppTheme.Typography.caption.copy(fontWeight = FontWeight.Bold), color = colors.danger)
                }
            }
            if (trailingOverlay != null) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { trailingOverlay() }
        }
        when (accessory) {
            VenueAccessory.None -> {}
            VenueAccessory.Chevron -> Symbol(Sym.chevronRight, size = 13, tint = colors.inkTertiary)
            is VenueAccessory.Checkbox ->
                Symbol(if (accessory.isOn) Sym.checkmarkSquareFill else Sym.square, size = 22, tint = if (accessory.isOn) colors.ink else colors.inkTertiary)
            is VenueAccessory.Radio ->
                Symbol(if (accessory.isOn) Sym.largecircleFillCircle else Sym.circle, size = 22, tint = if (accessory.isOn) colors.ink else colors.inkTertiary)
        }
    }
}

/** 一组球馆：标题 + 白色卡片里一行一家 */
@Composable
fun VenueSection(title: String?, detail: String?, venues: List<Venue>, row: @Composable (Venue) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        if (title != null) SectionTitle(title, detail = detail)
        Column(Modifier.fillMaxWidth().sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md)) {
            venues.forEachIndexed { index, venue ->
                if (index > 0) InsetDivider()
                row(venue)
            }
        }
    }
}

// MARK: - 地址搜索的结果行（还不在球馆库里）

@Composable
fun MapResultRow(title: String, subtitle: String, modifier: Modifier = Modifier, query: String = "", isLoading: Boolean = false) {
    val colors = AppTheme.colors
    Row(
        modifier.fillMaxWidth().padding(vertical = AppTheme.Spacing.md).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        IconTile(Sym.mappinAndEllipse, Modifier.padding(top = 2.dp), fill = colors.surfaceMuted, size = 42.dp, iconColor = colors.ink)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(highlighted(title, query), style = AppTheme.Typography.headline, color = colors.ink)
            Text(subtitle.ifEmpty { tr("地址待确认") }, style = AppTheme.Typography.footnote, color = colors.inkSecondary)
        }
        if (isLoading) LoadingDots() else Symbol(Sym.plusCircleFill, size = 22, tint = colors.ink)
    }
}

// MARK: - 地址块（大字、可复制）

@Composable
fun VenueAddressBlock(address: PostalAddress) {
    val colors = AppTheme.colors
    val context = LocalContext.current
    val appState = LocalEnv.current.appState
    val haptics = rememberHaptics()
    val copied = tr("地址已复制")
    val copyLabel = tr("复制地址")
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(address.streetLine, style = AppTheme.Typography.bodyBold, color = colors.ink)
            Text(address.cityLine, style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
        }
        Box(
            Modifier.size(44.dp).pressable {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                clipboard?.setPrimaryClip(ClipData.newPlainText(copyLabel, address.singleLine))
                haptics.success()
                appState.showToast(copied, Toast.Style.Success)
            }.semantics { contentDescription = copyLabel },
            contentAlignment = Alignment.Center,
        ) { Symbol(Sym.docOnDoc, size = 15, tint = colors.ink) }
    }
}

// MARK: - “是不是这一家？”查重列表

@Composable
fun DuplicateChoiceList(duplicates: List<VenueDuplicate>, onChoose: (Venue) -> Unit) {
    val colors = AppTheme.colors
    val blocksAdding = duplicates.any { it.kind.blocksAdding }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Symbol(Sym.exclamationmarkTriangleFill, size = 15, tint = colors.ink)
            Text(
                if (blocksAdding) tr("球馆库里已有这家球馆") else tr("同一位置已有球馆，是同一个吗？"),
                style = AppTheme.Typography.headline, color = colors.ink,
            )
        }
        Text(
            if (blocksAdding) {
                tr("名称和位置都跟已有球馆太接近，请直接选择它。大家选同一个球馆才能匹配到一起。")
            } else {
                tr("选同一个球馆，大家才能匹配到一起。如果是同楼的另一家，可以继续添加。")
            },
            style = AppTheme.Typography.footnote, color = colors.inkSecondary,
        )
        VenueSection(null, null, duplicates.map { it.venue }) { venue ->
            val duplicate = duplicates.first { it.venue.id == venue.id }
            VenueRow(
                venue, tr("相距 %@", DistanceFormatter.string(duplicate.distanceMeters / 1000)),
                Modifier.pressable(scale = 0.98f) { onChoose(venue) },
                accessory = VenueAccessory.None,
                trailingOverlay = {
                    Text(
                        tr("是这个"), style = AppTheme.Typography.footnoteBold, color = colors.onAccent,
                        modifier = Modifier.sticker(colors.lime, radius = 14.dp, shadow = AppTheme.Elevation.none, strokeWidth = 1.5.dp)
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                },
            )
        }
    }
}
