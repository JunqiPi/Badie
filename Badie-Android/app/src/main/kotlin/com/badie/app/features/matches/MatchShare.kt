package com.badie.app.features.matches

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.appcompat.content.res.AppCompatResources
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.badie.app.R
import com.badie.app.design.RoundedFamily
import com.badie.app.l10n.L10n
import com.badie.app.models.DateText
import com.badie.app.models.MatchFormat
import com.badie.app.models.MatchRules
import com.badie.app.models.MatchState
import java.io.File
import java.io.IOException
import kotlin.math.max
import kotlin.math.roundToInt

// 最终排名分享成图片：和等级卡同一套样式（米白底、墨色字、柠檬绿），4:5，1080×1350。
// 对应 iPhone MatchViews.swift 的 MatchShareCard / MatchShareRenderer

object MatchShareRenderer {
    private const val WIDTH = 360f
    private const val HEIGHT = 450f
    private const val SCALE = 3f
    private const val PAD = 22f

    private val ink = Color(0xFF17140F)
    private val cream = Color(0xFFF2EFE7)
    private val lime = Color(0xFFD4F33F)
    private val gray = Color(0xFF6F695E)

    fun render(context: Context, state: MatchState): ImageBitmap? = try {
        draw(
            context, state.name, MatchFormat.title(state.format, state.play),
            DateText.monthDay((state.endedAt ?: state.createdAt).toEpochMilli()), state.ranking ?: state.standings,
        )
    } catch (_: Exception) {
        null
    }

    private fun draw(context: Context, name: String, subtitle: String, date: String, rows: List<MatchState.Standing>): ImageBitmap {
        val image = ImageBitmap((WIDTH * SCALE).toInt(), (HEIGHT * SCALE).toInt())
        val measurer = TextMeasurer(createFontFamilyResolver(context), Density(1f), LayoutDirection.Ltr)
        CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, Canvas(image), Size(WIDTH * SCALE, HEIGHT * SCALE)) {
            scale(SCALE, SCALE, pivot = Offset.Zero) {
                drawRect(cream)
                val inner = WIDTH - PAD * 2
                // 顶上一行：BADIE、赛制 · 日期
                line(measurer, "BADIE", 13f, ink, PAD, PAD + 13f, 80f, tracking = 2f)
                line(measurer, "$subtitle · $date", 11f, gray, WIDTH - PAD, PAD + 12f, inner - 90f, weight = FontWeight.Bold, trailing = true)
                // 比赛名字
                line(measurer, name, 26f, ink, PAD, PAD + 16f + 14f + 26f, inner)
                var y = PAD + 16f + 14f + 34f + 14f
                val champion = rows.firstOrNull()
                if (champion != null) {
                    val height = 72f
                    drawRoundRect(ink, Offset(PAD, y), Size(inner, height), CornerRadius(16f))
                    val circle = Offset(PAD + 14f + 22f, y + height / 2)
                    drawCircle(lime, 22f, circle)
                    trophy(context, circle)
                    line(measurer, L10n.tr("冠军"), 12f, lime, PAD + 14f + 44f + 12f, y + 28f, 160f)
                    line(measurer, champion.name, 28f, cream, PAD + 14f + 44f + 12f, y + 58f, inner - 44f - 14f * 2 - 12f - 70f)
                    line(measurer, "${champion.wins}-${champion.losses}", 18f, cream, WIDTH - PAD - 14f, y + height / 2 + 7f, 70f, trailing = true)
                    y += height + 10f
                }
                // 其余名次（最多 7 行）
                rows.drop(1).take(7).forEach { row ->
                    val baseline = y + 20f
                    line(measurer, "${row.rank}", 15f, gray, PAD, baseline, 24f, weight = FontWeight.ExtraBold)
                    line(measurer, row.name, 15f, ink, PAD + 34f, baseline, inner - 34f - 108f, weight = FontWeight.ExtraBold)
                    line(measurer, "${row.wins}-${row.losses}", 15f, ink, WIDTH - PAD - 44f - 10f - 22f, baseline, 44f, weight = FontWeight.ExtraBold, center = true)
                    line(measurer, MatchRules.diffText(row.diff), 15f, ink, WIDTH - PAD, baseline, 44f, weight = FontWeight.ExtraBold, trailing = true)
                    drawRect(ink.copy(alpha = 0.1f), Offset(PAD, y + 29f), Size(inner, 1f))
                    y += 30f
                }
                line(measurer, "badie.rsvp", 11f, gray, PAD, HEIGHT - PAD, 120f, weight = FontWeight.ExtraBold)
            }
        }
        return image
    }

    /** 一行字：放不下就缩小（最小一半）。x 是左边（trailing 时是右边、center 时是中间），baseline 是基线 */
    private fun DrawScope.line(
        measurer: TextMeasurer, text: String, size: Float, color: Color, x: Float, baseline: Float, width: Float,
        weight: FontWeight = FontWeight.Black, tracking: Float = 0f, trailing: Boolean = false, center: Boolean = false,
    ) {
        fun style(factor: Float) = TextStyle(fontFamily = RoundedFamily, fontSize = (size * factor).sp, fontWeight = weight, letterSpacing = (tracking * factor).sp)
        var layout = measurer.measure(text, style(1f), softWrap = false, maxLines = 1)
        if (layout.size.width > width) {
            val factor = max(0.5f, width / layout.size.width)
            layout = measurer.measure(
                text, style(factor), softWrap = false, maxLines = 1, overflow = TextOverflow.Ellipsis,
                constraints = Constraints(maxWidth = width.roundToInt().coerceAtLeast(1)),
            )
        }
        val textWidth = layout.size.width.toFloat()
        val left = when {
            trailing -> x - textWidth
            center -> x - textWidth / 2
            else -> x
        }
        drawText(layout, color, Offset(left, baseline - layout.firstBaseline))
    }

    private fun DrawScope.trophy(context: Context, center: Offset) {
        val drawable = AppCompatResources.getDrawable(context, R.drawable.sym_trophy_fill) ?: return
        drawable.setTint(ink.toArgb())
        val half = 13
        drawable.setBounds(center.x.toInt() - half, center.y.toInt() - half, center.x.toInt() + half, center.y.toInt() + half)
        drawIntoCanvas { drawable.draw(it.nativeCanvas) }
    }

    /** 系统分享：图片先存到缓存目录，用 FileProvider 给别的 App 读 */
    fun share(context: Context, image: ImageBitmap, title: String) {
        val file = try {
            val dir = File(context.cacheDir, "cards").apply { mkdirs() }
            File(dir, "Badie-match.png").also { file -> file.outputStream().use { image.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it) } }
        } catch (_: IOException) {
            return
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_TITLE, title)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri(null, uri)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
