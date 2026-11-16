package com.badie.app.features.venues

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.LoadingDots
import com.badie.app.design.RulesButton
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StickerTextField
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.Toast
import com.badie.app.design.rememberHaptics
import com.badie.app.l10n.tr
import com.badie.app.models.Coordinate
import com.badie.app.models.TimeSlot
import com.badie.app.models.Venue
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 选球馆的三种用法 */
sealed interface VenuePickerMode {
    /** 快速匹配、常去球馆：最多选 [max] 个 */
    data class Multiple(val max: Int) : VenuePickerMode
    /** 建房间、建球群：选 1 个，选完关闭 */
    data object Single : VenuePickerMode
    /** 浏览：点开球馆页 */
    data object Browse : VenuePickerMode
}

/** 去“添加球馆”时带过去的名称和图钉位置 */
data class AddVenueDraft(val name: String, val coordinate: Coordinate, val fromLink: Boolean = false)

/**
 * 选择、搜索球馆：一个搜索框；没输入时先给“已选 / 常去 / 附近”，输入后是球馆库的结果。
 * 每一行都带地址，用户能确认“是不是这一家”。对应 iPhone 的 Features/Venues/VenuePickerView.swift。
 * iPhone 还会列 Apple 地图的结果；安卓要等 Google 地点搜索（要 key），现在找不到就“添加球馆”。
 *
 * 放在半屏弹层里用 [VenuePickerSheet]；整页用（快速匹配选球馆）直接放这个
 */
