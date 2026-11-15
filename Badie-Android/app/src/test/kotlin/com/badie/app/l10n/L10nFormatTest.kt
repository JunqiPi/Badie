package com.badie.app.l10n

import org.junit.Assert.assertEquals
import org.junit.Test

class L10nFormatTest {
    @Test
    fun fillsConvertedTextByIndex() {
        assertEquals("3 challenges", L10nFormat.fill("%1\$s challenges", listOf("3")))
        // 译文里参数的顺序可以和原文不一样
        assertEquals("周六 的 双打", L10nFormat.fill("%2\$s 的 %1\$s", listOf("双打", "周六")))
        assertEquals("胜率 60%", L10nFormat.fill("胜率 %1\$s%%", listOf("60")))
    }

    @Test
    fun fillsSourceTextInOrder() {
        assertEquals("3 个挑战待回应", L10nFormat.fillSource("%lld 个挑战待回应", listOf("3")))
        assertEquals("小林 · 匹配度 80%", L10nFormat.fillSource("%@ · 匹配度 %lld%%", listOf("小林", "80")))
        assertEquals("b a", L10nFormat.fillSource("%2\$@ %1\$@", listOf("a", "b")))
        assertEquals("球局", L10nFormat.fillSource("球局", emptyList()))
    }

    @Test
    fun withoutResourcesGivesSourceText() {
        // 单元测试里没有界面，取到的是简体中文原文
        assertEquals("2 条未读", L10n.tr("%lld 条未读", 2))
    }
}
