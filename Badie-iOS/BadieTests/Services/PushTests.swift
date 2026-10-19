import XCTest
@testable import Badie

/// 推送：通知里的网址打开对应页面（和网页同一套地址，新旧写法都认）
final class PushTests: XCTestCase {
    func testLinksOpenTheRightScreen() {
        XCTAssertEqual(PushRegistry.route(for: "/app/games/g-1/").route, .game(id: "g-1"))
        XCTAssertEqual(PushRegistry.route(for: "/games/g-1/").tab, .games)
        XCTAssertEqual(PushRegistry.route(for: "/rooms/r-1/").route, .room(id: "r-1"))
        XCTAssertEqual(PushRegistry.route(for: "/app/groups/p-1/").route, .group(id: "p-1"))
        XCTAssertEqual(PushRegistry.route(for: "/app/challenges/").route, .challenges)
        XCTAssertEqual(PushRegistry.route(for: "/app/games/").route, .notifications, "没有具体球局就打开通知列表")
        XCTAssertEqual(PushRegistry.route(for: "").route, .notifications)
    }
}
