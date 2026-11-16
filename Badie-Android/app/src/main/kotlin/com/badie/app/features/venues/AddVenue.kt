package com.badie.app.features.venues

import android.content.ClipboardManager
import android.content.Context
import android.location.Address
import android.location.Geocoder
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.badie.app.backend.VenueCandidate
import com.badie.app.backend.VenueDuplicate
import com.badie.app.backend.addVenue
import com.badie.app.backend.venueDuplicates
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.BrutalTextField
import com.badie.app.design.IconButton
import com.badie.app.design.InsetDivider
import com.badie.app.design.LoadingDots
import com.badie.app.design.RulesButton
import com.badie.app.design.Sym
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.AddressStyle
import com.badie.app.models.Coordinate
import com.badie.app.models.CountryInfo
import com.badie.app.models.PostalAddress
import com.badie.app.models.Venue
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.ZoneId
import java.util.Locale

/**
 * 手动添加球馆：核对图钉处的地址（可改）→ 填名称 → 查重 → 加入。也可以搜地址移动图钉，或粘贴 Google / Apple 地图链接。
 * 对应 iPhone 的 Features/Venues/AddVenueView.swift。
 *
 * 和 iPhone 不同：还没有地图（要 Google 地图的 key），图钉不能拖。图钉一开始在我的位置（没定位时在默认城市），
 * 搜地址、粘贴链接会移动它；手动改了地址的，添加前按地址重新找一次坐标。
 */
