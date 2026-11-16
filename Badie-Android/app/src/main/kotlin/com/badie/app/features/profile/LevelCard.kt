package com.badie.app.features.profile

import android.content.Context
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import com.badie.app.R
import com.badie.app.backend.VenueName
import com.badie.app.design.RoundedFamily
import com.badie.app.l10n.AppLanguage
import com.badie.app.l10n.L10n.tr
import com.badie.app.models.AssessmentGap
import com.badie.app.models.GameMode
import com.badie.app.models.PlayAxis
import com.badie.app.models.PlayProfile
import com.badie.app.models.PlayStyle
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillAssessmentResult
import com.badie.app.models.SkillLevel
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import com.badie.app.models.UsualTimeText
import com.badie.app.models.activeSlots
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// MARK: - 等级卡片：测级结果做成图片分享
//
// 一张 4:5 的卡，导出 1080×1350。图片就是卡片本身，有正面和背面：
// 正面是人物、头像、名字、打法和最强一拍；背面是知道的几行资料、离下一级还差什么、六项数字。
// App 里一次看一面，点一下翻面；分享的是当前这一面。所有打法用同一套颜色。
// 对应 iPhone 的 Features/LevelCard/LevelCardViews.swift；人物插画是 res/drawable-nodpi/play_<打法>.png（和网站同一套）。
// 卡片在本机画，不经过服务器；昵称和头像只印在图片上。

/** 卡片上的等级来源 */
enum class LevelCardLabel {
    /** 问卷自评 */
    SelfRated,
    /** 打过球、球友评价已经校准过等级 */
    Calibrated,
    /** 7–9 级审核通过 */
    Verified;

    val title: String
        get() = when (this) {
            SelfRated -> tr("自评")
            Calibrated -> tr("已校准")
            Verified -> tr("已认证")
        }

    companion object {
        fun of(user: User): LevelCardLabel = when {
            user.verifiedRating != null -> Verified
            !user.reputation.isNewPlayer -> Calibrated
            else -> SelfRated
        }
    }
}

/** 卡片的两面 */
enum class LevelCardFace { Front, Back }

/** 背面的一行 */
data class LevelCardRow(val label: String, val value: String)

