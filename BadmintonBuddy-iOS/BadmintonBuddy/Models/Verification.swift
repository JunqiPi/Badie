import Foundation

// MARK: - 高水平认证申请
//
// 7 起的档位只看能公开查到的证据，由人工审核：
// - 赛事成绩：tournamentsoftware.com 上公开的签表和成绩（按“最高组 / 次高组”的相对位置认定）
// - 全国排名 / 运动员等级：USAB 全国排名，或《运动员技术等级标准》电子证书（15 位编号，末位是等级码）
// - BWF：bwfbadminton.com 的球员页，看世界排名和赛果；只有 BWF ID 不够（报老将赛也要 BWF ID）
// 审核时核对证据上的姓名与本人证件，避免冒用别人的成绩。bwfbadminton.com 拒绝自动抓取，只能人工打开核验。

struct VerificationRequest: Identifiable, Codable, Hashable {
    enum Status: String, Codable, Hashable {
        case pending
        case approved
        case rejected
    }

    let id: String
    let userId: String
    let kind: VerificationStatus
    /// 申请的档位分值
    let claimedRating: Double
    /// 证据链接
    let evidenceURL: String
    /// 证据上的姓名（和证件核对）
    let nameOnRecord: String
    var note: String
    let submittedAt: Date
    var status: Status
    var reviewedAt: Date?
    var reviewNote: String?
    /// 审核通过的档位（可能比申请的低）
    var approvedRating: Double?

    var claimedTier: SkillTier { SkillTier(rating: claimedRating) }

    /// 一般几个工作日内审核
    static let reviewDays = 3
}

enum VerificationEvidence {

    /// 运动员技术等级电子证书（2025 起）：15 位，最后一位是等级码
    /// X = 国际级运动健将，0 = 运动健将，1 = 一级，2 = 二级，3 = 三级
    static func certificateMaxTier(_ text: String) -> SkillTier? {
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 15, code.dropLast().allSatisfy { $0.isASCII && $0.isNumber }, let last = code.last else { return nil }
        switch last {
        case "X", "0": return SkillTier(level: 8, modifier: .plus)
        case "1": return SkillTier(level: 8)
        case "2": return SkillTier(level: 8, modifier: .minus)
        case "3": return SkillTier(level: 7, modifier: .plus)
        default: return nil
        }
    }

    /// 每类证据接受的链接（为空表示任何 https 链接都可以，由人工判断）
    static func acceptedHosts(for kind: VerificationStatus) -> [String] {
        switch kind {
        case .bwf: return ["bwfbadminton.com", "bwf.tournamentsoftware.com", "bwfworldtour.bwfbadminton.com"]
        case .tournament: return ["tournamentsoftware.com"]
        case .national, .unverified: return []
        }
    }

    /// 填写提示
    static func placeholder(for kind: VerificationStatus) -> String {
        switch kind {
        case .bwf: return "bwfbadminton.com/player/12345/your-name"
        case .tournament: return "usab.tournamentsoftware.com/… 的成绩页"
        case .national: return "USAB 排名页链接，或 15 位电子证书编号"
        case .unverified: return ""
        }
    }

    /// 检查链接；有问题时返回原因
    static func problem(with link: String, for kind: VerificationStatus) -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请填写证据链接" }
        if kind == .national, certificateMaxTier(trimmed) != nil { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let host = url.host?.lowercased(),
              url.scheme?.lowercased() == "https", host.contains(".") else {
            return "链接格式不对，请复制完整的网页地址"
        }
        let hosts = acceptedHosts(for: kind)
        if !hosts.isEmpty, !hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return kind == .bwf
                ? "需要 BWF 官网的球员页（bwfbadminton.com/player/…）"
                : "需要 tournamentsoftware.com 上的成绩页"
        }
        if kind == .bwf {
            let path = url.path.lowercased()
            let isPlayerPage = path.hasPrefix("/player/") || path.hasPrefix("/player-profile/")
            let hasId = path.split(separator: "/").dropFirst().first.map { !$0.isEmpty } ?? false
            guard isPlayerPage, hasId else { return "需要具体的球员页，链接里要有球员 ID" }
        }
        return nil
    }

    /// 补全 https://（证书编号原样保留）
    static func normalized(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if certificateMaxTier(trimmed) != nil { return trimmed.uppercased() }
        return trimmed.contains("://") ? trimmed : "https://" + trimmed
    }
}
