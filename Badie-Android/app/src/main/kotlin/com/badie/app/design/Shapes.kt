package com.badie.app.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// 对应 iPhone 的 DesignSystem/Shapes.swift

/** 票据形状：左右各一个半圆缺口（球局卡片用）。[notchPosition] 是缺口中心离顶部的比例 */
class TicketShape(private val cornerRadius: Dp = 22.dp, private val notchRadius: Dp = 11.dp, private val notchPosition: Float = 0.62f) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline = with(density) {
        val r = min(cornerRadius.toPx(), min(size.height, size.width) / 2)
        val notch = notchRadius.toPx()
        val notchY = size.height * notchPosition
        val path = Path().apply {
            moveTo(r, 0f)
            lineTo(size.width - r, 0f)
            arcTo(Rect(size.width - 2 * r, 0f, size.width, 2 * r), -90f, 90f, false)
            lineTo(size.width, notchY - notch)
            arcTo(Rect(size.width - notch, notchY - notch, size.width + notch, notchY + notch), -90f, -180f, false)
            lineTo(size.width, size.height - r)
            arcTo(Rect(size.width - 2 * r, size.height - 2 * r, size.width, size.height), 0f, 90f, false)
            lineTo(r, size.height)
            arcTo(Rect(0f, size.height - 2 * r, 2 * r, size.height), 90f, 90f, false)
            lineTo(0f, notchY + notch)
            arcTo(Rect(-notch, notchY - notch, notch, notchY + notch), 90f, -180f, false)
            lineTo(0f, r)
            arcTo(Rect(0f, 0f, 2 * r, 2 * r), 180f, 90f, false)
            close()
        }
        Outline.Generic(path)
    }
}

/** 票据上的虚线分隔 */
@Composable
fun DashedDivider(modifier: Modifier = Modifier, color: Color = AppTheme.colors.onAccent) {
    Canvas(modifier.fillMaxWidth().height(2.dp).clearAndSetSemantics {}) {
        drawLine(
            color, Offset(0f, 1.dp.toPx()), Offset(size.width, 1.dp.toPx()), strokeWidth = 2.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx())),
        )
    }
}

/** 爆炸星形的路径（VS、折扣式徽章） */
fun starburstPath(size: Size, points: Int = 12, innerRatio: Float = 0.78f): Path = Path().apply {
    val center = Offset(size.width / 2, size.height / 2)
    val outer = min(size.width, size.height) / 2
    val inner = outer * innerRatio
    for (index in 0 until points * 2) {
        val angle = index * Math.PI / points - Math.PI / 2
        val radius = if (index % 2 == 0) outer else inner
        val x = center.x + (cos(angle) * radius).toFloat()
        val y = center.y + (sin(angle) * radius).toFloat()
        if (index == 0) moveTo(x, y) else lineTo(x, y)
    }
    close()
}

@Composable
fun StarburstBadge(text: String, modifier: Modifier = Modifier, fill: Color = AppTheme.colors.butter, size: Dp = 72.dp) {
    val colors = AppTheme.colors
    Box(modifier.size(size).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val path = starburstPath(this.size)
            translate(2.dp.toPx(), 3.dp.toPx()) { drawPath(path, colors.shadow) }
            drawPath(path, fill)
            drawPath(path, colors.stroke, style = Stroke(2.dp.toPx()))
        }
        Text(text, style = rounded((size.value * 0.3f).toInt(), FontWeight.Black), color = colors.onAccent)
    }
}
