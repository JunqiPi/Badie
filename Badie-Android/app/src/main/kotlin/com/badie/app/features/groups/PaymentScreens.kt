package com.badie.app.features.groups

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.InsetDivider
import com.badie.app.design.MenuRow
import com.badie.app.design.ScreenHeader
import com.badie.app.design.SheetScaffold
import com.badie.app.design.StickerTextField
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TagPill
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rememberHaptics
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.features.social.copyText
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DateText
import com.badie.app.models.FeeText
import com.badie.app.models.GroupLedger
import com.badie.app.models.LedgerRow
import com.badie.app.models.MyDue
import com.badie.app.models.NightPay
import com.badie.app.models.PayLinks
import com.badie.app.models.PaymentHandles
import com.badie.app.models.SessionTimes
import com.badie.app.models.TimeSlot
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.Route
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// 收款：对应 iPhone 的 Features/Night/LedgerViews.swift、PaySheet.swift 和当晚页的收款分段。
// 钱不经过 Badie：付钱的人点 Venmo / Cash App / PayPal 打开对应的网页或 App，Zelle 只能复制，付完自己点“我付了”

private fun zoneOf(tz: String?): ZoneId = tz?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.systemDefault()

private fun Instant.slotText(end: Instant, tz: String?): String {
    val zone = zoneOf(tz)
    return TimeSlot.of(toEpochMilli(), toEpochMilli(), end.toEpochMilli(), zone).formattedFull(zone = zone)
}

private fun openLink(context: Context, uri: Uri) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: Exception) {
    }
}

// MARK: - 你还没付（球群页最上面、球局页）

/** 按球群和收钱的人合起来的几场 */
private class Pile(val dues: List<MyDue>) {
    val first: MyDue get() = dues.first()
    val key: String get() = "${first.groupId}:${first.toId}"
    val total: Double get() = dues.sumOf { it.amount }
    val dates: String get() = dues.joinToString(", ") { DateText.monthDay(it.startsAt.toEpochMilli(), zoneOf(it.tz)) }
}

