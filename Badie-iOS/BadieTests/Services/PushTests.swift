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

    /// 点开 badie.rsvp 的链接：邀请链接带着码打开加入页，球群链接打开球群
    func testUniversalLinks() {
        XCTAssertEqual(PushRegistry.route(for: "https://badie.rsvp/join/?code=AB12CD").route, .joinRoom(code: "AB12CD"))
        XCTAssertEqual(PushRegistry.route(for: "https://badie.rsvp/join/").route, .joinRoom(code: nil))
        XCTAssertEqual(PushRegistry.route(for: "https://badie.rsvp/groups/p-1/").route, .group(id: "p-1"))
        XCTAssertEqual(PushRegistry.route(for: "https://badie.rsvp/games/g-1/?from=email").tab, .games)
        XCTAssertTrue(Room.joinLink("AB12CD").hasSuffix("/join/?code=AB12CD"))
    }

    /// 聊天推送和链接打开对应的会话
    func testChatLinks() {
        XCTAssertEqual(PushRegistry.route(for: "/messages/dm/u-2/").route, .chat(userId: "u-2"))
        XCTAssertEqual(PushRegistry.route(for: "/app/messages/dm/u-2/").tab, .messages)
        XCTAssertEqual(PushRegistry.route(for: "/messages/game/g-1/").route, .groupChat(threadId: MessageThread.gameThreadId("g-1")))
        XCTAssertEqual(PushRegistry.route(for: "https://badie.rsvp/messages/group/p-1/").route, .groupChat(threadId: MessageThread.groupThreadId("p-1")))
        XCTAssertEqual(PushRegistry.route(for: "/messages/").route, .notifications, "没有具体会话就打开通知列表")
    }
}
