package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * 项目、高水平认证的证据、防骗、球群、挑战。对应 iPhone 的 PlayEventTests、VerificationTests、
 * SocialRulesTests 里只用模型的部分（要模拟后端的那些等搬后端时再搬）
 */
class SocialRulesTest {
    // MARK: 项目

    @Test
    fun eventChoicesFollowModeAndGender() {
        assertEquals(listOf(null, PlayEvent.Men), PlayEvent.choices(GameMode.Singles, Gender.Male))
        assertEquals(listOf(null, PlayEvent.Women, PlayEvent.Mixed), PlayEvent.choices(GameMode.Doubles, Gender.Female))
        assertEquals("没选性别只能不限", listOf(null), PlayEvent.choices(GameMode.Doubles, Gender.Unspecified))
        // 直接约某个人：按两个人的性别定
        assertEquals("两个男生约单打就是男单", listOf(PlayEvent.Men), PlayEvent.choices(GameMode.Singles, Gender.Male, Gender.Male))
        assertEquals("男女约单打只能不限", listOf(null), PlayEvent.choices(GameMode.Singles, Gender.Male, Gender.Female))
        assertEquals(listOf(null, PlayEvent.Women), PlayEvent.choices(GameMode.Doubles, Gender.Female, Gender.Female))
        assertEquals(listOf(null, PlayEvent.Mixed), PlayEvent.choices(GameMode.Doubles, Gender.Female, Gender.Male))
    }

    @Test
    fun eventServerMapping() {
        assertEquals(PlayEvent.Women, PlayEvent.ofServer(Gender.Female, mixed = false))
        assertEquals(PlayEvent.Mixed, PlayEvent.ofServer(null, mixed = true))
        assertNull("不限", PlayEvent.ofServer(null, mixed = false))
        assertEquals(Gender.Male, PlayEvent.Men.gender)
        assertNull("混双不限性别，靠混双标记", PlayEvent.Mixed.gender)
    }

    @Test
    fun eventTitles() {
        assertEquals("女单", PlayEvent.Women.title(GameMode.Singles))
        assertEquals("男双", PlayEvent.Men.title(GameMode.Doubles))
        val open: PlayEvent? = null
        assertEquals("不限就写双打", GameMode.Doubles.title, open.title(GameMode.Doubles))
    }

    // MARK: 高水平认证

    @Test
    fun bwfEvidenceMustBePlayerPage() {
        assertNull(VerificationEvidence.problem("bwfbadminton.com/player/57945/demo-player", VerificationStatus.Bwf))
        assertNull(VerificationEvidence.problem("https://bwf.tournamentsoftware.com/player-profile/abc-123", VerificationStatus.Bwf))
        assertEquals("排名总表不算", "需要具体的球员页，链接里要有球员 ID", VerificationEvidence.problem("https://bwfbadminton.com/rankings/", VerificationStatus.Bwf))
        assertEquals("必须是 BWF 官网", "需要 BWF 官网的球员页（bwfbadminton.com/player/…）",
            VerificationEvidence.problem("https://example.com/player/1", VerificationStatus.Bwf))
        assertEquals("只接受 https", "链接格式不对，请复制完整的网页地址", VerificationEvidence.problem("http://bwfbadminton.com/player/1/x", VerificationStatus.Bwf))
        assertNull(VerificationEvidence.problem("https://usab.tournamentsoftware.com/sport/player.aspx?id=1", VerificationStatus.Tournament))
        assertEquals("需要 tournamentsoftware.com 上的成绩页", VerificationEvidence.problem("https://instagram.com/me", VerificationStatus.Tournament))
        assertEquals("请填写证据链接", VerificationEvidence.problem("  ", VerificationStatus.National))
        assertEquals("https://bwfbadminton.com/player/1/x", VerificationEvidence.normalized(" bwfbadminton.com/player/1/x "))
    }

    @Test
    fun certificateNumberCapsTier() {
        // 15 位电子证书，末位 2 = 二级 → 最高 7（州级）
        assertNull("位数不对", VerificationEvidence.certificateMaxTier("20250440100012"))
        assertEquals(SkillTier(7), VerificationEvidence.certificateMaxTier("202504401000122"))
        assertEquals(SkillTier(8, SkillTier.Modifier.Plus), VerificationEvidence.certificateMaxTier("20250440100012x"))
        assertNull(VerificationEvidence.problem("202504401000122", VerificationStatus.National))
        assertTrue(VerificationEvidence.problem("202504401000122", VerificationStatus.Bwf) != null)
        assertEquals("20250440100012X", VerificationEvidence.normalized("20250440100012x"))
    }

    @Test
    fun unverifiedPeersCannotPushPastSevenMinus() {
        val user = User.create("a", "测试", selfReportedLevel = 7).copy(
            selfReportedRating = SkillAssessment.maxTier.rating,
            reputation = ReputationScore(20, 9.3, 1.0, 100.0, 5.0),
        )
        assertEquals(VerificationStatus.unverifiedMaxTier, user.displayTier)
    }

    // MARK: 防骗

