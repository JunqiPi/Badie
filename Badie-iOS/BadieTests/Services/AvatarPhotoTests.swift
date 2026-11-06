import XCTest
@testable import Badie

/// 头像照片：上传后别人能看到，改资料不会丢照片，移除后恢复文字头像
@MainActor
final class AvatarPhotoTests: XCTestCase {

    func testUploadIsVisibleAndSurvivesProfileEdits() async throws {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        let me = backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 4, seedsDemoContent: false)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let uploaded = try await backend.uploadAvatarPhoto(jpeg)
        XCTAssertEqual(uploaded.avatar.photoVersion, 1)
        XCTAssertEqual(backend.db.avatarPhotos[me.id], jpeg)
        XCTAssertEqual(backend.user(id: me.id)?.avatar.photoVersion, 1, "其他人读到的资料里也有照片")

        var edited = uploaded
        edited.nickname = "阿杰2"
        edited.avatar = Avatar(symbol: "🏸", paletteIndex: 2)
        let saved = try await backend.updateProfile(edited)
        XCTAssertEqual(saved.avatar.photoVersion, 1, "改昵称、颜色不影响照片")
        XCTAssertEqual(saved.avatar.paletteIndex, 2)

        _ = try await backend.uploadAvatarPhoto(jpeg)
        XCTAssertEqual(backend.currentUser?.avatar.photoVersion, 2, "重新上传换新版本，刷新缓存")

        backend.removeAvatarPhoto()
        XCTAssertNil(backend.currentUser?.avatar.photoVersion)
        XCTAssertNil(backend.db.avatarPhotos[me.id])
    }

    /// 卡片背景和头像分开：各自上传、移除，互不影响；卡片颜色随资料保存
    func testCardPhotoIsSeparateFromAvatar() async throws {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        let me = backend.createAccount(phone: "+16265550124", nickname: "阿杰", level: 4, seedsDemoContent: false)
        let avatar = Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        let cover = Data([0xFF, 0xD8, 0x02, 0xFF, 0xD9])

        _ = try await backend.uploadAvatarPhoto(avatar)
        let uploaded = try await backend.uploadCardPhoto(cover)
        XCTAssertEqual(uploaded.avatar.cardPhotoVersion, 1)
        XCTAssertEqual(backend.db.avatarPhotos[AvatarPhotos.cardKey(me.id)], cover)
        XCTAssertEqual(backend.db.avatarPhotos[me.id], avatar, "头像不变")

        var edited = uploaded
        edited.avatar.cardColor = .ink
        let saved = try await backend.updateProfile(edited)
        XCTAssertEqual(saved.avatar.cardColor, .ink)
        XCTAssertEqual(saved.avatar.cardPhotoVersion, 1, "改颜色不影响背景照片")

        backend.removeCardPhoto()
        XCTAssertNil(backend.currentUser?.avatar.cardPhotoVersion)
        XCTAssertNil(backend.db.avatarPhotos[AvatarPhotos.cardKey(me.id)])
        XCTAssertEqual(backend.currentUser?.avatar.photoVersion, 1, "移除背景不影响头像")
    }

    /// 没选过颜色：按用户 ID 给的默认色固定不变，也不会是墨黑
    func testDefaultCardColor() {
        for id in ["a", "00000000-0000-0000-0000-000000000001", UUID().uuidString.lowercased()] {
            XCTAssertEqual(CardColor.default(for: id), CardColor.default(for: id))
            XCTAssertNotEqual(CardColor.default(for: id), .ink)
        }
        // 和网站用同一个算法：djb2 & 0x7fffffff，再对 7 种浅色取余
        XCTAssertEqual(CardColor.default(for: "00000000-0000-0000-0000-000000000001"), .lavender)
    }
}