@Composable
fun AddVenueContent(draft: AddVenueDraft, onClose: () -> Unit, onAdded: (Venue) -> Unit) {
    val env = LocalEnv.current
    val appState = env.appState
    val locationManager = env.locationManager
    val backend = appState.backend
    val colors = AppTheme.colors
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val geocoding = remember { Geocoding(context) }

    var pin by remember { mutableStateOf(draft.coordinate) }
    /** 图钉在真实的位置上（定位、链接、搜到的地址），不是默认城市 */
    var pinKnown by remember { mutableStateOf(draft.fromLink || locationManager.currentLocation != null) }
    var address by remember { mutableStateOf<PostalAddress?>(null) }
    var isGeocoding by remember { mutableStateOf(false) }
    var editsAddress by remember { mutableStateOf(false) }
    /** 手动改过地址：添加前按地址再找一次坐标 */
    var addressTyped by remember { mutableStateOf(false) }
    var addressQuery by remember { mutableStateOf("") }
    var addressHits by remember { mutableStateOf<List<Geocoding.Place>>(emptyList()) }

    var name by remember { mutableStateOf(draft.name) }
    var alias by remember { mutableStateOf("") }
    var unit by remember { mutableStateOf("") }
    var entranceNote by remember { mutableStateOf("") }
    var courtCount by remember { mutableIntStateOf(0) }

    var street by remember { mutableStateOf("") }
    var city by remember { mutableStateOf("") }
    var region by remember { mutableStateOf("") }
    var postalCode by remember { mutableStateOf("") }

    var duplicates by remember { mutableStateOf<List<VenueDuplicate>>(emptyList()) }
    var checkedDuplicates by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var geocodeRequest by remember { mutableIntStateOf(if (pinKnown) 1 else 0) }

    fun apply(resolved: PostalAddress) {
        address = resolved
        resolved.unit?.let { unit = it }
        street = resolved.street
        city = resolved.city
        region = resolved.region
        postalCode = resolved.postalCode
        addressTyped = false
    }

    fun resetDuplicates() {
        checkedDuplicates = false
        duplicates = emptyList()
    }

    // 识别图钉处的地址（移动图钉后等一下再识别）
    LaunchedEffect(geocodeRequest) {
        if (geocodeRequest == 0) return@LaunchedEffect
        isGeocoding = true
        delay(350)
        val result = geocoding.reverse(pin)
        isGeocoding = false
        if (result != null) {
            apply(result)
        } else {
            address = null
            street = ""; city = ""; region = ""; postalCode = ""
        }
    }
    // 搜地址（最多 5 条）
    LaunchedEffect(addressQuery) {
        val text = addressQuery.trim()
        if (text.isEmpty()) {
            addressHits = emptyList()
            return@LaunchedEffect
        }
        delay(300)
        addressHits = geocoding.search(text)
    }

    fun move(to: Coordinate) {
        pin = to
        pinKnown = true
        resetDuplicates()
    }

    val trimmedName = name.trim()
    val composedAddress: PostalAddress? = run {
        val country = address?.countryCode ?: CountryInfo.deviceCountry.code
        if (street.isEmpty() && city.isEmpty()) address
        else PostalAddress.create(street, unit, city, region, postalCode, country)
    }
    val nameLength = trimmedName.codePointCount(0, trimmedName.length)
    val canSubmit = nameLength in 2..60 && composedAddress?.isComplete == true && !isGeocoding && !isSaving
    val isBlocked = duplicates.any { it.kind.blocksAdding }
    val submitHint = when {
        isBlocked -> tr("如果确实是另一家，请改用能区分的名称（如分店名）")
        trimmedName.isEmpty() -> null
        nameLength < 2 -> tr("填写球馆名称")
        !isGeocoding && composedAddress?.isComplete != true -> tr("需要街道和城市，方便别人确认位置")
        else -> null
    }

    fun submit() {
        val finalAddress = composedAddress ?: return
        scope.launch {
            isSaving = true
            try {
                // 没有地图可以拖：地址是手打的、或者图钉还在默认城市，就按地址找坐标
                if (addressTyped || !pinKnown) {
                    val found = geocoding.search(finalAddress.singleLine).firstOrNull()
                    if (found != null) {
                        pin = found.location
                        pinKnown = true
                    } else if (!pinKnown) {
                        appState.showToast(L10n.tr("没找到这个地址"), Toast.Style.Error)
                        return@launch
                    }
                }
                val candidate = VenueCandidate(trimmedName, pin, finalAddress, timeZoneId = ZoneId.systemDefault().id)
                if (!checkedDuplicates) {
                    duplicates = backend.venueDuplicates(candidate)
                    checkedDuplicates = true
                    if (duplicates.isNotEmpty()) {
                        haptics.error()
                        return@launch
                    }
                }
                if (duplicates.any { it.kind.blocksAdding }) return@launch
                val venue = backend.addVenue(candidate, listOf(alias), courtCount.takeIf { it > 0 }, entranceNote)
                locationManager.courtAdded(venue)
                haptics.success()
                appState.showToast(L10n.tr("已添加：%@，等球友确认", venue.name), Toast.Style.Success)
                onAdded(venue)
            } catch (error: RemoteError) {
                appState.showError(error)
            } finally {
                isSaving = false
            }
        }
    }

    fun pasteLink() {
        val text = (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)
            ?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
        if (text.isNullOrBlank()) return
        scope.launch {
            var url = MapLinkParser.firstMapURL(text)
            if (url == null) {
                addressQuery = text.trim()
                return@launch
            }
            if (MapLinkParser.needsExpansion(url)) MapLinkParser.expand(url)?.let { url = it }
            val link = url?.let(MapLinkParser::parse)
            if (link == null) {
                appState.showToast(L10n.tr("没能识别这个地图链接"), Toast.Style.Error)
                return@launch
            }
            if (link.name != null && trimmedName.isEmpty()) name = link.name
            val coordinate = link.coordinate
            if (coordinate != null) {
                move(coordinate)
                geocodeRequest++
            } else {
                (link.query ?: link.name)?.let { addressQuery = it }
            }
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(tr("添加球馆"), style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(
                tr("添加球馆"),
                listOf(
                    tr("放好图钉、核对地址，其他球友才能找到同一个地方。"),
                    tr("移动地图，让图钉对准球馆入口，工业区、学校里的场馆尤其要对准。"),
                    tr("添加时会检查附近有没有同一家。"),
                    tr("添加后显示“待确认”，3 位球友确认后显示“球友确认”。"),
                ),
            )
            Spacer(Modifier.weight(1f))
            IconButton(Sym.xmark, tr("关闭"), onClick = onClose)
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            // 查重结果放在最上面：点“添加”后第一眼就能看到
            if (duplicates.isNotEmpty()) DuplicateChoiceList(duplicates, onAdded)

            // 找位置：搜地址、粘贴地图链接
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    SearchField(addressQuery, { addressQuery = it }, tr("搜索地址，快速移动图钉"), Modifier.weight(1f))
                    IconButton(Sym.docOnClipboard, tr("粘贴地图链接"), onClick = ::pasteLink)
                }
                if (addressHits.isNotEmpty() && addressQuery.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md)) {
                        addressHits.take(5).forEachIndexed { index, place ->
                            if (index > 0) InsetDivider()
                            MapResultRow(
                                place.title, place.address.compactLine,
                                Modifier.pressable(scale = 0.98f) {
                                    addressQuery = ""
                                    addressHits = emptyList()
                                    move(place.location)
                                    apply(place.address)
                                },
                                query = addressQuery,
                            )
                        }
                    }
                }
                // TODO(地图)：iPhone 这里是 260 高的地图，图钉固定在中间，拖地图移动图钉、松手后识别地址。
                // 安卓要等 Google 地图的 key（见 REQUIREMENTS.md 8.2），到时候在这里放地图，拖动后 move(中心点) 再 geocodeRequest++
            }

            // 图钉处的地址
            Column(
                Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(AppTheme.Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(tr("图钉处的地址"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, modifier = Modifier.weight(1f))
                    TextAction(if (editsAddress) tr("收起") else tr("修改"), { editsAddress = !editsAddress })
                }
                val current = composedAddress
                when {
                    isGeocoding -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        LoadingDots()
                        Text(tr("正在识别地址…"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                    }
                    current != null && current.isComplete -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(current.streetLine, style = AppTheme.Typography.bodyBold, color = colors.ink)
                        Text(current.cityLine, style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
                    }
                    else -> Text(tr("没识别到街道地址，请移动图钉或点“修改”手动填写"), style = AppTheme.Typography.footnote, color = colors.danger)
                }
                if (editsAddress) {
                    Column(Modifier.padding(top = AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                        fun typed(set: (String) -> Unit): (String) -> Unit = { value ->
                            set(value)
                            addressTyped = true
                            resetDuplicates()
                        }
                        BrutalTextField(tr("街道门牌"), tr("例：10410 Valley Blvd"), street, typed { street = it })
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                            BrutalTextField(tr("城市"), tr("例：El Monte"), city, typed { city = it }, Modifier.weight(1f))
                            BrutalTextField(tr("州/省"), "CA", region, typed { region = it }, Modifier.width(110.dp))
                        }
                        BrutalTextField(
                            tr("邮编"), "91731", postalCode, typed { postalCode = it },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                        )
                    }
                }
            }

            // 名称和说明
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                BrutalTextField(tr("球馆名称"), tr("例：Los Angeles Badminton Club"), name, {
                    name = it.take(60)
                    // 改了名称要重新查重
                    if (checkedDuplicates) resetDuplicates()
                }, characterLimit = 60)
                BrutalTextField(tr("常用简称（选填）"), tr("例：LABC、洛羽"), alias, { alias = it.take(20) }, characterLimit = 20)
                BrutalTextField(tr("单元/楼层（选填）"), tr("例：Unit B、2F"), unit, { unit = it.take(20) }, characterLimit = 20)
                BrutalTextField(tr("入口说明（选填）"), tr("例：从后门进，停车场在侧面"), entranceNote, { entranceNote = it.take(80) }, characterLimit = 80)
                CourtCountStepper(courtCount) { courtCount = it }
            }
        }

        // 底部按钮
        Column(Modifier.fillMaxWidth()) {
            InsetDivider()
            Column(
                Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen, vertical = AppTheme.Spacing.md),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                BrutalButton(
                    when {
                        isBlocked -> tr("请选择上面已有的球馆")
                        checkedDuplicates && duplicates.isNotEmpty() -> tr("加新球馆")
                        else -> tr("添加")
                    },
                    ::submit,
                    enabled = canSubmit && !isBlocked,
                )
                if (submitHint != null) Text(submitHint, style = AppTheme.Typography.caption, color = colors.inkTertiary)
            }
        }
    }
}

