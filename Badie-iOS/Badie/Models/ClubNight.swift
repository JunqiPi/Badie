import Foundation

// MARK: - 球群当晚：排场、比赛、收款（服务器的 JSON，见 docs/CLUB_NIGHT.md 的“接口”）
// 字段名按 RemoteJSON 的规则从 snake_case 转过来；服务器可能给 null 的都写成可选

/// 收款方式：都可以不填
struct PaymentHandles: Codable, Equatable {
    var venmo: String?
    var cashapp: String?
    var paypal: String?
    var zelle: String?

    var isEmpty: Bool { [venmo, cashapp, paypal, zelle].allSatisfy { ($0 ?? "").isEmpty } }
}

/// 帮手（当晚或比赛）
struct NightHelper: Decodable, Equatable, Identifiable {
    let id: String
    let nickname: String
}

/// 当晚页（night_state）：只有组织者和帮手拿得到
struct NightState: Decodable, Equatable {
    struct Person: Decodable, Equatable, Identifiable {
        /// 报名那一行的 id（访客也有）
        let id: String
        let name: String
        let userId: String?
        let guest: Bool
        /// absent | here | resting | left
        let status: String
        let waitlisted: Bool
        let games: Int
        /// 在哪片场地上打（不在场上为 nil）
        let onCourt: Int?
        let nextUp: Bool
        /// 等候的人排第几（和排人的顺序一样；不在等候为 nil）
        let queue: Int?
    }

    struct Game: Decodable, Equatable, Identifiable {
        let id: Int
        let court: Int
        /// 报名 id；双打前两个一队
        let players: [String]
        let startedAt: Date
    }

    let sessionId: String
    let groupId: String
    let group: String
    let venue: String?
    let startsAt: Date
    let endsAt: Date
    /// organizer | helper
    let role: String
    /// 开场前 1 小时到结束后 3 小时：能改排场
    let open: Bool
    let started: Bool
    let courts: Int
    let doubles: Bool
    let balance: Bool
    let boardCode: String?
    let matchId: String?
    let matchLive: Bool
    let helpers: [NightHelper]
    let undoUntil: Date?
    let people: [Person]
    let games: [Game]
    /// 接下来两场（报名 id）
    let next: [[String]]

    var isOrganizer: Bool { role == "organizer" }

    func person(_ id: String) -> Person? { people.first { $0.id == id } }

    func name(_ id: String) -> String { person(id)?.name ?? "?" }

    /// 一场的两边：双打前两个一队
    func sides(_ players: [String]) -> (a: [String], b: [String]) {
        let half = players.count / 2
        return (Array(players.prefix(half)), Array(players.dropFirst(half)))
    }

    /// 到了、不在场上的人，按排队的顺序（旧数据没有顺序时：手动放到下一场的在前，再按今晚打的场数）
    var waiting: [Person] {
        let list = people.enumerated().filter { $0.element.status == "here" && $0.element.onCourt == nil }
        return list.sorted { lhs, rhs in
            if let left = lhs.element.queue, let right = rhs.element.queue { return left < right }
            if lhs.element.nextUp != rhs.element.nextUp { return lhs.element.nextUp }
            if lhs.element.games != rhs.element.games { return lhs.element.games < rhs.element.games }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    var hereCount: Int { people.filter { $0.status == "here" }.count }

    /// 要显示的场地：设置的几片，加上减场地后还没打完的
    var courtNumbers: [Int] {
        Array(Set(Array(1...max(1, courts)) + games.map(\.court))).sorted()
    }
}

/// 当晚 → 收款（night_pay，只有组织者）
struct NightPay: Decodable, Equatable {
    struct Person: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let guest: Bool
        let status: String?
        /// 访客留了邮箱（能收提醒邮件）
        let email: Bool?
        let owes: Bool
        let paid: Bool
        let paidSelf: Bool?
    }

    let amount: Double?
    let amountSet: Bool?
    let payee: String?
    let payeeIsMe: Bool?
    let hasHandles: Bool?
    let remindedAt: Date?
    let canRemind: Bool?
    let people: [Person]

    var owing: [Person] { people.filter { $0.owes } }
    var unpaid: [Person] { owing.filter { !$0.paid } }
    var paid: [Person] { people.filter { $0.paid } }
    /// 不用付的（报了名没来、组织者点了不用付）
    var exempt: [Person] { people.filter { !$0.owes && !$0.paid } }
}

/// 球群页的当天场次（group_tonight）
struct GroupTonight: Decodable, Equatable, Identifiable {
    struct Pay: Decodable, Equatable {
        let to: String
        let amount: Double?
        let handles: PaymentHandles?
        let paid: Bool
        let paidSelf: Bool?
    }

