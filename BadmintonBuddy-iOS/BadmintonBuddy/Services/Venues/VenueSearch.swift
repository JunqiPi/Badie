import Foundation

// MARK: - 球馆搜索与查重（纯函数，便于测试）
//
// 搜索：名称、别名、英文首字母缩写（LABC）、中文拼音与首字母、地址（街道/城市/邮编）。
// 排序：匹配程度优先，其次距离。
// 查重：Apple Place ID 相同 → 同一家；200 米内且名称相近 → 很可能同一家；
//      40 米内（同一栋楼）→ 让用户确认，不自动合并（同楼可能有不同场馆，如 Unit A / Unit B）。

enum VenueSearch {

    struct Hit: Hashable {
        let venue: BadmintonCourt
        let score: Double
        let distanceKm: Double
    }

    // MARK: Normalization

    /// 小写、去重音、全角转半角、去标点、压缩空白
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// 英文名称首字母缩写："Los Angeles Badminton Club" → "labc"
    static func acronym(_ name: String) -> String {
        let words = tokens(name).filter { $0.unicodeScalars.allSatisfy(\.isASCII) && $0.first?.isLetter == true }
        guard words.count >= 2 else { return "" }
        return String(words.compactMap(\.first))
    }

    /// 展开大写缩写后的首字母："LA Badminton Club" / "L.A. Badminton Club" / "Los Angeles Badminton Club" → "labc"
    static func expandedAcronym(_ name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard words.count >= 2, words.allSatisfy({ $0.unicodeScalars.allSatisfy(\.isASCII) }) else { return "" }
        return words.map { word -> String in
            let isShortCaps = (2...4).contains(word.count) && word == word.uppercased() && word.allSatisfy(\.isLetter)
            return isShortCaps ? word.lowercased() : String(word.prefix(1)).lowercased()
        }.joined()
    }

    /// 中文拼音（全拼, 首字母）："朝阳体育中心" → ("chaoyangtiyuzhongxin", "cytyzx")
    static func pinyin(_ text: String) -> (full: String, initials: String) {
        guard text.unicodeScalars.contains(where: { $0.properties.isIdeographic }) else { return ("", "") }
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let syllables = tokens(mutable as String)
        return (syllables.joined(), String(syllables.compactMap(\.first)))
    }

    /// 名称里不区分球馆的通用词
    static let genericWords: Set<String> = [
        "badminton", "club", "center", "centre", "sports", "sport", "academy", "bc", "the", "inc", "llc",
        "gym", "court", "courts", "facility", "and", "of",
        "羽毛球", "羽毛球馆", "馆", "俱乐部", "中心", "体育", "体育馆", "球馆"
    ]

    // MARK: Search

    /// 单个球馆的匹配分（nil = 不匹配）
    static func matchScore(_ venue: BadmintonCourt, query: String) -> Double? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        let compactQuery = q.replacingOccurrences(of: " ", with: "")
        let queryTokens = q.split(separator: " ").map(String.init)

