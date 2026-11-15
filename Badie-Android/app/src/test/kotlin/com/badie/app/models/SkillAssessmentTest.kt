package com.badie.app.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 定级问卷：每个选项对应一个等级；技术、比赛能力各取平均并受最弱一项限制，两者以弱的为准；
 * 5+ 往上看俱乐部位置，6+ 要有比赛经历；经历保底，最高 6+。
 * 和 iPhone 的 SkillAssessmentTests、网页的 web/tests/assessment.test.ts 是同样的用例
 */
class SkillAssessmentTest {
    private val beginner = answers(listOf(1, 1, 1, 1, 1, 1, 1), listOf(0, 1, 1, 0))
    private val middle = answers(listOf(3, 3, 3, 2, 2, 2, 3), listOf(2, 2, 3, 2))
    private val strong = answers(listOf(4, 4, 4, 3, 3, 3, 4), listOf(3, 3, 4, 3))
    private val top = answers(listOf(5, 5, 5, 4, 4, 4, 5), listOf(4, 4, 5, 4))

    private fun code(answers: Map<String, Int>): String? = SkillAssessment.evaluate(answers)?.tier?.code

    @Test
    fun fourteenQuestions() {
        assertEquals(14, SkillAssessment.questions.size)
        assertEquals(73, SkillAssessment.questions.sumOf { it.options.size })
        assertEquals(SkillAssessment.demoAnswers.keys, SkillAssessment.questions.map { it.id }.toSet())
        for (question in SkillAssessment.questions) {
            assertEquals(question.options.indices.toList(), question.options.map { it.id })
        }
    }

    @Test
    fun incompleteAnswersHaveNoResult() {
        assertNull(SkillAssessment.evaluate(SkillAssessment.demoAnswers - "standing"))
    }

    @Test
    fun brandNewPlayerIsOneMinus() {
        assertEquals("1−", code(answers(listOf(0, 0, 0, 0, 0, 0, 0), listOf(0, 0, 0, 0))))
        assertEquals("1", code(answers(listOf(0, 0, 0, 0, 1, 0, 0), listOf(0, 1, 0, 0))))
    }

    @Test
    fun typicalIntermediateIsLevelFour() {
        val result = SkillAssessment.evaluate(SkillAssessment.demoAnswers)!!
        assertEquals("4", result.tier.code)
        assertEquals(7, result.dimensions.size)
        assertEquals("分项按档位显示", "3", result.dimensions.first { it.id == "backhand" }.code)
    }

    @Test
    fun middleAnswersDoNotJumpToFive() {
        assertEquals("2", code(beginner))
        assertEquals("3+", code(middle))
        assertEquals("5−", code(strong))
    }

    @Test
    fun weakestSkillHoldsTheLevelAndIsNamed() {
        // 其他都在 3 级左右，反手还只能绕头：短板把等级拉下来
        val result = SkillAssessment.evaluate(answers(listOf(3, 3, 3, 0, 2, 2, 3), listOf(2, 2, 3, 2)))!!
        assertEquals("3−", result.tier.code)
        assertTrue(result.limitingGate, result.limitingGate!!.startsWith("想到 3 级先补短板：反手后场"))
    }

    @Test
    fun weakerOfTechniqueAndGameDecides() {
        // 技术不错，但被动球、战术还弱
        val result = SkillAssessment.evaluate(answers(listOf(4, 4, 4, 3, 3, 3, 4), listOf(1, 2, 3, 1)))!!
        assertEquals("4−", result.tier.code)
        assertTrue(result.limitingGate, result.limitingGate!!.startsWith("想到 4 级先补短板：接杀和被动球"))
    }

