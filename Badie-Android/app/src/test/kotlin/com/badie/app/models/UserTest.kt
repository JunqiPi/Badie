package com.badie.app.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 口碑和等级：分数不公开，正面标签有门槛，问题只私下提醒。对应 iPhone 的 ReputationTests 和 SkillAssessmentTests 里用户的部分 */
class UserTest {
    private val now = 1_800_000_000_000L
    private var next = 0

    private fun survey(rater: String, match: String, tags: List<SurveyTag> = emptyList(), issues: List<SurveyIssue> = emptyList(), daysAgo: Double = 1.0) =
        MatchSurvey(
            id = "s${next++}", matchId = match, evaluatorId = rater, evaluatedUserId = "me", skillRating = 4, wasPunctual = true,
            attendance = AttendanceAnswer.OnTime, characterRating = 5, tags = tags, submittedAt = now - (daysAgo * 86_400_000).toLong(), issues = issues,
        )

    @Test
    fun publicTagsNeedFiveRatersAndThreeSessions() {
        val four = (0 until 4).map { survey("r$it", "m${it % 3}", tags = listOf(SurveyTag.Friendly)) }
        assertTrue("不到 5 位球友不展示", ReputationScore.publicTags(four).isEmpty())
        val five = four + survey("r4", "m0", tags = listOf(SurveyTag.Friendly, SurveyTag.Skilled))
        assertEquals("只有 1 位球友给的标签不展示", listOf(SurveyTag.Friendly), ReputationScore.publicTags(five))
        val twoSessions = (0 until 6).map { survey("r$it", "m${it % 2}", tags = listOf(SurveyTag.Friendly)) }
        assertTrue("不到 3 场不展示", ReputationScore.publicTags(twoSessions).isEmpty())
        val sameRaterTwice = (0 until 5).map { survey("r$it", "m${it % 3}") } +
            survey("r0", "m1", tags = listOf(SurveyTag.Patient)) + survey("r0", "m2", tags = listOf(SurveyTag.Patient))
        assertTrue("同一个人给两次只算一人", ReputationScore.publicTags(sameRaterTwice).isEmpty())
    }

    @Test
    fun recurringIssuesNeedThreeDistinctRatersWithinSixtyDays() {
        val rude = listOf(SurveyIssue.Rude)
        var surveys = listOf(survey("a", "m1", issues = rude), survey("b", "m2", issues = rude), survey("b", "m3", issues = rude))
        assertTrue(ReputationScore.recurringIssues(surveys, now).isEmpty())
        surveys = surveys + survey("c", "m4", issues = rude, daysAgo = 61.0)
        assertTrue("60 天前的不算", ReputationScore.recurringIssues(surveys, now).isEmpty())
        surveys = surveys + survey("d", "m5", issues = listOf(SurveyIssue.Rude, SurveyIssue.Hogging))
        assertEquals(rude, ReputationScore.recurringIssues(surveys, now))
    }

    @Test
    fun reliableBadgeUsesAttendanceOnly() {
        val user = User.create("u", "测试", selfReportedLevel = 4)
        assertFalse("至少打满 3 场", user.copy(attendance = AttendanceRecord(2, 0, 0)).isReliable)
        assertTrue(user.copy(attendance = AttendanceRecord(3, 0, 0)).isReliable)
        assertFalse(user.copy(attendance = AttendanceRecord(3, 0, 2)).isReliable)
        assertFalse(user.copy(attendance = AttendanceRecord(3, 1, 0)).isReliable)
        assertFalse("对外摘要不含任何评分", user.publicSummary.contains("★"))
        assertEquals("新球友 · 还没打过", user.publicSummary)
        assertEquals("20+ 场", user.copy(totalGames = 23).gamesBand)
        assertEquals(AttendanceRecord.Standing.Warned, AttendanceRecord(5, 1, 1).standing)
        assertEquals(71, AttendanceRecord(5, 1, 1).reliabilityPercentage)
    }

    @Test
    fun calibratingPlayersWeighPeersMore() {
        val reputation = ReputationScore(6, 4.0, 2.0, 100.0, 5.0)
        val user = User.create("u", "测试", selfReportedLevel = 6).copy(reputation = reputation)
        assertEquals(0.3 * 6 + 0.7 * 4, user.calculatedLevel, 0.001)
        val calibrating = user.copy(assessment = SkillAssessmentSummary(6, needsCalibration = true, isReturning = false, assessedAt = now))
        assertEquals(0.15 * 6 + 0.85 * 4, calibrating.calculatedLevel, 0.001)
        // 跳过了定级：暂按 3 级，球友评价占比更高
        val skipped = User.create("u", "测试", selfReportedLevel = SkillAssessment.PROVISIONAL_LEVEL).copy(assessmentSkippedAt = now)
        assertTrue(skipped.needsAssessment)
        assertEquals(SkillTier(3), skipped.displayTier)
        assertEquals(User.CALIBRATING_PEER_WEIGHT, skipped.peerWeight, 0.001)
    }

    @Test
    fun displayTierIsCappedUntilVerified() {
        // 没认证：球友评价再高也最多 7−
        val praised = User.create("u", "测试", selfReportedLevel = 6).copy(reputation = ReputationScore(10, 9.0, 3.0, 100.0, 5.0))
        assertEquals(VerificationStatus.unverifiedMaxTier, praised.displayTier)
        // 认证过：档位限制在这类证据的范围内；球友评价最多往下拉 1 档
        val verified = praised.copy(reputation = ReputationScore(10, 3.0, 3.0, 100.0, 5.0))
            .applyingVerification(VerificationStatus.Tournament, SkillTier(9))
        assertEquals(SkillTier(8).rating, verified.verifiedRating!!, 0.001)
        assertEquals(SkillTier(8).offset(-1), verified.displayTier)
        assertEquals(null, verified.applyingVerification(VerificationStatus.Unverified, SkillTier(1)).verifiedRating)
    }

    @Test
    fun avatarAndTag() {
        val user = User.create("u1", "阿杰", selfReportedLevel = 4)
        assertEquals("阿", user.avatarText)
        assertEquals("🏸", Avatar("", 0).text(""))
        assertEquals("😀", Avatar("", 0).text("😀abc"))
        assertEquals("#0042", user.copy(tag = 42).tagText)
        assertEquals("https://badie.rsvp/add/abc/", user.copy(friendCode = "abc").friendLink)
        assertEquals(9, User.create("u", "x", selfReportedLevel = 12).selfReportedLevel)
    }
}