/** 写了金额、还没付的场次：一张卡一个大按钮，几场一次付清（每一场都记“我付了”）。没有就什么都不显示 */
@Composable
fun DuesCard(dues: List<MyDue>, modifier: Modifier = Modifier, showsGroup: Boolean = true, onPaid: () -> Unit) {
    if (dues.isEmpty()) return
    val colors = AppTheme.colors
    var paying by remember { mutableStateOf<String?>(null) }
    val piles = dues.groupBy { "${it.groupId}:${it.toId}" }.values
        .map { list -> Pile(list.sortedBy { it.startsAt }) }
        .sortedBy { it.first.startsAt }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        piles.forEach { pile ->
            Column(
                Modifier.fillMaxWidth().sticker(colors.butter, radius = AppTheme.Radius.lg).padding(AppTheme.Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
            ) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(tr("你还没付"), style = AppTheme.Typography.headline, color = colors.onAccent)
                        Text(
                            if (showsGroup) "${pile.first.group} · ${pile.dates}" else pile.dates,
                            style = AppTheme.Typography.footnoteBold, color = colors.onAccent.copy(alpha = 0.75f), maxLines = 2,
                        )
                    }
                    Text(FeeText.text(pile.total), style = AppTheme.Typography.title2, color = colors.onAccent)
                }
                BrutalButton({ paying = pile.key }) {
                    Symbol(Sym.banknote, size = 16)
                    Spacer(Modifier.size(AppTheme.Spacing.sm))
                    Text(tr("付给 %@ · %@", pile.first.to, FeeText.text(pile.total)), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
    piles.firstOrNull { it.key == paying }?.let { pile ->
        SheetScaffold(onDismiss = { paying = null }) {
            PaySheet(pile) {
                paying = null
                onPaid()
            }
        }
    }
}

/** 付给组织者：金额、各个 App 的按钮、Zelle 复制、“我付了”（几场一起标） */
@Composable
private fun PaySheet(pile: Pile, onPaid: () -> Unit) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) }
    val handles = pile.first.handles ?: PaymentHandles()
    val note = "Badie · ${pile.first.group} · ${pile.dates}"
    val copied = tr("已复制")
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.lg)
            .navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                Text(tr("付给 %@", pile.first.to), style = AppTheme.Typography.title2, color = colors.ink, modifier = Modifier.semantics { heading() })
                Text("${pile.first.group} · ${pile.dates}", style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            }
            Text(FeeText.text(pile.total), style = rounded(40, FontWeight.Black), color = colors.ink)
        }
        handles.venmo?.takeIf { it.isNotEmpty() }?.let { AppRow("Venmo", "@$it") { openLink(context, PayLinks.venmo(it, pile.total, note)) } }
        handles.cashapp?.takeIf { it.isNotEmpty() }?.let { AppRow("Cash App", "$$it") { openLink(context, PayLinks.cashApp(it, pile.total)) } }
        handles.paypal?.takeIf { it.isNotEmpty() }?.let { AppRow("PayPal", it) { openLink(context, PayLinks.payPal(it, pile.total)) } }
        handles.zelle?.takeIf { it.isNotEmpty() }?.let { zelle ->
            Row(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).sticker(colors.surface, radius = 16.dp, shadow = AppTheme.Elevation.none)
                    .padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Zelle", style = AppTheme.Typography.headline, color = colors.ink)
                    Text(zelle, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                BrutalButton({
                    copyText(context, zelle)
                    env.appState.showToast(copied, Toast.Style.Success)
                }, kind = ButtonKind.Accent(colors.surfaceMuted), size = ButtonSize.Small, fullWidth = false) {
                    Symbol(Sym.docOnDoc, size = 14)
                    Spacer(Modifier.size(AppTheme.Spacing.xs))
                    Text(tr("复制"))
                }
            }
        }
        if (handles.isEmpty) {
            Text(tr("%@ 还没填收款方式，当面付就行。", pile.first.to), style = AppTheme.Typography.subheadline, color = colors.inkSecondary)
        } else {
            Text(tr("备注：%@", note), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
        }
        BrutalButton(tr("我付了"), {
            saving = true
            scope.launch {
                try {
                    pile.dues.forEach { env.payments.iPaid(it.sessionId, true) }
                    haptics.success()
                    onPaid()
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
                saving = false
            }
        }, enabled = !saving)
    }
}

@Composable
private fun AppRow(name: String, handle: String, onClick: () -> Unit) {
    val colors = AppTheme.colors
    Row(
        Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).pressable(scale = 0.98f, onClick = onClick)
            .sticker(colors.surface, radius = 16.dp).padding(horizontal = AppTheme.Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Text(name, style = AppTheme.Typography.headline, color = colors.ink, modifier = Modifier.weight(1f))
        Text(handle, style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1)
        Symbol(Sym.arrowUpRight, size = 13, tint = colors.inkSecondary)
    }
}

// MARK: - 收款记录（只有组织者）

