import Foundation

// MARK: - 国家/地区信息
//
// 每个国家的币种、手机号规则、地址书写顺序和常用导航 App；新增国家在 `CountryInfo.all` 里加一行。

enum AddressStyle: String, Codable, Hashable {
    /// 由小到大：门牌 街道, 城市, 州 邮编（美、加、英、澳、新、马…）
    case smallToLarge
    /// 由大到小：省/市 区 街道门牌（中国大陆、台湾、日本、韩国）
    case largeToSmall
}

enum NavigationApp: String, CaseIterable, Identifiable, Codable {
    case appleMaps, googleMaps, waze, amap, baidu, naver, kakao

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMaps: return String(localized: "Apple 地图")
        case .googleMaps: return String(localized: "Google 地图")
        case .waze: return "Waze"
        case .amap: return String(localized: "高德地图")
        case .baidu: return String(localized: "百度地图")
        case .naver: return String(localized: "Naver 地图")
        case .kakao: return "KakaoMap"
        }
    }
}

struct PhoneRule: Hashable {
    /// 国内号码（不含国家码、不含开头的 0）允许的位数
    let lengths: ClosedRange<Int>
    /// 国内号码的正则（不含国家码）；nil 表示只校验位数
    let pattern: String?
    /// 输入框占位示例
    let example: String

    func isValid(national digits: String) -> Bool {
        guard lengths.contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        guard let pattern else { return true }
        return digits.range(of: "^" + pattern + "$", options: .regularExpression) != nil
    }
}

struct CountryInfo: Identifiable, Hashable {
    /// ISO 3166-1 alpha-2
    let code: String
    let nameZh: String
    let callingCode: String
    let currencyCode: String
    let currencySymbol: String
    let addressStyle: AddressStyle
    let phone: PhoneRule
    /// 按当地习惯排序的导航 App
    let navigationApps: [NavigationApp]

    var id: String { code }

