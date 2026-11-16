package com.badie.app.features.profile

import com.badie.app.models.GameMode
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.ReputationScore
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillLevel
import com.badie.app.models.SkillTier
import com.badie.app.models.User
import com.badie.app.models.VerificationStatus
import com.badie.app.backend.VenueName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 等级卡片的链接和字、资料完成度、打赏入口。卡片的几条对应 iPhone 的 PlayStyleTests */
class LevelCardTest {
    @Test
    fun cardLinks() {
        assertEquals("4-plus", LevelCardData.slug(SkillTier(4, SkillTier.Modifier.Plus)))
        assertEquals("4", LevelCardData.slug(SkillTier(4)))
        assertEquals("1-minus", LevelCardData.slug(SkillTier(1, SkillTier.Modifier.Minus)))
        assertEquals("7 级起每级一个页面", "8", LevelCardData.slug(SkillTier(8, SkillTier.Modifier.Plus)))
        assertEquals("https://badie.rsvp/levels/4-plus/?ref=card", LevelCardData.url(SkillTier(4, SkillTier.Modifier.Plus), language = "en"))
        assertEquals("https://badie.rsvp/zh/levels/4-plus/?ref=card", LevelCardData.url(SkillTier(4, SkillTier.Modifier.Plus), language = "zh-Hans"))
        assertEquals("https://badie.rsvp/zh-hant/levels/3/?ref=card", LevelCardData.url(SkillTier(3), language = "zh-Hant"))
        assertEquals("https://badie.rsvp/ja/levels/3/?ref=card", LevelCardData.url(SkillTier(3), language = "ja"))
        for (tier in SkillTier.all.filter { it.level <= SkillLevel.MAX_SELF_SELECTABLE }) {
            assertEquals(tier, LevelCardData.tier(LevelCardData.slug(tier)))
        }
        assertNull(LevelCardData.tier("4-up"))
        assertNull(LevelCardData.tier("levels"))
    }

    @Test
    fun cardTextOnlyShowsWhatIsKnown() {
        var data = LevelCardData(SkillTier(4, SkillTier.Modifier.Plus), LevelCardLabel.SelfRated)
        val status = LevelCardLabel.SelfRated.title
        assertEquals("${data.tierLine} · $status", data.subline())
        // 什么都不知道：背面印这一档的标准
        assertEquals(listOf(data.tierLine), data.backRows.map { it.label })
        data = data.copy(region = "Los Angeles", mode = GameMode.Doubles, venue = "LABC", times = "周三晚上")
        assertEquals("LOS ANGELES · $status", data.subline(includesTier = false))
        assertEquals(listOf(GameMode.Doubles.title, "LABC", "周三晚上"), data.backRows.map { it.value })
        // 没有头像，或者关掉了“印上头像”：不印
        assertNull(data.avatarImage)
        assertFalse(data.footer.isEmpty())
        assertTrue(data.copy(showsURL = false).footer != data.footer)
    }

    @Test
    fun cardLabel() {
        var user = User(id = "u1", nickname = "阿杰", phone = "", selfReportedLevel = 4)
        assertEquals(LevelCardLabel.SelfRated, LevelCardLabel.of(user))
        user = user.copy(reputation = ReputationScore(ReputationScore.NEW_PLAYER_THRESHOLD, 4.0, 0.2, 100.0, 4.0))
        assertEquals(LevelCardLabel.Calibrated, LevelCardLabel.of(user))
        user = user.applyingVerification(VerificationStatus.Tournament, SkillTier(7))
        assertEquals(LevelCardLabel.Verified, LevelCardLabel.of(user))
    }

    @Test
    fun cardFromProfile() {
        val base = User(id = "u1", nickname = "阿杰", phone = "", selfReportedLevel = 4, tag = 3400, preferredMode = GameMode.Singles)
        val summary = com.badie.app.models.SkillAssessmentSummary(4, false, false, assessedAt = 0, rating = 4.0, answers = SkillAssessment.levelCardDemoAnswers)
        val user = base.copy(assessment = summary)
        val slots = listOf(RecurringTimeSlot.create(4, 19, endHour = 21), RecurringTimeSlot.create(7, 14, endHour = 17, isActive = false))
        val data = LevelCardData.make(user, VenueName("v1", "LABC", "Los Angeles"), slots, avatar = null)
        assertEquals("阿杰#3400", data.name)
        assertEquals("Los Angeles", data.region)
        assertEquals("LABC", data.venue)
        assertNotNull("打法从存着的答案算", data.play)
        assertEquals("关掉的空闲时间不印", com.badie.app.models.UsualTimeText.summary(slots.take(1)), data.times)
        assertEquals(4, data.backRows.size)
    }

    @Test
    fun profileCompleteness() {
        val user = User(id = "u1", nickname = "阿杰", phone = "", selfReportedLevel = 4)
        assertEquals(ProfileField.entries, ProfileField.missing(user, emptyList(), hasVenue = false))
        val inactive = listOf(RecurringTimeSlot.create(4, 19, endHour = 21, isActive = false))
        assertTrue("空闲时间只算打开的", ProfileField.UsualTimes in ProfileField.missing(user, inactive, hasVenue = true))
        val done = user.copy(avatar = user.avatar.copy(photoVersion = 1, cardPhotoVersion = 2))
        assertEquals(emptyList<ProfileField>(), ProfileField.missing(done, listOf(RecurringTimeSlot.create(4, 19, endHour = 21)), hasVenue = true))
    }

    @Test
    fun tipJarRegions() {
        assertTrue(TipJar.isAvailable("us"))
        assertTrue(TipJar.isAvailable("CN"))
        assertFalse("欧盟不显示", TipJar.isAvailable("DE"))
        assertFalse("拿不到地区不显示", TipJar.isAvailable(""))
        assertFalse(TipJar.isAvailable(null))
    }

    @Test
    fun feedbackLimits() {
        assertEquals("abcde", limited("abcdefg", 5))
        assertEquals("表情算一个字", "🏸🏸", limited("🏸🏸🏸", 2))
        assertEquals(listOf("bug", "idea", "court", "other"), FeedbackKind.entries.map { it.rawValue })
    }

    @Test
    fun slotsSortMondayFirst() {
        val sunday = RecurringTimeSlot.create(1, 9, endHour = 11)
        val mondayLate = RecurringTimeSlot.create(2, 19, endHour = 21)
        val mondayEarly = RecurringTimeSlot.create(2, 7, endHour = 9)
        assertEquals(listOf(mondayEarly, mondayLate, sunday), sortedSlots(listOf(sunday, mondayLate, mondayEarly)))
    }
}
