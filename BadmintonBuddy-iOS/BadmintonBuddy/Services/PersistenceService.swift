//
//  PersistenceService.swift
//  BadmintonBuddy
//
//  持久化服务实现，提供本地数据存储功能
//  使用 UserDefaults 存储 JSON 编码的数据
//
//  Requirements: 9.1, 9.2, 9.5
//

import Foundation

// MARK: - Persistence Service Implementation

/// 持久化服务实现类
/// 使用 UserDefaults 作为底层存储，JSON 格式编码数据
/// - Note: 适用于中小型数据存储（< 1MB），大型数据建议使用 FileManager
final class PersistenceService: PersistenceServiceProtocol {
    
    // MARK: - Properties
    
    /// UserDefaults 实例，用于数据存储
    private let userDefaults: UserDefaults
    
    /// JSON 编码器，配置为格式化输出便于调试
    private let encoder: JSONEncoder
    
    /// JSON 解码器
    private let decoder: JSONDecoder
    
    /// 存储键前缀，用于命名空间隔离
    private let keyPrefix: String
    
    // MARK: - Initialization
    
    /// 初始化持久化服务
    /// - Parameters:
    ///   - userDefaults: UserDefaults 实例，默认使用 standard
    ///   - keyPrefix: 存储键前缀，默认为 "BadmintonBuddy_"
    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "BadmintonBuddy_"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
        
        // 配置 JSON 编码器
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        // 配置 JSON 解码器
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - PersistenceServiceProtocol Implementation
    
    /// 保存对象到本地存储
    /// - Parameters:
    ///   - object: 要保存的对象（必须符合 Encodable）
    ///   - key: 存储键名
    /// - Throws: PersistenceError.encodingFailed 编码失败时
    /// - Note: 使用 JSON 格式编码数据，存储到 UserDefaults
    func save<T: Encodable>(_ object: T, key: String) throws {
        let prefixedKey = prefixedKey(for: key)
        
        do {
            // 将对象编码为 JSON 数据
            let data = try encoder.encode(object)
            
            // 存储到 UserDefaults
            userDefaults.set(data, forKey: prefixedKey)
            
            // 确保数据同步写入
            userDefaults.synchronize()
            
            #if DEBUG
            // 调试模式下打印保存的数据
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[PersistenceService] 保存成功 - 键: \(key)")
                print("[PersistenceService] 数据: \(jsonString.prefix(500))...")
            }
            #endif
            
        } catch let encodingError as EncodingError {
            // 处理编码错误，提取详细位置信息
            let position = extractEncodingErrorPosition(from: encodingError)
            throw PersistenceError.encodingFailed(underlying: encodingError)
        } catch {
            throw PersistenceError.encodingFailed(underlying: error)
        }
    }
    
    /// 从本地存储加载对象
    /// - Parameters:
    ///   - key: 存储键名
    ///   - type: 对象类型
    /// - Returns: 解码后的对象，如果不存在则返回 nil
    /// - Throws: PersistenceError.decodingFailed 解码失败时（包含错误位置信息）
    /// - Note: 使用 JSON 格式解码数据，错误信息包含失败位置
    func load<T: Decodable>(key: String, type: T.Type) throws -> T? {
        let prefixedKey = prefixedKey(for: key)
        
        // 检查数据是否存在
        guard let data = userDefaults.data(forKey: prefixedKey) else {
            #if DEBUG
            print("[PersistenceService] 未找到数据 - 键: \(key)")
            #endif
            return nil
        }
        
        // 验证数据不为空
        guard !data.isEmpty else {
            throw PersistenceError.dataCorrupted(key: key)
        }
        
        do {
            // 解码 JSON 数据
            let object = try decoder.decode(type, from: data)
            
            #if DEBUG
            print("[PersistenceService] 加载成功 - 键: \(key), 类型: \(type)")
            #endif
            
            return object
            
        } catch let decodingError as DecodingError {
            // 提取解码错误位置信息
            let position = JSONErrorLocationExtractor.extractPosition(from: decodingError)
            throw PersistenceError.decodingFailed(underlying: decodingError, position: position)
        } catch {
            throw PersistenceError.decodingFailed(underlying: error, position: nil)
        }
    }
    
    /// 删除指定键的数据
    /// - Parameter key: 存储键名
    /// - Throws: 删除操作不会抛出错误，即使键不存在也会静默成功
    func delete(key: String) throws {
        let prefixedKey = prefixedKey(for: key)
        
        // 从 UserDefaults 移除数据
        userDefaults.removeObject(forKey: prefixedKey)
        
        // 确保数据同步
        userDefaults.synchronize()
        
        #if DEBUG
        print("[PersistenceService] 删除成功 - 键: \(key)")
        #endif
    }
    
    // MARK: - Helper Methods
    
    /// 生成带前缀的存储键
    /// - Parameter key: 原始键名
    /// - Returns: 带前缀的完整键名
    private func prefixedKey(for key: String) -> String {
        return "\(keyPrefix)\(key)"
    }
    
    /// 从编码错误中提取位置信息
    /// - Parameter error: 编码错误
    /// - Returns: 错误位置描述字符串
    private func extractEncodingErrorPosition(from error: EncodingError) -> String? {
        switch error {
        case .invalidValue(_, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return path.isEmpty ? nil : "路径: \(path)"
        @unknown default:
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension PersistenceService {
    
    /// 检查指定键是否存在数据
    /// - Parameter key: 存储键名
    /// - Returns: 如果存在数据返回 true，否则返回 false
    func exists(key: String) -> Bool {
        let prefixedKey = prefixedKey(for: key)
        return userDefaults.data(forKey: prefixedKey) != nil
    }
    
    /// 清除所有带前缀的存储数据
    /// - Note: 仅清除本服务管理的数据，不影响其他 UserDefaults 数据
    func clearAll() {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.synchronize()
        
        #if DEBUG
        print("[PersistenceService] 已清除所有数据")
        #endif
    }
    
    /// 获取所有存储的键名（不含前缀）
    /// - Returns: 存储键名数组
    func allKeys() -> [String] {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        return allKeys
            .filter { $0.hasPrefix(keyPrefix) }
            .map { String($0.dropFirst(keyPrefix.count)) }
    }
}

// MARK: - Shared Instance

extension PersistenceService {
    
    /// 共享实例，用于全局访问
    static let shared = PersistenceService()
}
