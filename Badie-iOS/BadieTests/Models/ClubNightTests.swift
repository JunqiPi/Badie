import XCTest
@testable import Badie

/// 当晚和比赛：服务器给的 JSON 能读出来（字段名、可能为 null 的项、比赛的整数 id）
final class ClubNightTests: XCTestCase {

    func testDecodesNightState() throws {
        let json = """
        {"session_id":"s-1","group_id":"g-1","group":"LABC 周三","venue":"LABC","tz":"America/Los_Angeles",
         "starts_at":"2026-11-18T19:00:00-08:00","ends_at":"2026-11-18T22:00:00-08:00","role":"organizer",
         "open":true,"started":true,"courts":2,"doubles":true,"balance":false,"board_code":"AB12CD34",
         "match_id":null,"match_live":false,"helpers":[{"id":"u-2","nickname":"Amy"}],
         "undo_until":"2026-11-18T20:01:05.123456+00:00",
         "people":[
           {"id":"a","name":"Kevin","user_id":"u-1","guest":false,"status":"here","waitlisted":false,"games":2,"on_court":1,"next_up":false},
           {"id":"b","name":"Tony 2","user_id":null,"guest":true,"status":"here","waitlisted":false,"games":1,"on_court":null,"next_up":true,"queue":1},
           {"id":"c","name":"Mei","user_id":"u-3","guest":false,"status":"here","waitlisted":false,"games":0,"on_court":null,"next_up":false,"queue":2},
           {"id":"d","name":"Raj","user_id":"u-4","guest":false,"status":"absent","waitlisted":true,"games":0,"on_court":null,"next_up":false}],
         "games":[{"id":42,"court":1,"players":["a","x","y","z"],"started_at":"2026-11-18T19:40:00+00:00"}],
         "next":[["b","c","e","f"]]}
        """
        let state = try RemoteJSON.decode(NightState.self, from: Data(json.utf8))
        XCTAssertTrue(state.isOrganizer)
        XCTAssertEqual(state.boardCode, "AB12CD34")
        XCTAssertNil(state.matchId)
        XCTAssertNotNil(state.undoUntil)
        XCTAssertEqual(state.games.first?.id, 42)
        XCTAssertEqual(state.sides(state.games[0].players).a, ["a", "x"])
        XCTAssertNil(state.people[1].userId)
        XCTAssertEqual(state.hereCount, 3)
        // 等候：手动放到下一场的在前，再按场数
        XCTAssertEqual(state.waiting.map(\.id), ["b", "c"])
        XCTAssertEqual(state.courtNumbers, [1, 2])
        XCTAssertEqual(state.next.first?.count, 4)
    }

    func testNoPermissionIsNull() throws {
        XCTAssertNil(try RemoteJSON.decode(NightState?.self, from: Data("null".utf8)))
    }

    func testDecodesMatchState() throws {
        let json = """
        {"kind":"match","id":"m-1","name":"11月18日 比赛","format":"round_robin","play":"rotating","third_place":false,"doubles":false,"points":21,"best_of":1,
         "win_by_two":true,"courts":2,"rounds":7,"pools":null,"advance":null,"status":"live",
         "created_at":"2026-11-18T19:00:00+00:00","ended_at":null,"board_code":"ZX98YW76","session_id":null,
         "venue":null,"tie_at_cut":false,"round":3,
         "players":[{"id":"p1","name":"Kevin","team":null,"pool":null,"withdrawn":false},
                    {"id":"p2","name":"Amy","team":null,"pool":null,"withdrawn":false},
                    {"id":"p3","name":"Leo","team":null,"pool":null,"withdrawn":false},
                    {"id":"p4","name":"Raj","team":null,"pool":null,"withdrawn":true}],
         "games":[{"id":7,"round":1,"stage":"pool","a":["p1","p3"],"b":["p2","p4"],"status":"done","scores":[21,18],
                   "winner":1,"version":2,"scored_by":"Amy","flagged":true},
                  {"id":8,"round":3,"stage":"pool","a":["p1","p2"],"b":["p3","p4"],"court":1,"status":"playing","version":0},
                  {"id":9,"round":4,"stage":"ko","ko_size":8,"slot":1,"bye":true,"a":["p1"],"b":[],"status":"skipped","winner":1},
                  {"id":10,"round":4,"stage":"ko","ko_size":8,"slot":2,"a":["p2"],"b":["p3"],"status":"done","scores":[21,10,5,3],
                   "winner":1,"retired":2,"version":1}],
         "standings":[{"key":"p1","name":"Kevin","members":["p1"],"pool":null,"seed":1,"withdrawn":false,"played":1,"wins":1,
                       "losses":0,"pf":21,"pa":18,"diff":3,"rate":1.0,"rank":1,"tied":false}],
         "ranking":null,"role":"player","me":"p1","helpers":[],"undo_until":null}
        """
        let match = try RemoteJSON.decode(MatchState.self, from: Data(json.utf8))
        XCTAssertTrue(match.isLive)
        XCTAssertFalse(match.canManage)
        XCTAssertEqual(match.bestOf, 1)
        XCTAssertEqual(match.sideName(match.games[0].a), "Kevin · Leo")
        XCTAssertEqual(match.games[0].scoredBy, "Amy")
        XCTAssertNil(match.games[1].scores)
        // 球员只能在打的时候输自己那场
        XCTAssertFalse(match.canScore(match.games[0]))
        XCTAssertTrue(match.canScore(match.games[1]))
        XCTAssertEqual(match.standings.first?.diff, 3)
        XCTAssertEqual(MatchRules.scoreText([21, 18, 19, 21]), "21–18 19–21")
        // 轮空不是一场球
        XCTAssertEqual(match.realGames.count, 3)
        XCTAssertFalse(match.canScore(match.games[2]))
        XCTAssertEqual(match.games[3].retired, 2)
        XCTAssertEqual(MatchFormat.title(match.format, play: match.play), MatchPlay.rotating.title)
    }

