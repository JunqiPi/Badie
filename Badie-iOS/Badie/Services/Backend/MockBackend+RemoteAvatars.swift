import Foundation

// MARK: - 正式后端：照片头像
/// 照片存在公开的 avatars 桶里（文件名随机），地址只给打过交道的人。
/// 别人的头像：见到一个人就记下来，攒一会儿一起查地址，下载后放进本地缓存（版本号 = 地址的哈希，地址没变就不重新下载）
extension MockBackend {

    private struct AvatarRow: Decodable {
        let id: String
        let path: String
    }

    /// 上传自己的照片：先传新的、换上，再删旧的
    func remoteUploadAvatar(_ jpeg: Data) async throws -> User {
        let remote = try requireRemote()
        guard var user = currentUser else { throw BackendError.notSignedIn }
        let path = "\(user.id)/\(UUID().uuidString.lowercased()).jpg"
        try await remote.upload("avatars", path: path, data: jpeg, contentType: "image/jpeg")
        try await remote.call("set_avatar", ["p_path": path])
        if let old = remoteAvatarPath { try? await remote.removeFile("avatars", path: old) }
        remoteAvatarPath = path
        db.avatarPhotos[user.id] = jpeg
        user.avatar.photoVersion = Self.avatarVersion(path)
        db.users[user.id] = user
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }

    /// 改回文字头像
    func remoteRemoveAvatar() {
        let old = remoteAvatarPath
        remoteAvatarPath = nil
        runRemote { remote in
            try await remote.call("set_avatar", ["p_path": NSNull()])
            if let old { try? await remote.removeFile("avatars", path: old) }
        }
    }

    /// 记下要查头像的人（每次启动每人查一次），0.3 秒内见到的人一起查
    func queueAvatarCheck(_ userId: String) {
        guard isRemote, remoteAvatarChecked.insert(userId).inserted else { return }
        remoteAvatarQueue.append(userId)
        guard remoteAvatarQueue.count == 1 else { return }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await loadQueuedAvatars()
        }
    }

    func loadQueuedAvatars() async {
        let ids = remoteAvatarQueue
        remoteAvatarQueue = []
        guard let remote, !ids.isEmpty else { return }
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            guard let rows = try? await remote.rpc("avatars", ["p_users": batch], as: [AvatarRow].self) else { continue }
            let paths = Dictionary(rows.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
            for id in batch { await applyAvatar(paths[id], to: id) }
        }
        emit(.friendsChanged)
    }

    /// 地址变了才下载；没有照片就改回文字头像。下载失败下次启动再试
    func applyAvatar(_ path: String?, to userId: String) async {
        let version = path.map(Self.avatarVersion)
        guard var user = db.users[userId], user.avatar.photoVersion != version || (path != nil && db.avatarPhotos[userId] == nil) else { return }
        if let path {
            guard let data = try? await remote?.download("avatars", path: path) else { return }
            db.avatarPhotos[userId] = data
        } else {
            db.avatarPhotos[userId] = nil
        }
        user.avatar.photoVersion = version
        db.users[userId] = user
        scheduleSave()
        if userId == currentUserId { emit(.userUpdated(user)) }
    }

    static func avatarVersion(_ path: String) -> Int { abs(path.stableHash) }
}
