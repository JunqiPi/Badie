import Foundation

// MARK: - 各地政府开放数据里的羽毛球馆
//
// 由 scripts/build_open_data_venues.py 生成的 venues-XX.json（香港康文署、新加坡 SportSG、
// 台湾运动部、英格兰 Sport England）。只读、随 App 发布，不写进本地数据库；
// 球友确认、签到或纠错时才复制一份进库（库里的版本优先）。

enum OpenDataVenues {
    static let all: [BadmintonCourt] = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
        .filter { $0.lastPathComponent.hasPrefix("venues-") }
        .flatMap(VenueCatalog.decode)
    /// 位置可信、可以直接显示的
    static let located: [BadmintonCourt] = all.filter { $0.needsLocationCheck != true }
    static let byId: [String: BadmintonCourt] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}
