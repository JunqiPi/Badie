import XCTest
@testable import Badie

/// 定级问卷：一题一个技术（高远、杀球、吊球、反手后场、网前、平抽挡、步法）+ 台阶
/// （全部会 → 主动球全部不错 → 被动球能摆脱 → 战术 → 俱乐部位置），经历保底，最高 6+
final class SkillAssessmentTests: XCTestCase {

    /// 把“技术等级”换成选项序号：正手高远、步法从 1 级起，其余从 2 级起
    private func optionIndex(_ id: String, level: Int) -> Int {
        ["clear", "footwork"].contains(id) ? max(0, level - 1) : max(0, level - 2)
    }

    /// 所有技术分项都在 `level` 级，`overrides` 可以单独调整某几项（分项 ID → 等级）
    private func profile(_ level: Int, overrides: [String: Int] = [:], passive: Int = 1, doubles: Int = 2,
                         stability: Int = 2, tactics: Int = 0, standing: Int = 0,
                         experience: Int = 0, returning: Bool = false) -> [String: Int] {
        var answers: [String: Int] = [:]
        for id in SkillAssessment.techniqueIds {
            answers[id] = optionIndex(id, level: overrides[id] ?? level)
        }
        answers["passive"] = passive
        answers["doubles"] = doubles
        answers["stability"] = stability
        answers["tactics"] = tactics
        answers["standing"] = standing
        answers["experience"] = experience
        answers["recency"] = returning ? 1 : 0
        return answers
    }

    private func code(_ answers: [String: Int]) -> String? { SkillAssessment.evaluate(answers)?.tier.code }

