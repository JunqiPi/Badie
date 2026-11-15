package com.badie.app.design

import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.badie.app.R

// 设计系统 "Court Pop"：米白球场底、墨色描边、硬投影、柠檬主色、马卡龙贴纸辅色。
// 数值和 iPhone 的 DesignSystem/Theme.swift 一一对应。
// 规则：柠檬绿只作填充色，上面的文字永远用 onAccent（墨色）。

@Immutable
class BadieColors(
    val canvas: Color,
    val surface: Color,
    val surfaceMuted: Color,
    val divider: Color,
    val ink: Color,
    val inkSecondary: Color,
    /** 只用在禁用态、装饰或大号文字（对比度约 3:1） */
    val inkTertiary: Color,
    val stroke: Color,
    val shadow: Color,
    val inverse: Color,
    val onInverse: Color,
    val lavender: Color,
    val peach: Color,
    val pink: Color,
    val sky: Color,
    val butter: Color,
    val mint: Color,
    val danger: Color,
    val success: Color,
) {
    /** 强调色上的文字和图标，深浅模式一样 */
    val onAccent = Color(0xFF17140F)
    val lime = Color(0xFFD4F33F)
    val dangerFill = Color(0xFFD22F35)
    val star = Color(0xFFFFB800)

    /** 头像、贴纸的调色板（按用户 ID 稳定取色） */
    val palette: List<Color> get() = listOf(lavender, sky, peach, mint, butter, pink)

    fun paletteColor(index: Int): Color = palette[Math.floorMod(index, palette.size)]
}

internal val LightColors = BadieColors(
    canvas = Color(0xFFF5F0E6), surface = Color(0xFFFFFFFF), surfaceMuted = Color(0xFFEDE6D8), divider = Color(0xFFE6DFD0),
    ink = Color(0xFF17140F), inkSecondary = Color(0xFF5B554B), inkTertiary = Color(0xFF8C8579),
    stroke = Color(0xFF17140F), shadow = Color(0xFF17140F), inverse = Color(0xFF17140F), onInverse = Color(0xFFF5F0E6),
    lavender = Color(0xFFC8BEFF), peach = Color(0xFFFFC98F), pink = Color(0xFFFFB3CF), sky = Color(0xFFA8D8FF),
    butter = Color(0xFFFFE36E), mint = Color(0xFF9FE8C3), danger = Color(0xFFC92A2F), success = Color(0xFF1F7A47),
)

internal val DarkColors = BadieColors(
    canvas = Color(0xFF16131D), surface = Color(0xFF221E2B), surfaceMuted = Color(0xFF2C2737), divider = Color(0xFF332D40),
    ink = Color(0xFFF4EFE6), inkSecondary = Color(0xFFB9B2A6), inkTertiary = Color(0xFF857D90),
    stroke = Color(0xFF756A90), shadow = Color(0xFF07060A), inverse = Color(0xFFF4EFE6), onInverse = Color(0xFF17140F),
    lavender = Color(0xFFB3A6FF), peach = Color(0xFFF5B97A), pink = Color(0xFFF79CC0), sky = Color(0xFF8EC8F5),
    butter = Color(0xFFF2D45C), mint = Color(0xFF86D9B0), danger = Color(0xFFFF6B6E), success = Color(0xFF5BD38F),
)

private val LocalBadieColors = staticCompositionLocalOf { LightColors }

/** 圆体：拉丁字母和数字用 Nunito（网站也是它），中日韩等文字落到系统字体，和 iPhone 的做法一样 */
private fun nunito(weight: FontWeight) = Font(
    R.font.nunito, weight = weight,
    variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)),
)

val RoundedFamily = FontFamily(
    nunito(FontWeight.Medium), nunito(FontWeight.SemiBold), nunito(FontWeight.Bold),
    nunito(FontWeight.ExtraBold), nunito(FontWeight.Black),
)

/** 用 sp，跟着系统字号放大缩小 */
fun rounded(size: Int, weight: FontWeight): TextStyle =
    TextStyle(fontFamily = RoundedFamily, fontSize = size.sp, fontWeight = weight, lineHeight = (size * 1.3f).sp)

object AppTheme {
    val colors: BadieColors
        @Composable @ReadOnlyComposable get() = LocalBadieColors.current

    /** 字号对应 iPhone 的系统文字样式（标准字号下的点数） */
    object Typography {
        val display = rounded(34, FontWeight.Black)
        val title = rounded(28, FontWeight.ExtraBold)
        val title2 = rounded(22, FontWeight.ExtraBold)
        val title3 = rounded(20, FontWeight.Bold)
        val headline = rounded(17, FontWeight.Bold)
        val body = rounded(17, FontWeight.Medium)
        val bodyBold = rounded(17, FontWeight.Bold)
        val callout = rounded(16, FontWeight.Medium)
        val subheadline = rounded(15, FontWeight.Medium)
        val subheadlineBold = rounded(15, FontWeight.Bold)
        val footnote = rounded(13, FontWeight.Medium)
        val footnoteBold = rounded(13, FontWeight.Bold)
        val caption = rounded(12, FontWeight.SemiBold)
        val overline = rounded(11, FontWeight.ExtraBold)
    }

    /** 间距（4 的倍数） */
    object Spacing {
        val xxs = 2.dp
        val xs = 4.dp
        val sm = 8.dp
        val md = 12.dp
        val lg = 16.dp
        val xl = 20.dp
        val xxl = 24.dp
        val xxxl = 32.dp
        /** 页面左右边距 */
        val screen = 20.dp
        /** 给悬浮标签栏留的底部空白 */
        val tabBarClearance = 110.dp
    }

    object Radius {
        val sm = 10.dp
        val md = 14.dp
        val lg = 20.dp
        val xl = 26.dp
    }

    object Stroke {
        val width = 2.dp
        val hairline = 1.5.dp
    }

    object Elevation {
        /** 卡片、贴纸：右下硬投影 */
        val card = DpOffset(3.dp, 4.dp)
        /** 小元素 */
        val low = DpOffset(2.dp, 2.dp)
        val none = DpOffset(0.dp, 0.dp)
        /** 按钮：垂直投影，按下时压平 */
        val buttonDepth: Dp = 4.dp
    }

    object Motion {
        fun <T> press(): FiniteAnimationSpec<T> = tween(120, easing = LinearOutSlowInEasing)
        fun <T> standard(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.78f, stiffness = 320f)
        fun <T> bouncy(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.6f, stiffness = 195f)
        fun <T> gentle(): FiniteAnimationSpec<T> = tween(300, easing = FastOutSlowInEasing)
        const val collisionMillis = 700
    }
}

/** 外观：跟随系统、浅色、深色（设置里选） */
enum class Appearance { System, Light, Dark }

@Composable
fun BadieTheme(appearance: Appearance = Appearance.System, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        Appearance.System -> isSystemInDarkTheme()
        Appearance.Light -> false
        Appearance.Dark -> true
    }
    CompositionLocalProvider(LocalBadieColors provides if (dark) DarkColors else LightColors, content = content)
}
