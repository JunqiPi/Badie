import XCTest
@testable import Badie

/// 定级问卷：每个选项对应一个等级；技术、比赛能力各取平均并受最弱一项限制，两者以弱的为准；
/// 5+ 往上看俱乐部位置，6+ 要有比赛经历；经历保底，最高 6+。和网页 web/tests/assessment.test.ts 是同样的用例
final class SkillAssessmentTests: XCTestCase {

    /// 选项序号（A = 0）。技术：高远、杀球、吊球、反手、网前、平抽、步法；比赛：被动球、双打、稳定性、战术
    private func answers(_ technique: [Int], _ game: [Int], standing: Int = 0, experience: Int = 0,
                         returning: Bool = false) -> [String: Int] {
        var answers: [String: Int] = ["standing": standing, "experience": experience, "recency": returning ? 1 : 0]
        for (id, option) in zip(["clear", "smash", "drop", "backhand", "net", "drive", "footwork"], technique) { answers[id] = option }
        for (id, option) in zip(["passive", "doubles", "stability", "tactics"], game) { answers[id] = option }
        return answers
    }

    // 典型的几类球友
    private var beginner: [String: Int] { answers([1, 1, 1, 1, 1, 1, 1], [0, 1, 1, 0]) }
    private var middle: [String: Int] { answers([3, 3, 3, 2, 2, 2, 3], [2, 2, 3, 2]) }
    private var strong: [String: Int] { answers([4, 4, 4, 3, 3, 3, 4], [3, 3, 4, 3]) }
    private var top: [String: Int] { answers([5, 5, 5, 4, 4, 4, 5], [4, 4, 5, 4]) }

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
        XCTAssertEqual(code(answers([0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0])), "1−")
        XCTAssertEqual(code(answers([0, 0, 0, 0, 1, 0, 0], [0, 1, 0, 0])), "1")
    }

    func testTypicalIntermediateIsLevelFour() {
        let result = SkillAssessment.evaluate(SkillAssessment.demoAnswers)
        XCTAssertEqual(result?.tier.code, "4")
        XCTAssertEqual(result?.dimensions.count, 7)
        XCTAssertEqual(result?.dimensions.first { $0.id == "backhand" }?.code, "3", "分项按档位显示")
    }

    func testMiddleAnswersDoNotJumpToFive() {
        XCTAssertEqual(code(beginner), "2")
        XCTAssertEqual(code(middle), "3+")
        XCTAssertEqual(code(strong), "5−")
    }

    func testWeakestSkillHoldsTheLevelAndIsNamed() {
        // 其他都在 3 级左右，反手还只能绕头：短板把等级拉下来
        let result = SkillAssessment.evaluate(answers([3, 3, 3, 0, 2, 2, 3], [2, 2, 3, 2]))
        XCTAssertEqual(result?.tier.code, "3−")
        XCTAssertEqual(result?.limitingGate?.hasPrefix("想到 3 级先补短板：反手后场"), true)
    }

    func testWeakerOfTechniqueAndGameDecides() {
        // 技术不错，但被动球、战术还弱
        let result = SkillAssessment.evaluate(answers([4, 4, 4, 3, 3, 3, 4], [1, 2, 3, 1]))
        XCTAssertEqual(result?.tier.code, "4−")
        XCTAssertEqual(result?.limitingGate?.hasPrefix("想到 4 级先补短板：接杀和被动球"), true)
    }

    func testAboveFivePlusDependsOnClubStanding() {
        let unknown = SkillAssessment.evaluate(top)
        XCTAssertEqual(unknown?.tier.code, "5+")
        XCTAssertEqual(unknown?.limitingGate?.contains("俱乐部"), true)
        var risingStar = top
        risingStar["standing"] = 3
        XCTAssertEqual(code(risingStar), "6−")
        var nearTop = top
        nearTop["standing"] = 4
        XCTAssertEqual(code(nearTop), "6")
        // 霸主还要有比赛或青训经历
        var ace = top
        ace["standing"] = 5
        let noTournaments = SkillAssessment.evaluate(ace)
        XCTAssertEqual(noTournaments?.tier.code, "6")
        XCTAssertEqual(noTournaments?.limitingGate?.contains("比赛或青训经历"), true)
        ace["experience"] = 4
        let result = SkillAssessment.evaluate(ace)
        XCTAssertEqual(result?.tier, SkillAssessment.maxTier)
        XCTAssertEqual(result?.suggestsVerification, true, "参加过 A/Open 组：提示申请认证")
        // 位置再高，技术没到也不是 6
        var proud = strong
        proud["standing"] = 5
        XCTAssertEqual(code(proud), "5−")
    }

    func testStrengthsAreTheBestDimensions() {
        let result = SkillAssessment.evaluate(strong)
        XCTAssertEqual(result?.strengths.map(\.name), ["反手后场"])
        XCTAssertEqual(SkillAssessment.evaluate(top)?.strengths.isEmpty, true, "各项一样时没有突出的特点")
    }

    func testExperienceFloorRaisesLevelAndFlagsCalibration() {
        // 技术都在入门，但说自己 C/B 组进过前四 → 保底 5−，标记待校准
        var claimed = beginner
        claimed["experience"] = 3
        let result = SkillAssessment.evaluate(claimed)
        XCTAssertEqual(result?.tier.code, "5−")
        XCTAssertEqual(result?.needsCalibration, true)
    }

    func testReturningPlayerFloorIsOneLower() {
        var claimed = beginner
        claimed["experience"] = 3
        let active = SkillAssessment.evaluate(claimed)
        claimed["recency"] = 1
        let returning = SkillAssessment.evaluate(claimed)
        XCTAssertEqual(returning?.level, (active?.level ?? 0) - 1)
        XCTAssertEqual(returning?.isReturning, true)
    }

    func testEveryLevelHasDescriptions() {
        for level in SkillLevel.range {
            XCTAssertFalse(SkillLevel.name(for: level).isEmpty)
            XCTAssertGreaterThanOrEqual(SkillLevel.anchors(for: level).count, 2, "Lv.\(level) 至少 2 条描述")
            XCTAssertFalse(SkillLevel.dimensionNotes(for: level).isEmpty, "Lv.\(level) 有分项标准")
        }
        XCTAssertEqual(SkillLevel.usFlight(for: 4, region: "US"), "D 组")
        XCTAssertNil(SkillLevel.usFlight(for: 4, region: "MY"), "其他国家没有美国组别")
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
        let higher = try XCTUnwrap(SkillAssessment.evaluate(strong))
        XCTAssertThrowsError(try backend.updateAssessment(higher, now: now.addingTimeInterval(30 * 86400)))
        let updated = try backend.updateAssessment(higher, now: now.addingTimeInterval(91 * 86400))
        XCTAssertEqual(updated.selfReportedLevel, higher.level)
        XCTAssertEqual(updated.selfReportedRating ?? 0, higher.tier.rating, accuracy: 0.001)
        XCTAssertEqual(updated.displayTier, higher.tier)
    }
}
