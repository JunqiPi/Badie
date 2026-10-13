import XCTest
@testable import BadmintonBuddy

/// 口碑展示：分数不公开，正面标签有门槛，问题只私下提醒
@MainActor
final class ReputationTests: XCTestCase {

    private func survey(_ rater: String, _ match: String, tags: [SurveyTag] = [], issues: [SurveyIssue] = [],
                        daysAgo: Double = 1, target: String = "me") -> MatchSurvey {
        MatchSurvey(id: UUID().uuidString, matchId: match, evaluatorId: rater, evaluatedUserId: target, skillRating: 4,
                    wasPunctual: true, attendance: .onTime, characterRating: 5, tags: tags,
                    submittedAt: Date().addingTimeInterval(-daysAgo * 86400), issues: issues)
    }

    func testPublicTagsNeedFiveRatersAndThreeSessions() {
        let four = (0..<4).map { survey("r\($0)", "m\($0 % 3)", tags: [.friendly]) }
        XCTAssertTrue(ReputationScore.publicTags(from: four).isEmpty, "不到 5 位球友不展示")

        let five = four + [survey("r4", "m0", tags: [.friendly, .skilled])]
        XCTAssertEqual(ReputationScore.publicTags(from: five), [.friendly], "只有 1 位球友给的标签不展示")

        let twoSessions = (0..<6).map { survey("r\($0)", "m\($0 % 2)", tags: [.friendly]) }
        XCTAssertTrue(ReputationScore.publicTags(from: twoSessions).isEmpty, "不到 3 场不展示")

        let sameRaterTwice = (0..<5).map { survey("r\($0)", "m\($0 % 3)") } + [survey("r0", "m1", tags: [.patient]),
                                                                              survey("r0", "m2", tags: [.patient])]
        XCTAssertTrue(ReputationScore.publicTags(from: sameRaterTwice).isEmpty, "同一个人给两次只算一人")
    }

    func testRecurringIssuesNeedThreeDistinctRatersWithinSixtyDays() {
        var surveys = [
            survey("a", "m1", issues: [.rude]),
            survey("b", "m2", issues: [.rude]),
            survey("b", "m3", issues: [.rude])
        ]
        XCTAssertTrue(ReputationScore.recurringIssues(in: surveys).isEmpty)
        surveys.append(survey("c", "m4", issues: [.rude], daysAgo: 61))
        XCTAssertTrue(ReputationScore.recurringIssues(in: surveys).isEmpty, "60 天前的不算")
        surveys.append(survey("d", "m5", issues: [.rude, .hogging]))
        XCTAssertEqual(ReputationScore.recurringIssues(in: surveys), [.rude])
    }

    func testReliableBadgeUsesAttendanceOnly() {
        var user = User(id: "u", nickname: "测试", phone: "", selfReportedLevel: 4)
        user.attendance = AttendanceRecord(gamesPlayed: 2, noShows: 0, lateCancellations: 0)
        XCTAssertFalse(user.isReliable, "至少打满 3 场")
        user.attendance.gamesPlayed = 3
        XCTAssertTrue(user.isReliable)
        user.attendance.lateCancellations = 2
        XCTAssertFalse(user.isReliable)
        user.attendance.lateCancellations = 0
        user.attendance.noShows = 1
        XCTAssertFalse(user.isReliable)
        XCTAssertFalse(user.publicSummary.contains("★"), "对外摘要不含任何评分")
    }

    func testOtherPlayersSeeApproximateDistanceAndBandedGames() {
        XCTAssertEqual(DistanceFormatter.approximate(km: 2.1, unit: .miles), "3 英里内")
        XCTAssertEqual(DistanceFormatter.approximate(km: 12, unit: .miles), "10 英里内")
        XCTAssertEqual(DistanceFormatter.approximate(km: 80, unit: .miles), "25 英里外")
        XCTAssertEqual(DistanceFormatter.approximate(km: 7, unit: .kilometers), "10 公里内")
        var user = User(id: "u", nickname: "测试", phone: "", selfReportedLevel: 4)
        user.totalGames = 23
        XCTAssertEqual(user.gamesBand, "20+ 场")
    }

    func testPrivateNudgeIsSentOnceAndPublishedTagsRefreshMonthly() {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        let me = backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4,
                                       location: .fallbackCenter, seedsDemoContent: false)
        backend.db.surveys = ["a", "b", "c"].enumerated().map { index, rater in
            survey(rater, "m\(index)", tags: [.friendly], issues: [.hogging], target: me.id)
        }
        backend.sendPrivateNudges(to: me.id)
        backend.sendPrivateNudges(to: me.id)
        let nudges = backend.inbox().filter { $0.kind == .system && $0.body.contains(SurveyIssue.hogging.rawValue) }
        XCTAssertEqual(nudges.count, 1, "60 天内同一问题只提醒一次")

        // 月度刷新：达到门槛后才出现标签；同一个月内不再变化
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        backend.db.surveys += ["d", "e"].enumerated().map { index, rater in
            survey(rater, "m\(index)", tags: [.friendly], target: me.id)
        }
        backend.publishReputationIfNeeded(now: nextMonth)
        XCTAssertEqual(backend.user(id: me.id)?.reputation.publicTags, [.friendly])
        backend.db.surveys += ["f", "g"].map { survey($0, "m9", tags: [.skilled], target: me.id) }
        backend.publishReputationIfNeeded(now: nextMonth.addingTimeInterval(3600))
        XCTAssertEqual(backend.user(id: me.id)?.reputation.publicTags, [.friendly], "同一个月内不刷新")
    }
}
