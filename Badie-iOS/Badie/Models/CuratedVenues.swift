import Foundation

// MARK: - 平台收录的球馆
//
// 美国：逐家对照球馆官网 / 市政府页面核实，坐标来自门牌地址地理编码（见 docs/DESIGN.md §15，来源记在 data/us_venues.json 里）。
// 马来西亚：来自 OpenStreetMap，未经实地核实。

extension BadmintonCourt {
    static var curated: [BadmintonCourt] { curatedUS + curatedBeijing + curatedMY }

    static let curatedUS = VenueCatalog.load("curated-US")
    static let curatedMY = VenueCatalog.load("curated-MY")

    /// 北京：虚构数据，只用于国内演示与测试，不对外发布
    static let curatedBeijing: [BadmintonCourt] = [
        BadmintonCourt(
            id: "v-cn-bj-chaoyang",
            name: "朝阳体育中心羽毛球馆",
            aliases: ["朝体"],
            location: Coordinate(latitude: 39.9219, longitude: 116.4433),
            address: PostalAddress(street: "工体北路4号", city: "朝阳区", region: "北京市", countryCode: "CN"),
            timeZoneId: "Asia/Shanghai",
            amenities: [.parking, .shower, .locker, .cafe, .airConditioning],
            operatingHours: OperatingHours(openHour: 7, openMinute: 0, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 12,
            pricing: .perCourtHour(80),
            phone: "010-65012345"
        ),
        BadmintonCourt(
            id: "v-cn-bj-haidian",
            name: "海淀羽毛球训练基地",
            location: Coordinate(latitude: 39.9847, longitude: 116.3046),
            address: PostalAddress(street: "中关村南大街27号", city: "海淀区", region: "北京市", countryCode: "CN"),
            timeZoneId: "Asia/Shanghai",
            amenities: [.parking, .shower, .locker, .rental, .airConditioning],
            operatingHours: OperatingHours(openHour: 8, openMinute: 0, closeHour: 22, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 8,
            pricing: .perCourtHour(60)
        ),
        BadmintonCourt(
            id: "v-cn-bj-wangjing",
            name: "望京羽毛球俱乐部",
            location: Coordinate(latitude: 40.0028, longitude: 116.4716),
            address: PostalAddress(street: "望京西路50号", city: "朝阳区", region: "北京市", countryCode: "CN"),
            timeZoneId: "Asia/Shanghai",
            amenities: [.shower, .locker, .rental, .cafe],
            operatingHours: OperatingHours(openHour: 9, openMinute: 0, closeHour: 23, closeMinute: 0, daysOpen: Array(1...7)),
            courtCount: 6,
            pricing: .perCourtHour(70)
        )
    ]

    /// 默认球馆（预览与单元测试）：洛杉矶 LABC，演示数据也围绕它
    static var mock: BadmintonCourt { curatedUS.first { $0.id == "v-us-ca-labc" } ?? curatedBeijing[0] }
}