    /// 国旗 emoji：地区码字母映射到区域指示符号
    var flag: String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }

    /// 估算用球费（当地货币，整数）；0 表示通常自带球、不计入
    func shuttleFee(for mode: GameMode) -> Int {
        switch currencyCode {
        case "CNY": return mode == .doubles ? 15 : 10
        case "USD", "CAD", "AUD", "SGD", "NZD": return mode == .doubles ? 8 : 5
        default: return 0
        }
    }

    static let all: [CountryInfo] = [
        CountryInfo(code: "US", nameZh: String(localized: "美国"), callingCode: "1", currencyCode: "USD", currencySymbol: "$",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 10...10, pattern: "[2-9][0-9]{2}[2-9][0-9]{6}", example: "626 555 0123"),
                    navigationApps: [.appleMaps, .googleMaps, .waze]),
        CountryInfo(code: "CA", nameZh: String(localized: "加拿大"), callingCode: "1", currencyCode: "CAD", currencySymbol: "C$",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 10...10, pattern: "[2-9][0-9]{2}[2-9][0-9]{6}", example: "604 555 0123"),
                    navigationApps: [.appleMaps, .googleMaps, .waze]),
        CountryInfo(code: "CN", nameZh: String(localized: "中国大陆"), callingCode: "86", currencyCode: "CNY", currencySymbol: "¥",
                    addressStyle: .largeToSmall,
                    phone: PhoneRule(lengths: 11...11, pattern: "1[3-9][0-9]{9}", example: "138 0013 8000"),
                    navigationApps: [.amap, .baidu, .appleMaps]),
        CountryInfo(code: "HK", nameZh: String(localized: "中国香港"), callingCode: "852", currencyCode: "HKD", currencySymbol: "HK$",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 8...8, pattern: "[4-9][0-9]{7}", example: "5123 4567"),
                    navigationApps: [.appleMaps, .googleMaps]),
        CountryInfo(code: "TW", nameZh: String(localized: "中国台湾"), callingCode: "886", currencyCode: "TWD", currencySymbol: "NT$",
                    addressStyle: .largeToSmall,
                    phone: PhoneRule(lengths: 9...9, pattern: "9[0-9]{8}", example: "912 345 678"),
                    navigationApps: [.googleMaps, .appleMaps]),
        CountryInfo(code: "SG", nameZh: String(localized: "新加坡"), callingCode: "65", currencyCode: "SGD", currencySymbol: "S$",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 8...8, pattern: "[3689][0-9]{7}", example: "8123 4567"),
                    navigationApps: [.googleMaps, .appleMaps, .waze]),
        CountryInfo(code: "MY", nameZh: String(localized: "马来西亚"), callingCode: "60", currencyCode: "MYR", currencySymbol: "RM",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 9...10, pattern: "1[0-9]{8,9}", example: "12 345 6789"),
                    navigationApps: [.waze, .googleMaps, .appleMaps]),
        CountryInfo(code: "JP", nameZh: String(localized: "日本"), callingCode: "81", currencyCode: "JPY", currencySymbol: "¥",
                    addressStyle: .largeToSmall,
                    phone: PhoneRule(lengths: 10...10, pattern: "[789]0[0-9]{8}", example: "90 1234 5678"),
                    navigationApps: [.googleMaps, .appleMaps]),
        CountryInfo(code: "KR", nameZh: String(localized: "韩国"), callingCode: "82", currencyCode: "KRW", currencySymbol: "₩",
                    addressStyle: .largeToSmall,
                    phone: PhoneRule(lengths: 9...10, pattern: "1[0-9]{8,9}", example: "10 1234 5678"),
                    navigationApps: [.naver, .kakao, .appleMaps]),
        CountryInfo(code: "GB", nameZh: String(localized: "英国"), callingCode: "44", currencyCode: "GBP", currencySymbol: "£",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 10...10, pattern: "7[0-9]{9}", example: "7400 123456"),
                    navigationApps: [.googleMaps, .appleMaps, .waze]),
        CountryInfo(code: "AU", nameZh: String(localized: "澳大利亚"), callingCode: "61", currencyCode: "AUD", currencySymbol: "A$",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 9...9, pattern: "4[0-9]{8}", example: "412 345 678"),
                    navigationApps: [.googleMaps, .appleMaps, .waze]),
        CountryInfo(code: "IN", nameZh: String(localized: "印度"), callingCode: "91", currencyCode: "INR", currencySymbol: "₹",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 10...10, pattern: "[6-9][0-9]{9}", example: "98765 43210"),
                    navigationApps: [.googleMaps, .appleMaps]),
        CountryInfo(code: "ID", nameZh: String(localized: "印度尼西亚"), callingCode: "62", currencyCode: "IDR", currencySymbol: "Rp",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 9...12, pattern: "8[0-9]{8,11}", example: "812 3456 7890"),
                    navigationApps: [.googleMaps, .waze, .appleMaps]),
        CountryInfo(code: "TH", nameZh: String(localized: "泰国"), callingCode: "66", currencyCode: "THB", currencySymbol: "฿",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 9...9, pattern: "[689][0-9]{8}", example: "81 234 5678"),
                    navigationApps: [.googleMaps, .appleMaps]),
        CountryInfo(code: "VN", nameZh: String(localized: "越南"), callingCode: "84", currencyCode: "VND", currencySymbol: "₫",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 9...9, pattern: "[35789][0-9]{8}", example: "91 234 5678"),
                    navigationApps: [.googleMaps, .appleMaps]),
        CountryInfo(code: "PH", nameZh: String(localized: "菲律宾"), callingCode: "63", currencyCode: "PHP", currencySymbol: "₱",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 10...10, pattern: "9[0-9]{9}", example: "917 123 4567"),
                    navigationApps: [.googleMaps, .waze, .appleMaps]),
        CountryInfo(code: "DK", nameZh: String(localized: "丹麦"), callingCode: "45", currencyCode: "DKK", currencySymbol: "kr ",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 8...8, pattern: "[2-9][0-9]{7}", example: "20 12 34 56"),
                    navigationApps: [.appleMaps, .googleMaps]),
        CountryInfo(code: "NZ", nameZh: String(localized: "新西兰"), callingCode: "64", currencyCode: "NZD", currencySymbol: "NZ$",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 8...10, pattern: "2[0-9]{7,9}", example: "21 123 4567"),
                    navigationApps: [.googleMaps, .appleMaps, .waze]),
        CountryInfo(code: "DE", nameZh: String(localized: "德国"), callingCode: "49", currencyCode: "EUR", currencySymbol: "€",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 10...11, pattern: "1[5-7][0-9]{8,9}", example: "1512 3456789"),
                    navigationApps: [.googleMaps, .appleMaps]),
        CountryInfo(code: "FR", nameZh: String(localized: "法国"), callingCode: "33", currencyCode: "EUR", currencySymbol: "€",
                    addressStyle: .smallToLarge,
                    phone: PhoneRule(lengths: 9...9, pattern: "[67][0-9]{8}", example: "6 12 34 56 78"),
                    navigationApps: [.googleMaps, .appleMaps, .waze])
    ]

    /// 未收录的国家：通用规则（6–14 位数字）
    static func generic(_ code: String) -> CountryInfo {
        let upper = code.uppercased()
        let currency = Locale(identifier: "en_\(upper)").currency?.identifier ?? "USD"
        return CountryInfo(code: upper, nameZh: Locale.current.localizedString(forRegionCode: upper) ?? upper,
                           callingCode: "", currencyCode: currency, currencySymbol: currency + " ",
                           addressStyle: .smallToLarge,
                           phone: PhoneRule(lengths: 6...14, pattern: nil, example: ""),
                           navigationApps: [.appleMaps, .googleMaps, .waze])
    }

    static func info(for code: String?) -> CountryInfo {
        guard let code, !code.isEmpty else { return defaultCountry }
        return all.first { $0.code == code.uppercased() } ?? generic(code)
    }

    /// 首发市场
    static let defaultCountry = all[0]

    /// 设备所在地区（用于手机号默认国家码）；未知时为美国
    static var deviceCountry: CountryInfo {
        guard let region = Locale.current.region?.identifier,
              let info = all.first(where: { $0.code == region }) else { return defaultCountry }
        return info
    }

    /// 支持手机号登录的国家/地区
    static var phoneCountries: [CountryInfo] { all }
}

