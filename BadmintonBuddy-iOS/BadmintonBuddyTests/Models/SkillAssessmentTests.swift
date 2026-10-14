import XCTest
@testable import BadmintonBuddy

/// 定级问卷：中位数、门槛封顶、经历保底、回归球友、上限 7 级
final class SkillAssessmentTests: XCTestCase {

    /// 选项按题目顺序：clear, backhand, smash, defense, footwork, doubles, experience, recency
    private func answers(_ clear: Int, _ backhand: Int, _ smash: Int, _ defense: Int, _ footwork: Int, _ doubles: Int,
                         experience: Int = 0, returning: Bool = false) -> [String: Int] {
        ["clear": clear, "backhand": backhand, "smash": smash, "defense": defense, "footwork": footwork,
         "doubles": doubles, "experience": experience, "recency": returning ? 1 : 0]
    }

    func testIncompleteAnswersHaveNoResult() {
        var partial = answers(2, 2, 2, 2, 2, 2)
        partial["recency"] = nil
        XCTAssertNil(SkillAssessment.evaluate(partial))
    }

    func testBrandNewPlayerIsLevelOne() {
        XCTAssertEqual(SkillAssessment.evaluate(answers(0, 0, 0, 0, 0, 0))?.level, 1)
    }

    func testTypicalIntermediateIsLevelFour() {
        let result = SkillAssessment.evaluate(SkillAssessment.demoAnswers)
        XCTAssertEqual(result?.level, 4)
        XCTAssertEqual(result?.limitingGate, "反手能回到中后场，双打会轮转", "告诉用户升到 5 级还差什么")
        XCTAssertEqual(result?.needsCalibration, false)
    }

    func testGateCapsInflatedAnswers() {
        // 其他题都选很高，但正手高远只有 3–6 个到后场 → 最多 3 级
        let result = SkillAssessment.evaluate(answers(2, 4, 4, 4, 4, 4))
        XCTAssertEqual(result?.level, 3)
        XCTAssertEqual(result?.limitingGate, "正手高远 10 个里至少 7 个到后场")
    }

    func testTopAnswersReachSevenOnlyWithExperience() {
        XCTAssertEqual(SkillAssessment.evaluate(answers(4, 4, 4, 4, 4, 4, experience: 3))?.level, 7)
        // 没有比赛或青训经历：卡在 6 级
        XCTAssertEqual(SkillAssessment.evaluate(answers(4, 4, 4, 4, 4, 4, experience: 0))?.level, 6)
    }

    func testQuestionnaireNeverGivesEightOrNine() {
        let result = SkillAssessment.evaluate(answers(4, 4, 4, 4, 4, 4, experience: 4))
        XCTAssertEqual(result?.level, 7)
        XCTAssertEqual(result?.suggestsVerification, true, "参加过 A/Open 组：提示申请认证")
    }

    func testExperienceFloorRaisesLevelAndFlagsCalibration() {
        // 技术题像 2 级，但说自己 C/B 组进过前四 → 保底 5 级，标记待校准
        let result = SkillAssessment.evaluate(answers(1, 0, 0, 1, 1, 1, experience: 3))
        XCTAssertEqual(result?.level, 5)
        XCTAssertEqual(result?.needsCalibration, true)
    }

    func testReturningPlayerFloorIsOneLower() {
        let active = SkillAssessment.evaluate(answers(1, 0, 0, 1, 1, 1, experience: 3))
        let returning = SkillAssessment.evaluate(answers(1, 0, 0, 1, 1, 1, experience: 3, returning: true))
        XCTAssertEqual(returning?.level, (active?.level ?? 0) - 1)
        XCTAssertEqual(returning?.isReturning, true)
    }

    func testMedianRoundsDown() {
        // 分值 2,3,3,4,4,4 → 中位数 (3+4)/2 = 3.5 → 3
        XCTAssertEqual(SkillAssessment.evaluate(answers(1, 1, 1, 2, 2, 2))?.level, 3)
    }

    func testModifiersWithinLevel() {
        // 什么都不会：1−
        XCTAssertEqual(SkillAssessment.evaluate(answers(0, 0, 0, 0, 0, 0))?.tier.code, "1−")
        // 典型中级：本级
        XCTAssertEqual(SkillAssessment.evaluate(SkillAssessment.demoAnswers)?.tier.code, "4")
        // 被正手高远卡在 3 级、其他都很高：3+
        XCTAssertEqual(SkillAssessment.evaluate(answers(2, 4, 4, 4, 4, 4))?.tier.code, "3+")
        // 中位数在 3 和 4 之间：3+
        XCTAssertEqual(SkillAssessment.evaluate(answers(1, 1, 1, 2, 2, 2))?.tier.code, "3+")
        // 靠经历保底到 5 级、技术还没跟上：5−
        XCTAssertEqual(SkillAssessment.evaluate(answers(1, 0, 0, 1, 1, 1, experience: 3))?.tier.code, "5−")
    }

    func testQuestionnaireTopsOutAtSevenMinus() {
        let result = SkillAssessment.evaluate(answers(4, 4, 4, 4, 4, 4, experience: 4))
        XCTAssertEqual(result?.tier, SkillAssessment.maxTier)
        XCTAssertEqual(result?.tier.code, "7−")
    }

    func testEveryLevelHasAnchorsAndNames() {
        for level in SkillLevel.range {
            XCTAssertFalse(SkillLevel.name(for: level).isEmpty)
            XCTAssertGreaterThanOrEqual(SkillLevel.anchors(for: level).count, 2, "Lv.\(level) 至少 2 条可观察的动作")
        }
        XCTAssertEqual(SkillLevel.usFlight(for: 4), "D 组")
    }

    func testCalibratingPlayersWeighPeersMore() {
        var user = User(id: "u", nickname: "测试", phone: "", selfReportedLevel: 6)
        user.reputation = ReputationScore(evaluationCount: 6, peerLevelAverage: 4, averageSkillDeviation: 2,
                                          punctualityPercentage: 100, averageCharacterRating: 5)
        XCTAssertEqual(user.calculatedLevel, 0.3 * 6 + 0.7 * 4, accuracy: 0.001)
        user.assessment = SkillAssessmentSummary(level: 6, needsCalibration: true, isReturning: false, assessedAt: Date())
        XCTAssertEqual(user.calculatedLevel, 0.15 * 6 + 0.85 * 4, accuracy: 0.001)
    }

    @MainActor
    func testRetakeIsLimitedToEvery90Days() throws {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        let now = Date()
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4, seedsDemoContent: false,
                              assessment: SkillAssessmentSummary(level: 4, needsCalibration: false, isReturning: false,
                                                                 assessedAt: now))
        let higher = try XCTUnwrap(SkillAssessment.evaluate(answers(3, 2, 2, 2, 3, 3)))
        XCTAssertThrowsError(try backend.updateAssessment(higher, now: now.addingTimeInterval(30 * 86400)))
        let updated = try backend.updateAssessment(higher, now: now.addingTimeInterval(91 * 86400))
        XCTAssertEqual(updated.selfReportedLevel, higher.level)
        XCTAssertEqual(updated.selfReportedRating ?? 0, higher.tier.rating, accuracy: 0.001)
        XCTAssertEqual(updated.displayTier, higher.tier)
    }
}
