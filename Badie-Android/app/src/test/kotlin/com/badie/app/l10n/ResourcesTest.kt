package com.badie.app.l10n

import android.content.Context
import android.content.res.Configuration
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.util.Locale

/** 从 iPhone 的文字表转出来的资源，真的按各语言取一遍：参数顺序、单复数、找不到语言时用英文 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ResourcesTest {
    private fun tr(language: String, key: String, vararg args: Any?): String {
        val base: Context = RuntimeEnvironment.getApplication()
        val configuration = Configuration(base.resources.configuration).apply { setLocale(Locale.forLanguageTag(language)) }
        return L10n.lookup(base.createConfigurationContext(configuration).resources, key, args)
    }

    @Test
    fun eachLanguageHasItsOwnText() {
        assertEquals("球局", tr("zh-Hans-CN", "球局"))
        assertEquals("球局", tr("zh-CN", "球局"))
        assertEquals("Games", tr("en-US", "球局"))
        assertEquals(tr("zh-Hant-TW", "消息"), tr("zh-TW", "消息"))
        assertEquals(tr("id", "发现"), tr("in", "发现"))
        // 简体中文里另写过的句子用文字表里的写法
        assertEquals("实力相当", tr("zh-Hans", "同水平"))
        // 没有的语言用英文，和 iPhone 一样
        assertEquals(tr("en", "快速匹配"), tr("fr-FR", "快速匹配"))
    }

    @Test
    fun argumentsGoWhereTheTranslationPutsThem() {
        assertEquals("3 条未读", tr("zh-Hans", "%lld 条未读", 3))
        assertEquals("7 到 8+", tr("zh-Hans", "%@ 到 %@", "7", "8+"))
        assertEquals("7 to 8+", tr("en", "%@ 到 %@", "7", "8+"))
        assertEquals("Within 5 km", tr("en", "%lld %@内", 5, "km"))
        // 日语把数字放在后面
        assertEquals("未返信の挑戦 2 件", tr("ja", "%lld 个挑战待回应", 2))
        assertEquals("Alex · 80% match", tr("en", "%@ · 匹配度 %lld%%", "Alex", 80))
    }

    @Test
    fun englishAndHindiHavePlurals() {
        assertEquals("1 challenge awaiting reply", tr("en", "%lld 个挑战待回应", 1))
        assertEquals("2 challenges awaiting reply", tr("en", "%lld 个挑战待回应", 2))
        assertEquals("2 个挑战待回应", tr("zh-Hans", "%lld 个挑战待回应", 2))
    }

    @Test
    fun datesFollowTheLanguageOfTheText() {
        val base: Context = RuntimeEnvironment.getApplication()
        fun attach(language: String) {
            val configuration = Configuration(base.resources.configuration).apply { setLocale(Locale.forLanguageTag(language)) }
            L10n.attach(base.createConfigurationContext(configuration))
        }
        val time = java.time.ZonedDateTime.of(2026, 11, 16, 6, 39, 0, 0, java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        try {
            attach("en")
            val english = com.badie.app.models.DateText.time(time, java.time.ZoneOffset.UTC)
            attach("zh-Hans")
            val chinese = com.badie.app.models.DateText.time(time, java.time.ZoneOffset.UTC)
            assertEquals("界面是中文时不写 AM", false, chinese.contains("AM"))
            assertEquals(true, chinese.contains("6:39"))
            assertEquals(true, english.contains("6:39"))
        } finally {
            L10n.detach()
        }
    }
}
