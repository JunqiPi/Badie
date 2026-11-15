package com.badie.app.models

import com.badie.app.models.SkillAssessmentTest.Companion.answers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 打法：六个维度（进攻 = 杀球，网前 = 网前和吊球，防守 = 被动球和稳定性，速度 = 平抽挡，步法，战术 = 战术和双打），
 * 问卷定出 1–2 级是新星；否则最高和最低差不超过半级是六边形战士，再否则看最高的一项（一样高按进攻、网前、防守、速度、步法、战术）。
 * 和 iPhone 的 PlayStyleTests、网页 web/src/app/assessment.ts 的测试用同样的用例：改了这里，另外两边也要改。
 */
class PlayStyleTest {
    private class Fixture(
        val name: String,
        val technique: List<Int>,
        val game: List<Int>,
        /** 问卷定出的档位 */
        val tier: String,
        val style: PlayStyle,
        /** 进攻、网前、防守、速度、步法、战术 */
        val axes: List<Double>,
        /** 卡片上的数字（四舍五入到整级） */
        val shown: List<Int>,
        val bestShot: String,
        /** 离下一级还差：下一级 to 题目 ID */
        val gap: Pair<Int, String>?,
    )

    private val fixtures = listOf(
        Fixture("demo", listOf(4, 4, 4, 2, 3, 3, 4), listOf(2, 2, 3, 2), "4", PlayStyle.Allround,
            listOf(4.0, 4.0, 4.0, 4.0, 4.0, 3.75), listOf(4, 4, 4, 4, 4, 4), "clear", 5 to "backhand"),
        Fixture("cannon", listOf(4, 5, 4, 2, 3, 3, 4), listOf(2, 2, 3, 2), "4", PlayStyle.Cannon,
            listOf(6.0, 4.0, 4.0, 4.0, 4.0, 3.75), listOf(6, 4, 4, 4, 4, 4), "smash", 5 to "backhand"),
        Fixture("net", listOf(3, 2, 5, 2, 4, 2, 3), listOf(2, 2, 3, 2), "4−", PlayStyle.Net,
            listOf(2.5, 6.0, 4.0, 2.5, 3.0, 3.75), listOf(3, 6, 4, 3, 3, 4), "drop", 4 to "smash"),
        Fixture("wall", listOf(3, 2, 2, 2, 2, 2, 3), listOf(4, 2, 5, 2), "3+", PlayStyle.Wall,
            listOf(2.5, 2.5, 6.0, 2.5, 3.0, 3.75), listOf(3, 3, 6, 3, 3, 4), "clear", 4 to "drop"),
        Fixture("quick", listOf(3, 2, 2, 2, 2, 4, 3), listOf(1, 1, 2, 1), "3", PlayStyle.Quick,
            listOf(2.5, 2.5, 3.0, 6.0, 3.0, 2.75), listOf(3, 3, 3, 6, 3, 3), "drive", 4 to "drop"),
        Fixture("engine", listOf(3, 2, 2, 2, 2, 2, 5), listOf(1, 1, 2, 1), "3", PlayStyle.Engine,
            listOf(2.5, 2.5, 3.0, 2.5, 6.0, 2.75), listOf(3, 3, 3, 3, 6, 3), "footwork", 4 to "drop"),
        Fixture("captain", listOf(3, 2, 2, 2, 2, 2, 3), listOf(1, 4, 2, 4), "3+", PlayStyle.Captain,
            listOf(2.5, 2.5, 3.0, 2.5, 3.0, 6.0), listOf(3, 3, 3, 3, 3, 6), "clear", 4 to "drop"),
        // 3− 已经不是新星。进攻和网前一样高：按顺序取进攻；杀球和吊球一样好：按题目顺序取杀球
        Fixture("tieAttackNet", listOf(3, 4, 4, 2, 3, 2, 2), listOf(0, 0, 1, 0), "3−", PlayStyle.Cannon,
            listOf(4.0, 4.0, 2.0, 2.5, 2.5, 1.75), listOf(4, 4, 2, 3, 3, 2), "smash", 3 to "doubles"),
        // 最高和最低差半级：还是六边形战士
        Fixture("allroundHalf", listOf(4, 4, 4, 2, 3, 3, 4), listOf(2, 2, 2, 2), "4−", PlayStyle.Allround,
            listOf(4.0, 4.0, 3.5, 4.0, 4.0, 3.75), listOf(4, 4, 4, 4, 4, 4), "clear", 4 to "backhand"),
        // 差 0.75 级：看最高的一项
        Fixture("cannonEdge", listOf(4, 4, 4, 2, 3, 3, 4), listOf(2, 2, 3, 1), "4−", PlayStyle.Cannon,
            listOf(4.0, 4.0, 4.0, 4.0, 4.0, 3.25), listOf(4, 4, 4, 4, 4, 3), "clear", 4 to "backhand"),
        // 完全的新手（1−）：新星；网前 0.5 显示成 1；没有“还差”
        Fixture("brandNew", listOf(0, 0, 0, 0, 0, 0, 0), listOf(0, 0, 0, 0), "1−", PlayStyle.Rookie,
            listOf(1.0, 0.5, 1.5, 1.0, 1.0, 1.75), listOf(1, 1, 2, 1, 1, 2), "clear", null),
        // 2 级：新星（六项看是战术师也不算）；杀球和步法一样弱：按题目顺序取杀球
        Fixture("tieGap", listOf(1, 1, 2, 1, 1, 1, 1), listOf(0, 1, 1, 0), "2", PlayStyle.Rookie,
            listOf(1.5, 2.0, 2.0, 2.0, 1.5, 2.25), listOf(2, 2, 2, 2, 2, 2), "clear", 3 to "smash"),
        // 2 级的入门球友：新星
        Fixture("beginner", listOf(1, 1, 1, 1, 1, 1, 1), listOf(0, 1, 1, 0), "2", PlayStyle.Rookie,
            listOf(1.5, 1.5, 2.0, 2.0, 1.5, 2.25), listOf(2, 2, 2, 2, 2, 2), "clear", 3 to "drop"),
        // 5+ 往上看俱乐部位置：没有“还差”的那一项
        Fixture("top", listOf(5, 5, 5, 4, 4, 4, 5), listOf(4, 4, 5, 4), "5+", PlayStyle.Allround,
            listOf(6.0, 6.0, 6.0, 6.0, 6.0, 6.0), listOf(6, 6, 6, 6, 6, 6), "clear", null),
    )

