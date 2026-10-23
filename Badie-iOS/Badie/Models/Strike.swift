import Foundation

/// 我的爽约记录（近 180 天）：180 天内第 1 次警告、第 2 次 7 天不能约球、第 3 次永久；48 小时内可以申诉
struct MyStrikes: Equatable {
    enum Status: String {
        case active, appealed, upheld, overturned
    }

    struct Strike: Identifiable, Equatable {
        let id: Int
        let level: Int
        let status: Status
        let createdAt: Date
        let seen: Bool
        let canAppeal: Bool
        /// 那场球的开始时间和球馆
        let startsAt: Date
        let venue: String?
    }

    /// 不能约球到什么时候；永久是 distantFuture
    let suspendedUntil: Date?
    /// 近 180 天算数的次数（申诉中和撤销的不算）
    let recent: Int
    let strikes: [Strike]
}

extension Date {
    /// “暂停约球至 11月2日 19:00” / “已暂停约球”
    var suspensionText: String {
        self == .distantFuture ? String(localized: "已暂停约球")
            : String(localized: "暂停约球至 \(formatted(.dateTime.month().day().hour().minute()))")
    }
}
