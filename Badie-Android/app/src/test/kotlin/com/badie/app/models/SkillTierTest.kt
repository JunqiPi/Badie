package com.badie.app.models

import com.badie.app.models.SkillTier.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/** 细分档位：1− … 9+ 共 27 档，分值按 1/3 级。对应 iPhone 的 SkillTierTests */
class SkillTierTest {
    @Test
    fun twentySevenTiersInOrder() {
        assertEquals(27, SkillTier.all.size)
        assertEquals("1−", SkillTier.all.first().code)
        assertEquals("9+", SkillTier.all.last().code)
        assertEquals((0 until 27).toList(), SkillTier.all.map { it.index })
        assertEquals(SkillTier.all, SkillTier.all.sorted())
    }

    @Test
    fun ratingRoundTrip() {
        for (tier in SkillTier.all) assertEquals(tier, SkillTier.ofRating(tier.rating))
        assertEquals(4 + 1.0 / 3, SkillTier(4, Modifier.Plus).rating, 0.0001)
        assertEquals("Lv.4−", SkillTier(4, Modifier.Minus).text)
    }

    @Test
    fun ratingRoundsToNearestThird() {
        assertEquals(SkillTier(5, Modifier.Minus), SkillTier.ofRating(4.6))
        assertEquals(SkillTier(4), SkillTier.ofRating(4.1))
        assertEquals(SkillTier(4, Modifier.Plus), SkillTier.ofRating(4.2))
        // 超出范围的分值夹在 1− 和 9+ 之间
        assertEquals(SkillTier(1, Modifier.Minus), SkillTier.ofRating(0.2))
        assertEquals(SkillTier(9, Modifier.Plus), SkillTier.ofRating(12.0))
        assertEquals(SkillTier(9), SkillTier(12))
    }

    @Test
    fun offsetAndDifferenceText() {
        val four = SkillTier(4)
        assertEquals(SkillTier(4, Modifier.Plus).offset(1), four.offset(2))
        assertEquals(4, four.steps(SkillTier(5, Modifier.Plus)))
        assertEquals("实力相当", SkillTier.differenceText(0))
        assertEquals("高 1 档", SkillTier.differenceText(1))
        assertEquals("低 1 级", SkillTier.differenceText(-3))
        assertEquals("高 1 级 1 档", SkillTier.differenceText(4))
        assertEquals("7 到 8+", SkillTier.rangeText(SkillTier(7), SkillTier(8, Modifier.Plus)))
    }

    @Test
    fun eliteTiersHaveTheirOwnNames() {
        assertEquals("Lv.4+ 中级", SkillTier(4, Modifier.Plus).displayText)
        assertEquals("Lv.6− 崭露头角", SkillTier(6, Modifier.Minus).displayText)
        assertEquals("Lv.7 州级选手", SkillTier(7).displayText)
        assertEquals("Lv.9+ 世界顶尖", SkillTier(9, Modifier.Plus).displayText)
        // 每一档都有具体标准
        for (tier in SkillTier.all) assertFalse(tier.code, SkillLevel.tierCriteria(tier).isEmpty())
    }

    @Test
    fun matchingToleranceUsesTiers() {
        // 容忍 1 级 = 上下 3 档：4+ 能匹配 3+ 到 5+，匹配不到 3
        val me = SkillTier(4, Modifier.Plus)
        assertTrue(abs(me.steps(SkillTier(3, Modifier.Plus))) <= 3)
        assertTrue(abs(me.steps(SkillTier(3))) > 3)
    }

    @Test
    fun levelTables() {
        assertEquals("Lv.6 俱乐部高手", SkillLevel.displayText(6))
        for (level in SkillLevel.range) {
            assertFalse(SkillLevel.anchors(level).isEmpty())
            assertFalse(SkillLevel.dimensionNotes(level).isEmpty())
        }
        // 美国的赛事组别只给美国地区看
        assertEquals("D 组", SkillLevel.usFlight(4, region = "US"))
        assertEquals(null, SkillLevel.usFlight(4, region = "SG"))
        assertEquals(SkillTier(8, Modifier.Plus), VerificationStatus.National.maxTier)
        assertEquals(VerificationStatus.Tournament, VerificationStatus.of("regionalChampion"))
    }
}
