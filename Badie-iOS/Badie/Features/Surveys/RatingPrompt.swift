import Foundation

/// App Store 评分弹窗：打过 2 场以上、刚给球友打了好评时才问。苹果一年最多弹 3 次，我们再限 120 天最多一次
enum RatingPrompt {
    private static let key = "ratingPromptAskedAt"
    static let interval: TimeInterval = 120 * 86_400

    static func shouldAsk(totalGames: Int, positive: Bool, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard positive, totalGames >= 2 else { return false }
        guard let last = defaults.object(forKey: key) as? Date else { return true }
        return now.timeIntervalSince(last) > interval
    }

    static func markAsked(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: key)
    }
}
