//
//  LocationServiceProtocol.swift
//  BadmintonBuddy
//
//  定义位置服务协议，用于管理用户位置和地理围栏功能
//

import Foundation
import CoreLocation

/// 位置服务协议
/// 提供位置授权、位置更新和地理围栏过滤功能
/// - Requirements: 1.1, 1.2, 1.3, 1.4, 1.7
protocol LocationServiceProtocol {
    
    // MARK: - Properties
    
    /// 当前用户位置
    /// - Note: 当位置服务不可用时返回 nil
    var currentLocation: CLLocation? { get }
    
    /// 位置授权状态
    var authorizationStatus: CLAuthorizationStatus { get }
    
    // MARK: - Authorization
    
    /// 请求位置授权
    /// - Note: 首次调用时会显示系统授权弹窗
    func requestAuthorization()
    
    // MARK: - Location Updates
    
    /// 开始更新位置
    /// - Note: 位置变化超过100米时会触发更新
    func startUpdatingLocation()
    
    /// 停止更新位置
    func stopUpdatingLocation()
    
    // MARK: - Geofence
    
    /// 检查指定位置是否在给定半径范围内
    /// - Parameters:
    ///   - location: 要检查的位置
    ///   - radiusMiles: 半径（英里）
    /// - Returns: 如果在范围内返回 true
    /// - Note: 默认地理围栏半径为50英里
    func isWithinRange(_ location: CLLocation, radiusMiles: Double) -> Bool
}

// MARK: - Default Implementation

extension LocationServiceProtocol {
    /// 默认地理围栏半径：50英里
    static var defaultRadiusMiles: Double { 50.0 }
}
