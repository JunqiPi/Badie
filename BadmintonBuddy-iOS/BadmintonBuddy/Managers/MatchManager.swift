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

@MainActor
final class MatchManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case searching
        case results
        case empty
        case failed(String)
    }

    @Published var draft = MatchDraft()
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var proposals: [MatchProposal] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var suggestions: [MatchRelaxation] = []
    @Published private(set) var isConfirming = false
    /// 全屏匹配流程是否展示
    @Published var isFlowPresented = false
    @Published private(set) var games: [Game] = []
    /// 新确认的球局（用于跳转详情）
    @Published var justConfirmedGame: Game?

    private let backend: MockBackend
    private var searchTask: Task<Void, Never>?
    private var lastRequest: MatchRequest?
    private var declinedIds = Set<String>()
    /// 搜索动画最短展示时间
    var minimumSearchDuration: TimeInterval = 2.4

    init(backend: MockBackend) {
        self.backend = backend
        reloadGames()
        draft.apply(TimeSlot.suggestedDefault())
        backend.subscribe { [weak self] event in
            switch event {
            case .gamesChanged, .sessionChanged, .gameCreated:
                self?.reloadGames()
            default:
                break
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

    // MARK: Search flow

    var currentProposal: MatchProposal? {
        proposals.indices.contains(currentIndex) ? proposals[currentIndex] : nil
    }

    /// 准备默认草稿：首次使用常用时间/偏好模式，并预选最近的球馆
    func prepareDraft(user: User?, nearbyCourts: [BadmintonCourt], recurring: [RecurringTimeSlot], favorites: [String]) {
        if let mode = user?.preferredMode, draft.courtIds.isEmpty { draft.mode = mode }
        if draft.validation.isValid == false {
            if let next = recurring.activeSlots.compactMap({ $0.nextOccurrence() }).min(by: { $0.startTime < $1.startTime }) {
                draft.apply(next)
            } else {
                draft.apply(TimeSlot.suggestedDefault())
            }
        }
        let available = Set(nearbyCourts.map(\.id))
        draft.courtIds = draft.courtIds.filter { available.contains($0) }
        if draft.courtIds.isEmpty {
            let preferred = favorites.filter { available.contains($0) }
            let fallback = nearbyCourts.map(\.id)
            draft.courtIds = Array((preferred + fallback.filter { !preferred.contains($0) }).prefix(2))
        }
    }

    func startSearch(user: User, location: Coordinate, courts: [BadmintonCourt], radiusKm: Double) {
        guard let slot = draft.slot else { return }
        let selected = courts.filter { draft.courtIds.contains($0.id) }
        let request = MatchRequest(
            mode: draft.mode,
            slot: slot,
            courts: selected,
            skillTolerance: draft.skillTolerance,
            userId: user.id,
            userLevel: user.displayLevel,
            userLocation: location,
            radiusKm: radiusKm,
            excludedUserIds: []
        )
        declinedIds = []
        run(request)
    }

    func apply(_ relaxation: MatchRelaxation) {
        guard let request = lastRequest else { return }
        let next = relaxation.apply(to: request)
        draft.skillTolerance = next.skillTolerance
        draft.apply(next.slot)
        run(next)
    }

    private func run(_ request: MatchRequest) {
        searchTask?.cancel()
        lastRequest = request
        proposals = []
        suggestions = []
        currentIndex = 0
        isFlowPresented = true
        withAnimation(AppTheme.Motion.standard) { phase = .searching }
        let minimum = minimumSearchDuration
        searchTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            let outcome: Result<MatchSearchResult, Error>
            do {
                outcome = .success(try await self.backend.findMatches(request))
            } catch {
                outcome = .failure(error)
            }
            let remaining = minimum - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled, self.phase == .searching else { return }
            withAnimation(AppTheme.Motion.standard) {
                switch outcome {
                case .success(.proposals(let found)):
                    self.proposals = found
                    self.phase = .results
                    Haptics.impact()
                case .success(.none(let suggestions)):
                    self.suggestions = suggestions
                    self.phase = .empty
                case .failure(let error):
                    self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "匹配失败，请重试")
                }
            }
        }
    }

    /// 换一个：跳过当前方案（可基于对方口碑拒绝）
    func declineCurrent() {
        if let proposal = currentProposal {
            declinedIds.formUnion(proposal.others.map(\.id))
        }
        let next = proposals.indices.first { index in
            index > currentIndex && !proposals[index].others.contains { declinedIds.contains($0.id) }
        }
        withAnimation(AppTheme.Motion.standard) {
            if let next {
                currentIndex = next
            } else if var request = lastRequest {
                request.excludedUserIds.formUnion(declinedIds)
                run(request)
            }
        }
    }

    func confirmCurrent() async -> Game? {
        guard let proposal = currentProposal else { return nil }
        isConfirming = true
        defer { isConfirming = false }
        do {
            let game = try await backend.confirm(proposal)
            justConfirmedGame = game
            reloadGames()
            return game
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "确认失败")
            return nil
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        phase = .idle
        isFlowPresented = false
    }

    func finishFlow() {
        isFlowPresented = false
        phase = .idle
        proposals = []
        suggestions = []
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
