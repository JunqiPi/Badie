import Foundation

// MARK: - 匹配时的“同一个地方”
//
// 匹配只在双方都能去的球馆之间进行。以下视为同一处：
// 同一 ID；其中一个已合并到另一个；或相距 150 米以内（同一栋楼/同一园区，
// 例如有人新加了“LABC 2 号馆”，而别人选的是 LABC）。

enum VenueCluster {
    static let radiusMeters: Double = 150

    static func same(_ a: BadmintonCourt, _ b: BadmintonCourt) -> Bool {
        if a.id == b.id { return true }
        if a.mergedInto == b.id || b.mergedInto == a.id { return true }
        if let target = a.mergedInto, target == b.mergedInto { return true }
        return a.location.distanceKm(to: b.location) * 1000 <= radiusMeters
    }
}

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
            let key = keys.name(name)
            if key.compact == compactQuery { best = max(best, 100) }
            if key.acronym == compactQuery { best = max(best, 95) }
            if key.compact.hasPrefix(compactQuery) { best = max(best, 85) }
            if queryTokens.allSatisfy({ token in key.tokens.contains { $0.hasPrefix(token) } }) { best = max(best, 75) }
            if key.compact.contains(compactQuery) { best = max(best, 65) }
            if !key.pinyin.isEmpty {
                if key.pinyinInitials.hasPrefix(compactQuery) { best = max(best, 70) }
                if key.pinyin.hasPrefix(compactQuery) { best = max(best, 70) }
                if key.pinyin.contains(compactQuery) && compactQuery.count >= 4 { best = max(best, 55) }
            }
        }
        if best == 0 {
            // 地址：街道、城市、邮编
            let address = venue.postalAddress
            let key = keys.address([address.street, address.unit ?? "", address.city, address.region, address.postalCode].joined(separator: " "))
            if queryTokens.allSatisfy({ token in key.tokens.contains { $0.hasPrefix(token) } }) { best = 45 }
            else if key.compact.contains(compactQuery) && compactQuery.count >= 3 { best = 35 }
        }
        return best > 0 ? best : nil
    }

    /// 先把这些球馆搜索要用的写法算好（打开搜索页时在后台做，第一次搜索就不用等）
    static func prepare(_ venues: [BadmintonCourt]) {
        for venue in venues {
            for name in [venue.name] + venue.aliases { _ = keys.name(name) }
        }
    }

    /// 名称和地址搜索时要用的写法（规范化、分词、缩写、拼音）。球馆有三千多家，拼音转换又慢，
    /// 每打一个字都重算会卡，所以每个名字只算一次，存起来（名字不会变，存的是文字本身）
    private final class Keys: @unchecked Sendable {
        struct Name { let compact: String; let tokens: [String]; let acronym: String; let pinyin: String; let pinyinInitials: String }
        struct Address { let compact: String; let tokens: [String] }
        private let lock = NSLock()
        private var names: [String: Name] = [:]
        private var addresses: [String: Address] = [:]

        func name(_ text: String) -> Name {
            if let cached = lock.withLock({ names[text] }) { return cached }
            let normalized = VenueSearch.normalize(text)
            let py = VenueSearch.pinyin(text)
            let key = Name(compact: normalized.replacingOccurrences(of: " ", with: ""), tokens: normalized.split(separator: " ").map(String.init),
                           acronym: VenueSearch.acronym(text), pinyin: py.full, pinyinInitials: py.initials)
            lock.withLock { names[text] = key }
            return key
        }

        func address(_ text: String) -> Address {
            if let cached = lock.withLock({ addresses[text] }) { return cached }
            let normalized = VenueSearch.normalize(text)
            let key = Address(compact: normalized.replacingOccurrences(of: " ", with: ""), tokens: normalized.split(separator: " ").map(String.init))
            lock.withLock { addresses[text] = key }
            return key
        }
    }

    private static let keys = Keys()

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

        /// 同一地点 / 很可能同一家：不允许新建，只能选已有的
        var blocksAdding: Bool { self != .sameBuilding }
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
        return venues.filter { $0.mergedInto == nil }.compactMap { venue -> Duplicate? in
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
