//
//  PersistenceServiceTests.swift
//  BadmintonBuddyTests
//
//  PersistenceService 单元测试
//  验证 JSON 持久化服务的保存、加载、删除功能
//

import XCTest
@testable import BadmintonBuddy

final class PersistenceServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    /// 测试用的持久化服务实例
    private var sut: PersistenceService!
    
    /// 测试用的 UserDefaults 实例
    private var testUserDefaults: UserDefaults!
    
    /// 测试键前缀
    private let testKeyPrefix = "TestBadmintonBuddy_"
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        // 使用独立的 UserDefaults suite 进行测试，避免污染真实数据
        testUserDefaults = UserDefaults(suiteName: "com.badmintonbuddy.tests")
        sut = PersistenceService(userDefaults: testUserDefaults!, keyPrefix: testKeyPrefix)
    }
    
    override func tearDown() {
        // 清理测试数据
        sut.clearAll()
        testUserDefaults.removePersistentDomain(forName: "com.badmintonbuddy.tests")
        testUserDefaults = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Test Models
    
    /// 测试用的简单模型
    struct TestModel: Codable, Equatable {
        let id: String
        let name: String
        let value: Int
    }
    
    /// 测试用的带日期的模型
    struct TestModelWithDate: Codable, Equatable {
        let id: String
        let createdAt: Date
    }
    
    /// 测试用的嵌套模型
    struct TestNestedModel: Codable, Equatable {
        let id: String
        let items: [TestModel]
    }
    
    // MARK: - Save Tests
    
    func testSave_withValidObject_shouldSucceed() throws {
        // Given
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testKey"
        
        // When
        try sut.save(model, key: key)
        
        // Then
        XCTAssertTrue(sut.exists(key: key), "保存后数据应该存在")
    }
    
    func testSave_withDateObject_shouldSucceed() throws {
        // Given
        let model = TestModelWithDate(id: "1", createdAt: Date())
        let key = "testDateKey"
        
        // When
        try sut.save(model, key: key)
        
        // Then
        XCTAssertTrue(sut.exists(key: key), "带日期的对象保存后应该存在")
    }
    
    func testSave_withNestedObject_shouldSucceed() throws {
        // Given
        let items = [
            TestModel(id: "1", name: "项目1", value: 10),
            TestModel(id: "2", name: "项目2", value: 20)
        ]
        let model = TestNestedModel(id: "nested", items: items)
        let key = "testNestedKey"
        
        // When
        try sut.save(model, key: key)
        
        // Then
        XCTAssertTrue(sut.exists(key: key), "嵌套对象保存后应该存在")
    }
    
    func testSave_withEmptyArray_shouldSucceed() throws {
        // Given
        let emptyArray: [TestModel] = []
        let key = "testEmptyArrayKey"
        
        // When
        try sut.save(emptyArray, key: key)
        
        // Then
        XCTAssertTrue(sut.exists(key: key), "空数组保存后应该存在")
    }
    
    // MARK: - Load Tests
    
    func testLoad_withExistingKey_shouldReturnObject() throws {
        // Given
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testLoadKey"
        try sut.save(model, key: key)
        
        // When
        let loaded = try sut.load(key: key, type: TestModel.self)
        
        // Then
        XCTAssertNotNil(loaded, "加载的对象不应为 nil")
        XCTAssertEqual(loaded, model, "加载的对象应与保存的对象相等")
    }
    
    func testLoad_withNonExistingKey_shouldReturnNil() throws {
        // Given
        let key = "nonExistingKey"
        
        // When
        let loaded = try sut.load(key: key, type: TestModel.self)
        
        // Then
        XCTAssertNil(loaded, "不存在的键应返回 nil")
    }
    
    func testLoad_withDateObject_shouldPreserveDate() throws {
        // Given
        let originalDate = Date()
        let model = TestModelWithDate(id: "1", createdAt: originalDate)
        let key = "testDateLoadKey"
        try sut.save(model, key: key)
        
        // When
        let loaded = try sut.load(key: key, type: TestModelWithDate.self)
        
        // Then
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
        // Given
        let items = [
            TestModel(id: "1", name: "项目1", value: 10),
            TestModel(id: "2", name: "项目2", value: 20)
        ]
        let model = TestNestedModel(id: "nested", items: items)
        let key = "testNestedLoadKey"
        try sut.save(model, key: key)
        
        // When
        let loaded = try sut.load(key: key, type: TestNestedModel.self)
        
        // Then
        XCTAssertNotNil(loaded, "加载的嵌套对象不应为 nil")
        XCTAssertEqual(loaded, model, "嵌套对象应完整保存和加载")
        XCTAssertEqual(loaded?.items.count, 2, "嵌套数组应包含所有项目")
    }
    
    func testLoad_withWrongType_shouldThrowDecodingError() {
        // Given
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testWrongTypeKey"
        try? sut.save(model, key: key)
        
        // When/Then
        XCTAssertThrowsError(try sut.load(key: key, type: TestModelWithDate.self)) { error in
            guard case PersistenceError.decodingFailed = error else {
                XCTFail("应该抛出 decodingFailed 错误，实际抛出: \(error)")
                return
            }
        }
    }
    
    // MARK: - Delete Tests
    
    func testDelete_withExistingKey_shouldRemoveData() throws {
        // Given
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testDeleteKey"
        try sut.save(model, key: key)
        XCTAssertTrue(sut.exists(key: key), "删除前数据应该存在")
        
        // When
        try sut.delete(key: key)
        
        // Then
        XCTAssertFalse(sut.exists(key: key), "删除后数据不应该存在")
    }
    
    func testDelete_withNonExistingKey_shouldNotThrow() throws {
        // Given
        let key = "nonExistingDeleteKey"
        
        // When/Then
        XCTAssertNoThrow(try sut.delete(key: key), "删除不存在的键不应抛出错误")
    }
    
    // MARK: - Round-Trip Tests
    
    func testRoundTrip_withMultipleSaveLoad_shouldMaintainData() throws {
        // Given
        let key = "testRoundTripKey"
        
        // When - 多次保存和加载
        for i in 1...5 {
            let model = TestModel(id: "\(i)", name: "测试\(i)", value: i * 10)
            try sut.save(model, key: key)
            let loaded = try sut.load(key: key, type: TestModel.self)
            
            // Then
            XCTAssertEqual(loaded, model, "第 \(i) 次往返应保持数据一致")
        }
    }
    
    func testRoundTrip_withOverwrite_shouldReturnLatestData() throws {
        // Given
        let key = "testOverwriteKey"
        let model1 = TestModel(id: "1", name: "原始", value: 10)
        let model2 = TestModel(id: "2", name: "更新", value: 20)
        
        // When
        try sut.save(model1, key: key)
        try sut.save(model2, key: key)
        let loaded = try sut.load(key: key, type: TestModel.self)
        
        // Then
        XCTAssertEqual(loaded, model2, "应返回最新保存的数据")
    }
    
    // MARK: - Convenience Method Tests
    
    func testExists_withExistingKey_shouldReturnTrue() throws {
        // Given
        let model = TestModel(id: "1", name: "测试", value: 42)
        let key = "testExistsKey"
        try sut.save(model, key: key)
        
        // When
        let exists = sut.exists(key: key)
        
        // Then
        XCTAssertTrue(exists, "存在的键应返回 true")
    }
    
    func testExists_withNonExistingKey_shouldReturnFalse() {
        // Given
        let key = "nonExistingExistsKey"
        
        // When
        let exists = sut.exists(key: key)
        
        // Then
        XCTAssertFalse(exists, "不存在的键应返回 false")
    }
    
    func testAllKeys_shouldReturnAllSavedKeys() throws {
        // Given
        let keys = ["key1", "key2", "key3"]
        for key in keys {
            let model = TestModel(id: key, name: "测试", value: 1)
            try sut.save(model, key: key)
        }
        
        // When
        let allKeys = sut.allKeys()
        
        // Then
        XCTAssertEqual(Set(allKeys), Set(keys), "应返回所有保存的键")
    }
    
    func testClearAll_shouldRemoveAllData() throws {
        // Given
        let keys = ["clearKey1", "clearKey2", "clearKey3"]
        for key in keys {
            let model = TestModel(id: key, name: "测试", value: 1)
            try sut.save(model, key: key)
        }
        
        // When
        sut.clearAll()
        
        // Then
        for key in keys {
            XCTAssertFalse(sut.exists(key: key), "清除后键 \(key) 不应存在")
        }
        XCTAssertTrue(sut.allKeys().isEmpty, "清除后应没有任何键")
    }
    
    // MARK: - Error Position Tests
    
    func testLoad_withInvalidJSON_shouldIncludeErrorPosition() {
        // Given - 直接写入无效的 JSON 数据
        let key = "testInvalidJSONKey"
        let prefixedKey = "\(testKeyPrefix)\(key)"
        let invalidJSON = "{\"id\": 123}".data(using: .utf8)! // id 应该是 String，不是 Int
        testUserDefaults.set(invalidJSON, forKey: prefixedKey)
        
        // When/Then
        XCTAssertThrowsError(try sut.load(key: key, type: TestModel.self)) { error in
            guard case PersistenceError.decodingFailed(_, let position) = error else {
                XCTFail("应该抛出 decodingFailed 错误")
                return
            }
            // 验证错误包含位置信息
            XCTAssertNotNil(position, "解码错误应包含位置信息")
        }
    }
}
