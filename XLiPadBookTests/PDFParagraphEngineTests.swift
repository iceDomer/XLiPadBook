//
//  PDFParagraphEngineTests.swift
//  XLiPadBookTests
//
//  PDFParagraphEngine 单元测试
//

import XCTest
@testable import XLiPadBook

// MARK: - 测试数据构建辅助类

final class PDFParagraphEngineTests: XCTestCase {

    // MARK: - XLRange 测试

    func testXLRangeBasic() {
        // 测试范围基本属性
        let range = XLRange(start: 10.0, end: 100.0)
        XCTAssertEqual(range.start, 10.0)
        XCTAssertEqual(range.end, 100.0)
    }

    // MARK: - 行连通性测试

    /// 测试几何连通的行（Y轴方向相邻）
    func testLinesConnectedVertical() {
        let line1 = createPDFLine(rect: CGRect(x: 50, y: 500, width: 200, height: 20))
        let line2 = createPDFLine(rect: CGRect(x: 50, y: 470, width: 200, height: 20))

        // 两行Y轴间距30，行高20，膨胀后应该相交
        let connected = PDFParagraphEngine.linesConnected(line1, line2)
        XCTAssertTrue(connected)
    }

    /// 测试不相连的行（距离过远）
    func testLinesNotConnected() {
        let line1 = createPDFLine(rect: CGRect(x: 50, y: 500, width: 200, height: 20))
        let line2 = createPDFLine(rect: CGRect(x: 50, y: 300, width: 200, height: 20))

        // 两行Y轴间距200，行高20，膨胀后不相交
        let connected = PDFParagraphEngine.linesConnected(line1, line2)
        XCTAssertFalse(connected)
    }

    /// 测试水平方向连通的行（同一行）
    func testLinesConnectedHorizontal() {
        let line1 = createPDFLine(rect: CGRect(x: 50, y: 500, width: 200, height: 20))
        let line2 = createPDFLine(rect: CGRect(x: 240, y: 500, width: 200, height: 20))

        // 两行X轴相邻，应该连通
        let connected = PDFParagraphEngine.linesConnected(line1, line2)
        XCTAssertTrue(connected)
    }

    // MARK: - 列检测测试

    /// 测试单列布局检测
    func testDetectSingleColumn() {
        let lines = [
            createPDFLine(rect: CGRect(x: 50, y: 500, width: 300, height: 20)),
            createPDFLine(rect: CGRect(x: 50, y: 470, width: 300, height: 20)),
            createPDFLine(rect: CGRect(x: 50, y: 440, width: 300, height: 20))
        ]

        let columnRanges = PDFParagraphEngine.detectColumnRanges(from: lines)
        XCTAssertEqual(columnRanges.count, 1)
    }

    /// 测试双栏布局检测
    func testDetectDoubleColumn() {
        let pageWidth: CGFloat = 600
        let lines = [
            // 左栏
            createPDFLine(rect: CGRect(x: 50, y: 500, width: 200, height: 20)),
            createPDFLine(rect: CGRect(x: 50, y: 470, width: 200, height: 20)),
            // 右栏（与左栏有明显间距）
            createPDFLine(rect: CGRect(x: 350, y: 500, width: 200, height: 20)),
            createPDFLine(rect: CGRect(x: 350, y: 470, width: 200, height: 20))
        ]

        // 设置页面边界用于列检测计算
        lines.forEach { line in
            line.page = createMockPage(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: 800))
        }

