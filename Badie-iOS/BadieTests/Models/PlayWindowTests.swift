import XCTest
@testable import Badie

/// 附近的人里约人：大概的时间窗口、最近的一次空闲时间、两人空闲时间的交集、显示的说法
final class PlayWindowTests: XCTestCase {

    private let calendar = Calendar.current

    /// 2026-11-11 是周三
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func minutes(_ date: Date) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    // MARK: 最近的一次

    func testNextOccurrenceLaterThisWeek() {
        // 周三上午看“周六 14:00–18:00”：就是 11/14 那天
        let saturday = RecurringTimeSlot(dayOfWeek: 7, startHour: 14, endHour: 18)
        let window = PlayWindow.nextOccurrence(of: saturday, now: date(11, 10))
        XCTAssertEqual(window?.start, date(14, 14))
        XCTAssertEqual(window?.end, date(14, 18))
        XCTAssertEqual(window?.daypart, .afternoon)
    }

    func testNextOccurrenceTodayMovesStartOrSkipsToNextWeek() {
        let wednesday = RecurringTimeSlot(dayOfWeek: 4, startHour: 18, endHour: 22)
        // 19:10：最早 19:40 → 20:00 开始，还够打 2 小时
        let tonight = PlayWindow.nextOccurrence(of: wednesday, now: date(11, 19, 10))
        XCTAssertEqual(tonight?.start, date(11, 20))
        XCTAssertEqual(tonight?.end, date(11, 22))
        // 20:10：不够 2 小时了，就是下周三
        let nextWeek = PlayWindow.nextOccurrence(of: wednesday, now: date(11, 20, 10))
        XCTAssertEqual(nextWeek?.start, date(18, 18))
    }

    func testShortSlotIsExtendedToTwoHoursAndAligned() {
        // 07:15–08:00：开始取整到 07:30，延到 2 小时
        let early = RecurringTimeSlot(dayOfWeek: 5, startHour: 7, startMinute: 15, endHour: 8)
        let window = PlayWindow.nextOccurrence(of: early, now: date(11, 10))
        XCTAssertEqual(window?.start, date(12, 7, 30))
        XCTAssertEqual(window?.end, date(12, 9, 30))
        XCTAssertTrue(window?.isExact ?? false, "正好 2 小时就是定好的时间")
    }

    // MARK: 粗一点的时间

    func testWeekendAndNextWeekdays() {
        let weekend = PlayWindow.weekend(now: date(11, 10), daypart: .afternoon)
        XCTAssertEqual(weekend?.start, date(14, 14))
        XCTAssertEqual(weekend?.end, date(15, 18))
        let any = PlayWindow.weekend(now: date(11, 10), daypart: nil)
        XCTAssertEqual(any?.start, date(14, 8))
        XCTAssertEqual(any?.end, date(15, 22))
        // 周日晚上 21:00：这周末来不及了，就是下周末
        let late = PlayWindow.weekend(now: date(15, 21), daypart: nil)
        XCTAssertEqual(late?.start, date(21, 8))

        let weekdays = PlayWindow.nextWeekdays(now: date(11, 10), daypart: .evening)
        XCTAssertEqual(weekdays?.start, date(16, 18))
        XCTAssertEqual(weekdays?.end, date(20, 22))
    }

    func testPossibleStartsStayInsideDaypartEachDay() {
        let window = PlayWindow(start: date(14, 14), end: date(15, 18), daypart: .afternoon)
        let starts = window.possibleStarts(now: date(11, 10))
        // 每天 14:00、14:30 … 16:00 共 5 个，两天 10 个
        XCTAssertEqual(starts.count, 10)
        XCTAssertEqual(starts.first, date(14, 14))
        XCTAssertEqual(starts.last, date(15, 16))
        XCTAssertFalse(starts.contains(date(14, 17)), "17:00 开始就打到 19:00 了")
        // 快开始了：最早是现在过 30 分钟后的整半点
        let soon = PlayWindow(start: date(11, 14), end: date(11, 18)).possibleStarts(now: date(11, 14, 50))
        XCTAssertEqual(soon.first, date(11, 15, 30))
        XCTAssertEqual(soon.last, date(11, 16))
        XCTAssertFalse(PlayWindow(start: date(11, 14), end: date(11, 18)).isPossible(now: date(11, 16, 10)))
    }

    func testDeadlineAndExact() {
        let window = PlayWindow(start: date(14, 14), end: date(14, 18), daypart: .afternoon)
        XCTAssertEqual(window.deadline, date(14, 16))
        XCTAssertFalse(window.isExact)
        XCTAssertTrue(PlayWindow(start: date(14, 14), end: date(14, 16)).isExact)
    }

    // MARK: 两人空闲时间的交集

    func testFirstOverlapNeedsTwoHours() {
        let mine = [RecurringTimeSlot(dayOfWeek: 5, startHour: 19, endHour: 20),
                    RecurringTimeSlot(dayOfWeek: 7, startHour: 13, endHour: 18)]
        let theirs = [RecurringTimeSlot(dayOfWeek: 5, startHour: 18, endHour: 21),
                      RecurringTimeSlot(dayOfWeek: 7, startHour: 14, endHour: 20)]
        // 周四只重叠 1 小时，不算；周六 14:00–18:00
        let window = PlayWindow.firstOverlap(mine, theirs, now: date(11, 10))
        XCTAssertEqual(window?.start, date(14, 14))
        XCTAssertEqual(window?.end, date(14, 18))
        XCTAssertEqual(window?.daypart, .afternoon)
        XCTAssertNil(PlayWindow.firstOverlap(mine, [RecurringTimeSlot(dayOfWeek: 2, startHour: 7, endHour: 9)], now: date(11, 10)))
    }

