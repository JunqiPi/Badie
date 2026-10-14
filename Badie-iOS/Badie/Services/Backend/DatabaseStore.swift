import Foundation

/// 数据库文件存储（Application Support 下的 JSON 文件）
struct DatabaseStore {
    /// nil 表示仅内存（测试用）
    let url: URL?

    static var live: DatabaseStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return DatabaseStore(url: base.appendingPathComponent("Badie", isDirectory: true).appendingPathComponent("database.json"))
    }

    /// 演示/截图模式使用独立文件，不影响真实数据
    static var demo: DatabaseStore {
        DatabaseStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("badie-demo-database.json"))
    }

    static var inMemory: DatabaseStore { DatabaseStore(url: nil) }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() -> Database? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            let database = try Self.decoder.decode(Database.self, from: data)
            return database.version == Database.currentVersion ? database : nil
        } catch let error as DecodingError {
            #if DEBUG
            print("[DatabaseStore] 解析失败 \(JSONErrorLocationExtractor.extractPosition(from: error) ?? "")：\(error)")
            #endif
            return nil
        } catch {
            return nil
        }
    }

    func save(_ database: Database) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(database)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            #if DEBUG
            print("[DatabaseStore] 保存失败：\(error)")
            #endif
        }
    }

    func erase() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
