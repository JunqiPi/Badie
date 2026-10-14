import Foundation
import Combine

// MARK: - 房间 / 公开球局

@MainActor
final class RoomManager: ObservableObject {
    @Published private(set) var myRooms: [Room] = []
    @Published private(set) var publicRooms: [Room] = []
    /// 被踢出或房间关闭时的提示（供界面弹出）
    @Published var notice: String?
    /// 别人开局后，需要跳转到的新球局
    @Published var startedGameId: String?

    private let backend: MockBackend
    private var expirationTask: Task<Void, Never>?
    var radiusKm: Double = UserPreferences.defaultTravelRadius

    init(backend: MockBackend) {
        self.backend = backend
        reload()
        backend.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case .roomsChanged, .sessionChanged, .friendsChanged:
                self.reload()
            case .kicked(let code):
                self.notice = String(localized: "你已被移出房间 \(code)")
                self.reload()
            case .roomClosed(let code, let reason):
                self.notice = String(localized: "房间 \(code)：\(reason.message)")
                self.reload()
            case .gameCreated(let game):
                if case .room = game.origin, game.hostId != self.backend.currentUserId {
                    self.startedGameId = game.id
                }
            default:
                break
            }
        }
        startExpirationChecks()
    }

    func reload() {
        myRooms = backend.myOpenRooms()
        publicRooms = backend.publicRooms(radiusKm: radiusKm)
    }

    func room(id: String) -> Room? { backend.room(id: id) }

    /// 每 30 秒检查一次过期房间（私密房间 30 分钟无活动自动关闭）
    private func startExpirationChecks() {
        expirationTask?.cancel()
        expirationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { return }
                self.backend.expireRooms()
            }
        }
    }

    // MARK: Actions

    func create(_ draft: RoomDraft) async throws -> Room {
        let room = try await backend.createRoom(draft)
        reload()
        return room
    }

    func join(code: String) async throws -> Room {
        let room = try await backend.joinRoom(code: code)
        reload()
        return room
    }

    func joinPublic(_ room: Room) async throws -> Room {
        let joined = try await backend.joinPublicRoom(id: room.id)
        reload()
        return joined
    }

    func leave(_ room: Room) async throws {
        try await backend.leaveRoom(id: room.id)
        reload()
    }

    func kick(_ participant: RoomParticipant, from room: Room) async throws {
        try await backend.kick(participant.userId, from: room.id)
        reload()
    }

    func invite(_ userIds: [String], to room: Room) async throws {
        try await backend.invite(userIds, to: room.id)
        reload()
    }

    func updateDetails(_ room: Room, court: BadmintonCourt?, slot: TimeSlot?) async throws {
        _ = try await backend.updateRoomDetails(roomId: room.id, court: court, slot: slot)
        reload()
    }

    func start(_ room: Room) async throws -> Game {
        let game = try await backend.startRoom(id: room.id)
        reload()
        return game
    }
}
