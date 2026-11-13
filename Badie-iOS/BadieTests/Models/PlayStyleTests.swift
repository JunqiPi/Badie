import XCTest
@testable import Badie

/// 打法：六个维度（进攻 = 杀球，网前 = 网前和吊球，防守 = 被动球和稳定性，速度 = 平抽挡，步法，战术 = 战术和双打），
/// 问卷定出 1–2 级是新星；否则最高和最低差不超过半级是六边形战士，再否则看最高的一项（一样高按进攻、网前、防守、速度、步法、战术）。
/// 和网页 web/src/app/assessment.ts 的测试用同样的用例：改了这里，网页那边也要改。
final class PlayStyleTests: XCTestCase {

    /// 选项序号（A = 0）。技术：高远、杀球、吊球、反手、网前、平抽、步法；比赛：被动球、双打、稳定性、战术
    private func answers(_ technique: [Int], _ game: [Int]) -> [String: Int] {
        var answers: [String: Int] = ["standing": 0, "experience": 0, "recency": 0]
        for (id, option) in zip(["clear", "smash", "drop", "backhand", "net", "drive", "footwork"], technique) { answers[id] = option }
        for (id, option) in zip(["passive", "doubles", "stability", "tactics"], game) { answers[id] = option }
        return answers
    }

    private struct Fixture {
        let name: String
        let technique: [Int]
        let game: [Int]
        /// 问卷定出的档位
        let tier: String
        let style: PlayStyle
        /// 进攻、网前、防守、速度、步法、战术
        let axes: [Double]
        /// 卡片上的数字（四舍五入到整级）
        let shown: [Int]
        let bestShot: String
        /// 离下一级还差：(下一级, 题目 ID)
        let gap: (Int, String)?
    }

    private let fixtures: [Fixture] = [
        Fixture(name: "demo", technique: [4, 4, 4, 2, 3, 3, 4], game: [2, 2, 3, 2], tier: "4", style: .allround,
                axes: [4, 4, 4, 4, 4, 3.75], shown: [4, 4, 4, 4, 4, 4], bestShot: "clear", gap: (5, "backhand")),
        Fixture(name: "cannon", technique: [4, 5, 4, 2, 3, 3, 4], game: [2, 2, 3, 2], tier: "4", style: .cannon,
                axes: [6, 4, 4, 4, 4, 3.75], shown: [6, 4, 4, 4, 4, 4], bestShot: "smash", gap: (5, "backhand")),
        Fixture(name: "net", technique: [3, 2, 5, 2, 4, 2, 3], game: [2, 2, 3, 2], tier: "4−", style: .net,
                axes: [2.5, 6, 4, 2.5, 3, 3.75], shown: [3, 6, 4, 3, 3, 4], bestShot: "drop", gap: (4, "smash")),
        Fixture(name: "wall", technique: [3, 2, 2, 2, 2, 2, 3], game: [4, 2, 5, 2], tier: "3+", style: .wall,
                axes: [2.5, 2.5, 6, 2.5, 3, 3.75], shown: [3, 3, 6, 3, 3, 4], bestShot: "clear", gap: (4, "drop")),
        Fixture(name: "quick", technique: [3, 2, 2, 2, 2, 4, 3], game: [1, 1, 2, 1], tier: "3", style: .quick,
                axes: [2.5, 2.5, 3, 6, 3, 2.75], shown: [3, 3, 3, 6, 3, 3], bestShot: "drive", gap: (4, "drop")),
        Fixture(name: "engine", technique: [3, 2, 2, 2, 2, 2, 5], game: [1, 1, 2, 1], tier: "3", style: .engine,
                axes: [2.5, 2.5, 3, 2.5, 6, 2.75], shown: [3, 3, 3, 3, 6, 3], bestShot: "footwork", gap: (4, "drop")),
        Fixture(name: "captain", technique: [3, 2, 2, 2, 2, 2, 3], game: [1, 4, 2, 4], tier: "3+", style: .captain,
                axes: [2.5, 2.5, 3, 2.5, 3, 6], shown: [3, 3, 3, 3, 3, 6], bestShot: "clear", gap: (4, "drop")),
        // 3− 已经不是新星。进攻和网前一样高：按顺序取进攻；杀球和吊球一样好：按题目顺序取杀球
        Fixture(name: "tieAttackNet", technique: [3, 4, 4, 2, 3, 2, 2], game: [0, 0, 1, 0], tier: "3−", style: .cannon,
                axes: [4, 4, 2, 2.5, 2.5, 1.75], shown: [4, 4, 2, 3, 3, 2], bestShot: "smash", gap: (3, "doubles")),
        // 最高和最低差半级：还是六边形战士
        Fixture(name: "allroundHalf", technique: [4, 4, 4, 2, 3, 3, 4], game: [2, 2, 2, 2], tier: "4−", style: .allround,
                axes: [4, 4, 3.5, 4, 4, 3.75], shown: [4, 4, 4, 4, 4, 4], bestShot: "clear", gap: (4, "backhand")),
        // 差 0.75 级：看最高的一项
        Fixture(name: "cannonEdge", technique: [4, 4, 4, 2, 3, 3, 4], game: [2, 2, 3, 1], tier: "4−", style: .cannon,
                axes: [4, 4, 4, 4, 4, 3.25], shown: [4, 4, 4, 4, 4, 3], bestShot: "clear", gap: (4, "backhand")),
        // 完全的新手（1−）：新星；网前 0.5 显示成 1；没有“还差”
        Fixture(name: "brandNew", technique: [0, 0, 0, 0, 0, 0, 0], game: [0, 0, 0, 0], tier: "1−", style: .rookie,
                axes: [1, 0.5, 1.5, 1, 1, 1.75], shown: [1, 1, 2, 1, 1, 2], bestShot: "clear", gap: nil),
        // 2 级：新星（六项看是战术师也不算）；杀球和步法一样弱：按题目顺序取杀球
        Fixture(name: "tieGap", technique: [1, 1, 2, 1, 1, 1, 1], game: [0, 1, 1, 0], tier: "2", style: .rookie,
                axes: [1.5, 2, 2, 2, 1.5, 2.25], shown: [2, 2, 2, 2, 2, 2], bestShot: "clear", gap: (3, "smash")),
        // 2 级的入门球友：新星
        Fixture(name: "beginner", technique: [1, 1, 1, 1, 1, 1, 1], game: [0, 1, 1, 0], tier: "2", style: .rookie,
                axes: [1.5, 1.5, 2, 2, 1.5, 2.25], shown: [2, 2, 2, 2, 2, 2], bestShot: "clear", gap: (3, "drop")),
        // 5+ 往上看俱乐部位置：没有“还差”的那一项
        Fixture(name: "top", technique: [5, 5, 5, 4, 4, 4, 5], game: [4, 4, 5, 4], tier: "5+", style: .allround,
                axes: [6, 6, 6, 6, 6, 6], shown: [6, 6, 6, 6, 6, 6], bestShot: "clear", gap: nil)
    ]

