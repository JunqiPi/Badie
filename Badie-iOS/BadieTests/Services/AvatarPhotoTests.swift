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
}