@Composable
fun GroupLedgerScreen(groupId: String) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    var ledger by remember(groupId) { mutableStateOf<GroupLedger?>(null) }
    val earlier = remember(groupId) { mutableStateListOf<GroupLedger.Session>() }
    var reachedEnd by remember(groupId) { mutableStateOf(false) }
    var failed by remember(groupId) { mutableStateOf(false) }
    var busy by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableStateOf(0) }
    val marked = tr("已标成已付")
    val headers = listOf(tr("日期"), tr("时间"), tr("球馆"), tr("球友"), tr("访客"), tr("金额"), tr("已付"), tr("自己标的"))
    val guestWord = tr("访客")
    val selfWord = tr("自己标的")
    val exemptWord = tr("不用付")

    LaunchedEffect(groupId, reload) {
        try {
            ledger = env.payments.groupLedger(groupId)
            earlier.clear()
            reachedEnd = false
            failed = false
        } catch (_: RemoteError) {
            if (ledger == null) failed = true
        }
    }
    val sessions = ledger?.sessions.orEmpty() + earlier

    fun export() {
        busy = "export"
        scope.launch {
            try {
                val rows = env.payments.groupLedgerRows(groupId)
                LedgerExport.share(context, rows, headers, guestWord, selfWord, exemptWord)
            } catch (error: RemoteError) {
                env.appState.showError(error)
            }
            busy = null
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("收款"), onBack = { env.router.pop() }) {
            if (sessions.isNotEmpty()) IconButton(Sym.squareAndArrowUp, tr("导出")) { if (busy == null) export() }
        }
        val current = ledger
        when {
            current != null && sessions.isEmpty() ->
                EmptyStateView(Sym.banknote, tr("还没有开过的场次。"), message = tr("每一场开始后会出现在这里。"))
            current != null -> Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xl),
            ) {
                val owed = current.owed.orEmpty()
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        Text(tr("还欠着"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
                        if (owed.isNotEmpty()) Text(FeeText.text(owed.sumOf { it.amount }), style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                    }
                    if (owed.isEmpty()) {
                        Row(Modifier.fillMaxWidth().card(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                            Symbol(Sym.checkmarkCircleFill, size = 18, tint = colors.success)
                            Text(tr("都付了。"), style = AppTheme.Typography.bodyBold, color = colors.ink)
                        }
                    } else {
                        Column(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg).padding(horizontal = AppTheme.Spacing.lg)) {
                            owed.forEachIndexed { index, person ->
                                if (index > 0) InsetDivider()
                                Row(Modifier.defaultMinSize(minHeight = 64.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(person.name, style = AppTheme.Typography.bodyBold, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                            if (person.guest) TagPill(tr("访客"), fill = colors.mint)
                                        }
                                        Text("${tr("%lld 场", person.sessions)} · ${FeeText.text(person.amount)}", style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary)
                                    }
                                    BrutalButton(tr("标成已付"), {
                                        busy = person.key
                                        scope.launch {
                                            try {
                                                env.payments.markSignupsPaid(person.signups, true)
                                                haptics.success()
                                                env.appState.showToast(marked, Toast.Style.Success)
                                                reload++
                                            } catch (error: RemoteError) {
                                                env.appState.showError(error)
                                            }
                                            busy = null
                                        }
                                    }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false, enabled = busy == null)
                                }
                            }
                        }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Text(tr("开过的场次"), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
                    sessions.forEach { session -> LedgerSessionRow(session) { env.router.open(Route.SessionPayments(session.id)) } }
                    if (!reachedEnd && sessions.size >= GroupLedger.PAGE_SIZE) {
                        BrutalButton(tr("看更早的场次"), {
                            busy = "more"
                            scope.launch {
                                try {
                                    val page = env.payments.groupLedger(groupId, before = sessions.last().startsAt)
                                    earlier.addAll(page.sessions)
                                    if (page.sessions.size < GroupLedger.PAGE_SIZE) reachedEnd = true
                                } catch (error: RemoteError) {
                                    env.appState.showError(error)
                                }
                                busy = null
                            }
                        }, kind = ButtonKind.Secondary, size = ButtonSize.Medium, enabled = busy == null)
                    }
                }
            }
            failed -> EmptyStateView(Sym.lockFill, tr("只有组织者能看。"))
            else -> Box(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.ink)
            }
        }
    }
}

