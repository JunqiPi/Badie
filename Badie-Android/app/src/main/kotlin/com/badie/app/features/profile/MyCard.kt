package com.badie.app.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.badie.app.backend.VenueName
import com.badie.app.design.AppTheme
import com.badie.app.design.CoverCard
import com.badie.app.design.IconButton
import com.badie.app.design.NoShowPill
import com.badie.app.design.RoundActionLabel
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.pressable
import com.badie.app.design.sticker
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.User
import com.badie.app.models.UsualTimeText
import com.badie.app.models.activeSlots

// 对应 iPhone 的 Features/Profile/MyCardPreview.swift（卡片本身是 Features/Home/NearbyViews.swift 的 NearbyCardView）

/**
 * 我自己的卡片：和发现页“附近的人”同一张卡（常去的球馆、空闲时间）。
 * iPhone 的预览里还写我到常去球馆的距离；这里没有定位，不写
 */
@Composable
fun MyCard(user: User, slots: List<RecurringTimeSlot>, venue: VenueName?, recentNoShows: Int, modifier: Modifier = Modifier, onTap: (() -> Unit)? = null) {
    // 左上角：“常去 X”
    val pill = venue?.let { tr("常去 %@", it.name) }
    // “双打 · 靠谱”
    val line = listOfNotNull(user.preferredMode?.title, if (recentNoShows == 0) tr("靠谱") else null).joinToString(" · ")
    val times = slots.activeSlots
    CoverCard(user, pill, line, modifier, onProfile = onTap) {
        if (recentNoShows > 0) NoShowPill(recentNoShows)
        if (times.isNotEmpty()) UsualTimeChips(times)
    }
}

/** 空闲时间：最近的两段做成小胶囊，多了“+N” */
@Composable
fun UsualTimeChips(slots: List<RecurringTimeSlot>) {
    val sorted = UsualTimeText.sortedByNext(slots)
    val colors = AppTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        for (slot in sorted.take(2)) {
            val text = UsualTimeText.chip(slot)
            val label = tr("约 %@", text)
            Text(
                text, style = AppTheme.Typography.footnoteBold, color = colors.onAccent, maxLines = 1,
                modifier = Modifier
                    .defaultMinSize(minHeight = 32.dp)
                    .sticker(colors.lime, radius = 16.dp, shadow = AppTheme.Elevation.none, stroke = colors.onAccent, strokeWidth = 1.5.dp)
                    .padding(horizontal = 10.dp, vertical = 7.dp)
                    .semantics { contentDescription = label },
            )
        }
        if (sorted.size > 2) TagPill("+${sorted.size - 2}", fill = colors.lime)
    }
}

/** 别人在发现页刷到我时看到的样子：卡片 + 下面三个按不了的按钮 + 一句话 */
@Composable
fun MyCardPreviewContent(user: User, slots: List<RecurringTimeSlot>, venue: VenueName?, recentNoShows: Int, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg), horizontalAlignment = Alignment.CenterHorizontally) {
        MyCard(user, slots, venue, recentNoShows, Modifier.weight(1f))
        // 和真卡片一样的三个按钮，预览里按不了
        Row(
            Modifier.alpha(0.35f).clearAndSetSemantics {},
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RoundActionLabel(Sym.xmark, AppTheme.colors.surface, foreground = AppTheme.colors.ink)
            RoundActionLabel(Sym.heartFill, AppTheme.colors.lime, size = 80.dp)
            RoundActionLabel(Sym.starFill, AppTheme.colors.butter)
        }
        Text(
            tr("别人在首页刷到你时，看到的就是这张卡片"), style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary,
            textAlign = TextAlign.Center,
        )
    }
}

/** 全屏看自己的卡片（“我的”页点卡片） */
@Composable
fun MyCardPreview(user: User, slots: List<RecurringTimeSlot>, venue: VenueName?, recentNoShows: Int, onDismiss: () -> Unit) {
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val canvas = AppTheme.colors.canvas
        Column(
            Modifier
                .fillMaxSize()
                .drawBehind { drawRect(canvas) }
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = AppTheme.Spacing.screen),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            Row(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                Text(tr("我的卡片"), style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.weight(1f))
                IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
            }
            MyCardPreviewContent(user, slots, venue, recentNoShows, Modifier.weight(1f).padding(bottom = AppTheme.Spacing.lg))
        }
    }
}

/** 待处理的小胶囊（“去定级”、爽约）：图标、字、红色的数字 */
@Composable
fun CountPill(icon: com.badie.app.design.SymbolId, title: String, count: Int, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val danger = colors.dangerFill
    Row(
        Modifier
            .pressable(onClick = onClick)
            .defaultMinSize(minHeight = 36.dp)
            .sticker(colors.surface, radius = 18.dp, shadow = AppTheme.Elevation.none)
            .padding(horizontal = AppTheme.Spacing.md, vertical = 8.dp)
            .clearAndSetSemantics { contentDescription = if (count > 0) "$title $count" else title },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Symbol(icon, size = 12, tint = colors.ink)
        Text(title, style = AppTheme.Typography.footnoteBold, color = colors.ink, maxLines = 1)
        if (count > 0) {
            Text(
                "$count", style = AppTheme.Typography.overline.copy(fontFeatureSettings = "tnum"), color = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.drawBehind { drawRoundRect(danger, cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2)) }.padding(horizontal = 6.dp, vertical = 1.dp),
            )
        }
    }
}

/**
 * 资料完成度：“我的”页上的“资料 N/4”。按这个顺序提示下一项，点了跳到编辑资料里的那一项。
 * 常打不算：选“都行”和没填在服务器上都是空的，分不出来
 */
enum class ProfileField {
    CardPhoto, AvatarPhoto, UsualTimes, Venue;

    val hint: String
        get() = when (this) {
            CardPhoto -> L10n.tr("传一张卡片照片")
            AvatarPhoto -> L10n.tr("传一张头像照片")
            UsualTimes -> L10n.tr("填空闲时间，更容易被约")
            Venue -> L10n.tr("选常去的球馆")
        }

    companion object {
        /** 还缺的几项（空闲时间只算打开的） */
        fun missing(user: User, slots: List<RecurringTimeSlot>, hasVenue: Boolean): List<ProfileField> = entries.filter { field ->
            when (field) {
                CardPhoto -> user.avatar.cardPhotoVersion == null
                AvatarPhoto -> user.avatar.photoVersion == null
                UsualTimes -> slots.activeSlots.isEmpty()
                Venue -> !hasVenue
            }
        }

        /** “我的”页点了“资料 N/4”：打开编辑资料时跳到缺的那一项（iPhone 放在 AppState.editProfileFocus） */
        var pendingFocus by mutableStateOf<ProfileField?>(null)
    }
}