    @Test
    fun aboveFivePlusDependsOnClubStanding() {
        val unknown = SkillAssessment.evaluate(top)!!
        assertEquals("5+", unknown.tier.code)
        assertTrue(unknown.limitingGate!!.contains("俱乐部"))
        assertEquals("6−", code(top + ("standing" to 3)))
        assertEquals("6", code(top + ("standing" to 4)))
        // 霸主还要有比赛或青训经历
        val ace = top + ("standing" to 5)
        val noTournaments = SkillAssessment.evaluate(ace)!!
        assertEquals("6", noTournaments.tier.code)
        assertTrue(noTournaments.limitingGate!!.contains("比赛或青训经历"))
        val result = SkillAssessment.evaluate(ace + ("experience" to 4))!!
        assertEquals(SkillAssessment.maxTier, result.tier)
        assertTrue("参加过 A/Open 组：提示申请认证", result.suggestsVerification)
        // 位置再高，技术没到也不是 6
        assertEquals("5−", code(strong + ("standing" to 5)))
    }

    @Test
    fun strengthsAreTheBestDimensions() {
        assertEquals(listOf("反手后场"), SkillAssessment.evaluate(strong)!!.strengths.map { it.name })
        assertTrue("各项一样时没有突出的特点", SkillAssessment.evaluate(top)!!.strengths.isEmpty())
    }

    @Test
    fun experienceFloorRaisesLevelAndFlagsCalibration() {
        // 技术都在入门，但说自己 C/B 组进过前四 → 保底 5−，标记待校准
        val result = SkillAssessment.evaluate(beginner + ("experience" to 3))!!
        assertEquals("5−", result.tier.code)
        assertTrue(result.needsCalibration)
    }

    @Test
    fun returningPlayerFloorIsOneLower() {
        val claimed = beginner + ("experience" to 3)
        val active = SkillAssessment.evaluate(claimed)!!
        val returning = SkillAssessment.evaluate(claimed + ("recency" to 1))!!
        assertEquals(active.level - 1, returning.level)
        assertTrue(returning.isReturning)
    }

    @Test
    fun everyLevelHasDescriptions() {
        for (level in SkillLevel.range) {
            assertFalse(SkillLevel.name(level).isEmpty())
            assertTrue("Lv.$level 至少 2 条描述", SkillLevel.anchors(level).size >= 2)
            assertFalse("Lv.$level 有分项标准", SkillLevel.dimensionNotes(level).isEmpty())
        }
        assertEquals("D 组", SkillLevel.usFlight(4, region = "US"))
        assertNull("其他国家没有美国组别", SkillLevel.usFlight(4, region = "MY"))
        assertEquals("Lv.3+ 初级", SkillTier(3, SkillTier.Modifier.Plus).displayText)
        assertEquals("Lv.6 俱乐部高手", SkillTier(6).displayText)
    }

    @Test
    fun techniquesAreNotRequirementsAboveLevelFour() {
        // 技术在 4 级就全部熟练；5 级以上的档位标准看被动球、战术、俱乐部位置
        for (tier in SkillTier.all.filter { it.level in 5..6 }) {
            assertFalse(tier.code, SkillLevel.tierCriteria(tier).joinToString("").contains("反手"))
        }
        assertTrue(SkillLevel.tierCriteria(SkillTier(4)).joinToString("").contains("反手"))
    }

    @Test
    fun summaryRetakeEvery90Days() {
        val summary = SkillAssessmentSummary(level = 4, needsCalibration = false, isReturning = false, assessedAt = 0, rating = 4 + 1.0 / 3)
        assertEquals("4+", summary.tier.code)
        assertFalse(summary.canRetake(now = 30L * 86_400_000))
        assertTrue(summary.canRetake(now = 90L * 86_400_000))
        assertNull("旧数据没有答案：没有打法", summary.play)
    }

    companion object {
        /** 选项序号（A = 0）。技术：高远、杀球、吊球、反手、网前、平抽、步法；比赛：被动球、双打、稳定性、战术 */
        fun answers(technique: List<Int>, game: List<Int>, standing: Int = 0, experience: Int = 0, returning: Boolean = false): Map<String, Int> =
            mapOf("standing" to standing, "experience" to experience, "recency" to if (returning) 1 else 0) +
                listOf("clear", "smash", "drop", "backhand", "net", "drive", "footwork").zip(technique) +
                listOf("passive", "doubles", "stability", "tactics").zip(game)
    }
}