@Composable
private fun LedgerSessionRow(session: GroupLedger.Session, onClick: () -> Unit) {
    val colors = AppTheme.colors
    val all = session.owes > 0 && session.paid >= session.owes
    // 没写金额、也没人付过的（多半是以前没用收款的场次）不显示“已付 0/18”
    val tag = session.owes > 0 && (session.amount != null || session.paid > 0)
    Row(
        Modifier.fillMaxWidth().pressable(scale = 0.98f, onClick = onClick).sticker(colors.surface, radius = AppTheme.Radius.md).padding(AppTheme.Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(session.startsAt.slotText(session.endsAt, session.tz), style = AppTheme.Typography.bodyBold, color = colors.ink)
            Text(
                listOf(FeeText.price(session.amount) ?: tr("没写金额"), session.venue).joinToString(" · "),
                style = AppTheme.Typography.footnoteBold, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        if (tag) {
            TagPill(tr("已付 %lld/%lld", session.paid, session.owes), icon = if (all) Sym.checkmark else null, fill = if (all) colors.mint else colors.butter)
        }
        Symbol(Sym.chevronRight, size = 14, tint = colors.inkTertiary)
    }
}

// MARK: - 某一场的收款（收款记录点进来；和 iPhone 当晚页的“收款”一样）

@Composable
fun SessionPaymentsScreen(sessionId: String) {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var times by remember(sessionId) { mutableStateOf<SessionTimes?>(null) }
    var pay by remember(sessionId) { mutableStateOf<NightPay?>(null) }
    var loaded by remember(sessionId) { mutableStateOf(false) }
    var feeText by remember(sessionId) { mutableStateOf("") }
    var showsPaid by remember { mutableStateOf(false) }
    var showsExempt by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }

    LaunchedEffect(sessionId, reload) {
        try {
            if (times == null) times = env.payments.sessionTimes(sessionId)
            if (times?.role == "organizer") {
                val next = env.payments.nightPay(sessionId)
                if (pay == null || pay?.amount != next.amount) feeText = next.amount?.let(FeeText::plain) ?: ""
                pay = next
            }
        } catch (_: RemoteError) {
        }
        loaded = true
    }

    fun act(work: suspend () -> Unit) {
        scope.launch {
            try {
                work()
            } catch (error: RemoteError) {
                env.appState.showError(error)
            }
            reload++
        }
    }

    val remindedToast = { count: Int -> L10n.tr("已提醒 %lld 人", count) }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("收款"), onBack = { env.router.pop() })
        times?.let { Text(it.startsAt.slotText(it.endsAt, it.tz), style = AppTheme.Typography.caption, color = colors.inkSecondary, modifier = Modifier.align(Alignment.CenterHorizontally)) }
        val current = pay
        val session = times
        when {
            current != null && session != null -> {
                Column(
                    Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen)
                        .padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.xxl),
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
                ) {
                    // 每人多少钱（空 = 不写，0 = 这一场免费）
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        Text(tr("每人"), style = AppTheme.Typography.headline, color = colors.ink)
                        StickerTextField(
                            feeText, { feeText = it }, "", Modifier.width(130.dp),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        )
                        Spacer(Modifier.weight(1f))
                        val clean = feeText.trim().replace(",", ".")
                        BrutalButton(tr("保存"), {
                            act { env.payments.setSessionFee(sessionId, clean.toDoubleOrNull()) }
                        }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false,
                            enabled = feeText != (current.amount?.let(FeeText::plain) ?: "") && (clean.isEmpty() || clean.toDoubleOrNull() != null))
                    }
                    // 已付几人 / 要付几人
                    Column(Modifier.fillMaxWidth().card(fill = colors.mint, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
                        Text(tr("已付"), style = AppTheme.Typography.footnoteBold, color = colors.onAccent)
                        Text("${current.owing.count { it.paid }}/${current.owing.size}", style = rounded(40, FontWeight.Black), color = colors.onAccent)
                        current.amount?.let { Text(tr("每人 %@", FeeText.text(it)), style = AppTheme.Typography.subheadlineBold, color = colors.onAccent) }
                    }
                    if (current.hasHandles == false && current.payeeIsMe != false) {
                        Box(Modifier.fillMaxWidth().sticker(colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.lg)) {
                            MenuRow(Sym.banknote, tr("填收款方式"), tint = colors.butter) { env.router.open(Route.PaymentHandles) }
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                        Text(tr("没付 %lld", current.unpaid.size), style = AppTheme.Typography.title3, color = colors.ink, modifier = Modifier.semantics { heading() })
                        if (current.unpaid.isNotEmpty()) {
                            PeopleCard(current.unpaid) { person ->
                                PayName(person, Modifier.weight(1f))
                                TextAction(tr("不用付"), { act { env.payments.setSignupOwes(person.id, false) } })
                                val label = tr("%@ 标为已付", person.name)
                                Box(
                                    Modifier.size(48.dp).semantics { contentDescription = label }.pressable { act { env.payments.markSignupPaid(person.id, true) } },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Box(Modifier.size(28.dp).border(2.dp, colors.stroke, CircleShape))
                                }
                            }
                        }
                    }
                    Collapsible(tr("已付 %lld", current.paid.size), showsPaid, { showsPaid = it }) {
                        PeopleCard(current.paid) { person ->
                            PayName(person, Modifier.weight(1f))
                            if (person.paidSelf == true) Text(tr("自己标的"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
                            val label = tr("%@ 改回没付", person.name)
                            Box(
                                Modifier.size(48.dp).semantics { contentDescription = label }.pressable { act { env.payments.markSignupPaid(person.id, false) } },
                                contentAlignment = Alignment.Center,
                            ) {
                                Symbol(Sym.checkmarkCircleFill, size = 28, tint = colors.success)
                            }
                        }
                    }
                    if (current.exempt.isNotEmpty()) {
                        Collapsible(tr("不用付 %lld", current.exempt.size), showsExempt, { showsExempt = it }) {
                            PeopleCard(current.exempt) { person ->
                                PayName(person, Modifier.weight(1f))
                                BrutalButton(tr("加回来"), { act { env.payments.setSignupOwes(person.id, true) } }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
                            }
                        }
                    }
                }
                // 提醒没付的：不能提醒时写原因
                val now = Instant.now()
                val blocked = when {
                    current.unpaid.isEmpty() -> tr("都付了。")
                    current.canRemind == true -> null
                    current.remindedAt?.let { now.epochSecond - it.epochSecond < 12 * 3600 } == true -> tr("12 小时内提醒过了。")
                    now < session.startsAt -> tr("开场后才能提醒。")
                    else -> tr("结束 7 天后不能再提醒。")
                }
                Column(
                    Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg).navigationBarsPadding(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs),
                ) {
                    blocked?.let { Text(it, style = AppTheme.Typography.caption, color = colors.inkSecondary) }
                    BrutalButton({
                        scope.launch {
                            try {
                                val count = env.payments.remindUnpaid(sessionId)
                                env.appState.showToast(remindedToast(count), Toast.Style.Success)
                            } catch (error: RemoteError) {
                                env.appState.showError(error)
                            }
                            reload++
                        }
                    }, enabled = blocked == null) {
                        Symbol(Sym.bellFill, size = 16)
                        Spacer(Modifier.size(AppTheme.Spacing.sm))
                        Text(tr("提醒没付的"))
                    }
                }
            }
            loaded -> EmptyStateView(Sym.lockFill, tr("只有组织者能看。"))
            else -> Box(Modifier.fillMaxWidth().padding(top = AppTheme.Spacing.xxl), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.ink)
            }
        }
    }
}