/** 卡片上印的内容：只放已知的，不知道的那一行不显示 */
data class LevelCardData(
    val tier: SkillTier,
    val label: LevelCardLabel,
    /** “阿杰#3400” */
    val name: String? = null,
    /** 常去球馆所在的城市 */
    val region: String? = null,
    val play: PlayProfile? = null,
    val gap: AssessmentGap? = null,
    val mode: GameMode? = null,
    val venue: String? = null,
    val times: String? = null,
    /** 头像照片；没传过照片时为空 */
    val avatar: ImageBitmap? = null,
    /** 印网址（发小红书时关掉，改印“App Store 搜 Badie 羽毛球”） */
    val showsURL: Boolean = true,
    /** 印头像（有照片时才有用） */
    val showsAvatar: Boolean = true,
) {
    /** 这一档的网页（带 ?ref=card，网站据此显示“你的朋友是 4+。你呢？”） */
    val link: String get() = url(tier)

    /** “4+ 中级” */
    val tierLine: String get() = "${tier.code} ${tier.name}"

    /** 名字下面的小字：“LOS ANGELES · 4+ 中级 · 自评”，只印知道的。正面没有名字时大字已经是等级，不再印一遍 */
    fun subline(includesTier: Boolean = true): String =
        listOfNotNull(region?.uppercase(), if (includesTier) tierLine else null, label.title).joinToString(" · ")

    /** 背面的几行：只放知道的，最多 4 行 */
    val backRows: List<LevelCardRow>
        get() {
            val rows = mutableListOf<LevelCardRow>()
            mode?.let { rows += LevelCardRow(tr("偏好"), it.title) }
            venue?.let { rows += LevelCardRow(tr("常去球馆"), it) }
            times?.let { rows += LevelCardRow(tr("空闲时间"), it) }
            play?.let { rows += LevelCardRow(tr("最佳搭档"), it.style.partnerText) }
            // 什么都不知道时，印这一档的标准
            if (rows.isEmpty()) SkillLevel.tierCriteria(tier).firstOrNull()?.let { rows += LevelCardRow(tierLine, it) }
            return rows.take(4)
        }

    /** 底边的落款：网址或“App Store 搜 Badie 羽毛球” */
    val footer: String get() = if (showsURL) "BADIE.RSVP/LEVELS" else tr("App Store 搜 Badie 羽毛球")

    /** 要印的头像（没有照片或关掉了就是空） */
    val avatarImage: ImageBitmap? get() = if (showsAvatar) avatar else null

    /** 读屏念当前这一面上的字 */
    fun spokenSummary(face: LevelCardFace): String {
        val parts = listOfNotNull(name, tier.displayText, label.title).toMutableList()
        when (face) {
            LevelCardFace.Front -> parts += listOfNotNull(play?.style?.title, play?.style?.line)
            LevelCardFace.Back -> parts += backRows.map { "${it.label} ${it.value}" }
        }
        return parts.joinToString(", ")
    }

    companion object {
        /** 18 个自评档：/levels/4-plus/、/levels/4/、/levels/4-minus/；7 级起每级一个说明页 /levels/7/ */
        fun slug(tier: SkillTier): String {
            if (tier.level > SkillLevel.MAX_SELF_SELECTABLE) return "${tier.level}"
            return when (tier.modifier) {
                SkillTier.Modifier.Minus -> "${tier.level}-minus"
                SkillTier.Modifier.Base -> "${tier.level}"
                SkillTier.Modifier.Plus -> "${tier.level}-plus"
            }
        }

        /** 网页的语言前缀（和网站 i18n.ts 的 pathPrefixes 一样）：英文没有前缀，简体中文 /zh/，繁体 /zh-hant/，其他是语言代码 */
        fun languagePrefix(language: String = AppLanguage.current): String = when (language) {
            "en" -> ""
            "zh-Hans" -> "zh/"
            "zh-Hant" -> "zh-hant/"
            else -> if (language in AppLanguage.supported) "$language/" else ""
        }

        fun url(tier: SkillTier, language: String = AppLanguage.current): String =
            "https://badie.rsvp/${languagePrefix(language)}levels/${slug(tier)}/?ref=card"

        /** 网址里的档位：“4-plus” → 4+；“7” → 7 */
        fun tier(fromSlug: String): SkillTier? {
            val parts = fromSlug.split("-")
            val level = parts.firstOrNull()?.toIntOrNull()?.takeIf { it in SkillLevel.range } ?: return null
            return when (if (parts.size == 2) parts[1] else "") {
                "minus" -> SkillTier(level, SkillTier.Modifier.Minus)
                "plus" -> SkillTier(level, SkillTier.Modifier.Plus)
                "" -> if (parts.size == 1) SkillTier(level) else null
                else -> null
            }
        }

        /** 刚测完：等级就是问卷结果 */
        fun make(result: SkillAssessmentResult, user: User?, venue: VenueName?, slots: List<RecurringTimeSlot>, avatar: ImageBitmap?): LevelCardData {
            val data = LevelCardData(result.tier, LevelCardLabel.SelfRated, play = result.play, gap = result.nextGap)
            return if (user == null) data else data.filled(user, venue, slots, avatar)
        }

        /** “我的”里：显示的等级、球友评价校准过就写“已校准”，打法从存着的答案算 */
        fun make(user: User, venue: VenueName?, slots: List<RecurringTimeSlot>, avatar: ImageBitmap?): LevelCardData {
            val answers = user.assessment?.answers
            val tier = user.displayTier
            // 差的那一项只在还没到那一级时显示
            val gap = answers?.let(SkillAssessment::evaluate)?.nextGap?.takeIf { it.level.toDouble() > tier.rating }
            return LevelCardData(tier, LevelCardLabel.of(user), play = answers?.let(SkillAssessment::playProfile), gap = gap)
                .filled(user, venue, slots, avatar)
        }

        private fun LevelCardData.filled(user: User, venue: VenueName?, slots: List<RecurringTimeSlot>, avatar: ImageBitmap?) = copy(
            name = user.nickname + user.tagText,
            mode = user.preferredMode,
            venue = venue?.name,
            region = venue?.city?.takeIf { it.isNotEmpty() },
            times = UsualTimeText.summary(slots.activeSlots),
            // 头像：和 AvatarView 用同一份照片（传过照片才有）
            avatar = if (user.avatar.photoVersion == null) null else avatar,
        )
    }
}

