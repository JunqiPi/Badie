package com.badie.app.features.profile

import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.badie.app.backend.Backend
import com.badie.app.backend.BackendError
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.AvatarView
import com.badie.app.design.BrutalButton
import com.badie.app.design.BrutalTextField
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.CardCover
import com.badie.app.design.ChoiceChip
import com.badie.app.design.GenderPicker
import com.badie.app.design.LevelBadge
import com.badie.app.design.LoadingDots
import com.badie.app.design.LocalPhotos
import com.badie.app.design.RulesButton
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SegmentedSticker
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.VerifiedBadge
import com.badie.app.design.card
import com.badie.app.design.fill
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.sticker
import com.badie.app.features.onboarding.AvatarPaletteEditor
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.CardColor
import com.badie.app.models.DateText
import com.badie.app.models.GameMode
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillLevel
import com.badie.app.models.User
import com.badie.app.models.UsualTimeText
import com.badie.app.models.VerificationRequest
import com.badie.app.models.VerificationStatus
import com.badie.app.models.canAddMore
import com.badie.app.remote.RemoteError
import com.badie.app.shell.BadieSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// 编辑资料。对应 iPhone 的 Features/Profile/EditProfileView.swift

private enum class EditTab { Edit, Preview }

/** 选完照片、等着裁剪的那一张 */
private class CropItem(val image: Bitmap, val kind: CropKind)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EditProfileView() {
    val env = LocalEnv.current
    val appState = env.appState
    val backend = appState.backend
    val api = rememberProfileApi()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val photos = LocalPhotos.current ?: backend.photos
    val user = appState.currentUser ?: return

    var tab by remember { mutableStateOf(EditTab.Edit) }
    var nickname by remember { mutableStateOf(user.nickname) }
    var bio by remember { mutableStateOf(user.bio) }
    var gender by remember { mutableStateOf(user.gender) }
    var preferredMode by remember { mutableStateOf(user.preferredMode) }
    var avatar by remember { mutableStateOf(user.avatar) }
    var cardColor by remember { mutableStateOf(user.avatar.cardColor) }
    var slots by remember { mutableStateOf(api.recurringSlots()) }
    var showReassess by remember { mutableStateOf(false) }
    var showGuide by remember { mutableStateOf(false) }
    var showsSlotEditor by remember { mutableStateOf(false) }
    var slotToDelete by remember { mutableStateOf<RecurringTimeSlot?>(null) }
    var photoMenu by remember { mutableStateOf<CropKind?>(null) }
    var cropItem by remember { mutableStateOf<CropItem?>(null) }
    var isUploadingPhoto by remember { mutableStateOf(false) }
    var isUploadingCard by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var pickingFor by remember { mutableStateOf(CropKind.Avatar) }
    val scroll = rememberScrollState()
    val positions = remember { mutableStateMapOf<ProfileField, Int>() }

