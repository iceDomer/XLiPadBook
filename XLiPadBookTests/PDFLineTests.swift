//
//  PDFLineTests.swift
//  XLiPadBookTests
//
//  PDFLine 模型单元测试
//

import XCTest
import PDFKit
@testable import XLiPadBook

final class PDFLineTests: XCTestCase {

    // MARK: - 基础属性测试

    /// 测试默认初始化
    func testDefaultInitialization() {
        let line = PDFLine()

        XCTAssertNil(line.selection)
        XCTAssertNil(line.page)
        XCTAssertEqual(line.pageIndex, 0)
        XCTAssertEqual(line.rect, .zero)
        XCTAssertEqual(line.text, "")
        XCTAssertEqual(line.blockIndex, 0)
        XCTAssertEqual(line.paragraphIndex, 0)
        XCTAssertNil(line.font)
    }

    /// 测试属性赋值
    func testPropertyAssignment() {
        let line = PDFLine()
        let testRect = CGRect(x: 10, y: 20, width: 300, height: 20)
        let testFont = UIFont.systemFont(ofSize: 14)

        line.pageIndex = 5
        line.rect = testRect
        line.text = "测试文本"
        line.blockIndex = 2
        line.paragraphIndex = 3
        line.font = testFont

        XCTAssertEqual(line.pageIndex, 5)
        XCTAssertEqual(line.rect, testRect)
        XCTAssertEqual(line.text, "测试文本")
        XCTAssertEqual(line.blockIndex, 2)
        XCTAssertEqual(line.paragraphIndex, 3)
        XCTAssertEqual(line.font, testFont)
    }

    // MARK: - 几何计算测试

    /// 测试 rect 的几何属性
    func testRectGeometry() {
        let line = PDFLine()
        line.rect = CGRect(x: 50, y: 100, width: 200, height: 25)

        XCTAssertEqual(line.rect.minX, 50)
        XCTAssertEqual(line.rect.maxX, 250)
        XCTAssertEqual(line.rect.minY, 100)
        XCTAssertEqual(line.rect.maxY, 125)
        XCTAssertEqual(line.rect.midX, 150)
        XCTAssertEqual(line.rect.midY, 112.5)
        XCTAssertEqual(line.rect.width, 200)
        XCTAssertEqual(line.rect.height, 25)
    }

    /// 测试空 rect
    func testEmptyRect() {
        let line = PDFLine()
        line.rect = .zero

        XCTAssertEqual(line.rect.width, 0)
        XCTAssertEqual(line.rect.height, 0)
        XCTAssertTrue(line.rect.isEmpty)
    }

    // MARK: - 文本内容测试

    /// 测试空文本
    func testEmptyText() {
        let line = PDFLine()
        line.text = ""

        XCTAssertTrue(line.text.isEmpty)
        XCTAssertEqual(line.text.count, 0)
    }

    /// 测试长文本
    func testLongText() {
        let line = PDFLine()
        let longText = String(repeating: "这是一个很长的文本内容。", count: 100)
        line.text = longText

        XCTAssertEqual(line.text, longText)
        XCTAssertEqual(line.text.count, longText.count)
    }

    /// 测试特殊字符文本
    func testSpecialCharacters() {
        let line = PDFLine()
        let specialText = "Hello 世界 🌍 123 !@#$%^&*()"
        line.text = specialText

        XCTAssertEqual(line.text, specialText)
    }

    /// 测试多行文本（虽然通常PDFLine是单行）
    func testMultilineText() {
        let line = PDFLine()
        line.text = "第一行\n第二行\n第三行"

        XCTAssertEqual(line.text.components(separatedBy: "\n").count, 3)
    }

    // MARK: - 索引边界测试

    /// 测试负索引（虽然业务逻辑上不应该）
    func testNegativeIndices() {
        let line = PDFLine()
        line.pageIndex = -1
        line.blockIndex = -1
        line.paragraphIndex = -1

        XCTAssertEqual(line.pageIndex, -1)
        XCTAssertEqual(line.blockIndex, -1)
        XCTAssertEqual(line.paragraphIndex, -1)
    }

    /// 测试大索引值
    func testLargeIndices() {
        let line = PDFLine()
        line.pageIndex = Int.max
        line.blockIndex = 999999
        line.paragraphIndex = 888888

        XCTAssertEqual(line.pageIndex, Int.max)
        XCTAssertEqual(line.blockIndex, 999999)
        XCTAssertEqual(line.paragraphIndex, 888888)
    }

