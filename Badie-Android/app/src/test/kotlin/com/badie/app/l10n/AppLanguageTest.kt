package com.badie.app.l10n

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Locale

class AppLanguageTest {
    private fun match(vararg tags: String) = AppLanguage.match(tags.map(Locale::forLanguageTag))

    @Test
    fun picksTheFirstLanguageWeHave() {
        assertEquals("ko", match("ko-KR"))
        assertEquals("ja", match("fr-FR", "ja-JP", "en-US"))
        assertEquals("都没有就用英文", "en", match("fr-FR", "de-DE"))
        assertEquals("id", match("id-ID"))
        assertEquals("id", AppLanguage.match(Locale("in", "ID")))
        assertNull(AppLanguage.match(Locale.FRANCE))
    }

    @Test
    fun chineseGoesByScriptThenRegion() {
        assertEquals("zh-Hans", match("zh-CN"))
        assertEquals("zh-Hans", match("zh-Hans-SG"))
        assertEquals("zh-Hant", match("zh-TW"))
        assertEquals("zh-Hant", match("zh-HK"))
        assertEquals("zh-Hant", match("zh-Hant-US"))
        assertEquals("写明了简体就是简体", "zh-Hans", match("zh-Hans-TW"))
    }

    @Test
    fun tenLanguagesEachWithItsOwnName() {
        assertEquals(10, AppLanguage.supported.size)
        assertEquals(10, AppLanguage.supported.map(AppLanguage::name).toSet().size)
        assertEquals("fr", AppLanguage.name("fr"))
    }
}
