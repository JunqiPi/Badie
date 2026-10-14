import XCTest
@testable import BadmintonBuddy

final class ModelTests: XCTestCase {

    // MARK: Coordinate

    func testHaversineDistanceBeijingToShanghai() {
        let beijing = Coordinate(latitude: 39.9042, longitude: 116.4074)
        let shanghai = Coordinate(latitude: 31.2304, longitude: 121.4737)
        // 实际大圆距离约 1067 公里
        XCTAssertEqual(beijing.distanceKm(to: shanghai), 1067, accuracy: 10)
        XCTAssertEqual(beijing.distance(to: shanghai), 663, accuracy: 7)
        XCTAssertEqual(beijing.distanceKm(to: beijing), 0, accuracy: 0.0001)
    }

    func testOffsetByKilometersRoundTrips() {
        let origin = Coordinate.fallbackCenter
        let moved = origin.offsetBy(eastKm: 3, northKm: 4)
        XCTAssertEqual(origin.distanceKm(to: moved), 5, accuracy: 0.05)
    }

    func testDistanceFormatter() {
        XCTAssertEqual(DistanceFormatter.string(km: 0.456, unit: .kilometers), "460 米")
        XCTAssertEqual(DistanceFormatter.string(km: 2.34, unit: .kilometers), "2.3 公里")
        XCTAssertEqual(DistanceFormatter.string(km: 3.2187, unit: .miles), "2.0 英里")
        XCTAssertEqual(DistanceFormatter.string(km: 0.05, unit: .miles), "150 英尺")
        XCTAssertEqual(DistanceFormatter.radius(km: 16.09344, unit: .miles), "10 英里")
        XCTAssertEqual(DistanceFormatter.radius(km: 10, unit: .kilometers), "10 公里")
    }

    // MARK: TimeSlot

    private func slot(day: Int = 1, _ start: Int, _ end: Int) -> TimeSlot {
        let date = Calendar.current.date(byAdding: .day, value: day, to: Date())!
        return TimeSlot.on(date, startHour: start, endHour: end)!
    }

    func testOverlapRequiresThirtyMinutes() {
        let a = slot(18, 20)
        let b = slot(19, 22)
        let overlap = a.overlaps(with: b)
        XCTAssertNotNil(overlap)
        XCTAssertEqual(overlap?.duration, 3600)

        let date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let short = TimeSlot.on(date, startHour: 19, startMinute: 40, endHour: 21)!
        let shortOverlap = TimeSlot.on(date, startHour: 18, endHour: 20)!
        // 只重叠 20 分钟，不算匹配
        XCTAssertNil(short.overlaps(with: shortOverlap))
        XCTAssertNil(slot(8, 10).overlaps(with: slot(10, 12)))
    }

    func testOverlapAcrossDifferentDaysIsNil() {
        XCTAssertNil(slot(day: 1, 19, 21).overlaps(with: slot(day: 2, 19, 21)))
    }

    func testDurationValidation() {
        XCTAssertTrue(slot(19, 20).validate().isValid)
        XCTAssertEqual(slot(19, 19).validate(), .invalid(reason: "结束时间需要晚于开始时间"))
        let date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertFalse(TimeSlot.on(date, startHour: 19, endHour: 19, endMinute: 30)!.validate().isValid)
        XCTAssertFalse(slot(8, 17).validate().isValid, "超过 8 小时应无效")
        XCTAssertTrue(slot(8, 16).validate().isValid)
    }

    func testDateRangeValidation() {
        XCTAssertFalse(slot(day: -1, 19, 21).validate().isValid, "过去的日期无效")
        XCTAssertTrue(slot(day: 14, 19, 21).validate().isValid)
        XCTAssertFalse(slot(day: 15, 19, 21).validate().isValid, "超过 14 天无效")
    }

    func testTrimmedForGameCapsAtTwoHours() {
        let trimmed = slot(18, 22).trimmedForGame()
        XCTAssertEqual(trimmed.duration, 2 * 3600)
        XCTAssertEqual(trimmed.startTime, slot(18, 22).startTime)
        XCTAssertEqual(slot(19, 20).trimmedForGame().duration, 3600)
    }

