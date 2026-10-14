import Foundation
import MapKit
import UIKit

/// 导航到球馆：按球馆所在国家给出常用的导航 App。
/// - Google 地图、Waze 使用官方 Universal Link：装了 App 就打开 App，没装就打开网页，不会失败。
/// - 高德、百度只在国内使用；传入 WGS-84 坐标，由对方做坐标偏移。
@MainActor
enum MapsLauncher {

    static func apps(for court: BadmintonCourt) -> [NavigationApp] {
        court.country.navigationApps
    }

    /// 打开导航；第三方地图未安装（高德/百度）时返回 false
    static func open(_ court: BadmintonCourt, with app: NavigationApp) async -> Bool {
        let lat = court.location.latitude
        let lng = court.location.longitude
        switch app {
        case .appleMaps:
            if let placeId = court.applePlaceId, let item = await AppleMapsSearch.mapItem(placeId: placeId) {
                return item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
            }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: court.location.clCoordinate))
            item.name = court.name
            return item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        case .googleMaps:
            var components = URLComponents(string: "https://www.google.com/maps/dir/")!
            components.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: "\(lat),\(lng)")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        case .waze:
            var components = URLComponents(string: "https://waze.com/ul")!
            components.queryItems = [
                URLQueryItem(name: "ll", value: "\(lat),\(lng)"),
                URLQueryItem(name: "navigate", value: "yes")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        case .amap:
            var components = URLComponents()
            components.scheme = "iosamap"
            components.host = "path"
            components.queryItems = [
                URLQueryItem(name: "sourceApplication", value: "Badie"),
                URLQueryItem(name: "dlat", value: String(lat)),
                URLQueryItem(name: "dlon", value: String(lng)),
                URLQueryItem(name: "dname", value: court.name),
                // dev=1：传入 WGS-84，由高德偏移到 GCJ-02；已是 GCJ-02 时 dev=0
                URLQueryItem(name: "dev", value: court.datum == .wgs84 ? "1" : "0"),
                URLQueryItem(name: "t", value: "0")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        case .naver:
            var components = URLComponents()
            components.scheme = "nmap"
            components.host = "route"
            components.path = "/public"
            components.queryItems = [
                URLQueryItem(name: "dlat", value: String(lat)),
                URLQueryItem(name: "dlng", value: String(lng)),
                URLQueryItem(name: "dname", value: court.name),
                URLQueryItem(name: "appname", value: Bundle.main.bundleIdentifier ?? "com.badie.app")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        case .kakao:
            guard let url = URL(string: "kakaomap://route?ep=\(lat),\(lng)&by=PUBLICTRANSIT") else { return false }
            return await UIApplication.shared.open(url)
        case .baidu:
            var components = URLComponents()
            components.scheme = "baidumap"
            components.host = "map"
            components.path = "/direction"
            components.queryItems = [
                URLQueryItem(name: "destination", value: "latlng:\(lat),\(lng)|name:\(court.name)"),
                URLQueryItem(name: "coord_type", value: court.datum == .wgs84 ? "wgs84" : "gcj02"),
                URLQueryItem(name: "mode", value: "transit"),
                URLQueryItem(name: "src", value: "ios.badie.app")
            ]
            guard let url = components.url else { return false }
            return await UIApplication.shared.open(url)
        }
    }

    /// 拨打球馆电话
    static func call(_ phone: String) async -> Bool {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(digits)") else { return false }
        return await UIApplication.shared.open(url)
    }
}
