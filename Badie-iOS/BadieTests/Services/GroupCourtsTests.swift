import XCTest
@testable import Badie

/// 一个球群几个球馆：最多 5 个、第一个是主球馆、场次的球馆必须是群里的、删掉的球馆上的场次回到主球馆、附近任何一个球馆在范围内就算
@MainActor
final class GroupCourtsTests: XCTestCase {

    private var backend: MockBackend!
    private let center = Coordinate.fallbackCenter

    override func setUp() async throws {
        try await super.setUp()
        backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        Haptics.isEnabled = false
        _ = backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4, location: center, seedsDemoContent: false)
    }

    /// 在中心往北 km 公里处放一家球馆
    @discardableResult
    private func court(_ id: String, northKm: Double = 0) -> BadmintonCourt {
        let venue = BadmintonCourt(
            id: id, name: "Court \(id)", location: Coordinate(latitude: center.latitude + northKm / 111, longitude: center.longitude),
            address: PostalAddress(street: "", city: "Irvine", region: "CA", countryCode: "US"),
            timeZoneId: "America/Los_Angeles", source: .player, status: .unconfirmed
        )
        backend.db.venues[id] = venue
        return venue
    }

    private func schedule(_ id: String, daysAhead: Int, venueId: String? = nil) -> GroupSchedule {
        let weekday = Calendar.current.component(.weekday, from: Date().addingTimeInterval(Double(daysAhead) * 86400))
        return GroupSchedule(id: id, weekday: weekday, startMinutes: 19 * 60, endMinutes: 21 * 60, capacity: 8, feeNote: nil, venueId: venueId)
    }

    private func create(_ venueIds: [String], schedules: [GroupSchedule]) throws -> PlayGroup {
        try backend.createGroup(name: "多馆群", venueIds: venueIds, schedules: schedules, levelRange: 1...9, joinPolicy: .open, summary: "")
    }

    func testGroupKeepsSeveralCourtsWithMainFirst() throws {
        court("v-a"); court("v-b", northKm: 3); court("v-c", northKm: 6)
        let group = try create(["v-a", "v-b", "v-a", "v-c"], schedules: [schedule("s1", daysAhead: 1), schedule("s2", daysAhead: 2, venueId: "v-c")])
        XCTAssertEqual(group.venueId, "v-a", "第一个是主球馆，旧版本只认这个")
        XCTAssertEqual(group.venueIds, ["v-a", "v-b", "v-c"], "重复的只留一个")
        XCTAssertEqual(group.otherVenueIds, ["v-b", "v-c"])

        let sessions = backend.upcomingSessions(groupId: group.id)
        XCTAssertEqual(sessions.first { $0.scheduleId == "s1" }?.venueId, "v-a", "没选球馆的场次在主球馆")
        XCTAssertEqual(sessions.first { $0.scheduleId == "s2" }?.venueId, "v-c")
        XCTAssertEqual(backend.groups(atVenue: "v-c").map(\.id).contains(group.id), true, "球馆页能看到在这里打的球群")

        // 只有一个球馆：和以前一样
        let single = try backend.createGroup(name: "单馆群", venueId: "v-a", schedules: [schedule("s", daysAhead: 1)], levelRange: 1...9,
                                             joinPolicy: .open, summary: "")
        XCTAssertEqual(single.venueIds, ["v-a"])
        XCTAssertNil(single.otherVenueIds)
    }

    func testCourtLimitsAndScheduleCourtMustBelongToTheGroup() throws {
        let ids = (1...6).map { "v-\($0)" }
        for (index, id) in ids.enumerated() { court(id, northKm: Double(index)) }
        XCTAssertNoThrow(try create(Array(ids.prefix(5)), schedules: [schedule("s", daysAhead: 1)]), "最多 5 个")
        XCTAssertThrowsError(try create(ids, schedules: [schedule("s", daysAhead: 1)])) {
            XCTAssertEqual($0 as? BackendError, .groupVenuesInvalid)
        }
        XCTAssertThrowsError(try create([], schedules: [schedule("s", daysAhead: 1)])) {
            XCTAssertEqual($0 as? BackendError, .groupVenuesInvalid)
        }
        XCTAssertThrowsError(try create(["v-1", "v-missing"], schedules: [schedule("s", daysAhead: 1)])) {
            XCTAssertEqual($0 as? BackendError, .venueNotFound)
        }
        XCTAssertThrowsError(try create(["v-1", "v-2"], schedules: [schedule("s", daysAhead: 1, venueId: "v-3")]), "场次只能在群里的球馆") {
            XCTAssertEqual($0 as? BackendError, .groupScheduleInvalid)
        }
    }

    func testRemovingACourtMovesItsSessionsToTheMainCourt() throws {
        court("v-a"); court("v-b", northKm: 3); court("v-c", northKm: 6)
        let moved = schedule("s", daysAhead: 1, venueId: "v-b")
        let group = try create(["v-a", "v-b"], schedules: [moved])
        XCTAssertEqual(backend.upcomingSessions(groupId: group.id).first?.venueId, "v-b")

        // 不传球馆：不变
        try backend.updateGroup(id: group.id, name: group.name, schedules: [moved], levelRange: 1...9, joinPolicy: .open, summary: "")
        XCTAssertEqual(backend.group(id: group.id)?.venueIds, ["v-a", "v-b"])

        // 从来不是这个群的球馆：不行
        XCTAssertThrowsError(try backend.updateGroup(id: group.id, name: group.name, schedules: [schedule("s", daysAhead: 1, venueId: "v-c")],
                                                     levelRange: 1...9, joinPolicy: .open, summary: "", venueIds: ["v-a", "v-b"])) {
            XCTAssertEqual($0 as? BackendError, .groupScheduleInvalid)
        }

        // 删掉 v-b：这个场次和已经生成的场次都回到主球馆
        try backend.updateGroup(id: group.id, name: group.name, schedules: [moved], levelRange: 1...9, joinPolicy: .open, summary: "",
                                venueIds: ["v-a"])
        let updated = try XCTUnwrap(backend.group(id: group.id))
        XCTAssertEqual(updated.venueIds, ["v-a"])
        XCTAssertNil(updated.schedules.first?.venueId)
        XCTAssertEqual(updated.schedules.first?.effectiveVenueId(in: updated), "v-a")
        XCTAssertEqual(backend.upcomingSessions(groupId: group.id).first?.venueId, "v-a")
    }

    func testNearbyGroupsMatchAnyOfTheirCourts() throws {
        let far = court("v-far", northKm: 200)
        let near = court("v-near", northKm: 1)
        let both = try create(["v-far", "v-near"], schedules: [schedule("s", daysAhead: 1)])
        let farOnly = try create(["v-far"], schedules: [schedule("s", daysAhead: 1)])

        let nearby = backend.nearestGroups(to: near.location, radiusKm: 3).map(\.id)
        XCTAssertTrue(nearby.contains(both.id), "主球馆很远，但另一家在附近")
        XCTAssertFalse(nearby.contains(farOnly.id))
        XCTAssertTrue(backend.groups(near: near.location, radiusKm: 3).map(\.id).contains(both.id))
        XCTAssertEqual(backend.distanceKm(of: both, from: near.location) ?? 99, 0, accuracy: 0.01, "按最近的那家球馆算距离")

        // 近的在前
        let around = backend.nearestGroups(to: far.location, radiusKm: 300)
        let distances = around.compactMap { backend.distanceKm(of: $0, from: far.location) }
        XCTAssertEqual(distances, distances.sorted())
    }

    func testOldSavedGroupsStillDecode() throws {
        let old = #"{"id":"s","weekday":5,"startMinutes":1170,"endMinutes":1320,"capacity":8}"#
        let schedule = try JSONDecoder().decode(GroupSchedule.self, from: Data(old.utf8))
        XCTAssertNil(schedule.venueId)

        court("v-a")
        let group = try create(["v-a"], schedules: [self.schedule("s", daysAhead: 1)])
        let data = try JSONEncoder().encode(group)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["otherVenueIds"], "只有一个球馆时和旧数据一样")
        XCTAssertEqual(try JSONDecoder().decode(PlayGroup.self, from: data).venueIds, ["v-a"])
    }
}
