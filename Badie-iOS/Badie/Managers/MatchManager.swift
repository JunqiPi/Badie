import Foundation
import Combine
import SwiftUI

// MARK: - 匹配草稿（快速匹配设置）

struct MatchDraft: Equatable {
    var mode: GameMode = .singles
    var day: Date = Calendar.current.startOfDay(for: Date())
    /// 从 0 点起的分钟数
    var startMinutes: Int = 19 * 60
    var endMinutes: Int = 21 * 60
    var courtIds: [String] = []
    /// 1、2 或 8(不限)
    var skillTolerance: Int = 1
    /// 符合条件的提议直接替我接受（默认关闭）
    var autoAccept = false

    static let maxCourts = 3

    var slot: TimeSlot? {
        TimeSlot.on(day, startHour: startMinutes / 60, startMinute: startMinutes % 60,
                    endHour: endMinutes / 60, endMinute: endMinutes % 60)
    }

    var validation: TimeSlotValidationResult {
        guard let slot else { return .invalid(reason: "时间无效") }
        return slot.validate()
    }

    var canSearch: Bool { validation.isValid && !courtIds.isEmpty }

    mutating func toggleCourt(_ id: String) -> Bool {
        if let index = courtIds.firstIndex(of: id) {
            courtIds.remove(at: index)
            return true
        }
        guard courtIds.count < Self.maxCourts else { return false }
        courtIds.append(id)
        return true
    }

    mutating func apply(_ slot: TimeSlot) {
        let calendar = Calendar.current
        day = calendar.startOfDay(for: slot.startTime)
        startMinutes = calendar.component(.hour, from: slot.startTime) * 60 + calendar.component(.minute, from: slot.startTime)
        let endDay = calendar.startOfDay(for: slot.endTime)
        endMinutes = endDay > day ? 24 * 60 : calendar.component(.hour, from: slot.endTime) * 60 + calendar.component(.minute, from: slot.endTime)
    }
}

// MARK: - 匹配与球局管理
//
// 快速约球是一个“请求”：提交后挂在后台持续匹配，找到人发提议，所有人确认才成局。
// 全屏流程只是查看某个请求的窗口，关掉不影响请求。