// MARK: - 画卡片
//
// 画布固定 360×450 点（设计稿 540×675 的 2/3），导出时 ×3。每样东西按坐标放，文字按基线放。

/** 卡片的颜色：所有打法用同一套 */
private object Palette {
    val ink = Color(0xFF17140F)
    val cream = Color(0xFFF2EFE7)
    val lime = Color(0xFFD4F33F)
    /** 次要的字 */
    val gray = Color(0xFF9A948A)
    /** 打法的那句话 */
    val line = Color(0xFFD6D1C8)
    /** 背面每一行的底色和行名 */
    val rowFill = Color(0xFFE2DDD2)
    val rowLabel = Color(0xFF6F695E)
    /** 分隔线 */
    val hairline = Color.White.copy(alpha = 0.12f)
}

/** 人物插画的图片 */
private val PlayStyle.art: Int
    get() = when (this) {
        PlayStyle.Cannon -> R.drawable.play_cannon
        PlayStyle.Net -> R.drawable.play_net
        PlayStyle.Wall -> R.drawable.play_wall
        PlayStyle.Quick -> R.drawable.play_quick
        PlayStyle.Engine -> R.drawable.play_engine
        PlayStyle.Captain -> R.drawable.play_captain
        PlayStyle.Allround -> R.drawable.play_allround
        PlayStyle.Rookie -> R.drawable.play_rookie
    }

object LevelCardRenderer {
    /** 画布大小（点） */
    const val WIDTH = 360f
    const val HEIGHT = 450f
    private const val SCALE = 3f