    @MainActor
    func testSkippingAssessmentUsesProvisionalLevelUntilTaken() throws {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: SkillAssessment.provisionalLevel,
                              seedsDemoContent: false)
        backend.markAssessmentSkipped()
        let skipped = try XCTUnwrap(backend.currentUser)
        XCTAssertTrue(skipped.needsAssessment)
        XCTAssertEqual(skipped.displayTier, SkillTier(level: 3))
        XCTAssertEqual(skipped.peerWeight, User.calibratingPeerWeight, accuracy: 0.001, "没定级：球友评价占比更高")
        // 随时可以补测（不受 90 天限制）
        let result = try XCTUnwrap(SkillAssessment.evaluate(SkillAssessment.demoAnswers))
        let assessed = try backend.updateAssessment(result)
        XCTAssertFalse(assessed.needsAssessment)
        XCTAssertEqual(assessed.displayTier, SkillTier(level: 4))
    }

    func testIncompleteAnswersHaveNoResult() {
        var partial = SkillAssessment.demoAnswers
        partial["standing"] = nil
        XCTAssertNil(SkillAssessment.evaluate(partial))
    }

    func testBrandNewPlayerIsOneMinus() {
        var answers = profile(1, doubles: 0, stability: 0)
        answers["net"] = 0
        XCTAssertEqual(code(answers), "1−")
    }

    func testTypicalIntermediateIsLevelFour() {
        let result = SkillAssessment.evaluate(SkillAssessment.demoAnswers)
        XCTAssertEqual(result?.tier.code, "4")
        XCTAssertNil(result?.limitingGate, "没有卡住，结果页提示下一档的标准")
        XCTAssertEqual(result?.dimensions.count, 7)
        XCTAssertEqual(result?.dimensions.allSatisfy { $0.level == 4 }, true)
    }

    func testLevelThreeTiersFollowTheDimensions() {
        // 全部会（所有分项 3 级）
        XCTAssertEqual(code(profile(3)), "3")
        // 全部会，一两项不错（到 4 级）
        XCTAssertEqual(code(profile(3, overrides: ["clear": 4, "net": 4])), "3+")
        // 多数分项到 4 级，个别还在 3 级
        XCTAssertEqual(code(profile(4, overrides: ["backhand": 3, "drop": 3])), "4−")
        // 还有不会的（2 级）
        XCTAssertEqual(code(profile(3, overrides: ["backhand": 2])), "3−")
    }

    func testWeakestDimensionHoldsTheLevelAndIsNamed() {
        // 其他分项都很好，反手还只回到中场：“全部”看最弱的
        let result = SkillAssessment.evaluate(profile(5, overrides: ["backhand": 3]))
        XCTAssertEqual(result?.tier.code, "4−")
        XCTAssertEqual(result?.limitingGate?.contains("反手后场"), true)
    }

    func testFourPlusNeedsMasteryAndBetterStability() {
        let mastered = profile(4, overrides: ["smash": 5, "net": 5], stability: 3)
        XCTAssertEqual(code(mastered), "4+")
        // 有精通的分项，但实战一快就失误多：只算 4
        XCTAssertEqual(code(profile(4, overrides: ["smash": 5, "net": 5], stability: 2)), "4")
    }

    func testDoublesAwarenessIsPartOfFour() {
        let result = SkillAssessment.evaluate(profile(4, doubles: 1))
        XCTAssertEqual(result?.tier.code, "4−")
        XCTAssertEqual(result?.limitingGate?.contains("双打"), true)
    }

    func testFourCannotHandlePassiveBallsFiveCan() {
        let mastered = ["smash": 5, "net": 5]
        XCTAssertEqual(code(profile(4, overrides: mastered, passive: 1, stability: 3, tactics: 2)), "4+")
        XCTAssertEqual(code(profile(4, overrides: mastered, passive: 2, stability: 3, tactics: 2)), "5−")
        XCTAssertEqual(code(profile(4, overrides: mastered, passive: 3, stability: 3, tactics: 2)), "5")
        XCTAssertEqual(code(profile(4, overrides: mastered, passive: 3, stability: 3, tactics: 3)), "5+")
        // 被动球再好，主动球没有精通的分项也不算 5
        XCTAssertEqual(code(profile(4, passive: 3, stability: 3, tactics: 3)), "4")
    }

    func testSixNeedsStandingAndLevelSixTechnique() {
        let skilled = ["smash": 6, "net": 6]
        XCTAssertEqual(code(profile(5, overrides: skilled, passive: 3, stability: 4, tactics: 3, standing: 4)), "6")
        XCTAssertEqual(code(profile(5, overrides: skilled, passive: 3, stability: 4, tactics: 3, standing: 3)), "6−")
        // 准霸主，但没有到 6 级的绝活：6−
        let noSpecialty = SkillAssessment.evaluate(profile(5, passive: 3, stability: 4, tactics: 3, standing: 4))
        XCTAssertEqual(noSpecialty?.tier.code, "6−")
        XCTAssertEqual(noSpecialty?.limitingGate?.contains("绝活"), true)
    }

    func testClubStandingAloneIsNotSix() {
        // 在自己的局里很少输，但技术只到 4 级
        XCTAssertEqual(code(profile(4, standing: 5)), "4")
        // 5+ 了，但多数分项还没到 5 级
        let result = SkillAssessment.evaluate(profile(4, overrides: ["smash": 5, "net": 5], passive: 3, stability: 4,
                                                      tactics: 3, standing: 4))
        XCTAssertEqual(result?.tier.code, "5+")
        XCTAssertEqual(result?.limitingGate?.contains("多数技术分项到 5 级"), true)
    }

    func testQuestionnaireTopsOutAtSixPlus() {
        let top = profile(6, passive: 4, doubles: 4, stability: 5, tactics: 4, standing: 5, experience: 4)
        let result = SkillAssessment.evaluate(top)
        XCTAssertEqual(result?.tier, SkillAssessment.maxTier)
        XCTAssertEqual(result?.tier.code, "6+")
        XCTAssertEqual(result?.suggestsVerification, true, "参加过 A/Open 组：提示申请认证")
        // 6+ 要有比赛或青训经历
        let capped = SkillAssessment.evaluate(profile(6, passive: 4, doubles: 4, stability: 5, tactics: 4, standing: 5))
        XCTAssertEqual(capped?.tier.code, "6")
        XCTAssertEqual(capped?.limitingGate?.contains("比赛或青训经历"), true)
    }

    func testStrengthsAreTheBestDimensions() {
        let result = SkillAssessment.evaluate(profile(4, overrides: ["smash": 5], stability: 3))
        XCTAssertEqual(result?.strengths.map(\.name), ["正手杀球"])
        XCTAssertEqual(SkillAssessment.evaluate(profile(4))?.strengths.isEmpty, true, "各项一样时没有突出的特点")
    }

    func testExperienceFloorRaisesLevelAndFlagsCalibration() {
        // 分项都在 2 级，但说自己 C/B 组进过前四 → 保底 5−，标记待校准
        let result = SkillAssessment.evaluate(profile(2, experience: 3))
        XCTAssertEqual(result?.tier.code, "5−")
        XCTAssertEqual(result?.needsCalibration, true)
    }

    func testReturningPlayerFloorIsOneLower() {
        let active = SkillAssessment.evaluate(profile(2, experience: 3))
        let returning = SkillAssessment.evaluate(profile(2, experience: 3, returning: true))
        XCTAssertEqual(returning?.level, (active?.level ?? 0) - 1)
        XCTAssertEqual(returning?.isReturning, true)
    }

    func testEveryLevelHasDescriptions() {
        for level in SkillLevel.range {
            XCTAssertFalse(SkillLevel.name(for: level).isEmpty)
            XCTAssertGreaterThanOrEqual(SkillLevel.anchors(for: level).count, 2, "Lv.\(level) 至少 2 条描述")
            XCTAssertFalse(SkillLevel.dimensionNotes(for: level).isEmpty, "Lv.\(level) 有分项标准")
        }
        XCTAssertEqual(SkillLevel.usFlight(for: 4), "D 组")
        XCTAssertEqual(SkillTier(level: 3, modifier: .plus).displayText, "Lv.3+ 初级")
        XCTAssertEqual(SkillTier(level: 6).displayText, "Lv.6 俱乐部高手")
    }

    func testTechniquesAreNotRequirementsAboveLevelFour() {
        // 技术在 4 级就全部熟练；5 级以上的档位标准看被动球、战术、俱乐部位置
        for tier in SkillTier.all where (5...6).contains(tier.level) {
            XCTAssertFalse(SkillLevel.tierCriteria(for: tier).joined().contains("反手"), tier.code)
        }
        XCTAssertTrue(SkillLevel.tierCriteria(for: SkillTier(level: 4)).joined().contains("反手"))
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
        let higher = try XCTUnwrap(SkillAssessment.evaluate(profile(4, overrides: ["smash": 5, "net": 5], stability: 3)))
        XCTAssertThrowsError(try backend.updateAssessment(higher, now: now.addingTimeInterval(30 * 86400)))
        let updated = try backend.updateAssessment(higher, now: now.addingTimeInterval(91 * 86400))
        XCTAssertEqual(updated.selfReportedLevel, higher.level)
        XCTAssertEqual(updated.selfReportedRating ?? 0, higher.tier.rating, accuracy: 0.001)
        XCTAssertEqual(updated.displayTier, higher.tier)
    }
}
