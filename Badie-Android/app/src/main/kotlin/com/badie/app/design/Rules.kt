package com.badie.app.design

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.badie.app.l10n.tr
import kotlinx.coroutines.delay

// MARK: - 规则说明：页面上只有一个小“?”，点开是半屏的要点

/**
 * 页面本身只放名词、数字、状态词；“为什么”“怎么算”都收进这里（谁想看谁点）。
 * [points] 每条一句话
 */
@Composable
fun RulesButton(title: String, points: List<String>, modifier: Modifier = Modifier) {
    var showing by remember { mutableStateOf(false) }
    Box(
        modifier
            .size(32.dp)
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { showing = true }
            .semantics { contentDescription = title },
        contentAlignment = Alignment.Center,
    ) {
        Symbol(Sym.questionmarkCircle, size = 15, tint = AppTheme.colors.inkSecondary)
    }
    if (showing) {
        SheetScaffold(onDismiss = { showing = false }) { RulesSheet(title, points) }
    }
}

/** “?”点开的半屏：标题 + 一条条要点 */
@Composable
fun RulesSheet(title: String, points: List<String>) {
    val ink = AppTheme.colors.ink
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = AppTheme.Spacing.screen)
            .padding(bottom = AppTheme.Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
    ) {
        Text(title, style = AppTheme.Typography.title2, color = ink, modifier = Modifier.padding(top = AppTheme.Spacing.xl).semantics { heading() })
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            for (point in points) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    Box(Modifier.padding(top = 9.dp).size(5.dp).drawBehind { drawCircle(ink) })
                    Text(point, style = AppTheme.Typography.body, color = ink)
                }
            }
        }
    }
}

/** 半屏弹层的外壳：圆角 28，带拖动条，底色是页面底色 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetScaffold(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val handle = AppTheme.colors.inkTertiary
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = AppTheme.colors.canvas,
        tonalElevation = 0.dp,
        dragHandle = {
            Box(
                Modifier.padding(top = AppTheme.Spacing.sm).size(36.dp, 5.dp).drawBehind {
                    drawRoundRect(handle.copy(alpha = 0.5f), cornerRadius = CornerRadius(size.height / 2))
                },
            )
        },
    ) { content() }
}

// MARK: - 进度条

/** 柠檬色的进度条，带描边。[minimumFill] 是最少露出来的一截 */
@Composable
fun ProgressBar(progress: Float, modifier: Modifier = Modifier, height: Dp = 12.dp, minimumFill: Dp = 12.dp, label: String? = null) {
    val colors = AppTheme.colors
    val clamped = progress.coerceIn(0f, 1f)
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .drawBehind {
                val radius = CornerRadius(size.height / 2)
                drawRoundRect(colors.surfaceMuted, cornerRadius = radius)
                drawRoundRect(colors.lime, size = Size(maxOf(minimumFill.toPx(), size.width * clamped), size.height), cornerRadius = radius)
                val w = 2.dp.toPx()
                drawRoundRect(colors.stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius((size.height - w) / 2), style = Stroke(w))
            }
            .semantics {
                progressBarRangeInfo = ProgressBarRangeInfo(clamped, 0f..1f)
                if (label != null) contentDescription = label
            },
    )
}

// MARK: - 加载中的三个点

@Composable
fun LoadingDots(modifier: Modifier = Modifier) {
    val ink = androidx.compose.material3.LocalContentColor.current
    val still = reduceMotion()
    var phase by remember { mutableIntStateOf(0) }
    val label = tr("加载中")
    LaunchedEffect(still) {
        while (!still) {
            delay(350)
            phase = (phase + 1) % 3
        }
    }
    Row(modifier.semantics { contentDescription = label }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(3) { index ->
            val alpha = if (still) 0.6f else if (phase == index) 1f else 0.3f
            Box(Modifier.size(7.dp).drawBehind { drawCircle(ink.copy(alpha = alpha)) })
        }
    }
}

/** 系统关了动画（“移除动画”）时，弹跳、闪动这类装饰动效要停掉 */
@Composable
fun reduceMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) {
        android.provider.Settings.Global.getFloat(resolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

// MARK: - 文字高亮（柠檬色马克笔）

/**
 * 星号之间的部分高亮：柠檬绿底、墨色字（深浅模式都看得清），比如 "找个*搭子*打一场"。
 * 整句一起翻译，高亮的词在哪跟着语言走
 */
@Composable
fun markedText(text: String): AnnotatedString {
    val colors = AppTheme.colors
    return buildAnnotatedString {
        text.split("*").forEachIndexed { index, part ->
            if (index % 2 == 1) {
                withStyle(SpanStyle(background = colors.lime, color = colors.onAccent)) { append(part) }
            } else {
                append(part)
            }
        }
    }
}

// MARK: - 用户协议、隐私政策、联系我们：网站上的页面，在浏览器里打开

object LegalLinks {
    const val TERMS = "https://badie.rsvp/terms/"
    const val PRIVACY = "https://badie.rsvp/privacy/"
    const val CONTACT = "https://badie.rsvp/contact/"
    const val SUPPORT_EMAIL = "support@badie.rsvp"
    /** Ko-fi 主页（打赏） */
    const val KOFI = "https://ko-fi.com/badie"
}

/** 一排三个链接；一行放不下会自己换行 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LegalLinksRow(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val color = AppTheme.colors.inkSecondary
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.xs)) {
        for ((title, url) in listOf(tr("用户协议") to LegalLinks.TERMS, tr("隐私政策") to LegalLinks.PRIVACY, tr("联系我们") to LegalLinks.CONTACT)) {
            Text(
                title, style = AppTheme.Typography.footnoteBold.copy(textDecoration = TextDecoration.Underline), color = color,
                modifier = Modifier.clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
                    context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
                },
            )
        }
    }
}