    let id: String
    let startsAt: Date
    let endsAt: Date
    /// 组织者、帮手显示“排场”
    let canRun: Bool?
    /// 排场开始后的看板码：成员的“看排场”
    let board: String?
    /// 我要付的钱
    let pay: Pay?
    /// 组织者：还有几个人没付
    let unpaid: Int?
}

/// 我还没付的一场（my_dues）：开过的、写了金额的场次，60 天内
struct MyDue: Decodable, Equatable, Identifiable {
    let sessionId: String
    let groupId: String
    let group: String
    let startsAt: Date
    let endsAt: Date
    let tz: String?
    let amount: Double
    let to: String
    let toId: String
    let handles: PaymentHandles?

    var id: String { sessionId }
}

/// 收款记录（group_ledger，只有组织者）：开过的场次（新的在前），第一页还有谁还欠着
struct GroupLedger: Decodable, Equatable {
    struct Session: Decodable, Equatable, Identifiable {
        let id: String
        let startsAt: Date
        let endsAt: Date
        let venue: String
        let tz: String?
        let amount: Double?
        let payee: String?
        /// 要付几人、付了几人
        let owes: Int
        let paid: Int
    }

    /// 谁还欠着：注册用户按人、访客按名字合起来；signups 是那几行报名
    struct Owed: Decodable, Equatable, Identifiable {
        let userId: String?
        let name: String
        let guest: Bool
        let sessions: Int
        let amount: Double
        let signups: [String]

        var id: String { userId ?? "guest:" + name.lowercased() }

        enum CodingKeys: String, CodingKey {
            case userId = "id"
            case name, guest, sessions, amount, signups
        }
    }

    /// 一页几场；少于这个数就是翻到头了
    static let pageSize = 20

    let sessions: [Session]
    let owed: [Owed]?
}

/// 导出成表格的一行（group_ledger_rows）
struct LedgerRow: Decodable, Equatable {
    let startsAt: Date
    let tz: String?
    let venue: String
    let name: String
    let guest: Bool
    let amount: Double?
    let owes: Bool
    let paidAt: Date?
    let paidSelf: Bool
}

/// 球局页最上面的“今晚”（my_tonight）
struct TonightItem: Decodable, Equatable, Identifiable {
    /// night | match
    let kind: String
    let sessionId: String?
    let groupId: String?
    let matchId: String?
    let name: String
    let boardCode: String?
    /// court | next | waiting | resting
    let status: String
    let court: Int?
    let round: Int?
    let games: Int?