    // MARK: 时段

    func testDaypartContainingAndBest() {
        XCTAssertEqual(Daypart.containing(start: 14 * 60, end: 18 * 60), .afternoon)
        XCTAssertNil(Daypart.containing(start: 11 * 60, end: 15 * 60))
        XCTAssertEqual(Daypart.best(start: 17 * 60, end: 21 * 60), .evening)
        XCTAssertEqual(Daypart.best(start: 7 * 60, end: 9 * 60), .morning)
        XCTAssertNil(Daypart.best(start: 5 * 60, end: 7 * 60))
    }

    // MARK: 显示

    func testWindowText() {
        let now = date(11, 10)
        let saturday = PlayWindow(start: date(14, 14), end: date(14, 18), daypart: .afternoon)
        XCTAssertEqual(WindowText.headline(saturday, now: now), "\(DateText.weekday(date(14, 14))) \(Daypart.afternoon.title)")
        XCTAssertEqual(WindowText.range(saturday), "\(DateText.time(date(14, 14)))–\(DateText.time(date(14, 18)))")
        XCTAssertTrue(WindowText.caption(saturday).contains(WindowText.range(saturday)))

        let weekend = PlayWindow(start: date(14, 14), end: date(15, 18), daypart: .afternoon)
        XCTAssertEqual(WindowText.days(weekend, now: now), String(localized: "这周末"))
        XCTAssertEqual(WindowText.headline(weekend, now: now), "\(String(localized: "这周末")) · \(Daypart.afternoon.title)")
        XCTAssertEqual(WindowText.days(weekend, now: date(7, 10)), String(localized: "下周末"))

        let weekdays = PlayWindow(start: date(16, 18), end: date(20, 22), daypart: .evening)
        XCTAssertEqual(WindowText.days(weekdays, now: now), String(localized: "下周工作日"))

        // 正好 2 小时：只写时间
        let exact = PlayWindow(start: date(14, 14), end: date(14, 16))
        XCTAssertEqual(WindowText.caption(exact), WindowText.range(exact))
        XCTAssertEqual(WindowText.dayName(date(11, 20), now: now), String(localized: "今天"))
        XCTAssertEqual(WindowText.dayName(date(12, 20), now: now), String(localized: "明天"))
    }

    func testUsualTimeSummary() {
        let weekdays = (2...6).map { RecurringTimeSlot(dayOfWeek: $0, startHour: 19, endHour: 21) }
        let weekend = [RecurringTimeSlot(dayOfWeek: 7, startHour: 14, endHour: 17), RecurringTimeSlot(dayOfWeek: 1, startHour: 14, endHour: 17)]
        let evening = String(localized: "\(String(localized: "工作日"))\(Daypart.evening.title)", comment: "星期 + 时段，如“周六下午”")
        let afternoon = String(localized: "\(String(localized: "周末"))\(Daypart.afternoon.title)", comment: "星期 + 时段，如“周六下午”")
        XCTAssertEqual(UsualTimeText.summary(weekdays + weekend), "\(evening) · \(afternoon)")
        XCTAssertNil(UsualTimeText.summary([]))
        // 三段以上只写两段，加“等”
        let morning = RecurringTimeSlot(dayOfWeek: 3, startHour: 8, endHour: 10)
        let summary = UsualTimeText.summary(weekdays + weekend + [morning]) ?? ""
        XCTAssertEqual(summary, String(localized: "\(summaryPrefix(weekdays + weekend + [morning])) 等"))
    }

    private func summaryPrefix(_ slots: [RecurringTimeSlot]) -> String {
        // 按第一次出现排（周一开始）：工作日晚上，然后周二上午；周末下午被省掉
        let tuesday = String(localized: "\(RecurringTimeSlot.weekdayNames[2])\(Daypart.morning.title)", comment: "星期 + 时段，如“周六下午”")
        let evening = String(localized: "\(String(localized: "工作日"))\(Daypart.evening.title)", comment: "星期 + 时段，如“周六下午”")
        return "\(evening) · \(tuesday)"
    }

    func testServerUsualTimeRoundTrip() {
        let slot = RecurringTimeSlot(dayOfWeek: 7, startHour: 14, startMinute: 30, endHour: 24)
        XCTAssertEqual(slot.serverValue, ServerUsualTime(weekday: 7, start: "14:30", end: "24:00"))
        let back = RecurringTimeSlot(server: slot.serverValue)
        XCTAssertEqual(back?.dayOfWeek, 7)
        XCTAssertEqual(back?.startMinutes, 14 * 60 + 30)
        XCTAssertEqual(back?.endMinutes, 24 * 60)
        XCTAssertNil(RecurringTimeSlot(server: ServerUsualTime(weekday: 8, start: "10:00", end: "12:00")))
        XCTAssertNil(RecurringTimeSlot(server: ServerUsualTime(weekday: 2, start: "12:00", end: "10:00")))
        XCTAssertNil(RecurringTimeSlot(server: ServerUsualTime(weekday: 2, start: "24:30", end: "25:00")))
    }
}
