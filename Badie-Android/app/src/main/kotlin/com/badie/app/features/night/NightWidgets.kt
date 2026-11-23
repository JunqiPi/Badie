package com.badie.app.features.night

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.FitText
import com.badie.app.design.IconButton
import com.badie.app.design.IconTile
import com.badie.app.design.InsetDivider
import com.badie.app.design.SheetScaffold
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.groups.PayToContent
import com.badie.app.features.profile.openLink
import com.badie.app.features.social.copyText
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.FeeText
import com.badie.app.models.GroupTonight
import com.badie.app.models.PayLinks
import com.badie.app.models.PaymentHandles
import com.badie.app.models.TimeSlot
import com.badie.app.models.TonightItem
import com.badie.app.remote.RemoteError
import com.badie.app.shell.AppState
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.delay
import java.time.Instant

// 当晚和比赛共用的小部件、球群页场次行上的当天按钮、球局页的“今晚”卡、看板。
// 对应 iPhone 的 Features/Night/TonightViews.swift

/** 当晚页和比赛页的报错：not_allowed 在别处是约球的意思，这里说清楚是谁能做 */
fun AppState.showClubError(error: Throwable) {
    if (error is RemoteError.Server && error.code == "not_allowed") {
        showToast(L10n.tr("只有组织者和帮手能做这一步。"), Toast.Style.Error)
    } else {
        showError(error)
    }
}

/** 现在几点（毫秒），每 [period] 毫秒更新一次：撤销条、“x 分钟前更新”、场上打了几分钟 */
@Composable
fun rememberNow(period: Long): Long {
    val now by produceState(System.currentTimeMillis(), period) {
        while (true) {
            delay(period)
            value = System.currentTimeMillis()
        }
    }
    return now
}

// MARK: - 看板：App 里用浏览器标签页打开同一个网页（iPhone 是 App 里的 Safari）

fun openBoard(context: Context, code: String) {
    val url = PayLinks.board(code)
    try {
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri())
    } catch (_: Exception) {
        context.openLink(url)
    }
}

/**
 * 看板的链接（立在场边给大家扫）。iPhone 这里还有一个二维码，安卓要加二维码的依赖，先只显示链接（可以复制、打开）
 */
@Composable
fun BoardSheet(code: String, onDismiss: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val context = LocalContext.current
    val url = PayLinks.board(code)
    val copied = tr("已复制链接")
    SheetScaffold(onDismiss = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xl).navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
        ) {
            Row(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
                Text(tr("看板"), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
                IconButton(Sym.xmark, tr("关闭"), onClick = onDismiss)
            }
            Row(
                Modifier.fillMaxWidth().pressable(scale = 0.98f) { openBoard(context, code) }.sticker(colors.surface, radius = AppTheme.Radius.lg)
                    .padding(AppTheme.Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                IconTile(Sym.qrcode, fill = colors.lime, size = 44.dp)
                Text(
                    url.removePrefix("https://"), style = AppTheme.Typography.bodyBold, color = colors.ink, maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis, modifier = Modifier.weight(1f),
                )
                Symbol(Sym.arrowUpRight, size = 13, tint = colors.inkSecondary)
            }
            BrutalButton({
                copyText(context, url)
                env.appState.showToast(copied, Toast.Style.Success)
            }, kind = ButtonKind.Secondary) {
                Symbol(Sym.docOnDoc, size = 16)
                Spacer(Modifier.size(AppTheme.Spacing.sm))
                FitText(tr("复制链接"))
            }
        }
    }
}

// MARK: - 场边用的大按钮、场地号、场地数

/** 场地卡上的柠檬绿大按钮（打完了、输比分）：单手按得到 */
@Composable
fun BigActionButton(title: String, onClick: () -> Unit) {
    BrutalButton(onClick, Modifier.size(96.dp, 76.dp), kind = ButtonKind.Primary, size = ButtonSize.Large, fullWidth = false) {
        Text(title, style = AppTheme.Typography.headline, textAlign = TextAlign.Center, maxLines = 2)
    }
}

