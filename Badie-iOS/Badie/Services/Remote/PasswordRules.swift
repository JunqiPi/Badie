import CryptoKit
import Foundation

/// 密码规则（和网页一样）：至少 8 位，不强制大小写、数字、符号（NIST 800-63B 的建议）；注册、重设、修改时查一下是不是泄露过的密码。
/// 查法是 k-匿名：只把 SHA-1 的前 5 位发给 Have I Been Pwned，密码本身不离开手机。查不了（离线、超时）就放行
enum PasswordRules {
    static let minimumLength = 8
    /// Supabase 用 bcrypt，超过 72 字节的部分不起作用
    private static let maximumBytes = 72

    /// 返回要显示给用户的问题；没问题返回 nil
    static func problem(_ password: String,
                        lookup: @escaping SupabaseClient.Transport = { try await URLSession.shared.data(for: $0) }) async -> String? {
        if password.count < minimumLength { return String(localized: "密码至少要 8 位。") }
        if password.utf8.count > maximumBytes { return String(localized: "密码太长了，请换个短一点的。") }
        if await leaked(password, lookup: lookup) { return String(localized: "这个密码在数据泄露中出现过，请换一个。") }
        return nil
    }

    private static func leaked(_ password: String, lookup: SupabaseClient.Transport) async -> Bool {
        let hash = Insecure.SHA1.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined()
        var request = URLRequest(url: URL(string: "https://api.pwnedpasswords.com/range/\(hash.prefix(5))")!, timeoutInterval: 4)
        // 回复里混进次数为 0 的假条目，别人看流量大小也猜不出是哪个前缀
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        guard let (data, response) = try? await lookup(request), (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        let suffix = hash.dropFirst(5)
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).contains { line in
            let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && parts[0] == suffix && (Int(parts[1]) ?? 0) > 0
        }
    }
}