    /** 把一面画成图片：1080×1350 */
    fun render(context: Context, data: LevelCardData, face: LevelCardFace): ImageBitmap {
        val image = ImageBitmap((WIDTH * SCALE).toInt(), (HEIGHT * SCALE).toInt())
        val measurer = TextMeasurer(createFontFamilyResolver(context), Density(1f), LayoutDirection.Ltr)
        val painter = Painter(measurer)
        CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, Canvas(image), Size(WIDTH * SCALE, HEIGHT * SCALE)) {
            scale(SCALE, SCALE, pivot = Offset.Zero) {
                with(painter) {
                    when (face) {
                        LevelCardFace.Front -> front(context, data)
                        LevelCardFace.Back -> back(data)
                    }
                    edge()
                }
            }
        }
        return image
    }

    private enum class Anchor { Leading, Center, Trailing }

    private class Painter(val measurer: TextMeasurer) {
        private fun style(size: Float, weight: FontWeight, tracking: Float = 0f) =
            TextStyle(fontFamily = RoundedFamily, fontSize = size.sp, fontWeight = weight, letterSpacing = tracking.sp)

        /** 一行字：放不下就缩小（最小一半）。x 是这行字的左边、中间或右边（看 anchor），baseline 是基线 */
        fun DrawScope.line(
            text: String, size: Float, color: Color, x: Float, baseline: Float, width: Float,
            weight: FontWeight = FontWeight.Black, tracking: Float = 0f, anchor: Anchor = Anchor.Leading, minimumScale: Float = 0.5f,
        ) {
            var layout = measurer.measure(text, style(size, weight, tracking), softWrap = false, maxLines = 1)
            if (layout.size.width > width) {
                val factor = max(minimumScale, width / layout.size.width)
                layout = measurer.measure(text, style(size * factor, weight, tracking * factor), softWrap = false, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, constraints = Constraints(maxWidth = width.roundToInt().coerceAtLeast(1)))
            }
            // 字距会多出最后一个字后面的空，居中时往右挪一半
            val textWidth = layout.size.width.toFloat()
            val left = when (anchor) {
                Anchor.Leading -> x
                Anchor.Center -> x - textWidth / 2 + tracking / 2
                Anchor.Trailing -> x - textWidth
            }
            drawText(layout, color, Offset(left, baseline - layout.firstBaseline))
        }

        /** 按比例给顶点的多边形 */
        fun polygon(rect: Rect, points: List<Pair<Float, Float>>) = Path().apply {
            points.forEachIndexed { index, (px, py) ->
                val x = rect.left + px * rect.width
                val y = rect.top + py * rect.height
                if (index == 0) moveTo(x, y) else lineTo(x, y)
            }
            close()
        }

        val hexagon = listOf(0.5f to 0f, 1f to 0.25f, 1f to 0.75f, 0.5f to 1f, 0f to 0.75f, 0f to 0.25f)
        val tab = listOf(0.08f to 0f, 0.92f to 0f, 1f to 1f, 0f to 1f)

        /** 六边形等级徽章：左上角在 (x, y) */
        fun DrawScope.badge(code: String, fill: Color, text: Color, x: Float, y: Float, width: Float, height: Float, fontSize: Float) {
            drawPath(polygon(Rect(x, y, x + width, y + height), hexagon), fill)
            line(code, fontSize, text, x + width / 2, y + height / 2 + fontSize * 0.34f, width * 0.82f, anchor = Anchor.Center)
        }

        /** 头像：照片外面一圈柠檬绿，再一圈卡片底色。圆心在 (x, y)，radius 是照片的半径 */
        fun DrawScope.avatar(image: ImageBitmap, x: Float, y: Float, radius: Float) {
            val center = Offset(x, y)
            drawCircle(Palette.ink, radius + 4.67f, center)
            drawCircle(Palette.lime, radius + 2f, center)
            clipPath(Path().apply { addOval(Rect(center, radius)) }) {
                // 铺满圆圈（scaledToFill）
                val k = max(radius * 2 / image.width, radius * 2 / image.height)
                val w = image.width * k
                val h = image.height * k
                drawImage(
                    image, dstOffset = IntOffset((x - w / 2).roundToInt(), (y - h / 2).roundToInt()),
                    dstSize = IntSize(w.roundToInt(), h.roundToInt()),
                )
            }
        }

        /** 卡片边：一圈细线 */
        fun DrawScope.edge() {
            drawRoundRect(
                Color.White.copy(alpha = 0.14f), Offset(3.33f + 0.5f, 3.33f + 0.5f), Size(353.33f - 1f, 443.33f - 1f),
                CornerRadius(12f), style = Stroke(1f),
            )
        }

        // MARK: 正面

        fun DrawScope.front(context: Context, data: LevelCardData) {
            val top = 261.33f
            drawRect(Palette.ink, size = Size(WIDTH, HEIGHT))
            art(context, data, Rect(8f, 8f, 352f, top))
            badge(data.tier.code, Palette.ink, Palette.lime, 20f, 20f, 50.67f, 57.33f, 21.33f)
            modeMark(data, GameMode.Singles, 310f, 19.33f)
            modeMark(data, GameMode.Doubles, 310f, 56.67f)
            // 人物区和信息区交界上的 BADIE 标
            drawPath(polygon(Rect(128f, top - 12f, 232f, top + 8f), tab), Palette.ink)
            line("BADIE", 13.33f, Palette.lime, 180f, top + 3.33f, 100f, tracking = 3.33f, anchor = Anchor.Center)
            val photo = data.avatarImage
            if (photo != null) avatar(photo, 50.67f, top + 1.33f, 29.33f)
            // 名字（没有名字时印等级）和下面的小字。有头像时名字窄一点，不压到头像
            line(data.name ?: data.tierLine, 26.67f, Color.White, 180f, top + 44f, if (photo != null) 204f else 320f, anchor = Anchor.Center)
            line(
                data.subline(includesTier = data.name != null), 11.33f, Palette.gray, 180f, top + 65.33f, 320f,
                weight = FontWeight.ExtraBold, tracking = 0.67f, anchor = Anchor.Center,
            )
            drawRect(Palette.hairline, Offset(20f, top + 81.33f), Size(320f, 1f))
            // 左下打法、右下最强一拍、底边落款
            val play = data.play
            line(if (play == null) tr("等级") else tr("打法"), 10f, Palette.gray, 20f, 360f, 180f, weight = FontWeight.ExtraBold)
            line(play?.style?.title ?: data.tier.name, 29.33f, Color.White, 20f, 393.33f, 193.33f)
            if (play != null) {
                val layout = measurer.measure(
                    play.style.line, style(10f, FontWeight.Bold).copy(lineHeight = 13f.sp), maxLines = 2, overflow = TextOverflow.Ellipsis,
                    constraints = Constraints(maxWidth = 193),
                )
                drawText(layout, Palette.line, Offset(20f, 410.67f - layout.firstBaseline))
                play.bestShot?.let { shot ->
                    line(tr("最强一拍"), 10f, Palette.gray, 340f, 360f, 120f, weight = FontWeight.ExtraBold, anchor = Anchor.Trailing)
                    line(shot.name, 18.67f, Palette.lime, 340f, 390.67f, 120f, anchor = Anchor.Trailing)
                }
            }
            line(data.footer, 8.67f, Palette.gray, 180f, 436f, 306.67f, weight = FontWeight.ExtraBold, tracking = 2f, anchor = Anchor.Center)
        }

        /** 人物区：浅色底、重复的大字、人物（没有打法时不画人，只印等级） */
        private fun DrawScope.art(context: Context, data: LevelCardData, rect: Rect) {
            val shape = Path().apply {
                addRoundRect(RoundRect(rect, topLeft = CornerRadius(9.33f), topRight = CornerRadius(9.33f), bottomLeft = CornerRadius.Zero, bottomRight = CornerRadius.Zero))
            }
            clipPath(shape) {
                drawRect(Palette.cream, rect.topLeft, rect.size)
                val ghost = data.play?.style?.ghostWord ?: "BADIE"
                for (index in 0 until 4) {
                    val layout = measurer.measure(ghost, style(85.33f, FontWeight.Black), softWrap = false, maxLines = 1)
                    drawText(layout, Palette.ink.copy(alpha = 0.08f), Offset(rect.left - 12f, rect.top + 56f + index * 69.33f - layout.firstBaseline))
                }
                val play = data.play
                if (play != null) {
                    val image = ImageBitmap.imageResource(context.resources, play.style.art)
                    // 放进 220×256.67 的框，靠下
                    val k = min(220f / image.width, 256.67f / image.height)
                    val w = image.width * k
                    val h = image.height * k
                    val left = rect.left + 62f + (220f - w) / 2
                    val top = rect.top + 6f + (256.67f - h)
                    drawImage(image, dstOffset = IntOffset(left.roundToInt(), top.roundToInt()), dstSize = IntSize(w.roundToInt(), h.roundToInt()))
                } else {
                    val layout = measurer.measure(data.tier.code, style(120f, FontWeight.Black, -2f), softWrap = false, maxLines = 1)
                    drawText(layout, Palette.ink, Offset(rect.center.x - layout.size.width / 2f, rect.center.y - layout.size.height / 2f))
                }
            }
        }

        /** 单打 / 双打：偏好的那个涂黑；没填偏好就都不涂 */
        private fun DrawScope.modeMark(data: LevelCardData, mode: GameMode, x: Float, y: Float) {
            val on = data.mode == mode
            val size = 30.67f
            val center = Offset(x + size / 2, y + size / 2)
            drawCircle(if (on) Palette.ink else Palette.cream, size / 2, center)
            drawCircle(Palette.ink, size / 2 - 2.67f / 2, center, style = Stroke(2.67f))
            val count = if (mode == GameMode.Singles) 1 else 2
            val dot = 6.67f
            val total = count * dot + (count - 1) * 1.33f
            for (i in 0 until count) {
                drawCircle(if (on) Palette.cream else Palette.ink, dot / 2, Offset(center.x - total / 2 + dot / 2 + i * (dot + 1.33f), center.y))
            }
        }

        // MARK: 背面

        fun DrawScope.back(data: LevelCardData) {
            val panelTop = 85.33f
            val rows = data.backRows
            // 行少的时候每行高一点
            val rowHeight = if (rows.size > 3) 40f else 49.33f
            val rowGap = if (rows.size > 3) 5.33f else 6.67f
            val panelHeight = rows.size * rowHeight + max(rows.size - 1, 0) * rowGap + 29.33f
            val nextY = panelTop + panelHeight + 28f
            drawRect(Palette.ink, size = Size(WIDTH, HEIGHT))
            // 抬头：徽章、名字（没有就印打法）、小字，右上角头像。有头像时字窄一点
            val photo = data.avatarImage
            val width = if (photo == null) 266.67f else 213.33f
            badge(data.tier.code, Palette.lime, Palette.ink, 20f, 20f, 40f, 45.33f, 16f)
            line(data.name ?: data.play?.style?.title ?: data.tier.name, 20f, Color.White, 70.67f, 41.33f, width)
            line(data.subline(), 10f, Palette.gray, 70.67f, 60f, width, weight = FontWeight.ExtraBold, tracking = 0.67f)
            if (photo != null) avatar(photo, 318.67f, 42.67f, 20f)
            drawRoundRect(Palette.cream, Offset(16f, panelTop), Size(328f, panelHeight), CornerRadius(9.33f))
            rows.forEachIndexed { index, row ->
                val top = panelTop + 14.67f + index * (rowHeight + rowGap)
                row(row, 29.33f, top, rowHeight)
            }
            data.gap?.let { gap ->
                line(tr("离 %lld 级还差", gap.level), 10f, Palette.gray, 20f, nextY, 133.33f, weight = FontWeight.ExtraBold)
                line(gap.dimension.name, 14.67f, Palette.lime, 340f, nextY + 1.33f, 193.33f, anchor = Anchor.Trailing)
            }
            data.play?.let { stats(it, if (data.gap == null) nextY else nextY + 17.33f) }
            line(
                "${tr("测测你几级 · 2 分钟")} · ${data.footer}", 8.67f, Palette.gray, 180f, 434f, 306.67f,
                weight = FontWeight.ExtraBold, tracking = 2f, anchor = Anchor.Center,
            )
        }

        /** 面板里的一行：左边行名，右边内容 */
        private fun DrawScope.row(row: LevelCardRow, x: Float, y: Float, height: Float) {
            val width = 301.33f
            drawRoundRect(Palette.rowFill, Offset(x, y), Size(width, height), CornerRadius(5.33f))
            val labelLayout = measurer.measure(row.label, style(10f, FontWeight.ExtraBold, 0.67f), softWrap = false, maxLines = 1).let { layout ->
                if (layout.size.width <= 86.67f) layout else measurer.measure(
                    row.label, style(10f * max(0.6f, 86.67f / layout.size.width), FontWeight.ExtraBold, 0.67f), softWrap = false, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, constraints = Constraints(maxWidth = 87),
                )
            }
            drawText(labelLayout, Palette.rowLabel, Offset(x + 12f, y + (height - labelLayout.size.height) / 2))
            val valueWidth = (width - 24f - 86.67f - 6f).roundToInt()
            var size = 14f
            var value = measurer.measure(row.value, style(size, FontWeight.Black).copy(textAlign = TextAlign.End, lineHeight = 17f.sp), maxLines = 2, constraints = Constraints.fixedWidth(valueWidth))
            while ((value.hasVisualOverflow || value.size.height > height) && size > 14f * 0.6f) {
                size -= 0.5f
                value = measurer.measure(row.value, style(size, FontWeight.Black).copy(textAlign = TextAlign.End, lineHeight = (size * 1.2f).sp), maxLines = 2, constraints = Constraints.fixedWidth(valueWidth))
            }
            drawText(value, Palette.ink, Offset(x + width - 12f - valueWidth, y + (height - value.size.height) / 2))
        }

        /** 分隔线和六项数字；y 是分隔线的位置 */
        private fun DrawScope.stats(play: PlayProfile, y: Float) {
            val column = 320f / PlayAxis.entries.size
            drawRect(Palette.hairline, Offset(20f, y), Size(320f, 1f))
            PlayAxis.entries.forEachIndexed { index, axis ->
                val left = 20f + column * index
                line(axis.title, 9.33f, Palette.gray, left + column / 2, y + 30.67f, column - 4f, weight = FontWeight.ExtraBold, anchor = Anchor.Center)
                line("${play.displayValue(axis)}", 37.33f, Color.White, left + column / 2, y + 78.67f, column, tracking = -1f, anchor = Anchor.Center)
            }
        }
    }
}