    var id: String { sessionId ?? matchId ?? name }
}

// MARK: - 比赛

/// 赛制：循环 / 小组赛 + 淘汰赛 / 瑞士轮 / 单淘汰
enum MatchFormat: String, CaseIterable, Identifiable {
    case roundRobin = "round_robin", groups, swiss, knockout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roundRobin: return String(localized: "循环赛")
        case .groups: return String(localized: "小组赛 + 淘汰赛")
        case .swiss: return String(localized: "瑞士轮")
        case .knockout: return String(localized: "单淘汰")
        }
    }

    /// 自己定打几轮的：循环、瑞士轮
    var byRounds: Bool { self == .roundRobin || self == .swiss }
    /// 有淘汰赛的：可以打三四名
    var hasKnockout: Bool { self == .groups || self == .knockout }

    /// “循环赛 · 单打”；轮换搭档只有循环，就写“双打轮换搭档”
    static func title(_ format: String, play: String?) -> String {
        if play == MatchPlay.rotating.rawValue { return MatchPlay.rotating.title }
        let name = MatchFormat(rawValue: format)?.title ?? format
        guard let play = play.flatMap(MatchPlay.init(rawValue:)) else { return name }
        return "\(name) · \(play.title)"
    }
}

/// 参赛方式：单打 / 双打固定搭档 / 双打轮换搭档（只配循环）
enum MatchPlay: String, CaseIterable, Identifiable {
    case singles, fixed, rotating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singles: return String(localized: "单打")
        case .fixed: return String(localized: "双打固定搭档")
        case .rotating: return String(localized: "双打轮换搭档")
        }
    }
}

enum MatchSetup {
    /// 人数够不够这个赛制：不够时返回给人看的话（服务器还会再查一次）
    static func countProblem(format: MatchFormat, play: MatchPlay, players: Int, pools: Int, advance: Int) -> String? {
        let per = play == .fixed ? 2 : 1
        let entries = players / per
        if players > 64 || players < 2 { return String(localized: "要 2–64 人。") }
        if play == .rotating && players < 4 { return String(localized: "双打轮换搭档要 4–64 人。") }
        if play == .fixed && (players < 4 || players % 2 == 1) { return String(localized: "双打固定搭档要 4–64 人，而且是双数。") }
        if format == .swiss && entries < 3 { return String(localized: "瑞士轮至少要 \(3 * per) 人。") }
        if format == .groups && entries < pools * (advance + 1) {
            return String(localized: "\(pools) 组至少要 \(pools * (advance + 1) * per) 人。")
        }
        return nil
    }
}

/// 比分规则（和服务器的 score_winner、retire_scores_ok 一样）
enum MatchScoring {
    enum Check: Equatable {
        /// 还没填
        case empty
        case winner(Int)
        case problem(String)
    }

    struct Rules {
        let points: Int
        let bestOf: Int
        let winByTwo: Bool
    }

    /// 加分时打到几封顶：21 → 30、15 → 21、11 → 15
    static func cap(_ points: Int) -> Int { [21: 30, 15: 21, 11: 15][points] ?? points }

    static func gameDone(_ hi: Int, _ lo: Int, _ rules: Rules) -> Bool {
        guard lo >= 0, hi > lo else { return false }
        if !rules.winByTwo { return hi == rules.points }
        let top = cap(rules.points)
        return (hi == rules.points && lo <= rules.points - 2) || (hi > rules.points && hi <= top && (hi - lo == 2 || (hi == top && lo == hi - 1)))
    }

    /// 打得出来、但还没打完的一局
    static func unfinished(_ hi: Int, _ lo: Int, _ rules: Rules) -> Bool {
        hi < rules.points || (rules.winByTwo && lo >= rules.points - 1 && hi - lo <= 1 && hi < cap(rules.points))
    }

    /// 去掉后面没填的局（0–0）
    static func played(_ scores: [Int]) -> [Int] {
        var end = scores.count
        while end >= 2 && scores[end - 1] == 0 && scores[end - 2] == 0 { end -= 2 }
        return Array(scores.prefix(end))
    }

    /// 一局不合规时说哪里不对
    static func gameProblem(_ a: Int, _ b: Int, game: Int, _ rules: Rules) -> String {
        let hi = max(a, b), lo = min(a, b)
        let score = "\(a)–\(b)"
        let text: String
        if unfinished(hi, lo, rules) {
            text = String(localized: "\(score) 还没打完。")
        } else if rules.winByTwo {
            text = String(localized: "\(score) 打不出来：\(rules.points) 分一局，要领先 2 分，最多到 \(cap(rules.points))。")
        } else {
            text = String(localized: "\(score) 打不出来：一局打到 \(rules.points) 分就结束。")
        }
        return rules.bestOf == 1 ? text : String(localized: "第 \(game) 局：\(text)")
    }