    // 选照片：系统的照片选择器（不要权限），选完先裁剪
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val kind = pickingFor
        scope.launch {
            val image = withContext(Dispatchers.IO) { AvatarPhotos.decode(context, uri) }
            if (image == null) appState.showToast(L10n.tr("无法读取这张照片"), Toast.Style.Error) else cropItem = CropItem(image, kind)
        }
    }
    fun pick(kind: CropKind) {
        pickingFor = kind
        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    LaunchedEffect(Unit) {
        try {
            api.refreshVerification()
        } catch (_: RemoteError) {
        }
    }
    // 从“我的”页的“资料 N/4”进来：跳到缺的那一项（照片直接打开相册，其他滚过去）
    LaunchedEffect(Unit) {
        val field = ProfileField.pendingFocus ?: return@LaunchedEffect
        ProfileField.pendingFocus = null
        tab = EditTab.Edit
        delay(400)
        when (field) {
            ProfileField.CardPhoto -> pick(CropKind.Card)
            ProfileField.AvatarPhoto -> pick(CropKind.Avatar)
            ProfileField.UsualTimes, ProfileField.Venue -> positions[field]?.let { scroll.animateScrollTo(it) }
        }
    }

    // 还没保存的改动也显示出来：昵称、常打、头像颜色、卡片颜色
    val previewUser = user.copy(
        nickname = if (Backend.isValidNickname(nickname)) nickname else user.nickname,
        preferredMode = preferredMode,
        avatar = user.avatar.copy(symbol = avatar.symbol, paletteIndex = avatar.paletteIndex, cardColor = cardColor),
    )
    val hasPhoto = photos.avatar(user.id) != null && user.avatar.photoVersion != null

    fun persistSlots(next: List<RecurringTimeSlot>) {
        slots = api.persistSlots(next) { appState.showError(it) }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("编辑资料"), onBack = { env.router.pop() })
        SegmentedSticker(
            listOf(EditTab.Edit, EditTab.Preview), tab, { tab = it },
            Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.md),
        ) { if (it == EditTab.Edit) tr("编辑") else tr("预览") }
        if (tab == EditTab.Edit) {
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(scroll)
                    .padding(horizontal = AppTheme.Spacing.screen)
                    .padding(top = AppTheme.Spacing.sm, bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xxl),
            ) {
                // 照片：卡片照片（大）+ 头像（小），分开传
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SectionTitleText(tr("照片"))
                        RulesButton(
                            tr("卡片背景"),
                            listOf(tr("别人在首页刷到你时，看到的就是这张卡片"), tr("上传的照片会显示给其他球友"), tr("不传照片时用这个颜色")),
                        )
                    }
                    PhotoSlots(
                        card = {
                            val cover = photos.cardPhoto(user.id)?.takeIf { user.avatar.cardPhotoVersion != null }
                            PhotoSlot(tr("卡片"), tr("卡片照片"), cover != null, isUploadingCard, onClick = {
                                if (cover != null) photoMenu = CropKind.Card else pick(CropKind.Card)
                            }) { CardCover(previewUser.cardColor, cover) }
                        },
                        avatar = {
                            val photo = photos.avatar(user.id)?.takeIf { user.avatar.photoVersion != null }
                            PhotoSlot(tr("头像"), tr("头像照片"), photo != null, isUploadingPhoto, onClick = {
                                if (photo != null) photoMenu = CropKind.Avatar else pick(CropKind.Avatar)
                            }) {
                                if (photo != null) {
                                    Image(photo, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                                } else {
                                    val muted = AppTheme.colors.surfaceMuted
                                    Box(Modifier.fillMaxSize().drawBehind { drawRect(muted) }, contentAlignment = Alignment.Center) {
                                        AvatarView(previewUser.avatarText, paletteIndex = avatar.paletteIndex, size = 64.dp)
                                    }
                                }
                            }
                        },
                    )
                }
                // 卡片颜色（没传卡片照片时用）
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                    SectionTitleText(tr("没照片时的卡片颜色"))
                    CardColorRow(previewUser.cardColor) { color ->
                        cardColor = color
                        scope.launch {
                            try {
                                api.setCardColor(color)
                            } catch (error: RemoteError) {
                                appState.showError(error)
                            }
                        }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg)) {
                    SectionTitleText(tr("资料"))
                    BrutalTextField(
                        tr("昵称"), tr("2-12 个字"), nickname, { nickname = limited(it, 12) },
                        errorText = if (nickname.isEmpty() || Backend.isValidNickname(nickname)) null else tr("昵称需为 2-12 个字符"),
                        characterLimit = 12,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        FieldLabel(tr("常打"))
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            ChoiceChip(tr("单打"), preferredMode == GameMode.Singles) { preferredMode = GameMode.Singles }
                            ChoiceChip(tr("双打"), preferredMode == GameMode.Doubles) { preferredMode = GameMode.Doubles }
                            ChoiceChip(tr("都行"), preferredMode == null) { preferredMode = null }
                        }
                    }
                    Column(
                        Modifier.onGloballyPositioned { positions[ProfileField.Venue] = it.positionInParent().y.toInt() },
                        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                    ) {
                        FieldLabel(tr("常去球馆"))
                        VenueRow(api) { env.router.open(Route.Courts) }
                    }
                }
                // 空闲时间（就是“常用时间”：最多 5 段，每段 1–8 小时，改了马上存）
                Column(
                    Modifier.onGloballyPositioned { positions[ProfileField.UsualTimes] = it.positionInParent().y.toInt() },
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
                ) {
                    SectionTitleText(tr("空闲时间"))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        for (slot in sortedSlots(slots)) {
                            SlotChip(slot) { slotToDelete = slot }
                        }
                        if (slots.canAddMore) AddSlotChip { showsSlotEditor = true }
                    }
                }
                MultilineField(tr("一句话介绍"), tr("例：双打找固定搭档，周末有空"), bio, { bio = it }, 60)
                GenderPicker(gender, { gender = it })
                if (!hasPhoto) {
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        FieldLabel(tr("没照片时的头像"))
                        AvatarPaletteEditor(avatar) { avatar = it }
                    }
                }
                LevelSection(user, api, onGuide = { showGuide = true }, onReassess = { showReassess = true }) { env.router.open(Route.Verification) }
            }
        } else {
            MyCardPreviewContent(
                previewUser, slots, api.favoriteVenues().firstOrNull(), api.strikes?.recent ?: 0,
                Modifier.weight(1f).padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.sm),
            )
        }
        BrutalButton(
            {
                isSaving = true
                scope.launch {
                    try {
                        api.saveProfile(
                            user.copy(
                                nickname = nickname, bio = bio, gender = gender, preferredMode = preferredMode,
                                avatar = user.avatar.copy(symbol = avatar.symbol, paletteIndex = avatar.paletteIndex, cardColor = cardColor),
                            ),
                        )
                        appState.showToast(L10n.tr("资料已保存"), Toast.Style.Success)
                        env.router.pop()
                    } catch (error: BackendError) {
                        appState.showError(error)
                    } catch (error: RemoteError) {
                        appState.showError(error)
                    } finally {
                        isSaving = false
                    }
                }
            },
            Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.md),
            enabled = Backend.isValidNickname(nickname) && !isSaving,
        ) {
            if (isSaving) LoadingDots()
            Text(tr("保存"))
        }
    }

    if (showReassess) BadieSheet(onDismiss = { showReassess = false }) { dismiss -> ReassessSheet(dismiss) }
    if (showGuide) {
        BadieSheet(onDismiss = { showGuide = false }) { dismiss -> SkillLevelGuideView(user.displayTier, onClose = dismiss) }
    }
    if (showsSlotEditor) {
        BadieSheet(onDismiss = { showsSlotEditor = false }) { dismiss ->
            RecurringSlotEditor(onSave = { slot ->
                when {
                    !slots.canAddMore -> Unit
                    // 同一段加两次：不重复存
                    slots.any { it.dayOfWeek == slot.dayOfWeek && it.startMinutes == slot.startMinutes && it.endMinutes == slot.endMinutes } ->
                        appState.showToast(L10n.tr("已经有这一段了"))
                    else -> persistSlots(slots + slot)
                }
            }, onDismiss = dismiss)
        }
    }
    cropItem?.let { item ->
        BadieSheet(onDismiss = { cropItem = null }) { dismiss ->
            AvatarCropSheet(item.image, item.kind, dismiss) { jpeg ->
                scope.launch {
                    if (item.kind == CropKind.Avatar) isUploadingPhoto = true else isUploadingCard = true
                    try {
                        if (item.kind == CropKind.Avatar) {
                            backend.uploadAvatar(jpeg)
                            appState.showToast(L10n.tr("头像已更新"), Toast.Style.Success)
                        } else {
                            backend.uploadCardPhoto(jpeg)
                            appState.showToast(L10n.tr("卡片背景已更新"), Toast.Style.Success)
                        }
                    } catch (error: RemoteError) {
                        appState.showError(error)
                    } finally {
                        isUploadingPhoto = false
                        isUploadingCard = false
                    }
                }
            }
        }
    }
    photoMenu?.let { kind ->
        BadieSheet(onDismiss = { photoMenu = null }) { dismiss ->
            Column(
                Modifier.fillMaxWidth().padding(AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                BrutalButton(tr("换一张"), {
                    dismiss()
                    pick(kind)
                }, kind = ButtonKind.Secondary)
                BrutalButton(tr("移除照片"), {
                    dismiss()
                    scope.launch {
                        try {
                            if (kind == CropKind.Card) backend.removeCardPhoto() else backend.removeAvatar()
                        } catch (error: RemoteError) {
                            appState.showError(error)
                        }
                    }
                }, kind = ButtonKind.Destructive)
            }
        }
    }
    slotToDelete?.let { slot ->
        AlertDialog(
            onDismissRequest = { slotToDelete = null },
            containerColor = AppTheme.colors.surface,
            title = { Text(slot.displayText, style = AppTheme.Typography.headline, color = AppTheme.colors.ink) },
            confirmButton = {
                TextAction(tr("删除 %@", slot.displayText), {
                    slotToDelete = null
                    persistSlots(slots.filter { it.id != slot.id })
                }, color = AppTheme.colors.danger)
            },
            dismissButton = { TextAction(tr("取消"), { slotToDelete = null }, color = AppTheme.colors.ink) },
        )
    }
}

