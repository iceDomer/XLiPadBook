//
//  PDFParagraphEngine.swift
//  XLiPadBook
//
//  Created by ice on 6/3/2026.
//

import Foundation
import PDFKit

// MARK: - XLRange

struct XLRange {
    var start: CGFloat
    var end: CGFloat
}

// MARK: - PDFParagraphEngine

class PDFParagraphEngine {

    // MARK: - Public API

    /// 获取 selection 首行所在段落文本
    static func paragraphText(from selection: PDFSelection, document: PDFDocument) -> String {
        let currentBlocks = paragraphBlock(from: selection, document: document)
        return paragraphText(fromLines: currentBlocks)
    }

    /// 获取 selection 首行所在的 pageIndex，未找到返回 -1
    static func pageIndex(from selection: PDFSelection, document: PDFDocument) -> Int {
        let lines = buildLines(from: selection, document: document)
        return lines.first?.pageIndex ?? -1
    }

    /// 生成段落ID：mgid_pageIndex_blockIndex_paragraphIndex
    static func paragraphID(from selection: PDFSelection, document: PDFDocument, mgid: String) -> String {
        let currentBlocks = paragraphBlock(from: selection, document: document)
        guard let line = currentBlocks.first else { return "" }
        return "\(mgid)_\(line.pageIndex)_\(line.blockIndex)_\(line.paragraphIndex)"
    }

    /// 根据 paragraphID 获取段落数组
    static func paragraphLines(fromParagraphID paragraphID: String, document: PDFDocument) -> [PDFLine] {
        guard let (_, pageIdx, blockIdx, paraIdx) = parseParagraphID(paragraphID) else { return [] }
        guard pageIdx >= 0, pageIdx < document.pageCount else { return [] }
        guard let page = document.page(at: pageIdx) else { return [] }

        let pageBlocks = pageLinesBlocks(from: page, document: document)
        guard blockIdx >= 0, blockIdx < pageBlocks.count else { return [] }

        let block = pageBlocks[blockIdx]
        return paragraphLines(forParagraphIndex: paraIdx, inBlock: block)
    }

    // MARK: - Paragraph Block

    private static func paragraphBlock(from selection: PDFSelection, document: PDFDocument) -> [PDFLine] {
        let lines = buildLines(from: selection, document: document)
        guard let firstLine = lines.first else { return [] }
        let blocks = pageLinesBlocks(from: selection, document: document)
        return blockContaining(line: firstLine, fromBlocks: blocks)
    }

    // MARK: - Parse ParagraphID

    private static func parseParagraphID(_ paragraphID: String) -> (mgid: String, pageIndex: Int, blockIndex: Int, paragraphIndex: Int)? {
        let components = paragraphID.components(separatedBy: "_")
        guard components.count == 4,
              let pageIdx = Int(components[1]),
              let blockIdx = Int(components[2]),
              let paraIdx = Int(components[3]) else { return nil }
        return (components[0], pageIdx, blockIdx, paraIdx)
    }

    // MARK: - Build Lines

    private static func buildLines(fromPage page: PDFPage, document: PDFDocument) -> [PDFLine] {
        let pageRect = page.bounds(for: .mediaBox)
        guard let pageSelection = page.selection(for: pageRect) else { return [] }
        return buildLines(fromBaseSelection: pageSelection, document: document)
    }

    private static func buildLines(from selection: PDFSelection, document: PDFDocument) -> [PDFLine] {
        return buildLines(fromBaseSelection: selection, document: document)
    }