@Composable
private fun PeopleCard(people: List<NightPay.Person>, row: @Composable androidx.compose.foundation.layout.RowScope.(NightPay.Person) -> Unit) {
    Column(Modifier.fillMaxWidth().sticker(AppTheme.colors.surface, radius = AppTheme.Radius.lg, shadow = AppTheme.Elevation.none).padding(start = AppTheme.Spacing.lg, end = AppTheme.Spacing.xs)) {
        people.forEachIndexed { index, person ->
            if (index > 0) InsetDivider()
            Row(Modifier.defaultMinSize(minHeight = 52.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                row(person)
            }
        }
    }
}

@Composable
private fun PayName(person: NightPay.Person, modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(person.name, style = AppTheme.Typography.headline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (person.guest) {
            TagPill(tr("访客"), fill = colors.mint)
            if (person.email == false) Text(tr("没留邮箱"), style = AppTheme.Typography.caption, color = colors.inkSecondary)
        }
    }
}

/** 已付、不用付：收起来，点开再看 */
@Composable
private fun Collapsible(title: String, isOpen: Boolean, onToggle: (Boolean) -> Unit, content: @Composable () -> Unit) {
    val colors = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).pressable(scale = 1f) { onToggle(!isOpen) }
                .sticker(colors.surfaceMuted, radius = 16.dp, shadow = AppTheme.Elevation.none).padding(horizontal = AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = AppTheme.Typography.bodyBold, color = colors.ink, modifier = Modifier.weight(1f))
            Symbol(Sym.chevronDown, size = 13, tint = colors.ink, modifier = Modifier.rotate(if (isOpen) 180f else 0f))
        }
        if (isOpen) content()
    }
}

// MARK: - 我的 → 收款方式