    func testRecurringSlotNextOccurrenceAndLimit() {
        let today = Calendar.current.component(.weekday, from: Date())
        let tomorrowWeekday = today % 7 + 1
        let recurring = RecurringTimeSlot(dayOfWeek: tomorrowWeekday, startHour: 19, endHour: 21)
        let next = recurring.nextOccurrence()
        XCTAssertNotNil(next)
        XCTAssertTrue(Calendar.current.isDateInTomorrow(next!.date))
        XCTAssertTrue(recurring.isValidDuration)
        XCTAssertFalse(RecurringTimeSlot(dayOfWeek: 2, startHour: 19, endHour: 19, endMinute: 30).isValidDuration)

        let five = (1...5).map { RecurringTimeSlot(dayOfWeek: $0, startHour: 19, endHour: 21) }
        XCTAssertFalse(five.canAddMore)
        XCTAssertEqual(Array(five.prefix(3)).remainingSlots, 2)
    }

    // MARK: Room

    func testRoomCodeFormatAndUniqueness() {
        var codes = Set<String>()
        for _ in 0..<500 {
            let code = Room.generateCode(excluding: codes)
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(Room.isValidCode(code))
            XCTAssertFalse(code.contains { "0O1IL".contains($0) })
            XCTAssertFalse(codes.contains(code))
            codes.insert(code)
        }
    }

    func testRoomCodeNormalization() {
        XCTAssertEqual(Room.normalize("bx7 k2-m"), "BX7K2M")
        XCTAssertEqual(Room.normalize("abcdefgh"), "ABCDEF")
        XCTAssertFalse(Room.isValidCode("ABC10O"))
        XCTAssertFalse(Room.isValidCode("ABC"))
    }

    private func makeRoom(mode: GameMode, participants: Int, visibility: RoomVisibility = .privateRoom, lastActivity: Date = Date()) -> Room {
        let users = (0..<participants).map { User(id: "u\($0)", nickname: "球友\($0)", phone: "", selfReportedLevel: 4) }
        return Room(
            id: "r", code: "ABCDEF", ownerId: "u0", mode: mode, visibility: visibility,
            participants: users.map { RoomParticipant(user: $0) }, invitedUserIds: [], waitlist: [],
            court: nil, slot: nil, levelRange: 1...9, tags: [], note: "",
            createdAt: Date(), lastActivityAt: lastActivity, status: .open
        )
    }

    func testRoomReadyState() {
        XCTAssertFalse(makeRoom(mode: .singles, participants: 1).isReady)
        XCTAssertTrue(makeRoom(mode: .singles, participants: 2).isReady)
        XCTAssertFalse(makeRoom(mode: .doubles, participants: 3).isReady)
        XCTAssertTrue(makeRoom(mode: .doubles, participants: 4).isReady)
        XCTAssertEqual(makeRoom(mode: .doubles, participants: 1).openSeats, 3)
    }

    func testPrivateRoomExpiresAfterThirtyMinutes() {
        let fresh = makeRoom(mode: .singles, participants: 1, lastActivity: Date().addingTimeInterval(-29 * 60))
        let stale = makeRoom(mode: .singles, participants: 1, lastActivity: Date().addingTimeInterval(-31 * 60))
        XCTAssertFalse(fresh.isExpired())
        XCTAssertTrue(stale.isExpired())
    }

    // MARK: Cost

    func testCostSplitRoundsUpPerPerson() {
        let cost = CostSplit(basis: .courtHour, rate: 80, hours: 2, shuttleFee: 15, players: 4, currencyCode: "CNY")
        XCTAssertEqual(cost.total, 175)
        XCTAssertEqual(cost.perPerson, 44)
        XCTAssertEqual(cost.perPersonText, "¥44/人")
        XCTAssertEqual(CostSplit(basis: .courtHour, rate: 60, hours: 1.5, shuttleFee: 10, players: 2, currencyCode: "CNY").perPerson, 50)
    }

