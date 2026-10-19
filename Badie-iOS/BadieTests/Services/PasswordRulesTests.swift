import XCTest
@testable import Badie

/// 密码规则：长度，和“泄露过的密码”查询（只发 SHA-1 前 5 位，查不了就放行）。和网页的 password.test.ts 同样的用例
final class PasswordRulesTests: XCTestCase {
    /// "password" 的 SHA-1 是 5BAA6 1E4C9B93F3F0682250B6CF8331B7EE68FD8
    private func list(_ lines: [String]) -> SupabaseClient.Transport {
        { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.pwnedpasswords.com/range/5BAA6", "只发前 5 位")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Add-Padding"), "true")
            return (Data(lines.joined(separator: "\r\n").utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testRules() async {
        let tooShort = await PasswordRules.problem("short", lookup: list([]))
        XCTAssertEqual(tooShort, String(localized: "密码至少要 8 位。"))
        let leaked = await PasswordRules.problem("password", lookup: list(["0018A45C4D1DEF81644B54AB7F969B88D65:1", "1E4C9B93F3F0682250B6CF8331B7EE68FD8:9545824"]))
        XCTAssertEqual(leaked, String(localized: "这个密码在数据泄露中出现过，请换一个。"))
        let padding = await PasswordRules.problem("password", lookup: list(["1E4C9B93F3F0682250B6CF8331B7EE68FD8:0"]))
        XCTAssertNil(padding, "次数为 0 的是混进来的假条目")
        let offline = await PasswordRules.problem("correct horse battery") { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertNil(offline, "查不了就放行")
        let tooLong = await PasswordRules.problem(String(repeating: "x", count: 73), lookup: list([]))
        XCTAssertEqual(tooLong, String(localized: "密码太长了，请换个短一点的。"))
    }
}
