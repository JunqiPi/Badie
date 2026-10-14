import XCTest
@testable import BadmintonBuddy

/// 定级问卷：按“会不会 → 好不好 → 稳不稳 → 战术 → 俱乐部里的位置”的台阶计分，动作题封顶，经历保底，最高 6+
final class SkillAssessmentTests: XCTestCase {

    /// 选项序号对应 SkillAssessment.questions 里的顺序
    private func answers(breadth: Int, clear: Int, backhand: Int, smash: Int, defense: Int, doubles: Int,
                         stability: Int, tactics: Int = 0, standing: Int = 0,
                         experience: Int = 0, returning: Bool = false) -> [String: Int] {
        ["breadth": breadth, "clear": clear, "backhand": backhand, "smash": smash, "defense": defense,
         "doubles": doubles, "stability": stability, "tactics": tactics, "standing": standing,
         "experience": experience, "recency": returning ? 1 : 0]
    }

    func testIncompleteAnswersHaveNoResult() {
        var partial = SkillAssessment.demoAnswers
        partial["standing"] = nil
        XCTAssertNil(SkillAssessment.evaluate(partial))
    }

    func testBrandNewPlayerIsOneMinus() {
        let result = SkillAssessment.evaluate(answers(breadth: 0, clear: 0, backhand: 0, smash: 0, defense: 0, doubles: 0, stability: 0))
        XCTAssertEqual(result?.tier.code, "1−")
    }

    func testTypicalIntermediateIsLevelFour() {
        let result = SkillAssessment.evaluate(SkillAssessment.demoAnswers)
        XCTAssertEqual(result?.tier.code, "4")
        XCTAssertNil(result?.limitingGate, "没有被动作题卡住，结果页提示下一档的标准")
        XCTAssertEqual(result?.needsCalibration, false)
    }

    func testThreePlusKnowsEverythingButIsUnstable() {
        // 全部会、一两项不错、不稳定 → 3+
        let result = SkillAssessment.evaluate(answers(breadth: 3, clear: 2, backhand: 1, smash: 1, defense: 2, doubles: 1, stability: 2))
        XCTAssertEqual(result?.tier.code, "3+")
    }

    func testFourPlusNeedsMasteryAndBetterStability() {
        let mastered = answers(breadth: 5, clear: 3, backhand: 2, smash: 2, defense: 2, doubles: 2, stability: 3)
        XCTAssertEqual(SkillAssessment.evaluate(mastered)?.tier.code, "4+")
        // 有精通的技术，但实战一快就失误多：只算 4
        var unstable = mastered
        unstable["stability"] = 2
        XCTAssertEqual(SkillAssessment.evaluate(unstable)?.tier.code, "4")
    }

    func testFiveIsStableAndFivePlusAddsTactics() {
        let stable = answers(breadth: 5, clear: 4, backhand: 2, smash: 2, defense: 3, doubles: 3, stability: 4, tactics: 2)
        XCTAssertEqual(SkillAssessment.evaluate(stable)?.tier.code, "5")
        var tactical = stable
        tactical["tactics"] = 3
        XCTAssertEqual(SkillAssessment.evaluate(tactical)?.tier.code, "5+")
    }

    func testSixIsDecidedByStandingInTheClub() {
        let standout = answers(breadth: 5, clear: 4, backhand: 3, smash: 3, defense: 3, doubles: 4,
                               stability: 4, tactics: 3, standing: 4)
        XCTAssertEqual(SkillAssessment.evaluate(standout)?.tier.code, "6")
        var rising = standout
        rising["standing"] = 3
        XCTAssertEqual(SkillAssessment.evaluate(rising)?.tier.code, "6−")
    }

    func testClubTopWithoutTheSkillsIsNotSix() {
        // 在自己的局里很少输，但技术只到 4 级：俱乐部位置不算数
        let result = SkillAssessment.evaluate(answers(breadth: 4, clear: 3, backhand: 2, smash: 2, defense: 2, doubles: 2,
                                                      stability: 2, tactics: 1, standing: 5))
        XCTAssertEqual(result?.tier.code, "4")
    }

    func testLevelFourNeedsEveryTechniqueIncludingBackhand() {
        // 自称全部技术都不错，但反手只能挡过网：到不了 4
        let result = SkillAssessment.evaluate(answers(breadth: 4, clear: 3, backhand: 1, smash: 2, defense: 2, doubles: 2,
                                                      stability: 2))
        XCTAssertEqual(result?.tier.code, "4−")
        XCTAssertEqual(result?.limitingGate?.contains("反手"), true)
    }