    func testDropInAndUnknownPricing() {
        let dropIn = CostSplit(basis: .dropIn, rate: 15, hours: 2, shuttleFee: 8, players: 4, currencyCode: "USD")
        XCTAssertEqual(dropIn.total, 68)
        XCTAssertEqual(dropIn.perPerson, 17)
        XCTAssertEqual(dropIn.perPersonText, "$17/人")
        let unknown = CostSplit(basis: .unknown, rate: 0, hours: 2, shuttleFee: 8, players: 4, currencyCode: "USD")
        XCTAssertNil(unknown.perPerson)
        XCTAssertEqual(unknown.perPersonText, "费用待定")
    }

    // MARK: User level & reputation

    func testNewPlayerShowsSelfReportedLevel() {
        var user = User(id: "a", nickname: "测试", phone: "", selfReportedLevel: 5)
        user.reputation = ReputationScore(evaluationCount: 4, peerLevelAverage: 2, averageSkillDeviation: 3,
                                          punctualityPercentage: 100, averageCharacterRating: 5)
        XCTAssertTrue(user.isNewPlayer)
        XCTAssertEqual(user.displayLevel, 5)
    }

    func testWeightedLevelAfterFiveEvaluations() {
        var user = User(id: "a", nickname: "测试", phone: "", selfReportedLevel: 6)
        user.reputation = ReputationScore(evaluationCount: 5, peerLevelAverage: 4, averageSkillDeviation: 2,
                                          punctualityPercentage: 100, averageCharacterRating: 5)
        // 0.3 × 6 + 0.7 × 4 = 4.6 → 最近的一档是 5−（4.67）
        XCTAssertEqual(user.calculatedLevel, 4.6, accuracy: 0.0001)
        XCTAssertEqual(user.displayTier, SkillTier(level: 5, modifier: .minus))
        XCTAssertEqual(user.displayLevel, 5)
        XCTAssertEqual(user.displayLevelText, "Lv.5− 中高级")
        XCTAssertFalse(user.isNewPlayer)
    }

    func testUnverifiedUserCannotDisplayChampionLevels() {
        var user = User(id: "a", nickname: "测试", phone: "", selfReportedLevel: 7)
        user.reputation = ReputationScore(evaluationCount: 10, peerLevelAverage: 9, averageSkillDeviation: 2,
                                          punctualityPercentage: 100, averageCharacterRating: 5)
        XCTAssertEqual(user.displayTier, SkillTier(level: 7, modifier: .minus), "没认证最高 7−")
        XCTAssertEqual(user.displayLevelText, "Lv.7− 准州级")
        // 认证 8 级：0.3 × 8 + 0.7 × 9 = 8.7，但不超过认证的那一档
        user.applyVerification(.national, tier: SkillTier(level: 8))
        XCTAssertEqual(user.displayTier, SkillTier(level: 8))
        XCTAssertEqual(user.displayLevelText, "Lv.8 国家级")
        // 认证档位超出这类证据的范围时，按上限算：赛果最多到 8
        user.applyVerification(.tournament, tier: SkillTier(level: 9, modifier: .plus))
        XCTAssertEqual(user.verifiedRating ?? 0, SkillTier(level: 8).rating, accuracy: 0.001)
    }

    func testVerifiedPlayerCanBeCalibratedDownByPeers() {
        var user = User(id: "a", nickname: "测试", phone: "", selfReportedLevel: 6)
        user.applyVerification(.bwf, tier: SkillTier(level: 9))
        XCTAssertEqual(user.displayTier, SkillTier(level: 9), "新球友：直接显示认证档位")
        user.reputation = ReputationScore(evaluationCount: 8, peerLevelAverage: 8, averageSkillDeviation: 1,
                                          punctualityPercentage: 100, averageCharacterRating: 5)
        // 0.3 × 9 + 0.7 × 8 = 8.3 → 8+，但认证过的人最多往下调 1 档 → 9−
        XCTAssertEqual(user.displayTier, SkillTier(level: 9, modifier: .minus))
        XCTAssertEqual(user.displayLevelText, "Lv.9− 国际选手")
    }

