import XCTest
@testable import Badie

/// 项目：男单女单男双女双只能选自己的性别，混双只有双打；和服务器的性别限制、混双标记互相换算
final class PlayEventTests: XCTestCase {

    func testChoicesFollowModeAndGender() {
        XCTAssertEqual(PlayEvent.choices(mode: .singles, gender: .male), [nil, .men])
        XCTAssertEqual(PlayEvent.choices(mode: .doubles, gender: .female), [nil, .women, .mixed])
        XCTAssertEqual(PlayEvent.choices(mode: .doubles, gender: .unspecified), [nil], "没选性别只能不限")
    }

    func testServerMapping() {
        XCTAssertEqual(PlayEvent(gender: .female, mixed: false), .women)
        XCTAssertEqual(PlayEvent(gender: nil, mixed: true), .mixed)
        XCTAssertNil(PlayEvent(gender: nil, mixed: false), "不限")
        XCTAssertEqual(PlayEvent.men.gender, .male)
        XCTAssertNil(PlayEvent.mixed.gender, "混双不限性别，靠混双标记")
    }

    func testTitles() {
        XCTAssertEqual(PlayEvent.women.title(mode: .singles), String(localized: "女单"))
        XCTAssertEqual(PlayEvent.men.title(mode: .doubles), String(localized: "男双"))
        let open: PlayEvent? = nil
        XCTAssertEqual(open.title(mode: .doubles), GameMode.doubles.title, "不限就写双打")
    }
}