    private static func buildLines(fromBaseSelection baseSelection: PDFSelection, document: PDFDocument) -> [PDFLine] {
        var lines: [PDFLine] = []
        let pages = baseSelection.pages

        for sel in baseSelection.selectionsByLine() {
            guard let text = sel.string, !text.isEmpty else { continue }

            var linePage: PDFPage?
            var rect = CGRect.zero

            for page in pages {
                let r = sel.bounds(for: page)
                if !r.isEmpty {
                    linePage = page
                    rect = r
                    break
                }
            }

            guard let page = linePage, !rect.isEmpty else { continue }

            // 过滤竖排
            if text.count > 1, rect.height > rect.width * 2.0 { continue }

            // 过滤异常高度
            let pageRect = page.bounds(for: .mediaBox)
            if rect.height > pageRect.height * 0.05 { continue }

            let trimText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimText.isEmpty { continue }

            // 过滤纯数字编号（01、02、1、2、一、二 等页码/序号）
            let numberPattern = "^\\s*[零一二三四五六七八九十百\\d]+[、.]?\\s*$"
            if trimText.range(of: numberPattern, options: .regularExpression) != nil { continue }

            let line = PDFLine()
            line.selection = sel
            line.page = page
            line.rect = rect
            line.text = trimText

            let idx = document.index(for: page)
            line.pageIndex = idx == NSNotFound ? -1 : idx
            lines.append(line)
        }

        return lines
    }

    // MARK: - Page Blocks

    private static func pageLinesBlocks(from selection: PDFSelection, document: PDFDocument) -> [[PDFLine]] {
        let pages = selection.pages.sorted {
            guard let d1 = $0.document, let d2 = $1.document else { return false }
            return d1.index(for: $0) < d2.index(for: $1)
        }
        guard let firstPage = pages.first else { return [] }
        return pageLinesBlocks(from: firstPage, document: document)
    }

    private static func pageLinesBlocks(from page: PDFPage, document: PDFDocument) -> [[PDFLine]] {
        let pageLines = buildLines(fromPage: page, document: document)
        if pageLines.isEmpty { return [] }

        let blocks = buildBlocksIteratively(from: pageLines)

        var sortedBlocks: [[PDFLine]] = []
        var blockIndexCounter = 0

        for block in blocks {
            let currentBlockIndex = blockIndexCounter
            blockIndexCounter += 1
            block.forEach { $0.blockIndex = currentBlockIndex }

            let sortedLines = readingOrder(forBlock: block)
            sortedBlocks.append(sortedLines)
        }

        return mergeSemanticContinuousBlocks(sortedBlocks, pageLines: pageLines)
    }

    // MARK: - Block Contains Paragraph Ending Symbol

    private static func blockContainsParagraphEndingSymbol(_ block: [PDFLine]) -> Bool {
        let endingSymbols = CharacterSet(charactersIn: "。！？；.!?;…")
        let trailingWrapperSet = CharacterSet(charactersIn: "\u{201C}\u{2018}\"')）】》〉 ")

        for line in block {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            var index = trimmed.index(before: trimmed.endIndex)

            // 从后往前跳过引号/括号
            while true {
                let offset = trimmed.distance(from: trimmed.startIndex, to: index)
                let scalarIdx = trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: offset)
                let scalar = trimmed.unicodeScalars[scalarIdx]
                if trailingWrapperSet.contains(scalar) {
                    if index == trimmed.startIndex { break }
                    index = trimmed.index(before: index)
                } else {
                    break
                }
            }

            let offset = trimmed.distance(from: trimmed.startIndex, to: index)
            let scalarIdx = trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: offset)
            let scalar = trimmed.unicodeScalars[scalarIdx]

            // 处理英文小数 3.14
            let c = trimmed[index]
            if c == ".", index > trimmed.startIndex {
                let prevIndex = trimmed.index(before: index)
                if trimmed[prevIndex].isNumber { continue }
            }

