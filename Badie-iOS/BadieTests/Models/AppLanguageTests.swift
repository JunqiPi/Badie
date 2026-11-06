import XCTest
@testable import Badie

/// 在 App 里换语言：马上按所选语言显示文字；选“跟随系统”就回到系统语言
@MainActor
final class AppLanguageTests: XCTestCase {

    override func tearDown() {
        AppLanguage.choose(nil)
        super.tearDown()
    }

    func testChoosingLanguageChangesStringsRightAway() {
        XCTAssertNotNil(Bundle.main.path(forResource: "en", ofType: "lproj"), "打包里有英文文字表")
        AppLanguage.choose("en")
        XCTAssertEqual(AppLanguage.chosen, "en")
        XCTAssertEqual(Bundle.main.localizedString(forKey: "设置", value: nil, table: nil), "Settings", "直接查")
        XCTAssertEqual(String(localized: "设置"), "Settings")

        AppLanguage.choose("ko")
        XCTAssertEqual(String(localized: "设置"), "설정")
        XCTAssertEqual(MockBackend.serverLocale, "ko", "通知、邮件也用这种语言")

        AppLanguage.choose("zh-Hans")
        XCTAssertEqual(String(localized: "设置"), "设置")

        AppLanguage.choose(nil)
        XCTAssertNil(AppLanguage.chosen)
        XCTAssertTrue(AppLanguage.supported.contains(AppLanguage.current))
    }

    func testUnknownLanguageFollowsSystem() {
        AppLanguage.choose("fr")
        XCTAssertNil(AppLanguage.chosen)
    }
}
