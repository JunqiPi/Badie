import Foundation

/// 项目：男单 / 女单 / 男双 / 女双（只和自己同性别的人打）、混双（两男两女，每边一男一女）。
/// 没有项目（nil）= 不限，男女都可以，女子等级按低 1.5 级换算。
/// 混双里男生和男生比、女生和女生比，所以等级不换算，各按各的
enum PlayEvent: String, Codable, Hashable, Identifiable {
    case men, women, mixed

    var id: String { rawValue }

    /// 能选的项目（含不限 = nil）：只能选自己的性别；混双只有双打，也要先选性别
    static func choices(mode: GameMode, gender: Gender) -> [PlayEvent?] {
        guard gender != .unspecified else { return [nil] }
        let own: PlayEvent = gender == .female ? .women : .men
        return mode == .doubles ? [nil, own, .mixed] : [nil, own]
    }

    /// 服务器存的是性别限制和是否混双
    init?(gender: Gender?, mixed: Bool) {
        if mixed { self = .mixed; return }
        switch gender {
        case .male: self = .men
        case .female: self = .women
        default: return nil
        }
    }

    /// 发给服务器的性别限制（混双没有）
    var gender: Gender? {
        switch self {
        case .men: return .male
        case .women: return .female
        case .mixed: return nil
        }
    }

    func title(mode: GameMode) -> String {
        switch (self, mode) {
        case (.men, .singles): return String(localized: "男单")
        case (.men, .doubles): return String(localized: "男双")
        case (.women, .singles): return String(localized: "女单")
        case (.women, .doubles): return String(localized: "女双")
        case (.mixed, _): return String(localized: "混双")
        }
    }

    /// 选项下面的说明
    static func caption(_ event: PlayEvent?) -> String {
        switch event {
        case .mixed: return String(localized: "每边一男一女。男生和男生比、女生和女生比，所以等级不换算。")
        case .women: return String(localized: "只有女生能加入，按女子等级算。")
        case .men: return String(localized: "只有男生能加入。")
        case nil: return String(localized: "男女一起打时，女子等级按低约 1.5 级来算，这样比赛势均力敌。")
        }
    }
}

extension Optional where Wrapped == PlayEvent {
    /// 不限显示单打 / 双打
    func title(mode: GameMode) -> String { self?.title(mode: mode) ?? mode.title }
}
