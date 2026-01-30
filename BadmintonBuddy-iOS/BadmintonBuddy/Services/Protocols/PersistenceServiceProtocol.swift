//
//  PersistenceServiceProtocol.swift
//  BadmintonBuddy
//
//  定义持久化服务协议，用于本地数据存储
//

import Foundation

// MARK: - Persistence Service Protocol

/// 持久化服务协议
/// 提供通用的本地数据存储、读取和删除功能
/// - Requirements: 9.1, 9.2, 9.3, 9.4, 9.5
protocol PersistenceServiceProtocol {
    
    /// 保存对象到本地存储
    /// - Parameters:
    ///   - object: 要保存的对象（必须符合 Encodable）
    ///   - key: 存储键名
    /// - Throws: 编码失败或存储错误时抛出错误
    /// - Note: 使用 JSON 格式编码数据
    func save<T: Encodable>(_ object: T, key: String) throws
    
    /// 从本地存储加载对象
    /// - Parameters:
    ///   - key: 存储键名
    ///   - type: 对象类型
    /// - Returns: 解码后的对象，如果不存在则返回 nil
    /// - Throws: 解码失败时抛出错误（包含错误位置信息）
    /// - Note: 使用 JSON 格式解码数据
    func load<T: Decodable>(key: String, type: T.Type) throws -> T?
    
    /// 删除指定键的数据
    /// - Parameter key: 存储键名
    /// - Throws: 删除失败时抛出错误
    func delete(key: String) throws
}

// MARK: - Persistence Errors

/// 持久化服务错误类型
enum PersistenceError: Error, LocalizedError {
    case encodingFailed(underlying: Error)
    case decodingFailed(underlying: Error, position: String?)
    case storageError(underlying: Error)
    case keyNotFound(key: String)
    case dataCorrupted(key: String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            return "数据编码失败: \(error.localizedDescription)"
        case .decodingFailed(let error, let position):
            if let pos = position {
                return "数据解码失败 (位置: \(pos)): \(error.localizedDescription)"
            }
            return "数据解码失败: \(error.localizedDescription)"
        case .storageError(let error):
            return "存储错误: \(error.localizedDescription)"
        case .keyNotFound(let key):
            return "未找到数据: \(key)"
        case .dataCorrupted(let key):
            return "数据已损坏: \(key)"
        }
    }
}

// MARK: - Storage Keys

/// 预定义的存储键名
/// 用于统一管理本地存储的键名，避免硬编码
enum StorageKey {
    static let currentUser = "currentUser"
    static let friends = "friends"
    static let messageThreads = "messageThreads"
    static let pendingSurveys = "pendingSurveys"
    static let completedSurveys = "completedSurveys"
    static let recurringTimeSlots = "recurringTimeSlots"
    static let blockedUsers = "blockedUsers"
    static let cachedNearbyPlayers = "cachedNearbyPlayers"
    static let lastKnownLocation = "lastKnownLocation"
}

// MARK: - JSON Parsing Helpers

/// JSON 解析错误位置提取器
/// 用于从 DecodingError 中提取错误位置信息
struct JSONErrorLocationExtractor {
    
    /// 从 DecodingError 中提取错误位置描述
    /// - Parameter error: 解码错误
    /// - Returns: 错误位置描述字符串
    static func extractPosition(from error: DecodingError) -> String? {
        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return path.isEmpty ? nil : "路径: \(path)"
        @unknown default:
            return nil
        }
    }
}
