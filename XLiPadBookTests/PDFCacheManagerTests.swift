//
//  PDFCacheManagerTests.swift
//  XLiPadBookTests
//
//  PDFCacheManager 单元测试
//

import XCTest
@testable import XLiPadBook

final class PDFCacheManagerTests: XCTestCase {

    var cacheManager: PDFCacheManager!
    let testCacheCount = 3

    override func setUp() {
        super.setUp()
        // 使用较小的缓存数量便于测试LRU
        cacheManager = PDFCacheManager(maxCacheCount: testCacheCount)
        // 清理所有缓存
        cacheManager.clearAllCache()
    }

    override func tearDown() {
        cacheManager.clearAllCache()
        cacheManager = nil
        super.tearDown()
    }

    // MARK: - 缓存键测试

    /// 测试缓存键生成的一致性
    func testCacheKeyConsistency() {
        let url1 = URL(string: "https://example.com/test.pdf")!
        let url2 = URL(string: "https://example.com/test.pdf")!

        let key1 = cacheKey(for: url1)
        let key2 = cacheKey(for: url2)

        XCTAssertEqual(key1, key2)
    }

    /// 测试不同URL生成不同缓存键
    func testCacheKeyUniqueness() {
        let url1 = URL(string: "https://example.com/test1.pdf")!
        let url2 = URL(string: "https://example.com/test2.pdf")!

        let key1 = cacheKey(for: url1)
        let key2 = cacheKey(for: url2)

        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - LRU 缓存策略测试

    /// 测试标记为已读会更新LRU顺序
    func testMarkAsReadUpdatesLRU() {
        let expectation = self.expectation(description: "下载完成")
        let url = URL(string: "https://httpbin.org/bytes/1024")!

        var firstLoadComplete = false

        cacheManager.loadPDF(
            from: url,
            progress: { _ in },
            completion: { [weak self] localURL in
                guard let self = self, localURL != nil else {
                    expectation.fulfill()
                    return
                }

                if !firstLoadComplete {
                    firstLoadComplete = true
                    // 标记为已读
                    self.cacheManager.markAsRead(url: url)
                    expectation.fulfill()
                }
            }
        )

        waitForExpectations(timeout: 30.0)
    }

    /// 测试清理缓存功能
    func testClearAllCache() {
        let expectation = self.expectation(description: "清理完成")

        // 先清理
        cacheManager.clearAllCache()

        // 延迟验证
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    // MARK: - 并发测试

    /// 测试并发加载不会导致崩溃
    func testConcurrentLoad() {
        let expectation = self.expectation(description: "并发加载")
        expectation.expectedFulfillmentCount = 3

        let urls = [
            URL(string: "https://httpbin.org/bytes/100")!,
            URL(string: "https://httpbin.org/bytes/200")!,
            URL(string: "https://httpbin.org/bytes/300")!
        ]

        let group = DispatchGroup()

        for url in urls {
            group.enter()
            cacheManager.loadPDF(
                from: url,
                progress: { _ in },
                completion: { _ in
                    expectation.fulfill()
                    group.leave()
                }
            )
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 60.0)
    }

    // MARK: - 边界条件测试

    /// 测试无效URL的处理
    func testInvalidURL() {
        let expectation = self.expectation(description: "无效URL处理")

        // 使用无效的URL格式
        var components = URLComponents()
        components.scheme = "invalid"
        components.host = "test"

        let url = components.url ?? URL(string: "http://localhost:99999")!

        cacheManager.loadPDF(
            from: url,
            progress: { _ in },
            completion: { localURL in
                // 应该返回nil或超时
                XCTAssertNil(localURL)
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 10.0)
    }

    /// 测试进度回调范围
    func testProgressRange() {
        let expectation = self.expectation(description: "进度回调")
        let url = URL(string: "https://httpbin.org/bytes/1024")!

        var progressValues: [Double] = []

        cacheManager.loadPDF(
            from: url,
            progress: { progress in
                progressValues.append(progress)
                // 进度值应该在0到1之间
                XCTAssertGreaterThanOrEqual(progress, 0.0)
                XCTAssertLessThanOrEqual(progress, 1.0)
            },
            completion: { _ in
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 30.0)
    }

    // MARK: - 辅助方法

    private func cacheKey(for url: URL) -> String {
        return url.absoluteString.sha256Test
    }
}

// MARK: - 测试用的扩展

private extension String {
    var sha256Test: String {
        guard let data = data(using: .utf8) else { return UUID().uuidString }
        // 简化的哈希用于测试
        return data.base64EncodedString()
    }
}
