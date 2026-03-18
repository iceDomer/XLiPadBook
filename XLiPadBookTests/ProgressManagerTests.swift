//
//  ProgressManagerTests.swift
//  XLiPadBookTests
//
//  ProgressManager 单元测试
//

import XCTest
@testable import XLiPadBook

final class ProgressManagerTests: XCTestCase {

    // MARK: - 测试生命周期

    override func setUp() {
        super.setUp()
        // 清理测试数据
        cleanUpTestData()
    }

    override func tearDown() {
        // 清理测试数据
        cleanUpTestData()
        super.tearDown()
    }

    private func cleanUpTestData() {
        let testBookIds = ["test_book_1", "test_book_2", "test_book_empty", "", "special_!@#$%"]
        for bookId in testBookIds {
            UserDefaults.standard.removeObject(forKey: bookId)
        }
    }

    // MARK: - 基础功能测试

    /// 测试保存和读取进度
    func testSaveAndLoadProgress() {
        let bookId = "test_book_1"
        let page = 42

        // 保存进度
        ProgressManager.saveProgress(page: page, for: bookId)

        // 读取进度
        let loadedPage = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(loadedPage, page)
    }

    /// 测试更新进度
    func testUpdateProgress() {
        let bookId = "test_book_1"

        // 保存初始进度
        ProgressManager.saveProgress(page: 10, for: bookId)
        XCTAssertEqual(ProgressManager.lastProgress(for: bookId), 10)

        // 更新进度
        ProgressManager.saveProgress(page: 25, for: bookId)
        XCTAssertEqual(ProgressManager.lastProgress(for: bookId), 25)

        // 再次更新
        ProgressManager.saveProgress(page: 0, for: bookId)
        XCTAssertEqual(ProgressManager.lastProgress(for: bookId), 0)
    }

    // MARK: - 边界条件测试

    /// 测试未保存过进度的书籍返回0
    func testNoProgressReturnsZero() {
        let bookId = "never_saved_book"

        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, 0)
    }

    /// 测试保存第0页
    func testSavePageZero() {
        let bookId = "test_book_1"

        ProgressManager.saveProgress(page: 0, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, 0)
    }

    /// 测试保存大页码
    func testSaveLargePageNumber() {
        let bookId = "test_book_1"
        let largePage = 999999

        ProgressManager.saveProgress(page: largePage, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, largePage)
    }

    /// 测试保存负页码（边界情况）
    func testSaveNegativePage() {
        let bookId = "test_book_1"
        let negativePage = -5

        ProgressManager.saveProgress(page: negativePage, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        // UserDefaults 会保存负值
        XCTAssertEqual(progress, negativePage)
    }

    // MARK: - 多书籍测试

    /// 测试多本书籍进度独立存储
    func testMultipleBooksProgress() {
        let book1 = "test_book_1"
        let book2 = "test_book_2"

        ProgressManager.saveProgress(page: 10, for: book1)
        ProgressManager.saveProgress(page: 50, for: book2)

        XCTAssertEqual(ProgressManager.lastProgress(for: book1), 10)
        XCTAssertEqual(ProgressManager.lastProgress(for: book2), 50)
    }

    /// 测试更新一本书不影响其他书
    func testUpdateOneBookDoesNotAffectOthers() {
        let book1 = "test_book_1"
        let book2 = "test_book_2"

        // 初始保存
        ProgressManager.saveProgress(page: 10, for: book1)
        ProgressManager.saveProgress(page: 20, for: book2)

        // 更新book1
        ProgressManager.saveProgress(page: 30, for: book1)

        // 验证book2未变
        XCTAssertEqual(ProgressManager.lastProgress(for: book1), 30)
        XCTAssertEqual(ProgressManager.lastProgress(for: book2), 20)
    }

    // MARK: - 特殊ID测试

    /// 测试空字符串ID
    func testEmptyBookId() {
        let bookId = ""
        let page = 5

        ProgressManager.saveProgress(page: page, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, page)
    }

    /// 测试特殊字符ID
    func testSpecialCharactersBookId() {
        let bookId = "special_!@#$%"
        let page = 15

        ProgressManager.saveProgress(page: page, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, page)
    }

    /// 测试长ID
    func testLongBookId() {
        let bookId = String(repeating: "a", count: 1000)
        let page = 100

        ProgressManager.saveProgress(page: page, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, page)
    }

    /// 测试Unicode ID
    func testUnicodeBookId() {
        let bookId = "书籍_日本語_한국어_🎉"
        let page = 7

        ProgressManager.saveProgress(page: page, for: bookId)
        let progress = ProgressManager.lastProgress(for: bookId)

        XCTAssertEqual(progress, page)
    }

    // MARK: - 持久化测试

    /// 测试进度持久化（模拟应用重启）
    func testProgressPersistence() {
        let bookId = "test_book_1"
        let page = 123

        // 保存进度
        ProgressManager.saveProgress(page: page, for: bookId)

        // 直接从UserDefaults读取，模拟重新初始化
        let savedValue = UserDefaults.standard.integer(forKey: bookId)

        XCTAssertEqual(savedValue, page)
    }

    // MARK: - 性能测试

    /// 测试大量保存操作的性能
    func testPerformanceSaveOperations() {
        measure {
            for i in 0..<100 {
                let bookId = "perf_test_\(i)"
                ProgressManager.saveProgress(page: i, for: bookId)
            }
        }
    }

    /// 测试大量读取操作的性能
    func testPerformanceReadOperations() {
        // 先准备数据
        for i in 0..<100 {
            let bookId = "perf_test_\(i)"
            ProgressManager.saveProgress(page: i, for: bookId)
        }

        measure {
            for i in 0..<100 {
                let bookId = "perf_test_\(i)"
                _ = ProgressManager.lastProgress(for: bookId)
            }
        }
    }

    // MARK: - 线程安全测试

    /// 测试并发保存（UserDefaults 是线程安全的）
    func testConcurrentSave() {
        let expectation = self.expectation(description: "并发保存")
        expectation.expectedFulfillmentCount = 10

        let dispatchGroup = DispatchGroup()

        for i in 0..<10 {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .background).async {
                let bookId = "concurrent_book_\(i)"
                ProgressManager.saveProgress(page: i * 10, for: bookId)
                expectation.fulfill()
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            // 验证所有保存都成功
            for i in 0..<10 {
                let bookId = "concurrent_book_\(i)"
                let progress = ProgressManager.lastProgress(for: bookId)
                XCTAssertEqual(progress, i * 10)
                UserDefaults.standard.removeObject(forKey: bookId)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
    }
}