    func testScoreRulesOnlyAcceptRealScores() {
        let fifteen = MatchScoring.Rules(points: 15, bestOf: 1, winByTwo: false)
        XCTAssertEqual(MatchScoring.check([15, 9], fifteen), .winner(1))
        // 15 分封顶：16:1 存不了
        if case .winner = MatchScoring.check([16, 1], fifteen) { XCTFail("16:1 不该收") }
        let deuce = MatchScoring.Rules(points: 21, bestOf: 1, winByTwo: true)
        XCTAssertEqual(MatchScoring.check([22, 24], deuce), .winner(2))
        XCTAssertEqual(MatchScoring.check([30, 29], deuce), .winner(1))
        if case .winner = MatchScoring.check([21, 20], deuce) { XCTFail("21:20 没拉开 2 分") }
        if case .winner = MatchScoring.check([25, 3], deuce) { XCTFail("25:3 打不出来") }
        XCTAssertEqual(MatchScoring.check([], deuce), .empty)
        // 三局两胜：只填一局不收，赢满两局才行，第三局多余也不收
        let bo3 = MatchScoring.Rules(points: 21, bestOf: 3, winByTwo: true)
        if case .winner = MatchScoring.check([21, 10], bo3) { XCTFail("三局两胜只填一局") }
        XCTAssertEqual(MatchScoring.check([21, 10, 15, 21, 21, 19], bo3), .winner(1))
        if case .winner = MatchScoring.check([21, 10, 21, 15, 21, 3], bo3) { XCTFail("前两局已经分出胜负") }
        XCTAssertEqual(MatchScoring.played([21, 10, 21, 15, 0, 0]), [21, 10, 21, 15])
        // 中途退赛：前面的局打完、最后一局可以没打完
        XCTAssertNil(MatchScoring.retireProblem([21, 10, 5, 3], bo3))
        XCTAssertNil(MatchScoring.retireProblem([], bo3))
        XCTAssertNotNil(MatchScoring.retireProblem([21, 10, 21, 5], bo3))
        XCTAssertNotNil(MatchScoring.retireProblem([5, 3, 21, 10], bo3))
        XCTAssertNotNil(MatchScoring.retireProblem([25, 3], deuce))
    }

    func testCountRulesPerFormat() {
        XCTAssertNil(MatchSetup.countProblem(format: .roundRobin, play: .singles, players: 2, pools: 2, advance: 1))
        XCTAssertNotNil(MatchSetup.countProblem(format: .roundRobin, play: .rotating, players: 3, pools: 2, advance: 1))
        XCTAssertNotNil(MatchSetup.countProblem(format: .roundRobin, play: .fixed, players: 5, pools: 2, advance: 1))
        XCTAssertNotNil(MatchSetup.countProblem(format: .swiss, play: .singles, players: 2, pools: 2, advance: 1))
        XCTAssertNil(MatchSetup.countProblem(format: .knockout, play: .singles, players: 6, pools: 2, advance: 1))
        // 2 组各出 2 人：每组至少 3 人
        XCTAssertNotNil(MatchSetup.countProblem(format: .groups, play: .singles, players: 5, pools: 2, advance: 2))
        XCTAssertNil(MatchSetup.countProblem(format: .groups, play: .singles, players: 6, pools: 2, advance: 2))
    }

    func testPayLinksCarryTheAmount() {
        XCTAssertEqual(FeeText.text(12), "$12")
        XCTAssertEqual(FeeText.text(12.5), "$12.50")
        XCTAssertEqual(PayLinks.cashApp("kevinw", amount: 12)?.absoluteString, "https://cash.app/$kevinw/12")
        XCTAssertEqual(PayLinks.payPal("kevinw", amount: 12.5)?.absoluteString, "https://paypal.me/kevinw/12.50USD")
        let venmo = PayLinks.venmo("kevin-w", amount: 12, note: "Badie · LABC")?.absoluteString ?? ""
        XCTAssertTrue(venmo.hasPrefix("https://venmo.com/kevin-w?txn=pay&amount=12&note="), venmo)
        XCTAssertEqual(PayLinks.board("AB12CD34")?.absoluteString, "https://badie.rsvp/live/AB12CD34/")
    }
}