@Composable
fun VenuePickerView(
    mode: VenuePickerMode,
    selection: List<String>,
    onSelectionChange: (List<String>) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    /** 给了时段就标出这个时段不营业的球馆 */
    slot: TimeSlot? = null,
    initialQuery: String = "",
    /** 没登录（注册流程里）时只能从球馆库里选，不能新增 */
    allowsAdding: Boolean = true,
    /** 点开球馆详情；不给就关掉自己、推入球馆页 */
    onOpen: ((Venue) -> Unit)? = null,
) {
    val env = LocalEnv.current
    val locationManager = env.locationManager
    val appState = env.appState
    val colors = AppTheme.colors
    val haptics = rememberHaptics()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf(initialQuery) }
    var hits by remember { mutableStateOf<List<VenueSearch.Hit>?>(null) }
    var addDraft by remember { mutableStateOf<AddVenueDraft?>(null) }
    val trimmed = query.trim()

    StartLocation()
    // 打字时等一下再搜（连续输入只搜最后一次）
    LaunchedEffect(trimmed) {
        // 接着打字时先留着上一次的结果，不闪
        if (trimmed.isEmpty()) {
            hits = null
            return@LaunchedEffect
        }
        delay(150)
        hits = locationManager.searchCourts(trimmed)
    }

    fun showDetail(venue: Venue) {
        if (onOpen != null) {
            onOpen(venue)
        } else {
            onDismiss()
            env.router.open(Route.Venue(venue.id))
        }
    }

    fun choose(venue: Venue) {
        haptics.selection()
        when (mode) {
            is VenuePickerMode.Multiple -> when {
                venue.id in selection -> onSelectionChange(selection - venue.id)
                selection.size < mode.max -> onSelectionChange(selection + venue.id)
                else -> appState.showToast(com.badie.app.l10n.L10n.tr("最多选择 %lld 个球馆，先取消一个", mode.max))
            }
            VenuePickerMode.Single -> {
                onSelectionChange(listOf(venue.id))
                onDismiss()
            }
            VenuePickerMode.Browse -> showDetail(venue)
        }
    }

    fun accessory(venue: Venue): VenueAccessory = when (mode) {
        is VenuePickerMode.Multiple -> VenueAccessory.Checkbox(venue.id in selection)
        VenuePickerMode.Single -> VenueAccessory.Radio(venue.id in selection)
        VenuePickerMode.Browse -> VenueAccessory.Chevron
    }

    @Composable
    fun section(title: String, detail: String?, venues: List<Venue>) {
        VenueSection(title, detail, venues) { venue ->
            PickerRow(
                venue, query, accessory(venue), isSelected = venue.id in selection, slot = slot,
                onTap = { choose(venue) }, onShowDetail = { showDetail(venue) },
            )
        }
    }

    Column(modifier.fillMaxWidth()) {
        // 标题
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.xl, bottom = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (mode == VenuePickerMode.Browse) tr("搜索球馆") else tr("选择球馆"),
                    style = AppTheme.Typography.title, color = colors.ink, modifier = Modifier.semantics { heading() },
                )
                if (mode is VenuePickerMode.Multiple) {
                    Text(tr("已选 %lld/%lld", selection.size, mode.max), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
                }
            }
            if (mode is VenuePickerMode.Multiple) {
                BrutalButton(tr("完成"), onDismiss, size = ButtonSize.Small, fullWidth = false)
            } else {
                IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
            }
        }
        // 搜索框 + 粘贴地图链接
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            SearchField(query, { query = it }, tr("球馆名、简称（如 LABC）或地址"), Modifier.weight(1f))
            if (allowsAdding) {
                IconButton(Sym.docOnClipboard, tr("粘贴地图链接")) {
                    val text = (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)
                        ?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                    if (!text.isNullOrBlank()) {
                        scope.launch {
                            when (val result = handlePastedLink(text)) {
                                is PastedLink.Search -> query = result.text
                                is PastedLink.Add -> addDraft = result.draft
                                is PastedLink.Failed -> appState.showToast(result.message, Toast.Style.Error)
                            }
                        }
                    }
                }
            }
        }
        LazyColumn(
            Modifier.fillMaxWidth().weight(1f, fill = false),
            contentPadding = PaddingValues(start = AppTheme.Spacing.screen, end = AppTheme.Spacing.screen, top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            if (trimmed.isEmpty()) {
                val selected = locationManager.courts(selection)
                if (mode is VenuePickerMode.Multiple && selected.isNotEmpty()) {
                    item { section(tr("已选"), null, selected) }
                }
                val favorites = locationManager.favoriteCourts.filter { it.id !in selection || mode == VenuePickerMode.Browse }
                if (favorites.isNotEmpty()) item { section(tr("常去"), null, favorites) }
                val shown = (selected.map { it.id } + favorites.map { it.id }).toSet()
                val nearby = locationManager.nearbyCourts.filter { it.id !in shown }
                if (nearby.isNotEmpty()) {
                    item { section(tr("附近"), locationManager.radiusText, nearby) }
                } else if (favorites.isEmpty()) {
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                            Symbol(Sym.mappinSlash, size = 13, tint = colors.inkSecondary)
                            Text(tr("%@还没有收录的球馆", locationManager.radiusText), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                        }
                    }
                }
                // TODO(地图)：iPhone 在附近少于 3 家时加一段“Apple 地图上的附近结果”。安卓要等 Google Places 的 key
            } else {
                val found = hits
                when {
                    found == null -> item { Box(Modifier.fillMaxWidth().padding(AppTheme.Spacing.xl), contentAlignment = Alignment.Center) { LoadingDots() } }
                    found.isEmpty() -> item { EmptyStateView(Sym.magnifyingglass, tr("没有找到“%@”", trimmed)) }
                    else -> item { section(tr("Badie 球馆库"), tr("%lld 个", found.size), found.map { it.venue }) }
                }
                // TODO(地图)：iPhone 这里还有一段“Apple 地图”的地点联想（最多 6 条）。安卓要等 Google Places 的 key
            }
            item {
                if (allowsAdding) {
                    Row(Modifier.padding(top = AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                        AddVenueButton(Modifier.weight(1f)) { addDraft = AddVenueDraft(trimmed, locationManager.coordinate) }
                        RulesButton(
                            tr("添加球馆"),
                            listOf(tr("找不到常去的球馆，可以放个图钉、核对地址自己添加。"), tr("添加后其他球友也能搜到。"), tr("3 位球友确认后显示“球友确认”。")),
                        )
                    }
                } else {
                    Text(tr("注册后可以添加球馆"), style = AppTheme.Typography.footnote, color = colors.inkTertiary)
                }
            }
        }
    }

    addDraft?.let { draft ->
        SheetScaffold(onDismiss = { addDraft = null }, fullHeight = true) {
            AddVenueContent(draft, onClose = { addDraft = null }) { venue ->
                addDraft = null
                choose(venue)
            }
        }
    }
}

