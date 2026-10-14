import Foundation

// MARK: - Persistence Service Protocol

/// 键值形式的本地 JSON 存储
protocol PersistenceServiceProtocol {
    func save<T: Encodable>(_ object: T, key: String) throws
    /// 键不存在时返回 nil；解码失败抛出带出错路径的错误
    func load<T: Decodable>(key: String, type: T.Type) throws -> T?
    func delete(key: String) throws
}

// MARK: - Persistence Errors

enum PersistenceError: Error, LocalizedError {
    case encodingFailed(underlying: Error)
    case decodingFailed(underlying: Error, position: String?)
    case dataCorrupted(key: String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            return String(localized: "数据编码失败: \(error.localizedDescription)")
        case .decodingFailed(let error, let position):
            if let pos = position {
                return String(localized: "数据解码失败 (位置: \(pos)): \(error.localizedDescription)")
            }
            return String(localized: "数据解码失败: \(error.localizedDescription)")
        case .dataCorrupted(let key):
            return String(localized: "数据已损坏: \(key)")
        }
    }
}

// MARK: - Storage Keys

enum StorageKey {
    static let travelRadius = "travelRadiusKm"
}

// MARK: - JSON Parsing Helpers

enum JSONErrorLocationExtractor {

    /// 从 DecodingError 中取出出错的字段路径（如 "路径: users.u-1.nickname"）
    static func extractPosition(from error: DecodingError) -> String? {
        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return path.isEmpty ? nil : String(localized: "路径: \(path)")
        @unknown default:
            return nil
        }
    }
}