@Composable
fun PaymentHandlesScreen() {
    val env = LocalEnv.current
    val colors = AppTheme.colors
    val scope = rememberCoroutineScope()
    var handles by remember { mutableStateOf(PaymentHandles()) }
    var saving by remember { mutableStateOf(false) }
    val saved = tr("已保存")
    LaunchedEffect(Unit) {
        try {
            handles = env.payments.myPaymentHandles()
        } catch (_: RemoteError) {
        }
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(tr("收款方式"), onBack = { env.router.pop() })
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            Text(tr("只给同一场的人看。都可以不填。"), style = AppTheme.Typography.footnote, color = colors.inkSecondary)
            HandleField(tr("Venmo 用户名"), "@name", handles.venmo.orEmpty()) { handles = handles.copy(venmo = it) }
            HandleField(tr("Cash App 的 \$cashtag"), "\$cashtag", handles.cashapp.orEmpty()) { handles = handles.copy(cashapp = it) }
            HandleField(tr("PayPal.me 用户名"), "paypal.me/name", handles.paypal.orEmpty()) { handles = handles.copy(paypal = it) }
            HandleField(tr("Zelle 邮箱或手机号"), "", handles.zelle.orEmpty(), KeyboardType.Email) { handles = handles.copy(zelle = it) }
        }
        BrutalButton(tr("保存"), {
            saving = true
            scope.launch {
                try {
                    env.payments.setPaymentHandles(handles)
                    env.appState.showToast(saved, Toast.Style.Success)
                    env.router.pop()
                } catch (error: RemoteError) {
                    env.appState.showError(error)
                }
                saving = false
            }
        }, Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.md, bottom = AppTheme.Spacing.lg).navigationBarsPadding(), enabled = !saving)
    }
}

@Composable
private fun HandleField(label: String, placeholder: String, value: String, keyboard: KeyboardType = KeyboardType.Ascii, onChange: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        Text(label, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
        StickerTextField(value, onChange, placeholder, Modifier.fillMaxWidth(), style = AppTheme.Typography.body,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, autoCorrectEnabled = false))
    }
}

// MARK: - 编辑球群：每周场次的价格

/** 空 = 不写，0 = 免费。输入的字自己记着，能读成数字时才写回去（输到“12.”时不跳） */
@Composable
fun PriceField(price: Double?, onChange: (Double?) -> Unit) {
    var text by remember { mutableStateOf(price?.let(FeeText::plain) ?: "") }
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        Text(tr("每人价格（选填）"), style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.inkSecondary)
        StickerTextField(text, { value ->
            text = value
            val clean = value.trim().replace(",", ".")
            if (clean.isEmpty()) onChange(null) else clean.toDoubleOrNull()?.let { onChange(Math.round(it * 100) / 100.0) }
        }, tr("0 = 免费"), Modifier.fillMaxWidth(), style = AppTheme.Typography.body, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
    }
}

// MARK: - 导出成表格（CSV）

object LedgerExport {
    /** 日期和时间按球馆当地（2026-11-18、19:00），表格里好排序 */
    private fun local(instant: Instant, tz: String?): Pair<String, String> {
        val time = instant.atZone(zoneOf(tz))
        return DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.ROOT).format(time) to DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT).format(time)
    }

    private fun cell(text: String): String =
        if (text.any { it == ',' || it == '"' || it == '\n' }) "\"" + text.replace("\"", "\"\"") + "\"" else text

    fun csv(rows: List<LedgerRow>, headers: List<String>, guest: String, self: String, exempt: String): String {
        val lines = rows.map { row ->
            val (date, time) = local(row.startsAt, row.tz)
            val paid = row.paidAt?.let { local(it, row.tz).first } ?: if (row.owes) "" else exempt
            listOf(date, time, row.venue, row.name, if (row.guest) guest else "", row.amount?.let(FeeText::plain) ?: "", paid, if (row.paidSelf) self else "")
        }
        // 带 BOM，Excel 打开中文不乱码
        return Char(0xFEFF) + (listOf(headers) + lines).joinToString("\r\n") { line -> line.joinToString(",", transform = ::cell) }
    }

    fun share(context: Context, rows: List<LedgerRow>, headers: List<String>, guest: String, self: String, exempt: String) {
        val folder = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(folder, "badie-payments-${local(Instant.now(), null).first}.csv")
        file.writeText(csv(rows, headers, guest, self, exempt))
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).setType("text/csv").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
