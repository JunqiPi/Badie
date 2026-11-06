import Foundation
import ObjectiveC

/// App 里自己选语言（不用去系统设置）。
/// - 选的语言写进本 App 的 AppleLanguages：和系统“App 首选语言”存在同一个地方，下次启动系统就按它来（日期格式、App 名字也跟着变）
/// - 这次启动马上生效：把 Bundle.main 的文字查找转到所选语言的 .lproj；界面用新的 locale 从头建一遍
enum AppLanguage {
    /// 和服务器（通知、邮件）一致的 10 种语言
    static let supported = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "id", "ms", "th", "vi", "hi"]
    /// 源语言：string catalog 里的 key 就是简体中文
    static let source = "zh-Hans"

    private static let chosenKey = "BadieLanguage"
    private static let appleLanguages = "AppleLanguages"

    /// 每种语言用它自己的写法显示
    static func name(_ code: String) -> String {
        switch code {
        case "en": "English"
        case "zh-Hans": "简体中文"
        case "zh-Hant": "繁體中文"
        case "ja": "日本語"
        case "ko": "한국어"
        case "id": "Bahasa Indonesia"
        case "ms": "Bahasa Melayu"
        case "th": "ไทย"
        case "vi": "Tiếng Việt"
        case "hi": "हिन्दी"
        default: code
        }
    }

    /// 在 App 里选过的语言；nil = 跟随系统
    static var chosen: String? {
        UserDefaults.standard.string(forKey: chosenKey).flatMap { supported.contains($0) ? $0 : nil }
    }

    /// 现在实际用的语言
    static var current: String { chosen ?? system }

    /// 跟随系统时用哪种：按系统的语言顺序挑第一个我们有的
    static var system: String {
        let preferences = UserDefaults.standard.stringArray(forKey: appleLanguages) ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferences).first ?? "en"
    }

    static var locale: Locale { Locale(identifier: current) }

    /// 所选语言的文字表（String(localized:) 要显式传进去才会换语言）
    static var bundle: Bundle { LocalizedBundle.table }

    /// 启动时调用：之前选过语言就接着用
    static func installAtLaunch() {
        LocalizedBundle.use(current)
    }

    /// 换语言（nil = 跟随系统）
    static func choose(_ code: String?) {
        let defaults = UserDefaults.standard
        if let code, supported.contains(code) {
            defaults.set(code, forKey: chosenKey)
            defaults.set([code], forKey: appleLanguages)
        } else {
            defaults.removeObject(forKey: chosenKey)
            // 删掉本 App 这一层，读到的就是系统的语言顺序
            defaults.removeObject(forKey: appleLanguages)
        }
        LocalizedBundle.use(current)
    }
}

/// 让 Bundle.main 按所选语言查文字（String(localized:)、Text 都走这里）
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    /// 所选语言的 .lproj；nil 表示用 key 本身（源语言简体中文没有单独的文字表时）
    nonisolated(unsafe) private static var target: Bundle?
    nonisolated(unsafe) private static var usesKeys = false
    nonisolated(unsafe) private static var installed = false
    /// 源语言没有单独的文字表时：用一个空目录，查不到就显示 key（key 就是简体中文）
    nonisolated(unsafe) private static var keysOnly: Bundle?

    static var table: Bundle {
        if let target = Self.target { return target }
        if Self.usesKeys {
            if keysOnly == nil {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("BadieKeys.bundle", isDirectory: true)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                keysOnly = Bundle(url: url)
            }
            if let keysOnly { return keysOnly }
        }
        return .main
    }

    static func use(_ code: String) {
        if !installed {
            object_setClass(Bundle.main, LocalizedBundle.self)
            addLocalizationsVariant()
            installed = true
        }
        target = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        usesKeys = target == nil && code == AppLanguage.source
    }

    /// 按所选语言查一条文字；没选过（target 为空、也不是源语言）返回 nil，交回系统查
    private static func lookup(_ key: String, _ value: String?, _ tableName: String?) -> String? {
        if let target = Self.target { return target.localizedString(forKey: key, value: value, table: tableName) }
        if usesKeys, tableName == nil || tableName == "Localizable" { return (value?.isEmpty == false ? value : nil) ?? key }
        return nil
    }

    /// String(localized:) 在新系统上走带 localizations 参数的查找（按语言列表挑），这个也要接过来
    private static func addLocalizationsVariant() {
        let selector = NSSelectorFromString("localizedStringForKey:value:table:localizations:")
        guard let original = class_getInstanceMethod(Bundle.self, selector) else { return }
        typealias Lookup = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?, NSArray?) -> NSString
        let superImp = unsafeBitCast(method_getImplementation(original), to: Lookup.self)
        let block: @convention(block) (AnyObject, NSString, NSString?, NSString?, NSArray?) -> NSString = { bundle, key, value, table, localizations in
            if let text = lookup(key as String, value as String?, table as String?) { return text as NSString }
            return superImp(bundle, selector, key, value, table, localizations)
        }
        class_addMethod(LocalizedBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(original))
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let text = Self.lookup(key, value, tableName) { return text }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension String {
    /// 和系统的 String(localized:) 一样，只是按 App 里选的语言查：系统那个只认启动时的语言，换了语言不会变
    init(localized value: String.LocalizationValue, comment: StaticString? = nil) {
        self.init(localized: value, table: nil, bundle: AppLanguage.bundle, locale: AppLanguage.locale, comment: comment)
    }
}