    func testReputationIncrementalAverage() {
        let surveys = [
            MatchSurvey(id: "1", matchId: "m", evaluatorId: "x", evaluatedUserId: "a", skillRating: 5, wasPunctual: true,
                        attendance: .onTime, characterRating: 5, tags: [], submittedAt: Date()),
            MatchSurvey(id: "2", matchId: "m", evaluatorId: "y", evaluatedUserId: "a", skillRating: 3, wasPunctual: false,
                        attendance: .late, characterRating: 3, tags: [], submittedAt: Date())
        ]
        let score = ReputationScore.aggregate(surveys, selfRating: 4)
        XCTAssertEqual(score.evaluationCount, 2)
        XCTAssertEqual(score.peerLevelAverage, 4, accuracy: 0.0001)
        XCTAssertEqual(score.averageSkillDeviation, 1, accuracy: 0.0001)
        XCTAssertEqual(score.punctualityPercentage, 50, accuracy: 0.0001)
        XCTAssertEqual(score.averageCharacterRating, 4, accuracy: 0.0001)
        XCTAssertTrue(score.isNewPlayer)
        XCTAssertGreaterThan(score.compositeScore, 0)
    }

    func testAttendanceStanding() {
        XCTAssertEqual(AttendanceRecord(gamesPlayed: 10, noShows: 0, lateCancellations: 1).standing, .good)
        XCTAssertEqual(AttendanceRecord(gamesPlayed: 10, noShows: 1, lateCancellations: 0).standing, .warned)
        XCTAssertEqual(AttendanceRecord(gamesPlayed: 10, noShows: 2, lateCancellations: 0).standing, .prepayRequired)
        XCTAssertEqual(AttendanceRecord(gamesPlayed: 10, noShows: 3, lateCancellations: 0).standing, .suspended)
        XCTAssertEqual(AttendanceRecord(gamesPlayed: 3, noShows: 1, lateCancellations: 0).reliabilityPercentage, 75)
    }

    func testLevelCalibrationMovesOneTier() {
        let five = SkillTier(level: 5)
        XCTAssertEqual(LevelCalibration.lower.rating(from: five), SkillTier(level: 5, modifier: .minus))
        XCTAssertEqual(LevelCalibration.accurate.rating(from: five), five)
        XCTAssertEqual(LevelCalibration.higher.rating(from: five), SkillTier(level: 5, modifier: .plus))
        XCTAssertEqual(LevelCalibration.higher.rating(from: SkillTier(level: 9, modifier: .plus)), SkillTier(level: 9, modifier: .plus))
        XCTAssertEqual(LevelCalibration.lower.rating(from: SkillTier(level: 1, modifier: .minus)), SkillTier(level: 1, modifier: .minus))
    }

    // MARK: Messages

    func testMessageValidation() {
        XCTAssertEqual(Message.validate(""), .empty)
        XCTAssertEqual(Message.validate("   \n"), .empty)
        XCTAssertEqual(Message.validate("你好"), .valid)
        XCTAssertEqual(Message.validate(String(repeating: "羽", count: 1000)), .valid)
        XCTAssertEqual(Message.validate(String(repeating: "羽", count: 1001)), .tooLong)
    }

    func testThreadIdIsOrderIndependent() {
        XCTAssertEqual(MessageThread.id(for: "a", "b"), MessageThread.id(for: "b", "a"))
    }

    // MARK: Codable round trip

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let user = User(id: "a", nickname: "测试", phone: "+16265550123", selfReportedLevel: 4,
                        joinDate: Date(timeIntervalSince1970: 1_700_000_000),
                        lastActiveAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try decoder.decode(User.self, from: encoder.encode(user)), user)

        var room = makeRoom(mode: .doubles, participants: 2)
        room.status = .closed(.expired)
        let decodedRoom = try decoder.decode(Room.self, from: encoder.encode(room))
        XCTAssertEqual(decodedRoom.code, room.code)
        XCTAssertEqual(decodedRoom.status, .closed(.expired))
        XCTAssertEqual(decodedRoom.levelRange, 1...9)

        let message = Message(threadId: "a|b", senderId: "a", content: "房间码", sentAt: Date(timeIntervalSince1970: 1_700_000_000),
                              kind: .roomInvite(code: "ABCDEF"))
        XCTAssertEqual(try decoder.decode(Message.self, from: encoder.encode(message)), message)
    }
}