    @Test
    fun contactInfoDetection() {
        assertTrue(ContactInfoDetector.mentionsOffPlatformContact("我电话 626 555 0123"))
        assertTrue(ContactInfoDetector.mentionsOffPlatformContact("加我微信聊"))
        assertTrue(ContactInfoDetector.mentionsOffPlatformContact("先 Venmo 我 $20 占位"))
        assertFalse(ContactInfoDetector.mentionsOffPlatformContact("周四 19:30 LABC 见"))
        assertTrue(ContactInfoDetector.containsLink("看这个 https://example.com/x"))
        assertTrue(ContactInfoDetector.containsLink("去 badie.rsvp 看看"))
        assertFalse(ContactInfoDetector.containsLink("周四见"))
        assertFalse(ContactInfoDetector.containsLink("Lv.4+ 双打 19:30"))
    }

    // MARK: 球群

    private val zone = ZoneId.of("America/Los_Angeles")

    private fun schedule(weekday: Int = 3, start: Int = 19 * 60, end: Int = 21 * 60, capacity: Int = 8, fee: String? = null) =
        GroupSchedule("s$weekday", weekday, start, end, capacity, fee)

    @Test
    fun groupSchedulesAndFees() {
        assertTrue(GroupSchedule.areValid(listOf(schedule())))
        assertFalse("至少 1 小时", GroupSchedule.areValid(listOf(schedule(end = 19 * 60 + 30))))
        assertFalse("名额至少 4 人", GroupSchedule.areValid(listOf(schedule(capacity = 2))))
        assertTrue("教练带课 1 人也行", GroupSchedule.areValid(listOf(schedule(capacity = 1)), coached = true))
        assertFalse(GroupSchedule.areValid(listOf(schedule(fee = "费".repeat(121)))))
        assertFalse(GroupSchedule.areValid(emptyList()))

        assertEquals("每周二", schedule().weekdayTitle)
        assertEquals("19:00–21:00", schedule().timeText)
        val group = PlayGroup(
            "g", "周二夜场", "v", "o", listOf("o"), listOf("o"), emptyList(), "", 3..5,
            listOf(schedule(fee = "每人 $15"), schedule(5, fee = "每人 $15")), PlayGroup.JoinPolicy.Open, "ABC234", 0,
        )
        assertEquals(listOf("每人 $15"), group.feeLines)
        assertEquals(listOf("每周二 19:00–21:00: 每人 $15"), group.copy(schedules = listOf(schedule(fee = "每人 $15"), schedule(5))).feeLines)
        assertEquals("Lv.3–5", group.levelText)
        assertEquals(
            tr("来「%@」一起打羽毛球。%@ · %@ · %@。在 Badie App 输入群号 %@ 加入，报名、候补都在 App 里。", "周二夜场", "LABC",
                "每周二 19:00–21:00和每周四 19:00–21:00", "Lv.3–5", "ABC234") + "\nhttps://badie.rsvp/join/?code=ABC234",
            group.inviteText("LABC"),
        )

        // 2026-11-10 是周二
        val tuesday = ZonedDateTime.of(2026, 11, 10, 12, 0, 0, 0, zone).toInstant().toEpochMilli()
        val slot = schedule().slot(tuesday, zone)
        assertEquals(ZonedDateTime.of(2026, 11, 10, 19, 0, 0, 0, zone).toInstant().toEpochMilli(), slot?.startTime)
        assertNull(schedule().slot(addingDays(tuesday, 1, zone), zone))
        assertEquals("g|s3|20261110", GroupSession.makeId("g", "s3", tuesday, zone))
    }

    @Test
    fun groupSessionWaitlist() {
        val session = GroupSession("id", "g", "s", TimeSlot(0, 0, 1), 2, listOf("a", "b"), listOf("c", "d"))
        assertTrue(session.isFull)
        assertEquals(GroupSession.Status.SignedUp, session.status("a"))
        assertEquals(GroupSession.Status.Waitlisted(2), session.status("d"))
        assertEquals(GroupSession.Status.None, session.status("e"))
        assertEquals("近 30 天 4 场 · 平均每场 7 人", GroupActivity(4, 6.5).text)
        assertEquals("近 30 天还没开过场", GroupActivity(0, 0.0).text)
    }

    // MARK: 挑战

    @Test
    fun challengeExpiryAndReasons() {
        val now = 1_800_000_000_000L
        val court = Venue("v", "LABC", lat = 0.0, lon = 0.0, countryCode = "US")
        val slot = TimeSlot.of(now + 24 * 3_600_000L, now + 24 * 3_600_000L, now + 26 * 3_600_000L)
        val challenge = Challenge("c", "a", "b", court, slot, "", now, ChallengeStatus.Pending)
        assertEquals("开赛比 48 小时早，就按开赛算", slot.startTime, challenge.expiresAt)
        assertFalse(challenge.isExpired(now))
        assertTrue(challenge.isExpired(slot.startTime))
        assertEquals(GameMode.Singles, challenge.mode)
        assertTrue(challenge.involves("b"))
        assertFalse(challenge.involves("c"))
        assertEquals("a", challenge.other("b"))
        assertEquals("你同时最多发出 3 个挑战", ChallengeAvailability.TooManyOutgoing.reason())
        assertEquals("1/20 之后才能再次挑战 TA", ChallengeAvailability.Cooldown(now + 5 * 86_400_000L).reason(zone))
        assertNull(ChallengeAvailability.Available.reason())
    }
}