    func testFixtures() throws {
        for fixture in fixtures {
            let given = answers(fixture.technique, fixture.game)
            let profile = try XCTUnwrap(SkillAssessment.playProfile(given), fixture.name)
            XCTAssertEqual(profile.style, fixture.style, fixture.name)
            for (axis, expected) in zip(PlayAxis.allCases, fixture.axes) {
                XCTAssertEqual(profile.value(axis), expected, accuracy: 0.0001, "\(fixture.name) \(axis)")
            }
            XCTAssertEqual(PlayAxis.allCases.map(profile.displayValue), fixture.shown, fixture.name)
            XCTAssertEqual(profile.bestShot?.id, fixture.bestShot, fixture.name)

            let result = try XCTUnwrap(SkillAssessment.evaluate(given), fixture.name)
            XCTAssertEqual(result.tier.code, fixture.tier, fixture.name)
            XCTAssertEqual(result.play, profile, "结果里带着同样的打法：\(fixture.name)")
            XCTAssertEqual(result.nextGap?.level, fixture.gap?.0, fixture.name)
            XCTAssertEqual(result.nextGap?.dimension.id, fixture.gap?.1, fixture.name)
        }
    }

    func testGapIsTheFirstItemOfTheLimitingGate() throws {
        let result = try XCTUnwrap(SkillAssessment.evaluate(answers([3, 3, 3, 0, 2, 2, 3], [2, 2, 3, 2])))
        XCTAssertEqual(result.tier.code, "3−")
        XCTAssertEqual(result.nextGap?.level, 3)
        XCTAssertEqual(result.nextGap?.dimension.name, "反手后场")
        XCTAssertEqual(result.limitingGate?.hasPrefix("想到 3 级先补短板：反手后场"), true)
    }

    func testIncompleteAnswersHaveNoPlayStyle() {
        // 要答完全部题目：新星要看问卷定出的等级
        for id in ["tactics", "standing"] {
            var partial = answers([4, 4, 4, 2, 3, 3, 4], [2, 2, 3, 2])
            partial[id] = nil
            XCTAssertNil(SkillAssessment.playProfile(partial), id)
        }
    }

