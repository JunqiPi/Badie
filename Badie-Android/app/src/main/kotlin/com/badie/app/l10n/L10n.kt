package com.badie.app.l10n

import android.content.Context
import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext

/**
 * 界面文字。和 iPhone 一样，代码里写简体中文原文（就是 xcstrings 里的 key），
 * 参数的位置写 %@（文字）或 %lld（整数）：`tr("%lld 个挑战待回应", count)`。
 * 译文在构建时从 iPhone 的 Localizable.xcstrings 转出来，见 app/build.gradle.kts。
 */
object L10n {
    @Volatile
    private var resources: Resources? = null

    /** 当前界面的文字表。Activity 每次创建（包括换语言后重建）都要接一次 */
    fun attach(context: Context) {
        resources = context.resources
    }

    /** 不在界面里（管理器、错误提示）取文字。没接上界面时（单元测试）给简体中文原文 */
    fun tr(key: String, vararg args: Any?): String = lookup(resources, key, args)

    internal fun lookup(resources: Resources?, key: String, args: Array<out Any?>): String {
        val texts = args.map { it.toString() }
        if (resources == null) {
            return L10nTable.sourceText[key]?.let { L10nFormat.fill(it, texts) } ?: L10nFormat.fillSource(key, texts)
        }
        L10nTable.plurals[key]?.let { id ->
            val quantity = (args[L10nTable.pluralArg.getValue(key)] as Number).toInt()
            return L10nFormat.fill(resources.getQuantityText(id, quantity).toString(), texts)
        }
        val id = L10nTable.strings[key] ?: return L10nFormat.fillSource(key, texts)
        val text = resources.getString(id)
        return if (texts.isEmpty()) text else L10nFormat.fill(text, texts)
    }
}

/** 界面里取文字；换语言后界面重建，自然换成新的 */
@Composable
@ReadOnlyComposable
fun tr(key: String, vararg args: Any?): String {
    LocalConfiguration.current
    return L10n.lookup(LocalContext.current.resources, key, args)
}

internal object L10nFormat {
    private val converted = Regex("""%(?:(\d+)[$]s|%)""")
    private val source = Regex("""%(?:(\d+)[$])?(@|lld|%)""")

    /** 填转换后的文字：%1$s、%2$s 按序号，%% 是百分号 */
    fun fill(template: String, args: List<String>): String = converted.replace(template) { m ->
        val index = m.groupValues[1].toIntOrNull() ?: return@replace "%"
        args.getOrNull(index - 1) ?: m.value
    }

    /** 填原文：%@、%lld 按出现的顺序，也认 %1$@ 这种带序号的 */
    fun fillSource(template: String, args: List<String>): String {
        var next = 0
        return source.replace(template) { m ->
            if (m.groupValues[2] == "%") return@replace if (args.isEmpty()) m.value else "%"
            val index = m.groupValues[1].toIntOrNull() ?: ++next
            args.getOrNull(index - 1) ?: m.value
        }
    }
}