    /// 输的比分（已经去掉了后面没填的局）：合规就是赢的一边
    static func check(_ scores: [Int], _ rules: Rules) -> Check {
        if scores.isEmpty { return .empty }
        let need = rules.bestOf / 2 + 1
        var wins = [0, 0]
        for game in 0..<(scores.count / 2) {
            if wins[0] == need || wins[1] == need { return .problem(String(localized: "前两局已经分出胜负，第 3 局不用填。")) }
            let a = scores[game * 2], b = scores[game * 2 + 1]
            guard gameDone(max(a, b), min(a, b), rules) else { return .problem(gameProblem(a, b, game: game + 1, rules)) }
            wins[a > b ? 0 : 1] += 1
        }
        if wins[0] < need && wins[1] < need { return .problem(String(localized: "三局两胜，要有一边赢满两局。")) }
        return .winner(wins[0] == need ? 1 : 2)
    }

    /// 中途退赛的比分：前面的局打完了、还没分出胜负，最后一局可以没打完。合规是 nil
    static func retireProblem(_ scores: [Int], _ rules: Rules) -> String? {
        let need = rules.bestOf / 2 + 1
        var wins = [0, 0]
        let games = scores.count / 2
        for game in 0..<games {
            let a = scores[game * 2], b = scores[game * 2 + 1]
            if gameDone(max(a, b), min(a, b), rules) {
                wins[a > b ? 0 : 1] += 1
            } else if game < games - 1 || !unfinished(max(a, b), min(a, b), rules) {
                return gameProblem(a, b, game: game + 1, rules)
            }
        }
        if wins[0] >= need || wins[1] >= need { return String(localized: "已经分出胜负了，直接保存比分就行。") }
        return nil
    }
}

/// 比赛页（match_state）
struct MatchState: Decodable, Equatable {
    struct Player: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let team: Int?
        let pool: Int?
        let withdrawn: Bool
        /// 注册用户（只有组织者、帮手拿得到）
        let userId: String?
    }

    struct Game: Decodable, Equatable, Identifiable {
        let id: Int
        let round: Int
        /// pool | ko（淘汰赛，koSize 是这一轮的签位数：2 = 决赛）| third（三四名）
        let stage: String
        let pool: Int?
        let koSize: Int?
        let slot: Int?
        /// 轮空：不是一场球，不显示
        let bye: Bool?
        /// 中途退赛的一边（1 / 2）
        let retired: Int?
        let a: [String]
        let b: [String]
        let court: Int?
        /// queued | playing | done | cancelled | skipped
        let status: String
        /// 每局两个数：[a1, b1, a2, b2, …]
        let scores: [Int]?
        let winner: Int?
        let walkover: Bool?
        let version: Int?
        let scoredBy: String?
        let editedBy: String?
        let flagged: Bool?
    }

    /// 积分榜、最终排名的一行：一个人或一队
    struct Standing: Decodable, Equatable, Identifiable {
        let key: String
        let name: String
        let members: [String]
        let pool: Int?
        let played: Int
        let wins: Int
        let losses: Int
        let pf: Int
        let pa: Int
        let diff: Int
        let rank: Int
        let tied: Bool?
        let withdrawn: Bool?

        var id: String { key }
    }

    let id: String
    let name: String
    let format: String
    let play: String?
    let thirdPlace: Bool?
    let doubles: Bool
    let points: Int
    let bestOf: Int
    let winByTwo: Bool
    let courts: Int
    let rounds: Int
    let round: Int?
    let pools: Int?
    let advance: Int?
    /// live | done
    let status: String
    let createdAt: Date
    let endedAt: Date?
    let boardCode: String
    let sessionId: String?
    let venue: String?
    let tieAtCut: Bool?
    let players: [Player]
    let games: [Game]
    let standings: [Standing]
    let ranking: [Standing]?
    /// organizer | helper | player
    let role: String?
    /// 我在这场比赛里的球员 id
    let me: String?
    let helpers: [NightHelper]?
    let undoUntil: Date?

    var isLive: Bool { status == "live" }
    /// 轮空不是一场球
    var realGames: [Game] { games.filter { $0.bye != true } }
    var matchFormat: MatchFormat { MatchFormat(rawValue: format) ?? .roundRobin }
    var scoring: MatchScoring.Rules { MatchScoring.Rules(points: points, bestOf: bestOf, winByTwo: winByTwo) }
    var canManage: Bool { role == "organizer" || role == "helper" }
    var isOrganizer: Bool { role == "organizer" }

    func name(_ playerId: String) -> String { players.first { $0.id == playerId }?.name ?? "?" }

    func sideName(_ ids: [String]) -> String { ids.map { name($0) }.joined(separator: " · ") }

    /// 能不能输这一场的比分：组织者、帮手随时能改；球员只能在打的时候输自己那场
    func canScore(_ game: Game) -> Bool {
        if game.status == "cancelled" || game.bye == true { return false }
        if canManage { return isLive || game.status == "done" }
        guard let me else { return false }
        return game.status == "playing" && (game.a.contains(me) || game.b.contains(me))
    }

    func isMine(_ game: Game) -> Bool {
        guard let me else { return false }
        return game.a.contains(me) || game.b.contains(me)
    }
}

