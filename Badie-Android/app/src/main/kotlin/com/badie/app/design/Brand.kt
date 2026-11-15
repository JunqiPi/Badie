package com.badie.app.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.badie.app.R

/** 品牌标识：和 App 图标是同一张图。圆角方块，描边和硬投影跟贴纸卡片一致，随给的尺寸缩放 */
@Composable
fun AppLogo(modifier: Modifier = Modifier) {
    val colors = AppTheme.colors
    Image(
        painterResource(R.drawable.logo), contentDescription = null, contentScale = ContentScale.Crop,
        modifier = modifier
            .aspectRatio(1f)
            .drawBehind {
                val r = CornerRadius(size.minDimension * 0.225f)
                drawRoundRect(colors.shadow, Offset(AppTheme.Elevation.card.x.toPx(), AppTheme.Elevation.card.y.toPx()), size, r)
            }
            .clip(RoundedCornerShape(percent = 22))
            .drawWithContent {
                drawContent()
                val w = AppTheme.Stroke.width.toPx()
                val r = size.minDimension * 0.225f
                drawRoundRect(colors.stroke, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius(r - w / 2), style = Stroke(w))
            },
    )
}

/** 文字标识 "badie." */
@Composable
fun Wordmark(modifier: Modifier = Modifier, size: Int = 40) {
    val colors = AppTheme.colors
    Row(modifier.clearAndSetSemantics { contentDescription = "Badie" }, horizontalArrangement = Arrangement.spacedBy(1.dp)) {
        Text("badie", style = rounded(size, FontWeight.Black), color = colors.ink, modifier = Modifier.alignByBaseline())
        Spacer(
            Modifier
                .alignBy { it.measuredHeight }
                .size((size * 0.32f).dp)
                .drawBehind {
                    drawCircle(colors.lime)
                    drawCircle(colors.stroke, radius = this.size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                },
        )
    }
}
