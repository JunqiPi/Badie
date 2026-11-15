package com.badie.app.l10n

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

/**
 * App 里自己选语言（不用去系统设置）。选的语言交给系统的“App 语言”：和系统设置里给 Badie 选的是同一个值，
 * 界面马上重建成新语言，下次启动也接着用。
 */
object AppLanguage {
    /** 和服务器（通知、邮件）一致的 10 种语言 */
    val supported = listOf("en", "zh-Hans", "zh-Hant", "ja", "ko", "id", "ms", "th", "vi", "hi")

    /** 源语言：文字表里的 key 就是简体中文 */
    const val SOURCE = "zh-Hans"

    /** 每种语言用它自己的写法显示 */
    fun name(code: String): String = when (code) {
        "en" -> "English"
        "zh-Hans" -> "简体中文"
        "zh-Hant" -> "繁體中文"
        "ja" -> "日本語"
        "ko" -> "한국어"
        "id" -> "Bahasa Indonesia"
        "ms" -> "Bahasa Melayu"
        "th" -> "ไทย"
        "vi" -> "Tiếng Việt"
        "hi" -> "हिन्दी"
        else -> code
    }

    /** 这个地区设置对应我们的哪种语言；没有就是 null */
    fun match(locale: Locale): String? = when (val language = locale.language) {
        "zh" -> {
            val traditional = locale.script == "Hant" || (locale.script.isEmpty() && locale.country in setOf("TW", "HK", "MO"))
            if (traditional) "zh-Hant" else "zh-Hans"
        }
        // 印尼语在老系统上的代号是 in
        "in" -> "id"
        else -> language.takeIf { it in supported }
    }

    /** 按语言的先后顺序挑第一个我们有的（都没有就用英文） */
    fun match(locales: List<Locale>): String = locales.firstNotNullOfOrNull(::match) ?: "en"

    /** 只给本 App 设的语言（在 App 里或系统设置里选的）；null = 跟随系统 */
    val chosen: String?
        get() = AppCompatDelegate.getApplicationLocales().get(0)?.let(::match)

    /** 跟随系统时用哪种：按系统的语言顺序挑第一个我们有的 */
    val system: String
        get() = match(LocaleListCompat.getAdjustedDefault().let { list -> (0 until list.size()).mapNotNull(list::get) })

    /** 现在实际用的语言 */
    val current: String get() = chosen ?: system

    /** 换语言（null = 跟随系统）；不认识的语言也按跟随系统 */
    fun choose(code: String?) {
        val locales = if (code != null && code in supported) LocaleListCompat.forLanguageTags(code) else LocaleListCompat.getEmptyLocaleList()
        AppCompatDelegate.setApplicationLocales(locales)
    }
}
