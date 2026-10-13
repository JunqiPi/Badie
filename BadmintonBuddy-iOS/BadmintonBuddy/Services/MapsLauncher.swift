import Foundation
import MapKit
import UIKit

/// 导航到球馆：Apple 地图 / 高德 / 百度（国内用户常用后两者）
@MainActor
enum MapsLauncher {
    enum Provider: String, CaseIterable, Identifiable {
        case apple = "Apple 地图"
        case amap = "高德地图"
        case baidu = "百度地图"

        var id: String { rawValue }
    }

    /// 打开导航；第三方地图未安装时返回 false
    static func open(_ court: BadmintonCourt, with provider: Provider) async -> Bool {
        switch provider {
        case .apple:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: court.location.clCoordinate))
            item.name = court.name
            return item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        case .amap:
            var components = URLComponents()
            components.scheme = "iosamap"
            components.host = "path"
            components.queryItems = [
                URLQueryItem(name: "sourceApplication", value: "羽毛球搭子"),
                URLQueryItem(name: "dlat", value: String(court.location.latitude)),
                URLQueryItem(name: "dlon", value: String(court.location.longitude)),
                URLQueryItem(name: "dname", value: court.name),
                // dev=1：传入的是 WGS-84 坐标，由高德做偏移
                URLQueryItem(name: "dev", value: "1"),
                URLQueryItem(name: "t", value: "0")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        case .baidu:
            var components = URLComponents()
            components.scheme = "baidumap"
            components.host = "map"
            components.path = "/direction"
            components.queryItems = [
                URLQueryItem(name: "destination", value: "latlng:\(court.location.latitude),\(court.location.longitude)|name:\(court.name)"),
                URLQueryItem(name: "coord_type", value: "wgs84"),
                URLQueryItem(name: "mode", value: "transit"),
                URLQueryItem(name: "src", value: "ios.badie.app")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        }
    }

    /// 拨打球馆电话
    static func call(_ phone: String) async -> Bool {
        let digits = phone.filter { $0.isNumber || $0 == "-" }
        guard let url = URL(string: "tel://\(digits)") else { return false }
        return await UIApplication.shared.open(url)
    }
}