/// 我的 → 比赛（my_matches）
struct MyMatch: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let format: String
    let play: String?
    let status: String
    let createdAt: Date
    let endedAt: Date?
    let players: Int
    let rank: Int?
}

/// 新建比赛前的预计（match_preview）
struct MatchPreview: Decodable, Equatable {
    /// 循环打满一遍的轮数
    let fullRounds: Int
    /// 能选几轮：默认、最多
    let defaultRounds: Int
    let maxRounds: Int
    let rounds: Int
    let minutes: Double
}

// MARK: - 金额和付款链接

enum FeeText {
    /// $12、$12.50（只有美元）
    static func text(_ amount: Double) -> String {
        "$" + plain(amount)
    }

    /// 每场的价格：0 写“免费”，nil 不写
    static func price(_ price: Double?) -> String? {
        guard let price else { return nil }
        return price == 0 ? String(localized: "免费") : String(localized: "每人 \(text(price))")
    }

    /// 12、12.50：链接里用
    static func plain(_ amount: Double) -> String {
        let cents = Int((amount * 100).rounded())
        if cents % 100 == 0 { return String(cents / 100) }
        return String(format: "%d.%02d", cents / 100, cents % 100)
    }
}

enum PayLinks {
    static func venmo(_ name: String, amount: Double?, note: String) -> URL? {
        var components = URLComponents(string: "https://venmo.com/")
        components?.path = "/" + name
        var items = [URLQueryItem(name: "txn", value: "pay")]
        if let amount { items.append(URLQueryItem(name: "amount", value: FeeText.plain(amount))) }
        items.append(URLQueryItem(name: "note", value: note))
        components?.queryItems = items
        return components?.url
    }

    static func cashApp(_ name: String, amount: Double?) -> URL? {
        let base = "https://cash.app/$" + name
        return URL(string: amount.map { base + "/" + FeeText.plain($0) } ?? base)
    }

    static func payPal(_ name: String, amount: Double?) -> URL? {
        let base = "https://paypal.me/" + name
        return URL(string: amount.map { base + "/" + FeeText.plain($0) + "USD" } ?? base)
    }

    /// 公开看板：/live/<码>/
    static func board(_ code: String) -> URL? {
        URL(string: "https://badie.rsvp/live/\(code)/")
    }
}
