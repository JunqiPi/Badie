import XCTest
@testable import Badie

/// 临时诊断：哪种查找方式会跟着所选语言
@MainActor
final class AppLanguageProbeTests: XCTestCase {
    override func tearDown() { AppLanguage.choose(nil); super.tearDown() }

    private var en: Bundle { Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)! }

    func testProbeLocaleParameter() {
        XCTAssertEqual(String(localized: "设置", locale: Locale(identifier: "en")), "Settings")
    }

    func testProbeExplicitBundle() {
        XCTAssertEqual(String(localized: "设置", bundle: en), "Settings")
    }

    func testProbeNSLocalizedString() {
        AppLanguage.choose("en")
        XCTAssertEqual(NSLocalizedString("设置", comment: ""), "Settings")
    }

    func testProbeInterpolationExplicitBundle() {
        let n = 3
        XCTAssertEqual(String(localized: "近 180 天爽约 \(n) 次", bundle: en), "Missed games in 180 days: 3")
    }

    func testProbeResource() {
        AppLanguage.choose("en")
        var resource = LocalizedStringResource("设置")
        resource.locale = Locale(identifier: "en")
        XCTAssertEqual(String(localized: resource), "Settings")
    }
}