/** 周一排第一，同一天按开始时间 */
fun sortedSlots(slots: List<RecurringTimeSlot>): List<RecurringTimeSlot> =
    slots.sortedWith(compareBy<RecurringTimeSlot> { (it.dayOfWeek + 5) % 7 }.thenBy { it.startMinutes })

@Composable
private fun SectionTitleText(text: String) {
    Text(text, style = AppTheme.Typography.subheadlineBold, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
}

/** 两个照片格子：卡片 3:4 占三分之二宽；头像正方形，和卡片顶端对齐 */
@Composable
private fun PhotoSlots(card: @Composable () -> Unit, avatar: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val spacing = AppTheme.Spacing.sm
        val unit = (maxWidth - spacing) / 3
        Row(Modifier.height(unit * 8 / 3), horizontalArrangement = Arrangement.spacedBy(spacing)) {
            Box(Modifier.width(unit * 2).height(unit * 8 / 3)) { card() }
            Box(Modifier.size(unit)) { avatar() }
        }
    }
}

/** 一个照片格子：没照片时中间一个相机；左下角写“卡片”/“头像”；点了选照片，有照片时换一张或移除 */
@Composable
private fun PhotoSlot(label: String, accessibility: String, hasPhoto: Boolean, isUploading: Boolean, onClick: () -> Unit, content: @Composable () -> Unit) {
    val colors = AppTheme.colors
    val shape = RoundedCornerShape(AppTheme.Radius.md)
    val stroke = colors.stroke
    Box(
        Modifier
            .fillMaxSize()
            .pressable(enabled = !isUploading, onClick = onClick)
            .clip(shape)
            .clearAndSetSemantics {
                contentDescription = accessibility
                role = Role.Button
            },
    ) {
        content()
        if (isUploading) {
            Box(Modifier.fillMaxSize().drawBehind { drawRect(Color.Black.copy(alpha = 0.35f)) }, contentAlignment = Alignment.Center) {
                androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides Color.White) { LoadingDots() }
            }
        } else if (!hasPhoto) {
            CameraBadge(Modifier.align(Alignment.Center))
        }
        TagPill(label, Modifier.align(Alignment.BottomStart).padding(AppTheme.Spacing.sm), fill = Color.White, foreground = colors.onAccent)
        Box(
            Modifier.fillMaxSize().drawBehind {
                val w = AppTheme.Stroke.width.toPx()
                drawRoundRect(stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius(AppTheme.Radius.md.toPx() - w / 2), style = Stroke(w))
            },
        )
    }
}

