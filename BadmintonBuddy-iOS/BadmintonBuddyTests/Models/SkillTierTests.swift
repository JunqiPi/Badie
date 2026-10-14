import XCTest
@testable import BadmintonBuddy

/// 细分档位：1− … 9+ 共 27 档，分值按 1/3 级
final class SkillTierTests: XCTestCase {

    func testTwentySevenTiersInOrder() {
        XCTAssertEqual(SkillTier.all.count, 27)
        XCTAssertEqual(SkillTier.all.first?.code, "1−")
        XCTAssertEqual(SkillTier.all.last?.code, "9+")
        XCTAssertEqual(SkillTier.all.map(\.index), Array(0..<27))
        XCTAssertEqual(SkillTier.all, SkillTier.all.sorted())
    }

    func testRatingRoundTrip() {
        for tier in SkillTier.all {
            XCTAssertEqual(SkillTier(rating: tier.rating), tier)
        }
        XCTAssertEqual(SkillTier(level: 4, modifier: .plus).rating, 4 + 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(SkillTier(level: 4, modifier: .minus).text, "Lv.4−")
    }

    func testRatingRoundsToNearestThird() {
        XCTAssertEqual(SkillTier(rating: 4.6), SkillTier(level: 5, modifier: .minus))
        XCTAssertEqual(SkillTier(rating: 4.1), SkillTier(level: 4))
        XCTAssertEqual(SkillTier(rating: 4.2), SkillTier(level: 4, modifier: .plus))
        // 超出范围的分值夹在 1− 和 9+ 之间
        XCTAssertEqual(SkillTier(rating: 0.2), SkillTier(level: 1, modifier: .minus))
        XCTAssertEqual(SkillTier(rating: 12), SkillTier(level: 9, modifier: .plus))
    }

    func testOffsetAndDifferenceText() {
        let four = SkillTier(level: 4)
        XCTAssertEqual(four.offset(by: 2), SkillTier(level: 4, modifier: .plus).offset(by: 1))
        XCTAssertEqual(four.steps(to: SkillTier(level: 5, modifier: .plus)), 4)
        XCTAssertEqual(SkillTier.differenceText(0), "同水平")
        XCTAssertEqual(SkillTier.differenceText(1), "高 1 档")
        XCTAssertEqual(SkillTier.differenceText(-3), "低 1 级")
        XCTAssertEqual(SkillTier.differenceText(4), "高 1 级 1 档")
    }

    func testEliteTiersHaveTheirOwnNames() {
        XCTAssertEqual(SkillTier(level: 4, modifier: .plus).displayText, "Lv.4+ 中级")
        XCTAssertEqual(SkillTier(level: 6, modifier: .minus).displayText, "Lv.6− 崭露头角")
        XCTAssertEqual(SkillTier(level: 7).displayText, "Lv.7 州级选手")
        XCTAssertEqual(SkillTier(level: 9, modifier: .plus).displayText, "Lv.9+ 世界顶尖")
        // 每一档都有具体标准
        for tier in SkillTier.all {
            XCTAssertFalse(SkillLevel.tierCriteria(for: tier).isEmpty, tier.code)
        }
    }

    func testMatchingToleranceUsesTiers() {
        // 容忍 1 级 = 上下 3 档：4+ 能匹配 3+ 到 5+，匹配不到 3
        let me = SkillTier(level: 4, modifier: .plus)
        XCTAssertLessThanOrEqual(abs(me.steps(to: SkillTier(level: 3, modifier: .plus))), 3)
        XCTAssertGreaterThan(abs(me.steps(to: SkillTier(level: 3))), 3)
    }
}