            if endingSymbols.contains(scalar) { return true }
        }

        return false
    }

    // MARK: - Lines Connected

    private static func linesConnected(_ a: PDFLine, _ b: PDFLine) -> Bool {
        let ra = a.rect.insetBy(dx: -a.rect.height * 0.5, dy: -a.rect.height * 0.5)
        let rb = b.rect.insetBy(dx: -b.rect.height * 0.5, dy: -b.rect.height * 0.5)
        return ra.intersects(rb)
    }

    // MARK: - Build Blocks Iteratively

    private static func buildBlocksIteratively(from lines: [PDFLine]) -> [[PDFLine]] {
        var remaining = lines
        var resultBlocks: [[PDFLine]] = []

        while !remaining.isEmpty {
            let block = buildSingleBlock(from: remaining)
            if block.isEmpty { break }
            resultBlocks.append(block)
            let ids = Set(block.map { ObjectIdentifier($0) })
            remaining.removeAll { ids.contains(ObjectIdentifier($0)) }
        }

        return resultBlocks
    }

    private static func buildSingleBlock(from lines: [PDFLine]) -> [PDFLine] {
        guard let start = lines.first else { return [] }

        var block: [PDFLine] = []
        var visited = Set<ObjectIdentifier>()
        var stack: [PDFLine] = [start]
        visited.insert(ObjectIdentifier(start))

        while !stack.isEmpty {
            let current = stack.removeLast()
            block.append(current)

            for other in lines where !visited.contains(ObjectIdentifier(other)) {
                if linesConnected(current, other) {
                    visited.insert(ObjectIdentifier(other))
                    stack.append(other)
                }
            }
        }

        return block
    }

    // MARK: - Reading Order

    private static func readingOrder(forBlock block: [PDFLine]) -> [PDFLine] {
        let ranges = xRanges(fromBlock: block)
        let columnRanges = mergeXRanges(ranges)
        let columns = splitBlock(block, intoColumns: columnRanges)

        var result: [PDFLine] = []
        var paragraphIndex = 0

        for column in columns {
            let ordered = readingOrder(forColumnByIndentOnly: column, paragraphStartIndex: &paragraphIndex)
            result.append(contentsOf: ordered)
        }

        return result
    }

    private static func xRanges(fromBlock block: [PDFLine]) -> [XLRange] {
        return block.map { XLRange(start: $0.rect.minX, end: $0.rect.maxX) }
    }

    private static func mergeXRanges(_ ranges: [XLRange]) -> [XLRange] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var columns: [XLRange] = []
        var current: XLRange?

        for r in sorted {
            if current == nil {
                current = r
            } else if r.start <= current!.end {
                current!.end = max(current!.end, r.end)
            } else {
                columns.append(current!)
                current = r
            }
        }
        if let c = current { columns.append(c) }
        return columns
    }

    private static func splitBlock(_ block: [PDFLine], intoColumns columnRanges: [XLRange]) -> [[PDFLine]] {
        var columns: [[PDFLine]] = Array(repeating: [], count: columnRanges.count)

        for line in block {
            let centerX = line.rect.midX
            for (i, range) in columnRanges.enumerated() {
                if centerX >= range.start && centerX <= range.end {
                    columns[i].append(line)
                    break
                }
            }
        }

        return columns
    }

    // MARK: - Reading Order by Indent

    private static func readingOrder(forColumnByIndentOnly column: [PDFLine], paragraphStartIndex paragraphIndex: inout Int) -> [PDFLine] {
        let sorted = sortLinesByYDescending(column)
        let baseMinX = self.baseMinX(forColumn: sorted)
        let baseMaxX = self.baseMaxX(forColumn: sorted)
        let columnWidth = baseMaxX - baseMinX

        for (idx, line) in sorted.enumerated() {
            if idx > 0 {
                let prevLine = sorted[idx - 1]

                // 条件1：当前行首行缩进
                let currentLineIsHead = (line.rect.minX - baseMinX) > 10.0

                // 条件2：上一行是尾行（右侧留白超过列宽10%）
                let prevLineIsTail = (baseMaxX - prevLine.rect.maxX) > columnWidth * 0.1

                // 条件3：行间距超过行高阈值
                let gap = prevLine.rect.minY - line.rect.maxY
                let hasLargeGap = gap > line.rect.height * 0.8

                if currentLineIsHead || prevLineIsTail || hasLargeGap {
                    paragraphIndex += 1
                }
            }
            line.paragraphIndex = paragraphIndex
        }

        return sorted
    }

    private static func baseMinX(forColumn column: [PDFLine]) -> CGFloat {
        return column.reduce(CGFloat.greatestFiniteMagnitude) { min($0, $1.rect.minX) }
    }

    private static func baseMaxX(forColumn column: [PDFLine]) -> CGFloat {
        let maxXValues = column.map { $0.rect.maxX }.sorted()
        guard !maxXValues.isEmpty else { return 0 }
        return maxXValues[maxXValues.count / 2]
    }

    private static func sortLinesByYDescending(_ lines: [PDFLine]) -> [PDFLine] {
        return lines.sorted { $0.rect.maxY > $1.rect.maxY }
    }

    // MARK: - Block Containing Line

    private static func blockContaining(line targetLine: PDFLine, fromBlocks blocks: [[PDFLine]]) -> [PDFLine] {
        guard !targetLine.text.isEmpty else { return [] }

        for block in blocks {
            for line in block {
                guard isSameLine(r1: line.rect, r2: targetLine.rect) else { continue }
                if line.text.contains(targetLine.text) {
                    return paragraphLines(forParagraphIndex: line.paragraphIndex, inBlock: block)
                }
            }
        }

        return []
    }

    private static func paragraphLines(forParagraphIndex paragraphIndex: Int, inBlock block: [PDFLine]) -> [PDFLine] {
        return block.filter { $0.paragraphIndex == paragraphIndex }
    }

    private static func isSameLine(r1: CGRect, r2: CGRect) -> Bool {
        let threshold = min(r1.height, r2.height) * 0.5
        return abs(r1.midY - r2.midY) < threshold
    }

    private static func paragraphText(fromLines lines: [PDFLine]) -> String {
        return lines.reduce("") { $0 + $1.text }
    }

    // MARK: - Merge Semantic Continuous Blocks

    private static func mergeSemanticContinuousBlocks(_ blocks: [[PDFLine]], pageLines: [PDFLine]) -> [[PDFLine]] {
        guard blocks.count >= 2 else { return blocks }

        let columnRanges = detectColumnRanges(lines: pageLines)
        guard columnRanges.count >= 2 else { return blocks }

        // 按列分组，使用 NSMutableArray 以便原地修改
        let columns: [NSMutableArray] = (0..<columnRanges.count).map { _ in NSMutableArray() }

        for block in blocks {
            let colIdx = columnIndex(forBlock: block, inRanges: columnRanges)
            if colIdx >= 0 {
                columns[colIdx].add(NSMutableArray(array: block))
            }
        }

        // 列内按 Y 排序（maxY 越大越靠上）
        for col in columns {
            col.sort { a, b -> ComparisonResult in
                let maxYA = (a as! [PDFLine]).reduce(0.0) { max($0, $1.rect.maxY) }
                let maxYB = (b as! [PDFLine]).reduce(0.0) { max($0, $1.rect.maxY) }
                return maxYA > maxYB ? .orderedAscending : .orderedDescending
            }
        }

        // 跨列合并
        for col in 0..<(columns.count - 1) {
            guard columns[col].count > 0, columns[col + 1].count > 0 else { continue }

            let colBlocks = (columns[col] as! [NSMutableArray]).map { $0 as! [PDFLine] }
            let dominantH = dominantLineHeight(inColumn: colBlocks)
            var tailBlock: NSMutableArray? = nil

            for blockIdx in stride(from: columns[col].count - 1, through: 0, by: -1) {
                let block = (columns[col][blockIdx] as! NSMutableArray) as! [PDFLine]
                if lineHeightMatches(block, withHeight: dominantH), isTailBlock(block) {
                    tailBlock = columns[col][blockIdx] as? NSMutableArray
                    break
                }
            }

            guard let tail = tailBlock else { continue }

            var searchCol = col + 1
            while searchCol < columns.count {
                let searchNextCol = columns[searchCol]
                guard searchNextCol.count > 0 else { searchCol += 1; continue }

                var headBlock: [PDFLine]? = nil
                var headIdx = -1

                for i in 0..<searchNextCol.count {
                    let block = (searchNextCol[i] as! NSMutableArray) as! [PDFLine]
                    let tailLines = tail as! [PDFLine]
                    if isHeadBlock(block),
                       blockContainsParagraphEndingSymbol(block),
                       lineHeightMatches(tailLines, with: block) {
                        headBlock = block
                        headIdx = i
                        break
                    }
                }

                guard let head = headBlock else { break }

                mergeBlock(head, intoBlock: tail)
                (columns[searchCol] as NSMutableArray).removeObject(at: headIdx)

                if !isTailBlock(tail as! [PDFLine]) { break }
                searchCol += 1
            }
        }

        // 重整 blockIndex + 构建结果数组
        var result: [[PDFLine]] = []
        var idx = 0
        for col in columns {
            for blockObj in col {
                let block = (blockObj as! NSMutableArray) as! [PDFLine]
                block.forEach { $0.blockIndex = idx }
                idx += 1
                if blockContainsParagraphEndingSymbol(block) || block.count > 6 {
                    result.append(block)
                }
            }
        }

        return result
    }

    // MARK: - Reading Ordered Blocks

    private static func readingOrderedBlocks(fromBlocks blocks: [[PDFLine]], pageLines: [PDFLine]) -> [[PDFLine]] {
        guard !blocks.isEmpty else { return [] }

        let columnRanges = detectColumnRanges(lines: pageLines)
        if columnRanges.count < 2 {
            return sortBlocksByYDescending(blocks)
        }

        var columns: [[PDFLine]] = Array(repeating: [], count: columnRanges.count)

        for block in blocks {
            let colIdx = columnIndex(forBlock: block, inRanges: columnRanges)
            if colIdx >= 0 {
                columns[colIdx].append(contentsOf: block)
            }
        }

        return columns.map { sortLinesByYDescending($0) }
    }

    private static func sortBlocksByYDescending(_ blocks: [[PDFLine]]) -> [[PDFLine]] {
        return blocks.sorted {
            let maxYA = $0.reduce(0.0) { max($0, $1.rect.maxY) }
            let maxYB = $1.reduce(0.0) { max($0, $1.rect.maxY) }
            return maxYA > maxYB
        }
    }

    private static func insertionIndex(forBlock block: [PDFLine], inOrderedBlocks ordered: [[PDFLine]]) -> Int {
        let blockMaxY = block.reduce(0.0) { max($0, $1.rect.maxY) }
        for (i, candidate) in ordered.enumerated() {
            let candidateMaxY = candidate.reduce(0.0) { max($0, $1.rect.maxY) }
            if blockMaxY > candidateMaxY { return i }
        }
        return ordered.count
    }

    // MARK: - Detect Column Ranges

    private static func detectColumnRanges(lines: [PDFLine]) -> [XLRange] {
        guard !lines.isEmpty else { return [] }

        let centerXList = lines.map { $0.rect.midX }.sorted()

        let pageRect = lines.first?.page?.bounds(for: .mediaBox) ?? .zero
        let gapThreshold = pageRect.width * 0.10

        var clusters: [[CGFloat]] = []
        var current: [CGFloat] = []

        for x in centerXList {
            if current.isEmpty {
                current.append(x)
            } else {
                if x - current.last! > gapThreshold {
                    clusters.append(current)
                    current = []
                }
                current.append(x)
            }
        }
        if !current.isEmpty { clusters.append(current) }

        let padding = (lines.first?.rect.height ?? 0) * 0.5

        return clusters.map { cluster in
            XLRange(start: cluster.first! - padding, end: cluster.last! + padding)
        }
    }

    private static func columnIndex(forBlock block: [PDFLine], inRanges columnRanges: [XLRange]) -> Int {
        guard !block.isEmpty else { return -1 }
        let centerX = block.reduce(0.0) { $0 + $1.rect.midX } / CGFloat(block.count)

        for (i, range) in columnRanges.enumerated() {
            if centerX >= range.start && centerX <= range.end { return i }
        }
        return -1
    }

    // MARK: - Tail / Head Block

    private static func isTailBlock(_ block: [PDFLine]) -> Bool {
        guard let lastLine = block.last else { return false }
        let columnMaxX = baseMaxX(forColumn: block)
        let columnMinX = baseMinX(forColumn: block)
        let columnWidth = columnMaxX - columnMinX
        let trailingGap = columnMaxX - lastLine.rect.maxX

        return trailingGap <= columnWidth * 0.1 && !lineEndsWithParagraphSymbol(lastLine)
    }

    private static func isHeadBlock(_ block: [PDFLine]) -> Bool {
        guard let firstLine = block.first else { return false }
        return (firstLine.rect.minX - baseMinX(forColumn: block)) <= 10.0
    }

    // MARK: - Line Height Matching

    private static func lineHeightMatches(_ a: [PDFLine], with b: [PDFLine]) -> Bool {
        guard let lastA = a.last, let firstB = b.first else { return false }
        let hA = lastA.rect.height
        let hB = firstB.rect.height
        let avgH = (hA + hB) * 0.5
        return avgH > 0 && abs(hA - hB) / avgH <= 0.05
    }

    private static func lineHeightMatches(_ a: [PDFLine], withHeight height: CGFloat) -> Bool {
        guard !a.isEmpty else { return false }
        let hA = medianLineHeight(forBlock: a)
        let avgH = (hA + height) * 0.5
        return avgH > 0 && abs(hA - height) / avgH <= 0.05
    }

    private static func dominantLineHeight(inColumn column: [[PDFLine]]) -> CGFloat {
        var heightCount: [Int: Int] = [:]
        for block in column {
            for line in block {
                let key = Int(line.rect.height.rounded())
                heightCount[key, default: 0] += 1
            }
        }
        let dominant = heightCount.max { $0.value < $1.value }?.key ?? 0
        return CGFloat(dominant)
    }

    // MARK: - Merge Block

    private static func mergeBlock(_ next: [PDFLine], intoBlock prev: NSMutableArray) {
        guard !next.isEmpty, prev.count > 0 else { return }
        let prevLines = prev as! [PDFLine]

        let maxParagraphIndex = prevLines.reduce(0) { max($0, $1.paragraphIndex) }
        let prevBlockIndex = prevLines.first!.blockIndex
        let nextBaseIndex = next.first!.paragraphIndex

        for line in next {
            line.blockIndex = prevBlockIndex
            line.paragraphIndex = (line.paragraphIndex - nextBaseIndex) + maxParagraphIndex
            prev.add(line)
        }
    }

    // MARK: - Line Ends With Paragraph Symbol

    private static func lineEndsWithParagraphSymbol(_ line: PDFLine) -> Bool {
        let endingSymbols = CharacterSet(charactersIn: "。！？；.!?;…")
        let wrapperSet = CharacterSet(charactersIn: "\u{201C}\u{2018}\"')）】》〉 ")
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var index = trimmed.index(before: trimmed.endIndex)

        // 跳过包裹字符
        while true {
            let offset = trimmed.distance(from: trimmed.startIndex, to: index)
            let scalarIdx = trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: offset)
            let scalar = trimmed.unicodeScalars[scalarIdx]
            if wrapperSet.contains(scalar) {
                if index == trimmed.startIndex { return false }
                index = trimmed.index(before: index)
            } else {
                let c = trimmed[index]
                // 英文小数点不算句末（3.14）
                if c == ".", index > trimmed.startIndex {
                    let prevChar = trimmed[trimmed.index(before: index)]
                    if prevChar.isNumber { return false }
                }
                return endingSymbols.contains(scalar)
            }
        }
    }

    // MARK: - Median Line Height

    private static func medianLineHeight(forBlock block: [PDFLine]) -> CGFloat {
        let heights = block.map { $0.rect.height }.sorted()
        guard !heights.isEmpty else { return 0 }
        return heights[heights.count / 2]
    }
}

