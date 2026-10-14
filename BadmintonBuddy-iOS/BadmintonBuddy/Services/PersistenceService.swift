import Foundation

// MARK: - Persistence Service Implementation

/// 基于 UserDefaults 的实现，适合小数据（< 1MB）；所有键加前缀做命名空间隔离
final class PersistenceService: PersistenceServiceProtocol {

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let keyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "BadmintonBuddy_"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - PersistenceServiceProtocol

    func save<T: Encodable>(_ object: T, key: String) throws {
        let prefixedKey = prefixedKey(for: key)
        do {
            let data = try encoder.encode(object)
            userDefaults.set(data, forKey: prefixedKey)
            userDefaults.synchronize()

            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[PersistenceService] 保存成功 - 键: \(key)")
                print("[PersistenceService] 数据: \(jsonString.prefix(500))...")
            }
            #endif
        } catch {
            throw PersistenceError.encodingFailed(underlying: error)
        }
    }

    func load<T: Decodable>(key: String, type: T.Type) throws -> T? {
        let prefixedKey = prefixedKey(for: key)
        guard let data = userDefaults.data(forKey: prefixedKey) else {
            #if DEBUG
            print("[PersistenceService] 未找到数据 - 键: \(key)")
            #endif
            return nil
        }
        guard !data.isEmpty else {
            throw PersistenceError.dataCorrupted(key: key)
        }
        do {
            let object = try decoder.decode(type, from: data)
            #if DEBUG
            print("[PersistenceService] 加载成功 - 键: \(key), 类型: \(type)")
            #endif
            return object
        } catch let decodingError as DecodingError {
            let position = JSONErrorLocationExtractor.extractPosition(from: decodingError)
            throw PersistenceError.decodingFailed(underlying: decodingError, position: position)
        } catch {
            throw PersistenceError.decodingFailed(underlying: error, position: nil)
        }
    }

    /// 键不存在时静默成功
    func delete(key: String) throws {
        userDefaults.removeObject(forKey: prefixedKey(for: key))
        userDefaults.synchronize()

        #if DEBUG
        print("[PersistenceService] 删除成功 - 键: \(key)")
        #endif
    }

    private func prefixedKey(for key: String) -> String {
        "\(keyPrefix)\(key)"
    }
}

// MARK: - Convenience

extension PersistenceService {

    func exists(key: String) -> Bool {
        userDefaults.data(forKey: prefixedKey(for: key)) != nil
    }

    /// 只清除本服务（同一前缀）下的数据
    func clearAll() {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.synchronize()

        #if DEBUG
        print("[PersistenceService] 已清除所有数据")
        #endif
    }

    /// 所有已存储的键（不含前缀）
    func allKeys() -> [String] {
        userDefaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .map { String($0.dropFirst(keyPrefix.count)) }
    }
}
