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

enum MatchFormat: String, CaseIterable, Identifiable {
    case singles, fixed, rotating, groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singles: return String(localized: "单打循环")
        case .fixed: return String(localized: "双打固定搭档")
        case .rotating: return String(localized: "双打轮换搭档")
        case .groups: return String(localized: "分组循环 + 决赛")
        }
    }

    /// 人数不对时（invalid_player_count）
    var playerCountRule: String {
        switch self {
        case .singles: return String(localized: "单打循环要 2–64 人。")
        case .fixed: return String(localized: "双打固定搭档要 4–64 人，而且是双数。")
        case .rotating: return String(localized: "双打轮换搭档要 4–64 人。")
        case .groups: return String(localized: "分组循环每组至少要 2 人。")
        }
    }

    static func title(_ raw: String) -> String { MatchFormat(rawValue: raw)?.title ?? raw }
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
        /// pool | semi | final
        let stage: String
        let pool: Int?
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
    var canManage: Bool { role == "organizer" || role == "helper" }
    var isOrganizer: Bool { role == "organizer" }

    func name(_ playerId: String) -> String { players.first { $0.id == playerId }?.name ?? "?" }

    func sideName(_ ids: [String]) -> String { ids.map { name($0) }.joined(separator: " · ") }

    /// 能不能输这一场的比分：组织者、帮手随时能改；球员只能在打的时候输自己那场
    func canScore(_ game: Game) -> Bool {
        if game.status == "cancelled" { return false }
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
    let status: String
    let createdAt: Date
    let endedAt: Date?
    let players: Int
    let rank: Int?
}

/// 新建比赛前的预计（match_preview）
struct MatchPreview: Decodable, Equatable {
    let fullRounds: Int
    let rounds: Int
    let minutes: Double
}

// MARK: - 金额和付款链接

enum FeeText {
    /// $12、$12.50（只有美元）
    static func text(_ amount: Double) -> String {
        "$" + plain(amount)
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