        let columnRanges = PDFParagraphEngine.detectColumnRanges(from: lines)
        XCTAssertEqual(columnRanges.count, 2)
    }

    // MARK: - 段落边界检测测试

    /// 测试以句号结尾的行是段落结尾
    func testLineEndsWithParagraphSymbol() {
        let line = createPDFLine(text: "这是一个完整的句子。", rect: .zero)
        XCTAssertTrue(PDFParagraphEngine.lineEndsWithParagraphSymbol(line))
    }

    /// 测试以感叹号结尾的行
    func testLineEndsWithExclamation() {
        let line = createPDFLine(text: "太好了！", rect: .zero)
        XCTAssertTrue(PDFParagraphEngine.lineEndsWithParagraphSymbol(line))
    }

    /// 测试以问号结尾的行
    func testLineEndsWithQuestion() {
        let line = createPDFLine(text: "这是什么？", rect: .zero)
        XCTAssertTrue(PDFParagraphEngine.lineEndsWithParagraphSymbol(line))
    }

    /// 测试不以标点结尾的行不是段落结尾
    func testLineNotEndsWithSymbol() {
        let line = createPDFLine(text: "这是一个未完成的", rect: .zero)
        XCTAssertFalse(PDFParagraphEngine.lineEndsWithParagraphSymbol(line))
    }

    /// 测试英文小数点不算段落结尾
    func testDecimalPointNotParagraphEnd() {
        let line = createPDFLine(text: "数值为3.14", rect: .zero)
        XCTAssertFalse(PDFParagraphEngine.lineEndsWithParagraphSymbol(line))
    }

    /// 测试带引号的段落结尾
    func testLineEndsWithQuote() {
        let line = createPDFLine(text: "他说：\"你好。\"", rect: .zero)
        XCTAssertTrue(PDFParagraphEngine.lineEndsWithParagraphSymbol(line))
    }

    // MARK: - 段尾/段首检测测试

    /// 测试段尾块检测 - 右侧留白小且无句末标点
    func testIsTailBlock() {
        let lines = [
            createPDFLine(text: "这是段落中间", rect: CGRect(x: 50, y: 500, width: 280, height: 20)),
            createPDFLine(text: "这是段落末尾没有标点", rect: CGRect(x: 50, y: 470, width: 280, height: 20))
        ]

        // 列宽300，最后一行宽度280，右侧留白20（小于10%）
        XCTAssertTrue(PDFParagraphEngine.isTailBlock(lines))
    }

    /// 测试段首块检测 - 无明显缩进
    func testIsHeadBlock() {
        let lines = [
            createPDFLine(text: "段落开头", rect: CGRect(x: 50, y: 500, width: 200, height: 20)),
            createPDFLine(text: "段落内容", rect: CGRect(x: 50, y: 470, width: 250, height: 20))
        ]

        // 第一行minX=50，列minX=50，缩进为0（小于10）
        XCTAssertTrue(PDFParagraphEngine.isHeadBlock(lines))
    }

    /// 测试有缩进的不是段首
    func testIsNotHeadBlock() {
        let lines = [
            createPDFLine(text: "缩进段落", rect: CGRect(x: 70, y: 500, width: 200, height: 20)),
            createPDFLine(text: "段落内容", rect: CGRect(x: 50, y: 470, width: 250, height: 20))
        ]

        // 第一行minX=70，列minX=50，缩进为20（大于10）
        XCTAssertFalse(PDFParagraphEngine.isHeadBlock(lines))
    }

    // MARK: - 行高匹配测试

    /// 测试行高匹配
    func testLineHeightMatches() {
        let block1 = [
            createPDFLine(rect: CGRect(x: 0, y: 500, width: 100, height: 20)),
            createPDFLine(rect: CGRect(x: 0, y: 470, width: 100, height: 20))
        ]
        let block2 = [
            createPDFLine(rect: CGRect(x: 0, y: 440, width: 100, height: 20.5)),
            createPDFLine(rect: CGRect(x: 0, y: 410, width: 100, height: 20.5))
        ]

        // 行高20 vs 20.5，差异在5%以内
        XCTAssertTrue(PDFParagraphEngine.lineHeightMatches(block1, with: block2))
    }

    /// 测试行高不匹配
    func testLineHeightNotMatches() {
        let block1 = [
            createPDFLine(rect: CGRect(x: 0, y: 500, width: 100, height: 20))
        ]
        let block2 = [
            createPDFLine(rect: CGRect(x: 0, y: 440, width: 100, height: 30))
        ]

        // 行高20 vs 30，差异超过5%
        XCTAssertFalse(PDFParagraphEngine.lineHeightMatches(block1, with: block2))
    }

    // MARK: - 同线检测测试

    /// 测试同一行检测
    func testIsSameLine() {
        let rect1 = CGRect(x: 50, y: 500, width: 200, height: 20)
        let rect2 = CGRect(x: 260, y: 502, width: 150, height: 20)

        // midY差2，行高20，阈值10，应该认为是同一行
        XCTAssertTrue(PDFParagraphEngine.isSameLine(r1: rect1, r2: rect2))
    }

    /// 测试不同行检测
    func testIsNotSameLine() {
        let rect1 = CGRect(x: 50, y: 500, width: 200, height: 20)
        let rect2 = CGRect(x: 50, y: 450, width: 200, height: 20)

        // midY差50，超过阈值
        XCTAssertFalse(PDFParagraphEngine.isSameLine(r1: rect1, r2: rect2))
    }

    // MARK: - 段落ID解析测试

    /// 测试段落ID解析
    func testParseParagraphID() {
        let paragraphID = "book123_5_2_3"
        let result = PDFParagraphEngine.parseParagraphID(paragraphID)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.mgid, "book123")
        XCTAssertEqual(result?.pageIndex, 5)
        XCTAssertEqual(result?.blockIndex, 2)
        XCTAssertEqual(result?.paragraphIndex, 3)
    }

    /// 测试无效段落ID解析
    func testParseInvalidParagraphID() {
        let paragraphID = "invalid_id"
        let result = PDFParagraphEngine.parseParagraphID(paragraphID)

        XCTAssertNil(result)
    }

    // MARK: - 辅助方法

    private func createPDFLine(text: String = "测试文本", rect: CGRect) -> PDFLine {
        let line = PDFLine()
        line.text = text
        line.rect = rect
        return line
    }

    private func createMockPage(bounds: CGRect) -> PDFPage {
        // 创建一个简单的PDF页面用于测试
        // 实际测试中可能需要使用真实的PDF文档
        return PDFPage()
    }
}