/** 场地数 0–40（0 = 不确定）：两个按钮加减 */
@Composable
private fun CourtCountStepper(value: Int, onChange: (Int) -> Unit) {
    val colors = AppTheme.colors
    val label = tr("场地数")
    val text = if (value == 0) tr("不确定") else tr("%lld 片", value)
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
            contentDescription = label
            stateDescription = text
            progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), 0f..40f, steps = 39)
            setProgress { target ->
                onChange(target.toInt().coerceIn(0, 40))
                true
            }
        },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr("场地数（选填）"), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
            Text(text, style = AppTheme.Typography.bodyBold, color = colors.ink)
        }
        Row(
            Modifier.sticker(colors.surface, radius = 14.dp, shadow = AppTheme.Elevation.none).clearAndSetSemantics {},
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StepperHalf(Sym.minus, enabled = value > 0) { onChange(value - 1) }
            Box(Modifier.size(width = 1.5.dp, height = 24.dp).background(colors.divider))
            StepperHalf(Sym.plus, enabled = value < 40) { onChange(value + 1) }
        }
    }
}

@Composable
private fun StepperHalf(symbol: com.badie.app.design.SymbolId, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(width = 52.dp, height = 40.dp).pressable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        com.badie.app.design.Symbol(symbol, size = 17, tint = if (enabled) AppTheme.colors.ink else AppTheme.colors.inkTertiary)
    }
}