    // MARK: - 字体测试

    /// 测试不同字体
    func testDifferentFonts() {
        let line = PDFLine()

        let systemFont = UIFont.systemFont(ofSize: 14)
        line.font = systemFont
        XCTAssertEqual(line.font, systemFont)

        let boldFont = UIFont.boldSystemFont(ofSize: 16)
        line.font = boldFont
        XCTAssertEqual(line.font, boldFont)

        let italicFont = UIFont.italicSystemFont(ofSize: 12)
        line.font = italicFont
        XCTAssertEqual(line.font, italicFont)
    }

    /// 测试字体属性
    func testFontProperties() {
        let line = PDFLine()
        let font = UIFont.systemFont(ofSize: 14, weight: .medium)
        line.font = font

        XCTAssertEqual(line.font?.pointSize, 14)
        XCTAssertEqual(line.font?.fontName, font.fontName)
    }

    // MARK: - 对象标识测试

    /// 测试对象唯一性
    func testObjectIdentity() {
        let line1 = PDFLine()
        let line2 = PDFLine()

        XCTAssertNotEqual(ObjectIdentifier(line1), ObjectIdentifier(line2))
    }

    /// 测试相同属性不同对象
    func testEqualPropertiesDifferentObjects() {
        let line1 = PDFLine()
        line1.text = "相同文本"
        line1.pageIndex = 1
        line1.rect = CGRect(x: 0, y: 0, width: 100, height: 20)

        let line2 = PDFLine()
        line2.text = "相同文本"
        line2.pageIndex = 1
        line2.rect = CGRect(x: 0, y: 0, width: 100, height: 20)

        // 属性相同但不是同一个对象
        XCTAssertEqual(line1.text, line2.text)
        XCTAssertEqual(line1.pageIndex, line2.pageIndex)
        XCTAssertEqual(line1.rect, line2.rect)
        XCTAssertNotEqual(ObjectIdentifier(line1), ObjectIdentifier(line2))
    }

    // MARK: - 实际使用场景测试

    /// 测试模拟真实PDF行数据
    func testRealWorldScenario() {
        let line = PDFLine()

        // 模拟一页PDF中的某一行
        line.pageIndex = 5
        line.blockIndex = 2  // 第3个文本块
        line.paragraphIndex = 1  // 第2个段落
        line.rect = CGRect(x: 72, y: 650, width: 468, height: 14)  // 标准PDF坐标
        line.text = "这是一段示例文本，用于测试PDF行的数据结构。"
        line.font = UIFont.systemFont(ofSize: 12)

        // 验证这是一个"正文"行（宽度合理）
        XCTAssertGreaterThan(line.rect.width, 400)
        XCTAssertLessThan(line.rect.height, 20)

        // 验证有实际内容
        XCTAssertGreaterThan(line.text.count, 10)

        // 验证索引有效
        XCTAssertGreaterThanOrEqual(line.pageIndex, 0)
        XCTAssertGreaterThanOrEqual(line.blockIndex, 0)
        XCTAssertGreaterThanOrEqual(line.paragraphIndex, 0)
    }

    /// 测试标题行特征
    func testTitleLineCharacteristics() {
        let titleLine = PDFLine()
        titleLine.rect = CGRect(x: 72, y: 700, width: 200, height: 24)
        titleLine.text = "第一章 标题"
        titleLine.font = UIFont.boldSystemFont(ofSize: 18)

        // 标题通常字体更大、行高更高
        XCTAssertGreaterThan(titleLine.rect.height, 20)
        XCTAssertEqual(titleLine.font?.pointSize, 18)

        // 标题通常较短
        XCTAssertLessThan(titleLine.text.count, 50)
    }

    /// 测试页码行特征
    func testPageNumberCharacteristics() {
        let pageNumberLine = PDFLine()
        pageNumberLine.rect = CGRect(x: 280, y: 50, width: 40, height: 12)
        pageNumberLine.text = "123"
        pageNumberLine.font = UIFont.systemFont(ofSize: 10)

        // 页码通常很短
        XCTAssertLessThan(pageNumberLine.text.count, 10)

        // 页码通常位于页面底部
        XCTAssertLessThan(pageNumberLine.rect.minY, 100)

        // 页码字体较小
        XCTAssertLessThan(pageNumberLine.font?.pointSize ?? 0, 12)
    }
}