    func testTechniquesAreNotRequirementsAboveLevelFour() {
        // 技术在 4 级就全部熟练；5 级以上只看稳定、战术、俱乐部位置
        for tier in SkillTier.all where (5...6).contains(tier.level) {
            XCTAssertFalse(SkillLevel.tierCriteria(for: tier).joined().contains("反手"), tier.code)
        }
        for level in 5...6 {
            XCTAssertFalse(SkillLevel.anchors(for: level).joined().contains("反手"), "Lv.\(level)")
        }
        XCTAssertTrue(SkillLevel.tierCriteria(for: SkillTier(level: 4)).joined().contains("反手"))
    }

    func testInflatedClaimsAreCappedByActions() {
        // 自称样样精通、很稳、俱乐部顶尖，但具体动作做不到
        let result = SkillAssessment.evaluate(answers(breadth: 5, clear: 1, backhand: 1, smash: 1, defense: 1, doubles: 1,
                                                      stability: 5, tactics: 4, standing: 5))
        XCTAssertEqual(result?.tier.code, "4−")
        XCTAssertNotNil(result?.limitingGate, "告诉用户卡在哪里")
    }

    func testQuestionnaireTopsOutAtSixPlus() {
        let top = answers(breadth: 5, clear: 4, backhand: 4, smash: 4, defense: 4, doubles: 4,
                          stability: 5, tactics: 4, standing: 5, experience: 4)
        let result = SkillAssessment.evaluate(top)
        XCTAssertEqual(result?.tier, SkillAssessment.maxTier)
        XCTAssertEqual(result?.tier.code, "6+")
        XCTAssertEqual(result?.suggestsVerification, true, "参加过 A/Open 组：提示申请认证")
        // 6+ 要有比赛或青训经历
        var noExperience = top
        noExperience["experience"] = 0
        let capped = SkillAssessment.evaluate(noExperience)
        XCTAssertEqual(capped?.tier.code, "6")
        XCTAssertEqual(capped?.limitingGate, "有比赛或青训经历")
    }

    func testExperienceFloorRaisesLevelAndFlagsCalibration() {
        // 技术题像 3−，但说自己 C/B 组进过前四 → 保底 5−，标记待校准
        let result = SkillAssessment.evaluate(answers(breadth: 1, clear: 1, backhand: 0, smash: 0, defense: 1, doubles: 1,
                                                      stability: 1, experience: 3))
        XCTAssertEqual(result?.tier.code, "5−")
        XCTAssertEqual(result?.needsCalibration, true)
    }

    func testReturningPlayerFloorIsOneLower() {
        let active = SkillAssessment.evaluate(answers(breadth: 1, clear: 1, backhand: 0, smash: 0, defense: 1, doubles: 1,
                                                      stability: 1, experience: 3))
        let returning = SkillAssessment.evaluate(answers(breadth: 1, clear: 1, backhand: 0, smash: 0, defense: 1, doubles: 1,
                                                         stability: 1, experience: 3, returning: true))
        XCTAssertEqual(returning?.level, (active?.level ?? 0) - 1)
        XCTAssertEqual(returning?.isReturning, true)
    }

    func testEveryLevelHasAnchorsAndNames() {
        for level in SkillLevel.range {
            XCTAssertFalse(SkillLevel.name(for: level).isEmpty)
            XCTAssertGreaterThanOrEqual(SkillLevel.anchors(for: level).count, 2, "Lv.\(level) 至少 2 条描述")
        }
        XCTAssertEqual(SkillLevel.usFlight(for: 4), "D 组")
        XCTAssertEqual(SkillTier(level: 3, modifier: .plus).displayText, "Lv.3+ 初级")
        XCTAssertEqual(SkillTier(level: 6).displayText, "Lv.6 俱乐部高手")
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
        let higher = try XCTUnwrap(SkillAssessment.evaluate(
            answers(breadth: 5, clear: 3, backhand: 2, smash: 2, defense: 2, doubles: 2, stability: 3)))
        XCTAssertThrowsError(try backend.updateAssessment(higher, now: now.addingTimeInterval(30 * 86400)))
        let updated = try backend.updateAssessment(higher, now: now.addingTimeInterval(91 * 86400))
        XCTAssertEqual(updated.selfReportedLevel, higher.level)
        XCTAssertEqual(updated.selfReportedRating ?? 0, higher.tier.rating, accuracy: 0.001)
        XCTAssertEqual(updated.displayTier, higher.tier)
    }
}
