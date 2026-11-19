import Foundation

// MARK: - 正式后端：球群当晚的排场、比赛、收款
/// 都是直接调数据库函数，结果不进本地缓存：界面自己拿着最新一份，每 10 秒重拉。
/// 演示模式（没有服务器）时列表返回空，操作报“请先登录”
extension MockBackend {

    // MARK: 球群页、球局页

    /// 球群页的当天场次：排场、看排场、付钱、收款
    func remoteGroupTonight(_ groupId: String) async throws -> [GroupTonight] {
        guard let remote else { return [] }
        return try await remote.rpc("group_tonight", ["p_group": groupId], as: [GroupTonight].self)
    }

    /// 球局页最上面的“今晚”
    func remoteMyTonight() async throws -> [TonightItem] {
        guard let remote else { return [] }
        return try await remote.rpc("my_tonight", as: [TonightItem].self)
    }

    // MARK: 当晚

    /// 没权限时为 nil
    func remoteNightState(_ sessionId: String) async throws -> NightState? {
        guard let remote else { return nil }
        return try await remote.rpc("night_state", ["p_session": sessionId], as: NightState?.self)
    }

    func remoteNightSettings(_ sessionId: String, courts: Int, doubles: Bool, balance: Bool) async throws {
        try await requireRemote().call("night_settings", ["p_session": sessionId, "p_courts": courts, "p_doubles": doubles, "p_balance": balance])
    }

    func remoteNightStart(_ sessionId: String) async throws {
        try await requireRemote().call("night_start", ["p_session": sessionId])
    }

    /// 比赛打完，回到排场
    func remoteNightResume(_ sessionId: String) async throws {
        try await requireRemote().call("night_resume", ["p_session": sessionId])
    }

    /// 点名：signups 为 nil 是“全到了”；status 为 nil 是“没到”
    func remoteNightMark(_ sessionId: String, signups: [String]?, status: String?) async throws {
        try await requireRemote().call("night_mark", [
            "p_session": sessionId,
            "p_signups": signups.map { $0 as Any } ?? NSNull(),
            "p_status": status.map { $0 as Any } ?? NSNull(),
        ])
    }