// MARK: - 金额

enum Money {
    /// 整数金额 + 币种符号，如 "$12"、"¥80"、"RM 15"
    static func format(_ amount: Int, currency code: String) -> String {
        let symbol = CountryInfo.all.first { $0.currencyCode == code }?.currencySymbol ?? code + " "
        return symbol + amount.formatted(.number.grouping(.automatic))
    }

    /// 与币种对应的 SF Symbol
    static func icon(for code: String) -> String {
        switch code {
        case "CNY", "JPY": return "yensign.circle.fill"
        case "GBP": return "sterlingsign.circle.fill"
        case "EUR": return "eurosign.circle.fill"
        case "INR": return "indianrupeesign.circle.fill"
        case "KRW": return "wonsign.circle.fill"
        default: return "dollarsign.circle.fill"
        }
    }
}

// MARK: - 手机号（E.164）

struct PhoneNumber: Hashable {
    let country: CountryInfo
    /// 国内号码（已去掉开头的 0 与分隔符）
    let national: String

    init(country: CountryInfo, national input: String) {
        self.country = country
        var digits = input.filter { $0.isASCII && $0.isNumber }
        // 去掉国内长途前缀 0（日本 090…、英国 07…、马来西亚 012… 等）
        while digits.hasPrefix("0") && digits.count > country.phone.lengths.lowerBound { digits.removeFirst() }
        // 北美用户常把国家码 1 一起输入
        if country.callingCode == "1", digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        self.national = digits
    }

    var isValid: Bool { !country.callingCode.isEmpty && country.phone.isValid(national: national) }

    /// 存储格式：+16265550123
    var e164: String { "+" + country.callingCode + national }

    /// 展示格式：+1 626 555 0123
    var display: String { "+\(country.callingCode) " + Self.group(national, country: country) }

    /// 脱敏展示：+1 626 *** 0123
    var masked: String {
        guard national.count >= 7 else { return display }
        let head = String(national.prefix(3))
        let tail = String(national.suffix(4))
        return "+\(country.callingCode) \(head) *** \(tail)"
    }

    /// 解析 E.164（"+16265550123"）；兼容旧数据中不带国家码的 11 位大陆手机号
    static func parse(_ stored: String) -> PhoneNumber? {
        if stored.hasPrefix("+") {
            let digits = String(stored.dropFirst())
            // 最长前缀匹配国家码（852 优先于 8x）
            let candidates = CountryInfo.all
                .filter { digits.hasPrefix($0.callingCode) }
                .sorted { $0.callingCode.count > $1.callingCode.count }
            for country in candidates {
                let number = PhoneNumber(country: country, national: String(digits.dropFirst(country.callingCode.count)))
                if number.isValid { return number }
            }
            return nil
        }
        let legacy = PhoneNumber(country: CountryInfo.info(for: "CN"), national: stored)
        return legacy.isValid ? legacy : nil
    }

    private static func group(_ digits: String, country: CountryInfo) -> String {
        let chars = Array(digits)
        let sizes: [Int]
        switch (country.callingCode, chars.count) {
        case ("1", 10): sizes = [3, 3, 4]
        case ("86", 11): sizes = [3, 4, 4]
        default: sizes = chars.count > 8 ? [chars.count - 8, 4, 4] : [chars.count - 4, 4]
        }
        var result: [String] = []
        var index = 0
        for size in sizes where size > 0 && index < chars.count {
            let end = min(chars.count, index + size)
            result.append(String(chars[index..<end]))
            index = end
        }
        if index < chars.count { result.append(String(chars[index...])) }
        return result.joined(separator: " ")
    }
}