    @Test
    fun fixtures() {
        for (fixture in fixtures) {
            val given = answers(fixture.technique, fixture.game)
            val profile = SkillAssessment.playProfile(given)!!
            assertEquals(fixture.name, fixture.style, profile.style)
            for ((axis, expected) in PlayAxis.entries.zip(fixture.axes)) {
                assertEquals("${fixture.name} $axis", expected, profile.value(axis), 0.0001)
            }
            assertEquals(fixture.name, fixture.shown, PlayAxis.entries.map(profile::displayValue))
            assertEquals(fixture.name, fixture.bestShot, profile.bestShot?.id)
            val result = SkillAssessment.evaluate(given)!!
            assertEquals(fixture.name, fixture.tier, result.tier.code)
            assertEquals("结果里带着同样的打法：${fixture.name}", profile, result.play)
            assertEquals(fixture.name, fixture.gap?.first, result.nextGap?.level)
            assertEquals(fixture.name, fixture.gap?.second, result.nextGap?.dimension?.id)
        }
    }

    @Test
    fun gapIsTheFirstItemOfTheLimitingGate() {
        val result = SkillAssessment.evaluate(answers(listOf(3, 3, 3, 0, 2, 2, 3), listOf(2, 2, 3, 2)))!!
        assertEquals("3−", result.tier.code)
        assertEquals(3, result.nextGap?.level)
        assertEquals("反手后场", result.nextGap?.dimension?.name)
        assertTrue(result.limitingGate!!.startsWith("想到 3 级先补短板：反手后场"))
    }

    @Test
    fun incompleteAnswersHaveNoPlayStyle() {
        // 要答完全部题目：新星要看问卷定出的等级
        for (id in listOf("tactics", "standing")) {
            assertNull(id, SkillAssessment.playProfile(answers(listOf(4, 4, 4, 2, 3, 3, 4), listOf(2, 2, 3, 2)) - id))
        }
    }

    @Test
    fun partners() {
        assertEquals(PlayStyle.Net, PlayStyle.Cannon.partner)
        assertEquals(PlayStyle.Cannon, PlayStyle.Net.partner)
        assertEquals(PlayStyle.Quick, PlayStyle.Wall.partner)
        assertEquals(PlayStyle.Wall, PlayStyle.Quick.partner)
        assertEquals(PlayStyle.Captain, PlayStyle.Engine.partner)
        assertEquals(PlayStyle.Engine, PlayStyle.Captain.partner)
        assertNull(PlayStyle.Allround.partner)
        assertNull(PlayStyle.Rookie.partner)
        for (style in PlayStyle.entries) {
            assertFalse(style.title.isEmpty())
            assertFalse(style.line.isEmpty())
        }
    }

    @Test
    fun summaryKeepsAnswersForTheCard() {
        val given = answers(listOf(4, 5, 4, 2, 3, 3, 4), listOf(2, 2, 3, 2))
        val summary = SkillAssessmentSummary(level = 4, needsCalibration = false, isReturning = false, assessedAt = 0, rating = 4.0, answers = given)
        assertEquals(PlayStyle.Cannon, summary.play?.style)
    }

    @Test
    fun ghostWords() {
        assertEquals(listOf("SMASH", "NET", "WALL", "SPRING", "MOTOR", "TACTICS", "ALL-ROUND", "ROOKIE"), PlayStyle.entries.map { it.ghostWord })
    }
}
