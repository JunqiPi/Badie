import XCTest
@testable import BadmintonBuddy

final class PersistenceServiceTests: XCTestCase {

    private var sut: PersistenceService!
    private var testUserDefaults: UserDefaults!
    private let testKeyPrefix = "TestBadmintonBuddy_"

    override func setUp() {
        super.setUp()
        // 独立的 UserDefaults suite，避免污染真实数据
        testUserDefaults = UserDefaults(suiteName: "com.badmintonbuddy.tests")
        sut = PersistenceService(userDefaults: testUserDefaults!, keyPrefix: testKeyPrefix)
    }

    override func tearDown() {
        sut.clearAll()
        testUserDefaults.removePersistentDomain(forName: "com.badmintonbuddy.tests")
        testUserDefaults = nil
        sut = nil
        super.tearDown()
    }

    // MARK: Test Models

    struct TestModel: Codable, Equatable {
        let id: String
        let name: String
        let value: Int
    }

    struct TestModelWithDate: Codable, Equatable {
        let id: String
        let createdAt: Date
    }

    struct TestNestedModel: Codable, Equatable {
        let id: String
        let items: [TestModel]
    }

    // MARK: Save Tests

    func testSave_withValidObject_shouldSucceed() throws {
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testKey"

        try sut.save(model, key: key)

        XCTAssertTrue(sut.exists(key: key), "保存后数据应该存在")
    }

    func testSave_withDateObject_shouldSucceed() throws {
        let model = TestModelWithDate(id: "1", createdAt: Date())
        let key = "testDateKey"

        try sut.save(model, key: key)

        XCTAssertTrue(sut.exists(key: key), "带日期的对象保存后应该存在")
    }

    func testSave_withNestedObject_shouldSucceed() throws {
        let items = [
            TestModel(id: "1", name: "项目1", value: 10),
            TestModel(id: "2", name: "项目2", value: 20)
        ]
        let model = TestNestedModel(id: "nested", items: items)
        let key = "testNestedKey"

        try sut.save(model, key: key)

        XCTAssertTrue(sut.exists(key: key), "嵌套对象保存后应该存在")
    }

    func testSave_withEmptyArray_shouldSucceed() throws {
        let emptyArray: [TestModel] = []
        let key = "testEmptyArrayKey"

        try sut.save(emptyArray, key: key)

        XCTAssertTrue(sut.exists(key: key), "空数组保存后应该存在")
    }

    // MARK: Load Tests

    func testLoad_withExistingKey_shouldReturnObject() throws {
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testLoadKey"
        try sut.save(model, key: key)

        let loaded = try sut.load(key: key, type: TestModel.self)

        XCTAssertNotNil(loaded, "加载的对象不应为 nil")
        XCTAssertEqual(loaded, model, "加载的对象应与保存的对象相等")
    }

    func testLoad_withNonExistingKey_shouldReturnNil() throws {
        let key = "nonExistingKey"

        let loaded = try sut.load(key: key, type: TestModel.self)

        XCTAssertNil(loaded, "不存在的键应返回 nil")
    }

    func testLoad_withDateObject_shouldPreserveDate() throws {
        let originalDate = Date()
        let model = TestModelWithDate(id: "1", createdAt: originalDate)
        let key = "testDateLoadKey"
        try sut.save(model, key: key)

        let loaded = try sut.load(key: key, type: TestModelWithDate.self)

        XCTAssertNotNil(loaded, "加载的对象不应为 nil")
        // ISO8601 格式会丢失毫秒精度，所以比较时允许 1 秒误差
        XCTAssertEqual(
            loaded?.createdAt.timeIntervalSince1970 ?? 0,
            originalDate.timeIntervalSince1970,
            accuracy: 1.0,
            "日期应该被正确保存和加载"
        )
    }

    func testLoad_withNestedObject_shouldReturnCompleteObject() throws {
        let items = [
            TestModel(id: "1", name: "项目1", value: 10),
            TestModel(id: "2", name: "项目2", value: 20)
        ]
        let model = TestNestedModel(id: "nested", items: items)
        let key = "testNestedLoadKey"
        try sut.save(model, key: key)

        let loaded = try sut.load(key: key, type: TestNestedModel.self)

        XCTAssertNotNil(loaded, "加载的嵌套对象不应为 nil")
        XCTAssertEqual(loaded, model, "嵌套对象应完整保存和加载")
        XCTAssertEqual(loaded?.items.count, 2, "嵌套数组应包含所有项目")
    }

