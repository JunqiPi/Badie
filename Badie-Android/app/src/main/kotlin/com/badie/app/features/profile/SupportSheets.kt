package com.badie.app.features.profile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.telephony.TelephonyManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.badie.app.BuildConfig
import com.badie.app.backend.ProfileApi
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.ChoiceChip
import com.badie.app.design.IconTile
import com.badie.app.design.LegalLinks
import com.badie.app.design.LoadingDots
import com.badie.app.design.PasswordField
import com.badie.app.design.RulesButton
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.TextAction
import com.badie.app.design.Toast
import com.badie.app.design.card
import com.badie.app.design.pressable
import com.badie.app.design.rounded
import com.badie.app.design.sticker
import com.badie.app.l10n.AppLanguage
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.models.DistanceUnit
import com.badie.app.models.UserPreferences
import com.badie.app.remote.OkHttpTransport
import com.badie.app.remote.PasswordRules
import com.badie.app.remote.RemoteError
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.roundToInt

// MARK: - 帮助与反馈（对应 iPhone 的 Features/Support/HelpSheet.swift）

/** 反馈的类型：问题、想法、球馆、其他 */
enum class FeedbackKind(val rawValue: String) {
    Bug("bug"), Idea("idea"), Court("court"), Other("other");

    val title: String
        get() = when (this) {
            Bug -> L10n.tr("遇到问题")
            Idea -> L10n.tr("建议")
            Court -> L10n.tr("球馆信息")
            Other -> L10n.tr("其他")
        }

    val placeholder: String
        get() = when (this) {
            Bug -> L10n.tr("在哪个页面、做了什么、看到了什么")
            Idea -> L10n.tr("想要什么功能，用在什么场合")
            Court -> L10n.tr("球馆名字和哪里不对，或者我们漏掉的球馆")
            Other -> L10n.tr("想说什么都可以")
        }

    companion object {
        const val MAX_LENGTH = 2000
        const val MIN_LENGTH = 5

        /** 版本、系统、机型、语言：排查问题用，提交前显示给用户看 */
        val context: Map<String, String>
            get() = mapOf(
                "app" to "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                "platform" to "android",
                "os" to "Android ${Build.VERSION.RELEASE}",
                "device" to listOfNotNull(Build.MANUFACTURER, Build.MODEL).joinToString(" ").trim(),
                "locale" to AppLanguage.current,
            )

        val contextLine: String
            get() {
                val c = context
                return listOfNotNull("Badie ${c["app"] ?: ""}", c["os"], c["device"], c["locale"]).joinToString(" · ")
            }
    }
}