/** “场地 2”小牌子 */
@Composable
fun CourtTag(court: Int) {
    val colors = AppTheme.colors
    Text(
        tr("场地 %lld", court), style = AppTheme.Typography.footnoteBold, color = colors.onAccent,
        modifier = Modifier.background(colors.sky, RoundedCornerShape(8.dp)).border(AppTheme.Stroke.hairline, colors.stroke, RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

/** 场地数：减、几片、加（1–12） */
@Composable
fun CourtStepper(courts: Int, onChange: (Int) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val colors = AppTheme.colors
    val less = tr("减少场地")
    val more = tr("增加场地")
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(tr("场地"), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
        Box(
            Modifier.size(44.dp).semantics { contentDescription = less }.pressable(enabled = enabled && courts > 1) { onChange(maxOf(1, courts - 1)) },
            contentAlignment = Alignment.Center,
        ) { Symbol(Sym.minus, size = 17, tint = if (enabled && courts > 1) colors.ink else colors.inkTertiary) }
        Text(
            tr("%lld 片", courts), style = AppTheme.Typography.title3.copy(fontFeatureSettings = "tnum"), color = colors.ink,
            textAlign = TextAlign.Center, modifier = Modifier.widthIn(min = 56.dp),
        )
        Box(
            Modifier.size(44.dp).semantics { contentDescription = more }.pressable(enabled = enabled && courts < 12) { onChange(minOf(12, courts + 1)) },
            contentAlignment = Alignment.Center,
        ) { Symbol(Sym.plus, size = 17, tint = if (enabled && courts < 12) colors.ink else colors.inkTertiary) }
    }
}

/** 一个人的名字胶囊：右边是今晚打了几场（或一个小标记） */
@Composable
fun NameChip(name: String, modifier: Modifier = Modifier, count: Int? = null, note: String? = null, fill: Color = AppTheme.colors.surface, dimmed: Boolean = false) {
    val colors = AppTheme.colors
    Row(
        modifier.height(40.dp).background(fill, CircleShape).border(AppTheme.Stroke.hairline, colors.stroke, CircleShape)
            .padding(start = 12.dp, end = if (count == null) 12.dp else 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(name, style = AppTheme.Typography.bodyBold, color = if (dimmed) colors.inkSecondary else colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        note?.let { Text(it, style = AppTheme.Typography.caption, color = colors.inkSecondary, maxLines = 1) }
        count?.let {
            Box(Modifier.size(28.dp).background(colors.surfaceMuted, CircleShape), contentAlignment = Alignment.Center) {
                Text("$it", style = rounded(14, FontWeight.Black), color = colors.ink)
            }
        }
    }
}

/** “A · B 对 C · D” */
@Composable
fun MatchupLine(a: List<String>, b: List<String>) {
    val colors = AppTheme.colors
    val style = rounded(17, FontWeight.ExtraBold)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(a.joinToString(" · "), style = style, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        Text(tr("对"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
        Text(b.joinToString(" · "), style = style, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
    }
}

/** 撤销：10 秒内有效（[deadline] 是本机时间） */
@Composable
fun UndoButton(deadline: Long?, modifier: Modifier = Modifier, onUndo: () -> Unit) {
    if (deadline == null) return
    val now = rememberNow(1_000)
    if (now >= deadline) return
    BrutalButton(onUndo, modifier, kind = ButtonKind.Inverse, size = ButtonSize.Medium) {
        Symbol(Sym.arrowUturnLeftCircleFill, size = 15)
        Spacer(Modifier.size(AppTheme.Spacing.sm))
        Text(tr("撤销"))
    }
}

/** 页面底部的按钮条 */
@Composable
fun NightBottomBar(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(AppTheme.colors.canvas)) {
        InsetDivider()
        Column(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg).navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
            content = content,
        )
    }
}

// MARK: - 球群页场次行上的当天按钮
// 组织者、帮手：“排场”（柠檬绿，进当晚页）；结束后还有人没付：“收款 · n 人没付”。
// 球员：开场后“报名 / 已报名”换成“看排场”，要付钱的人换成“付给 Kevin · $12”（一行只有一个按钮）

/** 球员的按钮：付钱或看排场（换掉报名按钮） */
@Composable
fun TonightPlayerButton(item: GroupTonight, groupName: String) {
    val context = LocalContext.current
    val env = LocalEnv.current
    var showsPay by remember(item.id) { mutableStateOf(false) }
    // 刚在付款半屏里点了“我付了”（等下次拉到新数据之前先这样显示）
    var paidHere by remember(item.id) { mutableStateOf<Boolean?>(null) }
    val pay = item.pay
    if (pay != null && item.paysHere) {
        val paid = paidHere ?: pay.paid
        val title = when {
            paid -> tr("已付")
            pay.amount != null -> tr("付给 %@ · %@", pay.to, FeeText.text(pay.amount))
            else -> tr("付给 %@", pay.to)
        }
        BrutalButton(title, { showsPay = true }, kind = if (paid) ButtonKind.Secondary else ButtonKind.Primary, size = ButtonSize.Small, fullWidth = false)
        if (showsPay) {
            SheetScaffold(onDismiss = { showsPay = false }, fullHeight = true) {
                val slot = sessionSlot(item.startsAt, item.endsAt)
                PayToContent(
                    to = pay.to,
                    subtitle = if (groupName.isEmpty()) slot else "$slot · $groupName",
                    amount = pay.amount,
                    handles = pay.handles ?: PaymentHandles(),
                    // 付款备注：Badie · 周三 7 PM · 球群名
                    note = "Badie · ${DateText.weekdayHour(item.startsAt.toEpochMilli())} · $groupName",
                    paid = paid,
                    paidSelf = pay.paidSelf == true,
                    onMark = { env.payments.iPaid(item.id, it) },
                    onPaidChange = { value ->
                        paidHere = value
                        if (value) showsPay = false
                    },
                )
            }
        }
    } else if (item.board != null) {
        BrutalButton(tr("看排场"), { openBoard(context, item.board) }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
    }
}

/** 组织者、帮手的按钮：排场；当晚过了还有人没付：收款 */
@Composable
fun TonightRunButton(item: GroupTonight) {
    val router = LocalEnv.current.router
    if (item.canRun == true) {
        BrutalButton({ router.open(Route.Night(item.id)) }, size = ButtonSize.Medium) {
            Symbol(Sym.sportscourtFill, size = 15)
            Spacer(Modifier.size(AppTheme.Spacing.sm))
            Text(tr("排场"))
        }
    } else if ((item.unpaid ?: 0) > 0) {
        BrutalButton(tr("收款 · %lld 人没付", item.unpaid ?: 0), { router.open(Route.Night(item.id, pay = true)) }, kind = ButtonKind.Secondary, size = ButtonSize.Medium)
    }
}

/** 已经结束、不在“接下来的场次”里的当天场次（还能付钱、收款） */
@Composable
fun TonightPastRow(item: GroupTonight, groupName: String) {
    if (!item.hasAction) return
    val colors = AppTheme.colors
    Column(
        Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.md).padding(AppTheme.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            Text(sessionSlot(item.startsAt, item.endsAt), style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
            if (item.replacesSignup) TonightPlayerButton(item, groupName)
        }
        TonightRunButton(item)
    }
}

internal fun sessionSlot(start: Instant, end: Instant): String =
    TimeSlot.of(start.toEpochMilli(), start.toEpochMilli(), end.toEpochMilli()).formattedFull()

// MARK: - 球局页最上面的“今晚”卡

@Composable
fun TonightCard(items: List<TonightItem>, modifier: Modifier = Modifier) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val context = LocalContext.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        items.forEach { item ->
            Row(
                Modifier.fillMaxWidth()
                    .pressable(scale = 1f) {
                        when {
                            item.matchId != null -> env.router.open(Route.Match(item.matchId))
                            item.groupId != null -> env.router.open(Route.Group(item.groupId))
                        }
                    }
                    .sticker(colors.surface, radius = AppTheme.Radius.lg)
                    .padding(AppTheme.Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                IconTile(
                    if (item.kind == "match") Sym.trophyFill else Sym.sportscourtFill,
                    fill = if (item.status == "court" || item.status == "next") colors.mint else colors.sky, size = 44.dp,
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(tr("今晚 · %@", item.name), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    FitText(item.statusText, style = AppTheme.Typography.title3, color = colors.ink)
                }
                item.boardCode?.let { code ->
                    BrutalButton(tr("看全部"), { openBoard(context, code) }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
                }
            }
        }
    }
}
