package com.badie.app.l10n

import android.icu.text.ListFormatter
import java.util.Locale

/** 把几项连成一句：“反手后场、平抽挡和步法”。连接词跟着当前语言走 */
object ListText {
    fun and(items: List<String>, locale: Locale = Locale.getDefault()): String = try {
        ListFormatter.getInstance(locale).format(items)
    } catch (_: Throwable) {
        // 没有系统的时候（单元测试）：按简体中文的写法
        when (items.size) {
            0 -> ""
            1 -> items[0]
            else -> items.dropLast(1).joinToString("、") + "和" + items.last()
        }
    }
}