/**
 * 地址和坐标互查：用系统自带的地理编码（不花钱、不要 key）。系统没有这项服务、或者没网时返回空。
 * iPhone 用 Apple 地图做这件事；这里的结果质量要上真机再看
 */
class Geocoding(private val context: Context) {
    data class Place(val title: String, val location: Coordinate, val address: PostalAddress)

    private val geocoder: Geocoder? get() = if (Geocoder.isPresent()) Geocoder(context, Locale.getDefault()) else null

    /** 坐标 → 地址 */
    suspend fun reverse(coordinate: Coordinate): PostalAddress? = withContext(Dispatchers.IO) {
        val found = try {
            @Suppress("DEPRECATION")
            geocoder?.getFromLocation(coordinate.latitude, coordinate.longitude, 1)
        } catch (_: Exception) {
            null
        }
        found?.firstOrNull()?.let(::postalAddress)?.takeIf { it.isComplete }
    }

    /** 地址 → 最多 5 个地点 */
    suspend fun search(query: String): List<Place> = withContext(Dispatchers.IO) {
        val found = try {
            @Suppress("DEPRECATION")
            geocoder?.getFromLocationName(query, 5)
        } catch (_: Exception) {
            null
        }
        found.orEmpty().filter { it.hasLatitude() && it.hasLongitude() }.map { item ->
            val address = postalAddress(item)
            Place(item.featureName?.takeIf { it != item.subThoroughfare } ?: address.streetLine, Coordinate(item.latitude, item.longitude), address)
        }
    }

    companion object {
        /** 系统的地址换成分字段的地址（东亚地址门牌在街道后面，和 iPhone 的 VenueCandidate(mapItem:) 一样） */
        fun postalAddress(item: Address): PostalAddress {
            val country = item.countryCode ?: CountryInfo.deviceCountry.code
            val eastAsian = CountryInfo.info(country).addressStyle == AddressStyle.LargeToSmall
            val western = listOfNotNull(item.subThoroughfare, item.thoroughfare).joinToString(" ")
            return PostalAddress.create(
                street = if (eastAsian) listOfNotNull(item.thoroughfare, item.subThoroughfare).joinToString("") else western.ifEmpty { item.featureName.orEmpty() },
                city = if (eastAsian) item.subLocality ?: item.locality.orEmpty() else item.locality ?: item.subLocality.orEmpty(),
                region = if (eastAsian) item.locality ?: item.adminArea.orEmpty() else item.adminArea.orEmpty(),
                postalCode = item.postalCode.orEmpty(),
                countryCode = country,
            )
        }
    }
}