@MainActor
final class MatchManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// 正在提交请求（搜索动画）
        case submitting
        case failed(String)
    }

    @Published var draft = MatchDraft()
    @Published private(set) var phase: Phase = .idle
    /// 我的约球请求（进行中 + 最近结束）
    @Published private(set) var tickets: [MatchTicket] = []
    /// 请求对应的提议（按提议 ID）
    @Published private(set) var offers: [String: MatchOffer] = [:]
    /// 全屏流程正在查看的请求
    @Published private(set) var flowTicketId: String?
    @Published private(set) var suggestions: [MatchRelaxation] = []
    @Published private(set) var isResponding = false
    /// 全屏匹配流程是否展示
    @Published var isFlowPresented = false
    @Published private(set) var games: [Game] = []
    /// 流程外的进展提示（约成了 / 等你确认）
    @Published var notice: String?

    private let backend: MockBackend
    private var submitTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    /// 搜索动画最短展示时间
    var minimumSearchDuration: TimeInterval = 1.8
    /// 定时处理确认超时、锁定与再匹配的间隔
    static let processingInterval: TimeInterval = 15

    init(backend: MockBackend) {
        self.backend = backend
        reloadGames()
        reloadMatchmaking(announce: false)
        draft.apply(TimeSlot.suggestedDefault())
        backend.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case .gamesChanged, .gameCreated:
                self.reloadGames()
            case .sessionChanged:
                self.reloadGames()
                self.flowTicketId = nil
                self.reloadMatchmaking(announce: false)
            case .matchmakingChanged:
                self.reloadMatchmaking(announce: true)
            default:
                break
            }
        }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.processingInterval * 1_000_000_000))
                guard let self else { return }
                self.backend.processMatchmaking()
            }
        }
    }

    // MARK: Games

    var upcomingGames: [Game] {
        games.filter { $0.isUpcoming() }.sorted { $0.slot.startTime < $1.slot.startTime }
    }

    var pastGames: [Game] {
        games.filter { !$0.isUpcoming() }.sorted { $0.slot.startTime > $1.slot.startTime }
    }

    var nextGame: Game? { upcomingGames.first }

    func game(id: String) -> Game? { games.first { $0.id == id } ?? backend.game(id: id) }

    func reloadGames() {
        games = backend.games()
    }

    func user(id: String) -> User? { backend.user(id: id) }

    // MARK: Tickets

    /// 进行中或暂停的请求（首页/球局页展示）
    var openTickets: [MatchTicket] {
        tickets.filter { $0.isActive || $0.status == .paused }
    }

    var flowTicket: MatchTicket? {
        guard let flowTicketId else { return nil }
        return tickets.first { $0.id == flowTicketId } ?? backend.ticket(id: flowTicketId)
    }

    /// 请求当前的提议；已成局的请求返回成局的那个提议
    func offer(for ticket: MatchTicket) -> MatchOffer? {
        if let id = ticket.offerId { return offers[id] ?? backend.offer(id: id) }
        if let gameId = ticket.gameId { return backend.offer(forGameId: gameId) }
        return nil
    }

    func poolSummary(for ticket: MatchTicket) -> (available: Int, compatible: Int) {
        backend.poolSummary(for: ticket.id)
    }

    /// 重新读取请求与提议（不弹提示）
    func reloadTickets() {
        reloadMatchmaking(announce: false)
    }

    private func reloadMatchmaking(announce: Bool) {
        let previous = Dictionary(uniqueKeysWithValues: tickets.map { ($0.id, $0.status) })
        tickets = backend.myTickets()
        var map: [String: MatchOffer] = [:]
        for ticket in tickets {
            if let offer = offer(forFresh: ticket) { map[offer.id] = offer }
        }
        offers = map
        if let ticket = flowTicket, ticket.status == .searching {
            suggestions = backend.suggestions(for: ticket.id)
        }
        guard announce else { return }
        for ticket in tickets where previous[ticket.id] != nil && previous[ticket.id] != ticket.status {
            let isShowing = isFlowPresented && flowTicketId == ticket.id
            switch ticket.status {
            case .matched:
                Haptics.success()
                if !isShowing { notice = "约成了！\(ticket.slot.formattedFull)" }
            case .offered(let offerId):
                if map[offerId]?.seat(of: ticket.userId)?.response == .pending {
                    Haptics.impact()
                    if !isShowing { notice = "找到搭子了，去确认吧" }
                }
            default:
                break
            }
        }
    }

    private func offer(forFresh ticket: MatchTicket) -> MatchOffer? {
        if let id = ticket.offerId { return backend.offer(id: id) }
        if let gameId = ticket.gameId { return backend.offer(forGameId: gameId) }
        return nil
    }

    // MARK: Draft

    /// 准备默认草稿：首次使用常用时间/偏好模式，并预选常去球馆（其次最近的球馆）
    /// - Parameter favorites: 常去球馆 ID（已按距离排序；不受出行范围限制）
    /// - Parameter isValidCourt: 球馆是否仍在球馆库中
    func prepareDraft(user: User?, nearbyCourts: [BadmintonCourt], recurring: [RecurringTimeSlot], favorites: [String],
                      isValidCourt: (String) -> Bool = { _ in true }) {
        if let mode = user?.preferredMode, draft.courtIds.isEmpty { draft.mode = mode }
        if draft.validation.isValid == false {
            if let next = recurring.activeSlots.compactMap({ $0.nextOccurrence() }).min(by: { $0.startTime < $1.startTime }) {
                draft.apply(next)
            } else {
                draft.apply(TimeSlot.suggestedDefault())
            }
        }
        draft.courtIds = draft.courtIds.filter(isValidCourt)
        if draft.courtIds.isEmpty {
            let preferred = favorites.filter(isValidCourt)
            let fallback = nearbyCourts.map(\.id)
            draft.courtIds = Array((preferred + fallback.filter { !preferred.contains($0) }).prefix(2))
        }
    }

    // MARK: Flow

    /// 提交约球请求并打开流程
    func startSearch(user: User, location: Coordinate, courts: [BadmintonCourt], radiusKm: Double) {
        guard let slot = draft.slot else { return }
        let courtIds = courts.map(\.id).filter { draft.courtIds.contains($0) }
        let snapshot = draft
        submitTask?.cancel()
        suggestions = []
        flowTicketId = nil
        isFlowPresented = true
        withAnimation(AppTheme.Motion.standard) { phase = .submitting }
        let minimum = minimumSearchDuration
        submitTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            let outcome: Result<MatchTicket, Error>
            do {
                outcome = .success(try await self.backend.submitTicket(
                    mode: snapshot.mode, slot: slot, courtIds: courtIds, skillTolerance: snapshot.skillTolerance,
                    radiusKm: radiusKm, origin: location, autoAccept: snapshot.autoAccept))
            } catch {
                outcome = .failure(error)
            }
            let remaining = minimum - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                // 动画期间用户关掉了：请求照常保留
                return
            }
            withAnimation(AppTheme.Motion.standard) {
                switch outcome {
                case .success(let ticket):
                    self.flowTicketId = ticket.id
                    self.reloadMatchmaking(announce: false)
                    self.phase = .idle
                    if ticket.offerId != nil { Haptics.impact() }
                case .failure(let error):
                    self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "没能发起请求，请重试")
                }
            }
        }
    }

    /// 打开某个请求（首页卡片、通知）
    func openTicket(_ id: String) {
        guard backend.ticket(id: id) != nil else { return }
        submitTask?.cancel()
        flowTicketId = id
        phase = .idle
        reloadMatchmaking(announce: false)
        isFlowPresented = true
    }

    /// 关掉流程（请求继续在后台匹配）
    func closeFlow() {
        if phase == .submitting {
            // 还没拿到请求 ID 时关闭：等提交完成后照常保留请求
            submitTask = nil
        }
        isFlowPresented = false
        phase = .idle
    }

    /// 放宽条件后继续找（同一个请求）
    func apply(_ relaxation: MatchRelaxation) {
        guard let ticket = flowTicket, let me = backend.currentUser else { return }
        let next = relaxation.apply(to: backend.matchRequest(for: ticket, owner: me))
        do {
            try backend.updateTicket(ticket.id, slot: next.slot, skillTolerance: next.skillTolerance, radiusKm: next.radiusKm)
            draft.skillTolerance = next.skillTolerance
            draft.apply(next.slot)
            reloadMatchmaking(announce: false)
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "调整失败")
        }
    }

    /// 接受 / 拒绝当前提议
    func respond(accept: Bool) async {
        guard let ticket = flowTicket, let offerId = ticket.offerId else { return }
        isResponding = true
        defer { isResponding = false }
        do {
            try await backend.respond(toOffer: offerId, accept: accept)
            reloadMatchmaking(announce: false)
            if accept { Haptics.success() }
        } catch {
            reloadMatchmaking(announce: false)
            notice = (error as? LocalizedError)?.errorDescription
        }
    }

    func cancelTicket(_ id: String) {
        backend.cancelTicket(id)
        reloadMatchmaking(announce: false)
        if flowTicketId == id { closeFlow() }
    }

    func resumeTicket(_ id: String) {
        do {
            try backend.resumeTicket(id)
            reloadMatchmaking(announce: false)
        } catch {
            notice = (error as? LocalizedError)?.errorDescription
        }
    }

    /// 到点没约成：用同样的条件转成临时局（只找附近此刻在找人的球友）
    func retryAsLastMinute(_ ticket: MatchTicket) {
        submitTask?.cancel()
        withAnimation(AppTheme.Motion.standard) { phase = .submitting }
        submitTask = Task { [weak self] in
            guard let self else { return }
            do {
                let next = try await self.backend.submitTicket(
                    mode: ticket.mode, slot: ticket.slot, courtIds: ticket.courtIds, skillTolerance: ticket.skillTolerance,
                    radiusKm: ticket.radiusKm, origin: ticket.origin, autoAccept: true)
                self.flowTicketId = next.id
                self.reloadMatchmaking(announce: false)
                withAnimation(AppTheme.Motion.standard) { self.phase = .idle }
            } catch {
                withAnimation(AppTheme.Motion.standard) {
                    self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "没能发起请求")
                }
            }
        }
    }

    // MARK: Game actions

    func cancel(_ game: Game) async throws {
        try await backend.cancelGame(id: game.id)
        ReminderService.cancel(gameId: game.id)
        reloadGames()
    }

    func checkIn(_ game: Game) async throws {
        _ = try await backend.checkIn(gameId: game.id)
        reloadGames()
    }

    func togglePaid(_ game: Game, userId: String) {
        backend.togglePaid(gameId: game.id, userId: userId)
    }

    func complete(_ game: Game, didWin: Bool?, score: String) async throws {
        try await backend.completeGame(id: game.id, didWin: didWin, score: score)
        ReminderService.cancel(gameId: game.id)
        reloadGames()
    }

    /// 开关提醒；返回是否成功（未授权通知时返回 false）
    func setReminder(_ game: Game, enabled: Bool) async -> Bool {
        if enabled {
            let scheduled = await ReminderService.schedule(for: game)
            guard scheduled > 0 else { return false }
        } else {
            ReminderService.cancel(gameId: game.id)
        }
        backend.setReminder(gameId: game.id, enabled: enabled)
        return true
    }

    /// 首页日期条：某天附近有空的人数
    func availableCount(on day: Date, radiusKm: Double) -> Int {
        backend.availableCount(on: day, radiusKm: radiusKm)
    }
}