    /// 现场加人（访客），返回报名 id
    @discardableResult
    func remoteNightAdd(_ sessionId: String, name: String) async throws -> String {
        try await requireRemote().rpc("night_add", ["p_session": sessionId, "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines)],
                                      as: String.self)
    }

    func remoteNightFinish(game: Int) async throws {
        try await requireRemote().call("night_finish", ["p_game": game])
    }

    func remoteNightSwap(game: Int, out: String, in replacement: String) async throws {
        try await requireRemote().call("night_swap", ["p_game": game, "p_out": out, "p_in": replacement])
    }

    /// next：放到下一场；false 是跳过（排到等候的最后）
    func remoteNightBump(_ signupId: String, next: Bool) async throws {
        try await requireRemote().call("night_bump", ["p_signup": signupId, "p_next": next])
    }

    func remoteNightUndo(_ sessionId: String) async throws {
        try await requireRemote().call("night_undo", ["p_session": sessionId])
    }

    func remoteNightHelpers(_ sessionId: String, users: [String]) async throws {
        try await requireRemote().call("night_helpers", ["p_session": sessionId, "p_users": users])
    }

    // MARK: 收款

    func remoteNightPay(_ sessionId: String) async throws -> NightPay {
        try await requireRemote().rpc("night_pay", ["p_session": sessionId], as: NightPay.self)
    }

    /// 每人多少钱（nil = 不填）
    func remoteSetSessionFee(_ sessionId: String, amount: Double?) async throws {
        try await requireRemote().call("set_session_fee", ["p_session": sessionId, "p_amount": amount.map { $0 as Any } ?? NSNull()])
    }

    func remoteMarkSignupPaid(_ signupId: String, paid: Bool) async throws {
        try await requireRemote().call("mark_signup_paid", ["p_signup": signupId, "p_paid": paid])
    }

    /// true 加回来，false 不用付
    func remoteSetSignupOwes(_ signupId: String, owes: Bool) async throws {
        try await requireRemote().call("set_signup_owes", ["p_signup": signupId, "p_owes": owes])
    }

    /// 返回提醒了几个人
    func remoteRemindUnpaid(_ sessionId: String) async throws -> Int {
        try await requireRemote().rpc("remind_unpaid", ["p_session": sessionId], as: Int.self)
    }

    /// 付钱的人自己点“我付了”（false 是改回来）
    func remoteIPaid(_ sessionId: String, paid: Bool) async throws {
        try await requireRemote().call("i_paid", ["p_session": sessionId, "p_paid": paid])
    }

    func remoteMyPaymentHandles() async throws -> PaymentHandles {
        guard let remote else { return PaymentHandles() }
        return try await remote.rpc("my_payment_handles", as: PaymentHandles.self)
    }

    /// 空字符串 = 不填
    func remoteSetPaymentHandles(_ handles: PaymentHandles) async throws {
        try await requireRemote().call("set_payment_handles", [
            "p_venmo": handles.venmo ?? "", "p_cashapp": handles.cashapp ?? "",
            "p_paypal": handles.paypal ?? "", "p_zelle": handles.zelle ?? "",
        ])
    }

    // MARK: 比赛

    func remoteMatchPreview(format: MatchFormat, players: Int, courts: Int, points: Int, bestOf: Int,
                            pools: Int?, advance: Int?, rounds: Int?) async throws -> MatchPreview? {
        guard let remote else { return nil }
        var args: [String: Any] = ["p_format": format.rawValue, "p_players": players, "p_courts": courts, "p_points": points,
                                   "p_best_of": bestOf, "p_doubles": false]
        if let pools { args["p_pools"] = pools }
        if let advance { args["p_advance"] = advance }
        if let rounds { args["p_rounds"] = rounds }
        return try await remote.rpc("match_preview", args, as: MatchPreview.self)
    }

    /// players：[{user_id} | {signup_id} | {name}]，按顺序是种子。返回比赛 id
    func remoteCreateMatch(name: String, venueId: String?, courts: Int, format: MatchFormat, points: Int, bestOf: Int,
                           winByTwo: Bool, players: [[String: Any]], rounds: Int?, pools: Int?, advance: Int?,
                           sessionId: String?) async throws -> String {
        var args: [String: Any] = [
            "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines), "p_venue": venueId.map { $0 as Any } ?? NSNull(),
            "p_courts": courts, "p_format": format.rawValue, "p_points": points, "p_best_of": bestOf,
            "p_win_by_two": winByTwo, "p_players": players,
        ]
        if let rounds { args["p_rounds"] = rounds }
        if let pools { args["p_pools"] = pools }
        if let advance { args["p_advance"] = advance }
        if let sessionId { args["p_session"] = sessionId }
        return try await requireRemote().rpc("create_match", args, as: String.self)
    }

    /// 没权限或已删掉时为 nil
    func remoteMatchState(_ matchId: String) async throws -> MatchState? {
        guard let remote else { return nil }
        return try await remote.rpc("match_state", ["p_match": matchId], as: MatchState?.self)
    }

    func remoteMatchScore(game: Int, scores: [Int], version: Int, force: Bool) async throws {
        try await requireRemote().call("match_score", ["p_game": game, "p_scores": scores, "p_version": version, "p_force": force])
    }

    func remoteMatchFlag(game: Int) async throws {
        try await requireRemote().call("match_flag", ["p_game": game])
    }

    func remoteMatchUndo(_ matchId: String) async throws {
        try await requireRemote().call("match_undo", ["p_match": matchId])
    }

    /// 退赛：给了 game 就这一场算对方赢；没打的场次取消
    func remoteMatchWithdraw(player: String, game: Int?) async throws {
        var args: [String: Any] = ["p_player": player]
        if let game { args["p_game"] = game }
        try await requireRemote().call("match_withdraw", args)
    }

    /// 只有双打轮换搭档能中途加人（访客，输名字）
    func remoteMatchAddPlayer(_ matchId: String, name: String) async throws {
        _ = try await requireRemote().rpc("match_add_player", ["p_match": matchId, "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines)],
                                          as: String.self)
    }

    func remoteMatchCourts(_ matchId: String, courts: Int) async throws {
        try await requireRemote().call("match_courts", ["p_match": matchId, "p_courts": courts])
    }

    func remoteMatchHelpers(_ matchId: String, users: [String]) async throws {
        try await requireRemote().call("match_helpers", ["p_match": matchId, "p_users": users])
    }

    /// 出线卡在并列上时，组织者选谁出线（key 按种子顺序）
    func remoteMatchQualify(_ matchId: String, keys: [String]) async throws {
        try await requireRemote().call("match_qualify", ["p_match": matchId, "p_keys": keys])
    }

    func remoteMatchEnd(_ matchId: String) async throws {
        try await requireRemote().call("match_end", ["p_match": matchId])
    }

    func remoteMatchDelete(_ matchId: String) async throws {
        try await requireRemote().call("match_delete", ["p_match": matchId])
    }

    func remoteMyMatches() async throws -> [MyMatch] {
        guard let remote else { return [] }
        return try await remote.rpc("my_matches", as: [MyMatch].self)
    }
}