/** 照片格子中间的相机标 */
@Composable
private fun CameraBadge(modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    val lime = colors.lime
    val ink = colors.onAccent
    Box(
        modifier.size(38.dp).drawBehind {
            drawCircle(lime)
            drawCircle(ink, size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
        },
        contentAlignment = Alignment.Center,
    ) { Symbol(Sym.cameraFill, size = 15, tint = ink) }
}

/** 8 种卡片颜色，点了就存 */
@Composable
private fun CardColorRow(selected: CardColor, onSelect: (CardColor) -> Unit) {
    val haptics = rememberHaptics()
    val colors = AppTheme.colors
    Row(Modifier.fillMaxWidth()) {
        for (color in CardColor.entries) {
            val isSelected = color == selected
            val fill = color.fill
            val stroke = colors.stroke
            val ring = if (isSelected) colors.ink else Color.Transparent
            Box(
                Modifier
                    .weight(1f)
                    .defaultMinSize(minHeight = 44.dp)
                    .pressable(scale = 1f, role = Role.RadioButton) {
                        haptics.selection()
                        onSelect(color)
                    }
                    .semantics {
                        contentDescription = color.displayName
                        this.selected = isSelected
                    },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier.size(38.dp).drawBehind {
                        val inner = 15.dp.toPx()
                        drawCircle(fill, inner)
                        drawCircle(stroke, inner - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                        drawCircle(ring, size.minDimension / 2 - 1.25.dp.toPx(), style = Stroke(2.5.dp.toPx()))
                    },
                )
            }
        }
    }
}

/** 常去球馆（收藏的球馆）：“X +2”，点了去球馆页 */
@Composable
private fun VenueRow(api: ProfileApi, onClick: () -> Unit) {
    LaunchedEffect(Unit) {
        try {
            api.refreshFavoriteVenues()
        } catch (_: RemoteError) {
        }
    }
    val favorites = api.favoriteVenues()
    val count = api.backend.favoriteVenueIds.size
    val value = favorites.firstOrNull()?.let { if (count > 1) "${it.name} +${count - 1}" else it.name } ?: tr("未设置")
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .defaultMinSize(minHeight = 48.dp)
            .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.md, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
    ) {
        Symbol(Sym.mappinCircleFill, size = 17, tint = AppTheme.colors.ink)
        Text(
            value, style = AppTheme.Typography.subheadlineBold, color = if (favorites.isEmpty()) AppTheme.colors.inkTertiary else AppTheme.colors.ink,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        Symbol(Sym.chevronRight, size = 13, tint = AppTheme.colors.inkTertiary)
    }
}

/** 一段空闲时间：打开的是柠檬色；点了可以删 */
@Composable
private fun SlotChip(slot: RecurringTimeSlot, onClick: () -> Unit) {
    val colors = AppTheme.colors
    Text(
        UsualTimeText.chip(slot), style = AppTheme.Typography.footnoteBold, color = if (slot.isActive) colors.onAccent else colors.inkSecondary, maxLines = 1,
        modifier = Modifier
            .pressable(onClick = onClick)
            .defaultMinSize(minHeight = 38.dp)
            .sticker(if (slot.isActive) colors.lime else colors.surfaceMuted, radius = 19.dp, shadow = AppTheme.Elevation.none)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .semantics { contentDescription = slot.displayText },
    )
}

@Composable
private fun AddSlotChip(onClick: () -> Unit) {
    val colors = AppTheme.colors
    Row(
        Modifier
            .pressable(onClick = onClick)
            .defaultMinSize(minHeight = 38.dp)
            .sticker(colors.surface, radius = 19.dp, shadow = AppTheme.Elevation.none)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Symbol(Sym.plus, size = 12, tint = colors.ink)
        Text(tr("加一段"), style = AppTheme.Typography.footnoteBold, color = colors.ink, maxLines = 1)
    }
}

// MARK: 等级（只能通过问卷或球友评价改变）

@Composable
private fun LevelSection(user: User, api: ProfileApi, onGuide: () -> Unit, onReassess: () -> Unit, onVerification: () -> Unit) {
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FieldLabel(tr("等级"))
            RulesButton(tr("等级"), levelRules(user))
        }
        Column(Modifier.card(colors.surface, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                LevelBadge(user.displayTier)
                VerifiedBadge(user.verificationStatus)
                if (user.needsAssessment) TagPill(tr("未定级"), fill = colors.butter)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                BrutalButton(onGuide, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small) {
                    Symbol(Sym.listNumber, size = 13)
                    Spacer(Modifier.size(6.dp))
                    Text(tr("对照表"), maxLines = 1)
                }
                val assessment = user.assessment
                if (assessment != null && !assessment.canRetake(System.currentTimeMillis())) {
                    Text(
                        tr("下次可重测：%@", DateText.shortDay(assessment.nextRetakeDate())), style = AppTheme.Typography.caption, color = colors.inkTertiary,
                        modifier = Modifier.weight(1f),
                    )
                } else {
                    BrutalButton(onReassess, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Small) {
                        Symbol(if (assessment == null) Sym.checklist else Sym.arrowCounterclockwise, size = 13)
                        Spacer(Modifier.size(6.dp))
                        Text(if (assessment == null) tr("开始定级") else tr("重新测评"), maxLines = 1)
                    }
                }
            }
            HorizontalDivider(color = colors.divider)
            Row(
                Modifier.fillMaxWidth().pressable(scale = 1f, onClick = onVerification).padding(vertical = AppTheme.Spacing.xs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
            ) {
                Symbol(Sym.checkmarkSealFill, size = 17, tint = colors.ink)
                Text(verificationTitle(user, api.verification), style = AppTheme.Typography.subheadlineBold, color = colors.ink, modifier = Modifier.weight(1f))
                Symbol(Sym.chevronRight, size = 12, tint = colors.ink)
            }
        }
    }
}

/** 原来写在等级卡片上的说明 */
@Composable
private fun levelRules(user: User): List<String> = listOf(
    SkillLevel.descriptor(user.displayLevel),
    when {
        user.needsAssessment -> tr("你跳过了定级，现在暂按 Lv.%lld 匹配。花一分钟做完定级，匹配会准很多。", SkillAssessment.PROVISIONAL_LEVEL)
        user.isNewPlayer -> tr("等级来自定级问卷；打满 5 场并获得评价后会按球友评价自动校准。")
        else -> tr("你已有 %lld 次球友评价，等级主要由球友评价决定。", user.reputation.evaluationCount)
    },
    tr("问卷最高 6+。打过州 / 地区公开赛最高组、有全国排名、运动员等级证书或 BWF 世界排名，可以凭证据认证 7− 到 9+"),
)

@Composable
private fun verificationTitle(user: User, request: VerificationRequest?): String = when {
    request?.status == VerificationRequest.Status.Pending -> tr("高水平认证 · 审核中")
    user.verificationStatus != VerificationStatus.Unverified -> tr("已认证 %@ · 申请更高档位", user.tierCap.text)
    else -> tr("申请高水平认证")
}
