package com.badie.app.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

/** 一个图标；都列在自动生成的 [Sym] 里 */
@JvmInline
value class SymbolId(val drawable: Int)

/**
 * 画一个图标。[size] 照 iPhone 的字号写：同样的字号下，这里的图标框要大三成，看起来才一样大。
 */
@Composable
fun Symbol(symbol: SymbolId, size: Int, modifier: Modifier = Modifier, tint: Color = LocalContentColor.current) {
    Image(
        painter = painterResource(symbol.drawable),
        contentDescription = null,
        modifier = modifier.size((size * 1.3f).dp),
        colorFilter = ColorFilter.tint(tint),
    )
}