/** 帮助与反馈：在 App 里直接写给我们，回复会作为通知发回来；也可以发邮件 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HelpSheet(api: ProfileApi, onDismiss: () -> Unit) {
    val appState = LocalEnv.current.appState
    val scope = rememberCoroutineScope()
    var kind by remember { mutableStateOf(FeedbackKind.Bug) }
    var text by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    val trimmed = text.trim()
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = AppTheme.Spacing.screen)
            .padding(bottom = AppTheme.Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        SheetHeader(tr("帮助与反馈"), onDismiss)
        Text(tr("我们会读每一条，回复会出现在你的通知里。"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
            for (option in FeedbackKind.entries) ChoiceChip(option.title, kind == option) { kind = option }
        }
        MultilineField(kind.title, kind.placeholder, text, { text = it }, FeedbackKind.MAX_LENGTH)
        Text(tr("会一起发送：%@", FeedbackKind.contextLine), style = AppTheme.Typography.caption, color = AppTheme.colors.inkTertiary)
        BrutalButton(
            {
                isSending = true
                scope.launch {
                    try {
                        api.submitFeedback(kind.rawValue, trimmed, FeedbackKind.context)
                        appState.showToast(L10n.tr("收到了，谢谢你。"), Toast.Style.Success)
                        onDismiss()
                    } catch (error: RemoteError) {
                        appState.showError(error)
                    } finally {
                        isSending = false
                    }
                }
            },
            enabled = !isSending && trimmed.codePointCount(0, trimmed.length) >= FeedbackKind.MIN_LENGTH,
        ) {
            if (isSending) LoadingDots()
            Text(tr("发送"))
        }
        Text(tr("也可以发邮件"), style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.padding(top = AppTheme.Spacing.sm))
        ContactCard()
    }
}

/** 联系邮箱：写邮件，或者复制地址 */
@Composable
fun ContactCard() {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    fun copy() {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboard?.setPrimaryClip(ClipData.newPlainText("Badie", LegalLinks.SUPPORT_EMAIL))
        copied = true
    }
    Column(Modifier.card(AppTheme.colors.surface, shadow = AppTheme.Elevation.none), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
        Text(tr("问题、bug、建议，或者我们漏掉的球馆，都可以发邮件告诉我们。一般几天内回复。"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
        Text(LegalLinks.SUPPORT_EMAIL, style = AppTheme.Typography.bodyBold, color = AppTheme.colors.ink)
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            BrutalButton(tr("写邮件"), {
                val body = "\n\n—\nBadie ${BuildConfig.VERSION_NAME} · Android ${Build.VERSION.RELEASE}"
                val url = "mailto:${LegalLinks.SUPPORT_EMAIL}?subject=Badie&body=${android.net.Uri.encode(body)}"
                if (!context.openLink(url)) copy()
            }, kind = ButtonKind.Secondary, size = ButtonSize.Small, fullWidth = false)
            TextAction(if (copied) tr("已复制") else tr("复制邮箱地址"), { copy() })
        }
    }
}

// MARK: - 支持 Badie（对应 iPhone 的 Features/Support/TipJar.swift）

/** 安卓不做内购，只放 Ko-fi 的链接（用户 2026-11-13 定） */
object TipJar {
    /** 欧盟 27 国（ISO 两位字母） */
    private val euRegions = setOf(
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
        "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
    )

    /** 地区拿不到或在欧盟就不显示入口（和 iPhone 一样）。哪些地区最终显示，等对完 Play 的付款政策再定 */
    fun isAvailable(region: String?): Boolean {
        val code = region?.trim()?.uppercase(Locale.ROOT)
        return !code.isNullOrEmpty() && code !in euRegions
    }

    /** 安卓拿不到商店地区：先看 SIM 卡的国家，没有再看系统的地区设置 */
    fun isAvailable(context: Context): Boolean {
        val telephony = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        val sim = try {
            telephony?.simCountryIso
        } catch (_: SecurityException) {
            null
        }
        return isAvailable(sim?.takeIf { it.isNotBlank() } ?: Locale.getDefault().country)
    }
}

@Composable
fun TipJarSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        SheetHeader(tr("支持 Badie"), onDismiss)
        Text(tr("Badie 免费，没有广告。觉得好用，可以请我们喝点什么。"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
        Row(
            Modifier
                .fillMaxWidth()
                .pressable { context.openLink(LegalLinks.KOFI) }
                .sticker(AppTheme.colors.surface, radius = AppTheme.Radius.md)
                .padding(AppTheme.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md),
        ) {
            IconTile(Sym.heartFill, fill = AppTheme.colors.butter, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(tr("在 Ko-fi 上打赏"), style = AppTheme.Typography.bodyBold, color = AppTheme.colors.ink)
                Text(tr("银行卡 · 金额随意"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
            }
            Symbol(Sym.arrowUpRight, size = 13, tint = AppTheme.colors.inkTertiary)
        }
    }
}

// MARK: - 设置或修改密码（对应 iPhone 的 Features/Profile/PasswordSheet.swift）

/** 用验证码、Apple、Google 登录过的人也可以加一个密码，之后用邮箱 + 密码登录 */
@Composable
fun PasswordSheet(api: ProfileApi, onDismiss: () -> Unit) {
    val appState = LocalEnv.current.appState
    val scope = rememberCoroutineScope()
    var password by remember { mutableStateOf("") }
    var errorText by remember { mutableStateOf<String?>(null) }
    var isWorking by remember { mutableStateOf(false) }
    fun save() {
        if (password.isEmpty() || isWorking) return
        isWorking = true
        scope.launch {
            try {
                val problem = PasswordRules.problem(password, OkHttpTransport.transport)
                if (problem != null) {
                    errorText = problem
                    return@launch
                }
                api.updatePassword(password)
                appState.showToast(L10n.tr("密码已保存"), Toast.Style.Success)
                onDismiss()
            } catch (error: RemoteError) {
                errorText = error.message?.takeIf { it.isNotEmpty() } ?: L10n.tr("没能保存，请再试一次。")
            } finally {
                isWorking = false
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Column(Modifier.padding(top = AppTheme.Spacing.xl), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
            Text(tr("设置新密码"), style = AppTheme.Typography.title2, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
            Text(tr("以后可以用邮箱和这个密码登录。至少 8 位，用一句好记的话最方便。"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
        }
        PasswordField(password, { password = it; errorText = null }, placeholder = tr("新密码"), isNew = true, invalid = errorText != null, onSubmit = ::save)
        errorText?.let { Text(it, style = AppTheme.Typography.footnoteBold, color = AppTheme.colors.danger) }
        BrutalButton(::save, enabled = password.isNotEmpty() && !isWorking) {
            if (isWorking) LoadingDots()
            Text(tr("保存密码"))
        }
    }
}

// MARK: - 附近范围（对应 iPhone 的 Features/Courts/CourtsView.swift 里的 TravelRadiusSheet）

@Composable
fun TravelRadiusSheet(api: ProfileApi, onDismiss: () -> Unit) {
    val unit = DistanceUnit.current
    val low = maxOf(1.0, kotlin.math.ceil(unit.value(UserPreferences.MINIMUM_TRAVEL_RADIUS)))
    val high = kotlin.math.floor(unit.value(UserPreferences.MAXIMUM_TRAVEL_RADIUS))
    var value by remember { mutableFloatStateOf(unit.value(api.travelRadiusKm).roundToInt().toDouble().coerceIn(low, high).toFloat()) }
    val label = tr("附近范围")
    Column(
        Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Row(Modifier.padding(top = AppTheme.Spacing.xl), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = AppTheme.Typography.title, color = AppTheme.colors.ink, modifier = Modifier.semantics { heading() })
            RulesButton(label, listOf(tr("附近的球馆、球局和球群按这个范围显示。"), tr("匹配只看你选的球馆，搜索也不受范围限制。")))
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${value.roundToInt()}", style = rounded(48, androidx.compose.ui.text.font.FontWeight.Black).copy(fontFeatureSettings = "tnum"), color = AppTheme.colors.ink)
            Text(tr("%@内", unit.title), style = AppTheme.Typography.headline, color = AppTheme.colors.ink, modifier = Modifier.padding(bottom = 10.dp))
        }
        Slider(
            value, { value = it.roundToInt().toFloat() }, valueRange = low.toFloat()..high.toFloat(), steps = (high - low).toInt() - 1,
            colors = SliderDefaults.colors(thumbColor = AppTheme.colors.ink, activeTrackColor = AppTheme.colors.ink, inactiveTrackColor = AppTheme.colors.surfaceMuted, activeTickColor = AppTheme.colors.ink.copy(alpha = 0f), inactiveTickColor = AppTheme.colors.ink.copy(alpha = 0f)),
            modifier = Modifier.semantics {
                contentDescription = label
                stateDescription = "${value.roundToInt()} ${unit.title}"
            },
        )
        BrutalButton(tr("完成"), {
            api.updateTravelRadius(unit.km(value.toDouble()))
            onDismiss()
        })
    }
}