    func testLoad_withWrongType_shouldThrowDecodingError() {
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testWrongTypeKey"
        try? sut.save(model, key: key)

        XCTAssertThrowsError(try sut.load(key: key, type: TestModelWithDate.self)) { error in
            guard case PersistenceError.decodingFailed = error else {
                XCTFail("应该抛出 decodingFailed 错误，实际抛出: \(error)")
                return
            }
        }
    }

    // MARK: Delete Tests

    func testDelete_withExistingKey_shouldRemoveData() throws {
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testDeleteKey"
        try sut.save(model, key: key)
        XCTAssertTrue(sut.exists(key: key), "删除前数据应该存在")

        try sut.delete(key: key)

        XCTAssertFalse(sut.exists(key: key), "删除后数据不应该存在")
    }

    func testDelete_withNonExistingKey_shouldNotThrow() throws {
        let key = "nonExistingDeleteKey"

        XCTAssertNoThrow(try sut.delete(key: key), "删除不存在的键不应抛出错误")
    }

    // MARK: Round-Trip Tests

    func testRoundTrip_withMultipleSaveLoad_shouldMaintainData() throws {
        let key = "testRoundTripKey"

        for i in 1...5 {
            let model = TestModel(id: "\(i)", name: "测试\(i)", value: i * 10)
            try sut.save(model, key: key)
            let loaded = try sut.load(key: key, type: TestModel.self)

            XCTAssertEqual(loaded, model, "第 \(i) 次往返应保持数据一致")
        }
    }

    func testRoundTrip_withOverwrite_shouldReturnLatestData() throws {
        let key = "testOverwriteKey"
        let model1 = TestModel(id: "1", name: "原始", value: 10)
        let model2 = TestModel(id: "2", name: "更新", value: 20)

        try sut.save(model1, key: key)
        try sut.save(model2, key: key)
        let loaded = try sut.load(key: key, type: TestModel.self)

        XCTAssertEqual(loaded, model2, "应返回最新保存的数据")
    }

    // MARK: Convenience Method Tests

    func testExists_withExistingKey_shouldReturnTrue() throws {
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testExistsKey"
        try sut.save(model, key: key)

        let exists = sut.exists(key: key)

        XCTAssertTrue(exists, "存在的键应返回 true")
    }

    func testExists_withNonExistingKey_shouldReturnFalse() {
        let key = "nonExistingExistsKey"

        let exists = sut.exists(key: key)

        XCTAssertFalse(exists, "不存在的键应返回 false")
    }

    func testAllKeys_shouldReturnAllSavedKeys() throws {
        let keys = ["key1", "key2", "key3"]
        for key in keys {
            let model = TestModel(id: key, name: "测试", value: 1)
            try sut.save(model, key: key)
        }

        let allKeys = sut.allKeys()

        XCTAssertEqual(Set(allKeys), Set(keys), "应返回所有保存的键")
    }

    func testClearAll_shouldRemoveAllData() throws {
        let keys = ["clearKey1", "clearKey2", "clearKey3"]
        for key in keys {
            let model = TestModel(id: key, name: "测试", value: 1)
            try sut.save(model, key: key)
        }

        sut.clearAll()

        for key in keys {
            XCTAssertFalse(sut.exists(key: key), "清除后键 \(key) 不应存在")
        }
        XCTAssertTrue(sut.allKeys().isEmpty, "清除后应没有任何键")
    }

    // MARK: Error Position Tests

    func testLoad_withInvalidJSON_shouldIncludeErrorPosition() {
        let key = "testInvalidJSONKey"
        let prefixedKey = "\(testKeyPrefix)\(key)"
        let invalidJSON = "{\"id\": 123}".data(using: .utf8)! // id 应该是 String，不是 Int
        testUserDefaults.set(invalidJSON, forKey: prefixedKey)

        XCTAssertThrowsError(try sut.load(key: key, type: TestModel.self)) { error in
            guard case PersistenceError.decodingFailed(_, let position) = error else {
                XCTFail("应该抛出 decodingFailed 错误")
                return
            }
            XCTAssertNotNil(position, "解码错误应包含位置信息")
        }
    }
}