        var best: Double = 0
        for name in [venue.name] + venue.aliases {
            let n = normalize(name)
            let compactName = n.replacingOccurrences(of: " ", with: "")
            let nameTokens = n.split(separator: " ").map(String.init)
            if compactName == compactQuery { best = max(best, 100) }
            if acronym(name) == compactQuery { best = max(best, 95) }
            if compactName.hasPrefix(compactQuery) { best = max(best, 85) }
            if queryTokens.allSatisfy({ token in nameTokens.contains { $0.hasPrefix(token) } }) { best = max(best, 75) }
            if compactName.contains(compactQuery) { best = max(best, 65) }
            let py = pinyin(name)
            if !py.full.isEmpty {
                if py.initials.hasPrefix(compactQuery) { best = max(best, 70) }
                if py.full.hasPrefix(compactQuery) { best = max(best, 70) }
                if py.full.contains(compactQuery) && compactQuery.count >= 4 { best = max(best, 55) }
            }
        }
        if best == 0 {
            // 地址：街道、城市、邮编
            let address = venue.postalAddress
            let haystack = normalize([address.street, address.unit ?? "", address.city, address.region, address.postalCode].joined(separator: " "))
            let addressTokens = haystack.split(separator: " ").map(String.init)
            if queryTokens.allSatisfy({ token in addressTokens.contains { $0.hasPrefix(token) } }) { best = 45 }
            else if haystack.replacingOccurrences(of: " ", with: "").contains(compactQuery) && compactQuery.count >= 3 { best = 35 }
        }
        return best > 0 ? best : nil
    }

    /// 搜索并排序：匹配分减去距离惩罚（每公里 0.3 分，最多 60 分）
    static func search(_ venues: [BadmintonCourt], query: String, near center: Coordinate, limit: Int = 20) -> [Hit] {
        venues.compactMap { venue -> Hit? in
            guard let score = matchScore(venue, query: query) else { return nil }
            let distance = venue.distance(from: center)
            let statusBonus: Double = venue.status == .unconfirmed ? 0 : 3
            return Hit(venue: venue, score: score - min(distance * 0.3, 60) + statusBonus, distanceKm: distance)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.distanceKm < $1.distanceKm }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: Duplicates

    /// 名称相似度 0...1：去掉通用词后的词集合 Jaccard；缩写互相匹配视为 1
    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let compactA = normalize(a).replacingOccurrences(of: " ", with: "")
        let compactB = normalize(b).replacingOccurrences(of: " ", with: "")
        if compactA == compactB { return 1 }
        if !acronym(a).isEmpty && acronym(a) == compactB { return 1 }
        if !acronym(b).isEmpty && acronym(b) == compactA { return 1 }
        let expandedA = expandedAcronym(a), expandedB = expandedAcronym(b)
        if expandedA.count >= 3 && expandedA == expandedB { return 0.9 }
        let hasIdeographs = (a + b).unicodeScalars.contains { $0.properties.isIdeographic }
        let setA = Set(tokens(a)).subtracting(genericWords)
        let setB = Set(tokens(b)).subtracting(genericWords)
        if hasIdeographs || setA.isEmpty || setB.isEmpty {
            // 中文名没有空格分词：去掉“羽毛球馆/中心/体育”等通用词后看是否互相包含
            let coreA = stripGeneric(compactA), coreB = stripGeneric(compactB)
            guard !coreA.isEmpty, !coreB.isEmpty else { return 0 }
            return coreA.contains(coreB) || coreB.contains(coreA) ? 0.8 : 0
        }
        let intersection = setA.intersection(setB).count
        return Double(intersection) / Double(setA.union(setB).count)
    }

    private static func stripGeneric(_ compact: String) -> String {
        var result = compact
        for word in genericWords.sorted(by: { $0.count > $1.count }) where word.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
            result = result.replacingOccurrences(of: word, with: "")
        }
        return result
    }

    enum DuplicateKind: Int, Comparable {
        /// Apple Place ID 相同
        case samePlace = 0
        /// 200 米内且名称相近
        case likely = 1
        /// 40 米内（同一栋楼），名称不同
        case sameBuilding = 2

        static func < (lhs: DuplicateKind, rhs: DuplicateKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Duplicate: Hashable {
        let venue: BadmintonCourt
        let kind: DuplicateKind
        let distanceMeters: Double
    }

    static let likelyDuplicateRadiusMeters: Double = 200
    static let sameBuildingRadiusMeters: Double = 40

    static func duplicates(name: String, location: Coordinate, applePlaceId: String?, alternatePlaceIds: [String] = [],
                           in venues: [BadmintonCourt]) -> [Duplicate] {
        let placeIds = Set(([applePlaceId].compactMap { $0 } + alternatePlaceIds).filter { !$0.isEmpty })
        return venues.compactMap { venue -> Duplicate? in
            let meters = venue.location.distanceKm(to: location) * 1000
            if let venueId = venue.applePlaceId, placeIds.contains(venueId) {
                return Duplicate(venue: venue, kind: .samePlace, distanceMeters: meters)
            }
            if meters <= likelyDuplicateRadiusMeters && nameSimilarity(name, venue.name) >= 0.5 {
                return Duplicate(venue: venue, kind: .likely, distanceMeters: meters)
            }
            if meters <= likelyDuplicateRadiusMeters,
               venue.aliases.contains(where: { nameSimilarity(name, $0) >= 0.5 }) {
                return Duplicate(venue: venue, kind: .likely, distanceMeters: meters)
            }
            if meters <= sameBuildingRadiusMeters {
                return Duplicate(venue: venue, kind: .sameBuilding, distanceMeters: meters)
            }
            return nil
        }
        .sorted { $0.kind != $1.kind ? $0.kind < $1.kind : $0.distanceMeters < $1.distanceMeters }
    }
}