    func testPartners() {
        XCTAssertEqual(PlayStyle.cannon.partner, .net)
        XCTAssertEqual(PlayStyle.net.partner, .cannon)
        XCTAssertEqual(PlayStyle.wall.partner, .quick)
        XCTAssertEqual(PlayStyle.quick.partner, .wall)
        XCTAssertEqual(PlayStyle.engine.partner, .captain)
        XCTAssertEqual(PlayStyle.captain.partner, .engine)
        XCTAssertNil(PlayStyle.allround.partner)
        XCTAssertNil(PlayStyle.rookie.partner)
        for style in PlayStyle.allCases {
            XCTAssertFalse(style.title.isEmpty)
            XCTAssertFalse(style.line.isEmpty)
        }
    }

    func testSummaryKeepsAnswersForTheCard() throws {
        let given = answers([4, 5, 4, 2, 3, 3, 4], [2, 2, 3, 2])
        let summary = SkillAssessmentSummary(level: 4, needsCalibration: false, isReturning: false, assessedAt: Date(),
                                             rating: 4, answers: given)
        XCTAssertEqual(summary.play?.style, .cannon)
        // 旧数据没有答案：读得出来，只是没有打法
        let old = #"{"level":4,"needsCalibration":false,"isReturning":false,"assessedAt":0}"#
        let decoded = try JSONDecoder().decode(SkillAssessmentSummary.self, from: Data(old.utf8))
        XCTAssertNil(decoded.answers)
        XCTAssertNil(decoded.play)
    }

    // MARK: 卡片链接

    func testCardLinks() {
        XCTAssertEqual(LevelCardData.slug(for: SkillTier(level: 4, modifier: .plus)), "4-plus")
        XCTAssertEqual(LevelCardData.slug(for: SkillTier(level: 4)), "4")
        XCTAssertEqual(LevelCardData.slug(for: SkillTier(level: 1, modifier: .minus)), "1-minus")
        XCTAssertEqual(LevelCardData.slug(for: SkillTier(level: 8, modifier: .plus)), "8", "7 级起每级一个页面")
        XCTAssertEqual(LevelCardData.url(for: SkillTier(level: 4, modifier: .plus), language: "en").absoluteString,
                       "https://badie.rsvp/levels/4-plus/?ref=card")
        XCTAssertEqual(LevelCardData.url(for: SkillTier(level: 4, modifier: .plus), language: "zh-Hans").absoluteString,
                       "https://badie.rsvp/zh/levels/4-plus/?ref=card")
        XCTAssertEqual(LevelCardData.url(for: SkillTier(level: 3), language: "zh-Hant").absoluteString,
                       "https://badie.rsvp/zh-hant/levels/3/?ref=card")
        XCTAssertEqual(LevelCardData.url(for: SkillTier(level: 3), language: "ja").absoluteString,
                       "https://badie.rsvp/ja/levels/3/?ref=card")
        for tier in SkillTier.all where tier.level <= SkillLevel.maxSelfSelectable {
            XCTAssertEqual(LevelCardData.tier(fromSlug: LevelCardData.slug(for: tier)), tier)
        }
        XCTAssertNil(LevelCardData.tier(fromSlug: "4-up"))
        XCTAssertNil(LevelCardData.tier(fromSlug: "levels"))
    }

    func testCardTextOnlyShowsWhatIsKnown() {
        var data = LevelCardData(tier: SkillTier(level: 4, modifier: .plus), label: .selfRated)
        let status = LevelCardLabel.selfRated.title
        XCTAssertEqual(data.subline(), "\(data.tierLine) · \(status)")
        // 什么都不知道：背面印这一档的标准
        XCTAssertEqual(data.backRows.map(\.label), [data.tierLine])
        data.region = "Los Angeles"
        data.mode = .doubles
        data.venue = "LABC"
        data.times = "周三晚上"
        XCTAssertEqual(data.subline(includesTier: false), "LOS ANGELES · \(status)")
        XCTAssertEqual(data.backRows.map(\.value), [GameMode.doubles.title, "LABC", "周三晚上"])
        // 没有头像，或者关掉了“印上头像”：不印
        XCTAssertNil(data.avatarImage)
        XCTAssertFalse(data.footer.isEmpty)
    }

    func testGhostWords() {
        XCTAssertEqual(PlayStyle.allCases.map(\.ghostWord),
                       ["SMASH", "NET", "WALL", "SPRING", "MOTOR", "TACTICS", "ALL-ROUND", "ROOKIE"])
    }

    func testCardLabel() {
        var user = User(id: "u1", nickname: "阿杰", phone: "", selfReportedLevel: 4)
        XCTAssertEqual(LevelCardLabel(user: user), .selfRated)
        user.reputation.evaluationCount = ReputationScore.newPlayerThreshold
        XCTAssertEqual(LevelCardLabel(user: user), .calibrated)
        user.applyVerification(.tournament, tier: SkillTier(level: 7))
        XCTAssertEqual(LevelCardLabel(user: user), .verified)
    }
}