/** 半屏弹层里的选球馆（拉满） */
@Composable
fun VenuePickerSheet(
    mode: VenuePickerMode,
    selection: List<String>,
    onSelectionChange: (List<String>) -> Unit,
    onDismiss: () -> Unit,
    slot: TimeSlot? = null,
    initialQuery: String = "",
    allowsAdding: Boolean = true,
    onOpen: ((Venue) -> Unit)? = null,
) {
    SheetScaffold(onDismiss = onDismiss, fullHeight = true) {
        VenuePickerView(mode, selection, onSelectionChange, onDismiss, Modifier.fillMaxSize(), slot, initialQuery, allowsAdding, onOpen)
    }
}

/** “添加球馆”（次要按钮，带加号） */
@Composable
fun AddVenueButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    BrutalButton(onClick, modifier, kind = ButtonKind.Secondary, size = ButtonSize.Medium) {
        Symbol(Sym.plusCircleFill, size = 15)
        Text(tr("添加球馆"), Modifier.padding(start = AppTheme.Spacing.sm))
    }
}

/** 搜索框：放大镜 + 输入 + 清除 */
@Composable
fun SearchField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Box(modifier) {
        StickerTextField(
            value, onValueChange, placeholder,
            style = AppTheme.Typography.body,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
            trailing = if (value.isEmpty()) null else {
                {
                    val label = tr("清除搜索")
                    Box(
                        Modifier.size(44.dp).combinedClickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { onValueChange("") }
                            .semantics { contentDescription = label },
                        contentAlignment = Alignment.Center,
                    ) { Symbol(Sym.xmarkCircleFill, size = 17, tint = colors.inkTertiary) }
                }
            },
        )
    }
}

/** 一行球馆：点一下选（或打开），长按出“查看详情与地图” */
@Composable
private fun PickerRow(
    venue: Venue,
    query: String,
    accessory: VenueAccessory,
    isSelected: Boolean,
    slot: TimeSlot?,
    onTap: () -> Unit,
    onShowDetail: () -> Unit,
) {
    val locationManager = LocalEnv.current.locationManager
    var menu by remember { mutableStateOf(false) }
    Box {
        VenueRow(
            venue, venue.formattedDistance(locationManager.coordinate),
            Modifier
                .combinedClickable(
                    remember { MutableInteractionSource() }, indication = null,
                    role = if (accessory is VenueAccessory.Chevron) Role.Button else Role.Checkbox,
                    onLongClick = { menu = true }, onClick = onTap,
                )
                .semantics(mergeDescendants = true) { selected = isSelected },
            regulars = locationManager.regularsCount(venue.id),
            isFavorite = locationManager.isFavorite(venue.id),
            query = query,
            accessory = accessory,
            isClosedForSlot = slot?.let { !venue.isOpen(it) } ?: false,
        )
        DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = AppTheme.colors.surface) {
            DropdownMenuItem(
                text = { Text(tr("查看详情与地图"), style = AppTheme.Typography.bodyBold, color = AppTheme.colors.ink) },
                leadingIcon = { Symbol(Sym.map, size = 17, tint = AppTheme.colors.ink) },
                onClick = {
                    menu = false
                    onShowDetail()
                },
            )
        }
    }
}

/** 粘贴的文字该怎么用 */
sealed interface PastedLink {
    /** 不是地图链接，或者链接里只有名称：当搜索词 */
    data class Search(val text: String) : PastedLink
    /** 链接里有坐标：带着坐标和名称去“添加球馆”，由用户核对地址 */
    data class Add(val draft: AddVenueDraft) : PastedLink
    data class Failed(val message: String) : PastedLink
}

/** 粘贴 Google / Apple 地图链接。iPhone 还会拿名称去 Apple 地图找那个地点；安卓没有地点搜索，名称当搜索词 */
suspend fun handlePastedLink(text: String): PastedLink {
    var url = MapLinkParser.firstMapURL(text) ?: return PastedLink.Search(text.trim())
    if (MapLinkParser.needsExpansion(url)) {
        url = MapLinkParser.expand(url) ?: return PastedLink.Failed(com.badie.app.l10n.L10n.tr("链接打不开，试试直接搜索名称"))
    }
    val link = MapLinkParser.parse(url) ?: return PastedLink.Failed(com.badie.app.l10n.L10n.tr("没能识别这个地图链接，试试直接搜索名称"))
    link.coordinate?.let { return PastedLink.Add(AddVenueDraft(link.name.orEmpty(), it, fromLink = true)) }
    (link.name ?: link.query)?.let { return PastedLink.Search(it) }
    return PastedLink.Failed(com.badie.app.l10n.L10n.tr("没能定位这个链接，试试直接搜索名称"))
}
