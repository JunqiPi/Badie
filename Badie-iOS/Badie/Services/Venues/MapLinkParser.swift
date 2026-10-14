import Foundation

// MARK: - 地图分享链接解析
//
// 群聊里常直接发 Google / Apple 地图链接。粘贴后从链接里取出坐标、名称或 Place ID，
// 再走与搜索相同的“查重 → 确认”流程。短链（maps.app.goo.gl、goo.gl/maps、maps.apple/p/…）
// 需要先联网展开为长链，由调用方处理（见 `needsExpansion`）。

struct ParsedMapLink: Equatable {
    enum Provider: String, Equatable { case apple, google }

    let provider: Provider
    var coordinate: Coordinate?
    var name: String?
    /// 搜索词或地址（没有坐标时用它去地图搜索）
    var query: String?
    var applePlaceId: String?
    var googlePlaceId: String?
}

enum MapLinkParser {

    /// 从一段文字里找出第一个地图链接（兼容“分享自微信”的前后缀文字）
    static func firstMapURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first { isMapURL($0) }
    }

    static func isMapURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.hasSuffix("maps.apple.com") || host == "maps.apple" || host.hasSuffix("maps.app.goo.gl")
            || host.hasSuffix("goo.gl") || host.contains("google.") && (url.path.hasPrefix("/maps") || host.hasPrefix("maps."))
    }

    /// 短链需要联网展开
    static func needsExpansion(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.hasSuffix("maps.app.goo.gl") || host == "goo.gl" || host == "maps.apple" ||
            (host.hasSuffix("maps.apple.com") && url.path.hasPrefix("/p/"))
    }

    static func parse(_ url: URL) -> ParsedMapLink? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.hasSuffix("maps.apple.com") { return parseApple(url) }
        if host.contains("google.") { return parseGoogle(url) }
        return nil
    }

    // MARK: Apple

    private static func parseApple(_ url: URL) -> ParsedMapLink? {
        let items = queryItems(url)
        var link = ParsedMapLink(provider: .apple)
        link.applePlaceId = items["place-id"]
        link.coordinate = coordinate(from: items["coordinate"] ?? items["ll"] ?? items["sll"])
        link.name = items["name"] ?? items["q"].flatMap { coordinate(from: $0) == nil ? $0 : nil }
        link.query = items["address"] ?? items["q"]
        if link.coordinate == nil, let q = items["q"] { link.coordinate = coordinate(from: q) }
        guard link.coordinate != nil || link.applePlaceId != nil || link.query != nil else { return nil }
        return link
    }

    // MARK: Google

    private static func parseGoogle(_ url: URL) -> ParsedMapLink? {
        let items = queryItems(url)
        var link = ParsedMapLink(provider: .google)
        let path = url.path.removingPercentEncoding ?? url.path
        let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString

        // 地点精确坐标：data=…!3d34.0764!4d-118.0461（优先于 @ 后的视野中心）
        if let lat = firstMatch(#"!3d(-?\d+(?:\.\d+)?)"#, in: absolute),
           let lng = firstMatch(#"!4d(-?\d+(?:\.\d+)?)"#, in: absolute),
           let latitude = Double(lat), let longitude = Double(lng) {
            link.coordinate = validCoordinate(latitude, longitude)
        }
        // /maps/place/<名称>/@lat,lng,17z
        if let range = path.range(of: "/maps/place/") {
            let rest = path[range.upperBound...]
            let name = rest.split(separator: "/").first.map(String.init)?.replacingOccurrences(of: "+", with: " ")
            if let name, !name.hasPrefix("@"), !name.isEmpty { link.name = name }
        }
        if link.coordinate == nil, let at = firstMatch(#"@(-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?)"#, in: path) {
            link.coordinate = coordinate(from: at)
        }
        // ?q= / ?query= / ?destination=
        for key in ["q", "query", "destination", "daddr"] {
            guard let value = items[key], !value.isEmpty else { continue }
            if let coordinate = coordinate(from: value) {
                if link.coordinate == nil { link.coordinate = coordinate }
            } else {
                link.query = value
                if link.name == nil { link.name = value.components(separatedBy: ",").first }
            }
        }
        link.googlePlaceId = items["query_place_id"] ?? items["destination_place_id"]
        guard link.coordinate != nil || link.query != nil || link.name != nil else { return nil }
        return link
    }

    // MARK: Helpers

    private static func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var result: [String: String] = [:]
        for item in items {
            guard let value = item.value?.replacingOccurrences(of: "+", with: " "), result[item.name] == nil else { continue }
            result[item.name] = value.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    static func coordinate(from text: String?) -> Coordinate? {
        guard let text else { return nil }
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        return validCoordinate(lat, lng)
    }

    private static func validCoordinate(_ latitude: Double, _ longitude: Double) -> Coordinate? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude), !(latitude == 0 && longitude == 0) else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
