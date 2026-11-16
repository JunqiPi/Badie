package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** 时间段、房间、费用、等级、消息、存盘。对应 iPhone 的 ModelTests（距离在 GeoTest） */
class ModelTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    /** 2026-11-11 周三 10:00 */
    private val now = ZonedDateTime.of(2026, 11, 11, 10, 0, 0, 0, zone).toInstant().toEpochMilli()

    // MARK: TimeSlot

    private fun slot(day: Int = 1, start: Int, end: Int): TimeSlot =
        TimeSlot.on(addingDays(now, day, zone), startHour = start, endHour = end, zone = zone)!!

    private fun TimeSlot.check(maxDuration: Long = TimeSlotConstants.MAXIMUM_DURATION) = validate(now, maxDuration, zone)

    @Test
    fun overlapRequiresThirtyMinutes() {
        val overlap = slot(start = 18, end = 20).overlaps(slot(start = 19, end = 22), zone)
        assertNotNull(overlap)
        assertEquals(3_600_000L, overlap?.duration)

        val date = addingDays(now, 1, zone)
        val short = TimeSlot.on(date, 19, 40, 21, zone = zone)!!
        val shortOverlap = TimeSlot.on(date, startHour = 18, endHour = 20, zone = zone)!!
        // 只重叠 20 分钟，不算匹配
        assertNull(short.overlaps(shortOverlap, zone))
        assertNull(slot(start = 8, end = 10).overlaps(slot(start = 10, end = 12), zone))
    }

    @Test
    fun overlapAcrossDifferentDaysIsNil() {
        assertNull(slot(1, 19, 21).overlaps(slot(2, 19, 21), zone))
    }

    @Test
    fun durationValidation() {
        assertTrue(slot(start = 19, end = 20).check().isValid)
        assertEquals(TimeSlotValidationResult.Invalid("结束时间需要晚于开始时间"), slot(start = 19, end = 19).check())
        val date = addingDays(now, 1, zone)
        assertFalse(TimeSlot.on(date, startHour = 19, endHour = 19, endMinute = 30, zone = zone)!!.check().isValid)
        assertFalse("超过 8 小时应无效", slot(start = 8, end = 17).check().isValid)
        assertTrue(slot(start = 8, end = 16).check().isValid)
    }

    @Test
    fun dateRangeValidation() {
        assertFalse("过去的日期无效", slot(-1, 19, 21).check().isValid)
        assertTrue(slot(30, 19, 21).check().isValid)
        assertFalse("超过 30 天无效", slot(31, 19, 21).check().isValid)
    }

    @Test
    fun anyTimeAllowsSixteenHoursForMatching() {
        assertFalse("开局最长 8 小时", slot(2, 7, 23).check().isValid)
        assertTrue(slot(2, 7, 23).check(TimeSlotConstants.MAXIMUM_MATCH_DURATION).isValid)
        assertEquals("最长 16 小时", slot(2, 0, 24).check(TimeSlotConstants.MAXIMUM_MATCH_DURATION).errorMessage)
    }

    @Test
    fun trimmedForGameCapsAtTwoHours() {
        val trimmed = slot(start = 18, end = 22).trimmedForGame(zone = zone)
        assertEquals(2 * 3_600_000L, trimmed.duration)
        assertEquals(slot(start = 18, end = 22).startTime, trimmed.startTime)
        assertEquals(3_600_000L, slot(start = 19, end = 20).trimmedForGame(zone = zone).duration)
    }

    @Test
    fun recurringSlotNextOccurrenceAndLimit() {
        val today = weekdayOf(now, zone)
        val tomorrowWeekday = today % 7 + 1
        val recurring = RecurringTimeSlot.create(tomorrowWeekday, startHour = 19, endHour = 21)
        val next = recurring.nextOccurrence(now, zone)
        assertNotNull(next)
        assertTrue(isSameDay(next!!.date, addingDays(now, 1, zone), zone))
        assertTrue(recurring.isValidDuration)
        assertFalse(RecurringTimeSlot.create(2, startHour = 19, endHour = 19, endMinute = 30).isValidDuration)
        assertEquals("星期夹到 1–7", 7, RecurringTimeSlot.create(9, startHour = 19, endHour = 21).dayOfWeek)

        val five = (1..5).map { RecurringTimeSlot.create(it, startHour = 19, endHour = 21) }
        assertFalse(five.canAddMore)
        assertEquals(2, five.take(3).remainingSlots)
    }

    @Test
    fun suggestedDefaultAndRelativeText() {
        // 10 点：今晚 19–21 点
        val tonight = TimeSlot.suggestedDefault(now, zone)
        assertEquals(settingTime(now, 19, 0, zone), tonight.startTime)
        assertEquals("2 小时", tonight.formattedDuration)
        assertEquals("1 小时 30 分", TimeSlot(0, 0, 90 * 60_000L).formattedDuration)
        // 18:40：从 19:00 再过 30 分钟开始
        val evening = TimeSlot.suggestedDefault(settingTime(now, 18, 40, zone), zone)
        assertEquals(settingTime(now, 19, 30, zone), evening.startTime)
        assertEquals(settingTime(now, 21, 30, zone), evening.endTime)

        assertEquals("刚刚", DateText.relative(now - 59 * 60_000L, now))
        assertEquals("3 小时前", DateText.relative(now - 3 * 3_600_000L, now))
        assertEquals("还有 2 小时 15 分", DateText.countdown(now + 135 * 60_000L, now))
        assertEquals("已开始", DateText.countdown(now, now))
        assertEquals("剩 1 分钟", DateText.remaining(now + 20_000L, now))
        assertEquals("今天 · 周三", DateText.relativeDay(now, now, zone))
        assertEquals("明天 · 周四", DateText.relativeDay(addingDays(now, 1, zone), now, zone))
        assertEquals("11月14日周六", DateText.relativeDay(addingDays(now, 3, zone), now, zone))
        assertEquals("19:00–21:00", tonight.formattedTimeRange(zone))
        assertEquals("11/14", DateText.shortDay(addingDays(now, 3, zone), zone))
        assertEquals("昨天", DateText.compact(addingDays(now, -1, zone), now, zone))
    }

    // MARK: Room

    @Test
    fun roomCodeFormatAndUniqueness() {
        val codes = mutableSetOf<String>()
        repeat(500) {
            val code = Room.generateCode(codes)
            assertEquals(6, code.length)
            assertTrue(Room.isValidCode(code))
            assertFalse(code.any { it in "0O1IL" })
            assertFalse(code in codes)
            codes += code
        }
    }

    @Test
    fun roomCodeNormalization() {
        assertEquals("BX7K2M", Room.normalize("bx7 k2-m"))
        assertEquals("ABCDEF", Room.normalize("abcdefgh"))
        assertFalse(Room.isValidCode("ABC10O"))
        assertFalse(Room.isValidCode("ABC"))
    }

    private fun makeRoom(mode: GameMode, participants: Int, visibility: RoomVisibility = RoomVisibility.PrivateRoom, lastActivity: Long = now): Room {
        val users = (0 until participants).map { User.create("u$it", "球友$it", selfReportedLevel = 4) }
        return Room(
            id = "r", code = "ABCDEF", ownerId = "u0", mode = mode, visibility = visibility,
            participants = users.map { RoomParticipant.of(it, now) }, invitedUserIds = emptyList(), waitlist = emptyList(),
            levelRange = 1..9, tags = emptyList(), note = "", createdAt = now, lastActivityAt = lastActivity, status = RoomStatus.Open,
        )
    }

    @Test
    fun roomReadyState() {
        assertFalse(makeRoom(GameMode.Singles, 1).isReady)
        assertTrue(makeRoom(GameMode.Singles, 2).isReady)
        assertFalse(makeRoom(GameMode.Doubles, 3).isReady)
        assertTrue(makeRoom(GameMode.Doubles, 4).isReady)
        assertEquals(3, makeRoom(GameMode.Doubles, 1).openSeats)
        assertEquals(tr("不限水平"), makeRoom(GameMode.Doubles, 1).levelRangeText)
    }

    @Test
    fun privateRoomExpiresAfterThirtyMinutes() {
        val fresh = makeRoom(GameMode.Singles, 1, lastActivity = now - 29 * 60_000L)
        val stale = makeRoom(GameMode.Singles, 1, lastActivity = now - 31 * 60_000L)
        assertFalse(fresh.isExpired(now))
        assertTrue(stale.isExpired(now))
    }

    // MARK: Cost

    @Test
    fun costSplitRoundsUpPerPerson() {
        val cost = CostSplit(CostSplit.Basis.CourtHour, rate = 80, hours = 2.0, shuttleFee = 15, players = 4, currencyCode = "CNY")
        assertEquals(175, cost.total)
        assertEquals(44, cost.perPerson)
        assertEquals("¥44/人", cost.perPersonText)
        assertEquals("场地 ¥80/时 × 2 小时 + 用球 ¥15 = ¥175，4 人 AA", cost.breakdownText)
        assertEquals(50, CostSplit(CostSplit.Basis.CourtHour, 60, 1.5, 10, 2, "CNY").perPerson)
    }

    @Test
    fun dropInAndUnknownPricing() {
        val dropIn = CostSplit(CostSplit.Basis.DropIn, rate = 15, hours = 2.0, shuttleFee = 8, players = 4, currencyCode = "USD")
        assertEquals(68, dropIn.total)
        assertEquals(17, dropIn.perPerson)
        assertEquals("$17/人", dropIn.perPersonText)
        val unknown = CostSplit(CostSplit.Basis.Unknown, rate = 0, hours = 2.0, shuttleFee = 8, players = 4, currencyCode = "USD")
        assertNull(unknown.perPerson)
        assertEquals("费用待定", unknown.perPersonText)
    }

    @Test
    fun scoreCountsGames() {
        assertEquals(GameCount(2, 1), GameResult.games("21:18 19:21 21-15"))
        assertNull("2:1 是局数，不是比分", GameResult.games("2:1"))
        assertTrue(GameResult.isValidScore(" 21:18, 19/21 "))
        assertTrue(GameResult.isValidScore(""))
        assertFalse(GameResult.isValidScore("21:18 我赢了"))
    }

    // MARK: User level & reputation

    private fun reputation(count: Int, peer: Double, deviation: Double) = ReputationScore(count, peer, deviation, 100.0, 5.0)

    @Test
    fun newPlayerShowsSelfReportedLevel() {
        val user = User.create("a", "测试", selfReportedLevel = 5).copy(reputation = ReputationScore(4, 2.0, 3.0, 100.0, 5.0))
        assertTrue(user.isNewPlayer)
        assertEquals(5, user.displayLevel)
    }

    @Test
    fun weightedLevelAfterFiveEvaluations() {
        val user = User.create("a", "测试", selfReportedLevel = 6).copy(reputation = reputation(5, 4.0, 2.0))
        // 0.3 × 6 + 0.7 × 4 = 4.6 → 最近的一档是 5−（4.67）
        assertEquals(4.6, user.calculatedLevel, 0.0001)
        assertEquals(SkillTier(5, SkillTier.Modifier.Minus), user.displayTier)
        assertEquals(5, user.displayLevel)
        assertEquals("Lv.5− 中高级", user.displayLevelText)
        assertFalse(user.isNewPlayer)
    }

    @Test
    fun unverifiedUserCannotDisplayChampionLevels() {
        var user = User.create("a", "测试", selfReportedLevel = 7).copy(reputation = reputation(10, 9.0, 2.0))
        assertEquals("没认证最高 7−", SkillTier(7, SkillTier.Modifier.Minus), user.displayTier)
        assertEquals("Lv.7− 准州级", user.displayLevelText)
        // 认证 8 级：0.3 × 8 + 0.7 × 9 = 8.7，但不超过认证的那一档
        user = user.applyingVerification(VerificationStatus.National, SkillTier(8))
        assertEquals(SkillTier(8), user.displayTier)
        assertEquals("Lv.8 国家级", user.displayLevelText)
        // 认证档位超出这类证据的范围时，按上限算：赛果最多到 8
        user = user.applyingVerification(VerificationStatus.Tournament, SkillTier(9, SkillTier.Modifier.Plus))
        assertEquals(SkillTier(8).rating, user.verifiedRating ?: 0.0, 0.001)
    }

    @Test
    fun verifiedPlayerCanBeCalibratedDownByPeers() {
        var user = User.create("a", "测试", selfReportedLevel = 6).applyingVerification(VerificationStatus.Bwf, SkillTier(9))
        assertEquals("新球友：直接显示认证档位", SkillTier(9), user.displayTier)
        user = user.copy(reputation = reputation(8, 8.0, 1.0))
        // 0.3 × 9 + 0.7 × 8 = 8.3 → 8+，但认证过的人最多往下调 1 档 → 9−
        assertEquals(SkillTier(9, SkillTier.Modifier.Minus), user.displayTier)
        assertEquals("Lv.9− 国际选手", user.displayLevelText)
    }

    @Test
    fun reputationIncrementalAverage() {
        val surveys = listOf(
            MatchSurvey("1", "m", "x", "a", 5, true, AttendanceAnswer.OnTime, 5, emptyList(), now),
            MatchSurvey("2", "m", "y", "a", 3, false, AttendanceAnswer.Late, 3, emptyList(), now),
        )
        val score = ReputationScore.aggregate(surveys, selfRating = 4.0)
        assertEquals(2, score.evaluationCount)
        assertEquals(4.0, score.peerLevelAverage, 0.0001)
        assertEquals(1.0, score.averageSkillDeviation, 0.0001)
        assertEquals(50.0, score.punctualityPercentage, 0.0001)
        assertEquals(4.0, score.averageCharacterRating, 0.0001)
        assertTrue(score.isNewPlayer)
        assertTrue(score.compositeScore > 0)
    }

    @Test
    fun attendanceStanding() {
        assertEquals(AttendanceRecord.Standing.Good, AttendanceRecord(10, 0, 1).standing)
        assertEquals(AttendanceRecord.Standing.Warned, AttendanceRecord(10, 1, 0).standing)
        assertEquals(AttendanceRecord.Standing.PrepayRequired, AttendanceRecord(10, 2, 0).standing)
        assertEquals(AttendanceRecord.Standing.Suspended, AttendanceRecord(10, 3, 0).standing)
        assertEquals(75, AttendanceRecord(3, 1, 0).reliabilityPercentage)
    }

    @Test
    fun levelCalibrationMovesOneTier() {
        val five = SkillTier(5)
        assertEquals(SkillTier(5, SkillTier.Modifier.Minus), LevelCalibration.Lower.rating(five))
        assertEquals(five, LevelCalibration.Accurate.rating(five))
        assertEquals(SkillTier(5, SkillTier.Modifier.Plus), LevelCalibration.Higher.rating(five))
        assertEquals(SkillTier(9, SkillTier.Modifier.Plus), LevelCalibration.Higher.rating(SkillTier(9, SkillTier.Modifier.Plus)))
        assertEquals(SkillTier(1, SkillTier.Modifier.Minus), LevelCalibration.Lower.rating(SkillTier(1, SkillTier.Modifier.Minus)))
    }

    // MARK: Messages

    @Test
    fun messageValidation() {
        assertEquals(MessageValidation.Empty, Message.validate(""))
        assertEquals(MessageValidation.Empty, Message.validate("   \n"))
        assertEquals(MessageValidation.Valid, Message.validate("你好"))
        assertEquals(MessageValidation.Valid, Message.validate("羽".repeat(1000)))
        assertEquals(MessageValidation.TooLong, Message.validate("羽".repeat(1001)))
        assertEquals("表情按一个字算", MessageValidation.Valid, Message.validate("🏸".repeat(1000)))
    }

    @Test
    fun threadIdIsOrderIndependent() {
        assertEquals(MessageThread.id("a", "b"), MessageThread.id("b", "a"))
    }

    // MARK: 存盘

    @Test
    fun codableRoundTrip() {
        val json = Json { ignoreUnknownKeys = true }
        val user = User(id = "a", nickname = "测试", phone = "+16265550123", selfReportedLevel = 4, joinDate = 1_700_000_000_000, lastActiveAt = 1_700_000_000_000)
        assertEquals(user, json.decodeFromString(User.serializer(), json.encodeToString(User.serializer(), user)))

        val room = makeRoom(GameMode.Doubles, 2).copy(
            status = RoomStatus.Closed(RoomCloseReason.Expired), tags = listOf(RoomTag.Casual),
            court = Venue("v", "LABC", lat = 34.0, lon = -118.0, countryCode = "US", pricing = VenuePricing.DropIn(15)),
        )
        val text = json.encodeToString(Room.serializer(), room)
        val decodedRoom = json.decodeFromString(Room.serializer(), text)
        assertEquals(room, decodedRoom)
        assertEquals(1..9, decodedRoom.levelRange)
        assertTrue("标签按原文存", "欢乐局" in text)

        val message = Message(threadId = "a|b", senderId = "a", content = "房间码", sentAt = 1_700_000_000_000, kind = MessageKind.RoomInvite("ABCDEF"))
        assertEquals(message, json.decodeFromString(Message.serializer(), json.encodeToString(Message.serializer(), message)))

        val item = json.decodeFromString(InboxItem.serializer(), """{"id":"i","kind":"somethingNew","title":"t","body":"b","createdAt":1}""")
        assertEquals("不认识的种类读成系统通知", InboxItem.Kind.System, item.kind)
        assertNotEquals(message.id, Message(threadId = "a|b", senderId = "a", content = "x").id)
    }
}