// MARK: - 扩展以访问私有方法

extension PDFParagraphEngine {
    static func linesConnected(_ a: PDFLine, _ b: PDFLine) -> Bool {
        let insetA = a.rect.height * 0.5
        let insetB = b.rect.height * 0.5
        let ra = a.rect.insetBy(dx: -insetA, dy: -insetA)
        let rb = b.rect.insetBy(dx: -insetB, dy: -insetB)
        return ra.intersects(rb)
    }

    static func detectColumnRanges(from lines: [PDFLine]) -> [XLRange] {
        guard !lines.isEmpty else { return [] }

        let centerXList = lines.map { $0.rect.midX }.sorted()
        let pageRect = lines[0].page?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 600, height: 800)
        let gapThreshold = pageRect.width * 0.10

        var clusters: [[CGFloat]] = []
        var current: [CGFloat] = []

        for x in centerXList {
            if current.isEmpty {
                current.append(x)
            } else {
                let gap = x - current.last!
                if gap > gapThreshold {
                    clusters.append(current)
                    current = []
                }
                current.append(x)
            }
        }
        if !current.isEmpty { clusters.append(current) }

        let padding = 4.0
        return clusters.map { cluster in
            XLRange(start: (cluster.first ?? 0) - padding,
                    end:   (cluster.last  ?? 0) + padding)
        }
    }

    static func isTailBlock(_ block: [PDFLine]) -> Bool {
        guard let lastLine = block.last else { return false }
        let columnMaxX = baseMaxX(forColumn: block)
        let columnMinX = baseMinX(forColumn: block)
        let columnWidth = columnMaxX - columnMinX
        let trailingGap = columnMaxX - lastLine.rect.maxX
        return trailingGap <= columnWidth * 0.1 && !lineEndsWithParagraphSymbol(lastLine)
    }

    static func isHeadBlock(_ block: [PDFLine]) -> Bool {
        guard let firstLine = block.first else { return false }
        let columnMinX = baseMinX(forColumn: block)
        let indent = firstLine.rect.minX - columnMinX
        return indent <= 10.0
    }

    static func lineHeightMatches(_ a: [PDFLine], with b: [PDFLine]) -> Bool {
        guard let lastA = a.last, let firstB = b.first else { return false }
        let hA = lastA.rect.height
        let hB = firstB.rect.height
        let avgH = (hA + hB) * 0.5
        return avgH > 0 && abs(hA - hB) / avgH <= 0.05
    }

    static func isSameLine(r1: CGRect, r2: CGRect) -> Bool {
        let threshold = min(r1.height, r2.height) * 0.5
        return abs(r1.midY - r2.midY) < threshold
    }

    static func parseParagraphID(_ paragraphID: String) -> (mgid: String, pageIndex: Int, blockIndex: Int, paragraphIndex: Int)? {
        let parts = paragraphID.components(separatedBy: "_")
        guard parts.count == 4,
              let pageIndex = Int(parts[1]),
              let blockIndex = Int(parts[2]),
              let paragraphIndex = Int(parts[3]) else { return nil }
        return (parts[0], pageIndex, blockIndex, paragraphIndex)
    }

    static func lineEndsWithParagraphSymbol(_ line: PDFLine) -> Bool {
        let endingSymbols = CharacterSet(charactersIn: "。！？；.!?;…")
        let wrapperSet = CharacterSet(charactersIn: "\u{201C}\u{2018}\"')）】》〉 ")
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var index = trimmed.index(before: trimmed.endIndex)
        while index >= trimmed.startIndex {
            let scalar = trimmed.unicodeScalars[trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: trimmed.distance(from: trimmed.startIndex, to: index))]
            if wrapperSet.contains(scalar) {
                if index == trimmed.startIndex { return false }
                index = trimmed.index(before: index)
            } else {
                if scalar == Unicode.Scalar("."), index > trimmed.startIndex {
                    let prevIdx = trimmed.index(before: index)
                    let prevScalarIdx = trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: trimmed.distance(from: trimmed.startIndex, to: prevIdx))
                    if let prevScalar = trimmed.unicodeScalars[prevScalarIdx...].first,
                       CharacterSet.decimalDigits.contains(prevScalar) {
                        return false
                    }
                }
                return endingSymbols.contains(scalar)
            }
        }
        return false
    }

    private static func baseMinX(forColumn column: [PDFLine]) -> CGFloat {
        return column.map { $0.rect.minX }.min() ?? 0
    }

    private static func baseMaxX(forColumn column: [PDFLine]) -> CGFloat {
        let sorted = column.map { $0.rect.maxX }.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }
}

private struct XLRange {
    var start: CGFloat
    var end: CGFloat
}
