//
//  PDFParagraphEngine.swift
//  XLiPadBook
//
//  Created by ice on 6/3/2026.
//

import UIKit
import PDFKit

// MARK: - Range 辅助结构（替代 OC 的 XLRange struct）

private struct XLRange {
    var start: CGFloat
    var end: CGFloat
}

// MARK: - PDFParagraphEngine

final class PDFParagraphEngine {

    // MARK: - 公开接口

    /// 获取 selection 首行所在段落文本
    static func paragraphText(from selection: PDFSelection, document: PDFDocument) -> String {
        let lines = paragraphBlock(from: selection, document: document)
        return paragraphText(from: lines)
    }

    /// 获取 selection 首行所在的 pageIndex，未找到返回 -1
    static func pageIndex(from selection: PDFSelection, document: PDFDocument) -> Int {
        let lines = buildLines(from: selection, document: document)
        return lines.first?.pageIndex ?? -1
    }

    /// 生成段落ID：mgid_pageIndex_blockIndex_paragraphIndex
    static func paragraphID(from selection: PDFSelection, document: PDFDocument, mgid: String) -> String {
        let lines = paragraphBlock(from: selection, document: document)
        guard let line = lines.first else { return "" }
        return "\(mgid)_\(line.pageIndex)_\(line.blockIndex)_\(line.paragraphIndex)"
    }

    /// 根据 paragraphID 获取段落 lines 数组
    static func paragraphLines(fromParagraphID paragraphID: String, document: PDFDocument) -> [PDFLine] {
        guard let parsed = parseParagraphID(paragraphID) else { return [] }
        let (_, pageIndex, blockIndex, paragraphIndex) = parsed

        guard pageIndex >= 0, pageIndex < document.pageCount else { return [] }
        guard let page = document.page(at: pageIndex) else { return [] }

        let pageBlocks = pageLinesBlocks(from: page, document: document)
        guard blockIndex >= 0, blockIndex < pageBlocks.count else { return [] }

        return paragraphLines(forParagraphIndex: paragraphIndex, inBlock: pageBlocks[blockIndex])
    }

    // MARK: - 内部：段落定位

    /// 获取当前段落所在 block
    private static func paragraphBlock(from selection: PDFSelection, document: PDFDocument) -> [PDFLine] {
        let lines = buildLines(from: selection, document: document)
        guard let firstLine = lines.first else { return [] }
        let blocks = pageLinesBlocks(from: selection, document: document)
        return blockContaining(line: firstLine, fromBlocks: blocks)
    }

    /// 解析 paragraphID → (mgid, pageIndex, blockIndex, paragraphIndex)
    private static func parseParagraphID(_ paragraphID: String) -> (String, Int, Int, Int)? {
        let parts = paragraphID.components(separatedBy: "_")
        guard parts.count == 4,
              let pageIndex = Int(parts[1]),
              let blockIndex = Int(parts[2]),
              let paragraphIndex = Int(parts[3]) else { return nil }
        return (parts[0], pageIndex, blockIndex, paragraphIndex)
    }

    // MARK: - Line 构建

    /// 获取页面所有 lines
    private static func buildLines(fromPage page: PDFPage, document: PDFDocument) -> [PDFLine] {
        let pageRect = page.bounds(for: .mediaBox)
        guard let pageSelection = page.selection(for: pageRect) else { return [] }
        return buildLines(fromBaseSelection: pageSelection, document: document)
    }

    /// 获取选中区域的 lines
    private static func buildLines(from selection: PDFSelection, document: PDFDocument) -> [PDFLine] {
        return buildLines(fromBaseSelection: selection, document: document)
    }

    private static func buildLines(fromBaseSelection baseSelection: PDFSelection, document: PDFDocument) -> [PDFLine] {
        var lines: [PDFLine] = []
        let pages = baseSelection.pages

        // 过滤纯数字编号（页码/序号）
        let numberPattern = "^\\s*[零一二三四五六七八九十百\\d]+[、.]?\\s*$"
        let numberPredicate = NSPredicate(format: "SELF MATCHES %@", numberPattern)

        for sel in baseSelection.selectionsByLine() {
            guard let text = sel.string, !text.isEmpty else { continue }

            // 找到当前行所属 page
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

            let width = rect.width
            let height = rect.height

            // 过滤竖排
            if text.count > 1, height > width * 2.0 { continue }

            // 过滤异常高度
            let pageRect = page.bounds(for: .mediaBox)
            if height > pageRect.height * 0.05 { continue }

            let trimText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimText.isEmpty { continue }

            // 过滤纯数字编号
            if numberPredicate.evaluate(with: trimText) { continue }

            // 构建模型
            let line = PDFLine()
            line.selection = sel
            line.page = page
            line.rect = rect
            line.text = trimText

            let pageIndex = document.index(for: page)
            line.pageIndex = pageIndex == NSNotFound ? -1 : pageIndex
            line.font = dominantFont(from: sel)

            lines.append(line)
        }

        return lines
    }

    // MARK: - 分块

    private static func pageLinesBlocks(from selection: PDFSelection, document: PDFDocument) -> [[PDFLine]] {
        let pages = selection.pages
        guard !pages.isEmpty else { return [] }

        // 按 pageIndex 排序
        let sorted = pages.sorted {
            ($0.document?.index(for: $0) ?? 0) < ($1.document?.index(for: $1) ?? 0)
        }
        guard let firstPage = sorted.first else { return [] }
        return pageLinesBlocks(from: firstPage, document: document)
    }

    private static func pageLinesBlocks(from page: PDFPage, document: PDFDocument) -> [[PDFLine]] {
        var sortedBlocks: [[PDFLine]] = []

        let pageLines = buildLines(fromPage: page, document: document)
        guard !pageLines.isEmpty else { return [] }

        let blocks = buildBlocksIteratively(from: pageLines)

        var blockIndexCounter = 0
        for block in blocks {
            let currentBlockIndex = blockIndexCounter
            blockIndexCounter += 1
            block.forEach { $0.blockIndex = currentBlockIndex }
            let sortedLines = readingOrder(forBlock: block)
            sortedBlocks.append(sortedLines)
        }

        // 统计全页主体字体
        let pageBodyFont = dominantFont(fromBlocks: sortedBlocks)

        // 含主体字体的 block 参与语义合并，其余直接保留
        var blocksToMerge: [[PDFLine]] = []
        var blocksSkip:    [[PDFLine]] = []

        for block in sortedBlocks {
            if blockFontMatches(block, containsFont: pageBodyFont) {
                blocksToMerge.append(block)
            } else {
                blocksSkip.append(block)
            }
        }

        // 语义合并：把跨列但内容连续的相邻 block 合并
        blocksToMerge = mergeSemanticContinuousBlocks(blocksToMerge)

        sortedBlocks = blocksToMerge + blocksSkip
        return sortedBlocks
    }

    /// 判断一个 block 中是否至少有一行以段落结尾符号结尾
    private static func blockContainsParagraphEndingSymbol(_ block: [PDFLine]) -> Bool {
        let endingSymbols = CharacterSet(charactersIn: "。！？；.!?;…")
        let wrapperSet    = CharacterSet(charactersIn: "\u{201C}\u{2018}\"')）】》〉 ")

        for line in block {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var index = trimmed.index(before: trimmed.endIndex)

            // 从后往前跳过引号/括号
            while index >= trimmed.startIndex {
                let scalar = trimmed.unicodeScalars[trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: trimmed.distance(from: trimmed.startIndex, to: index))]
                if wrapperSet.contains(scalar) {
                    if index == trimmed.startIndex { break }
                    index = trimmed.index(before: index)
                } else {
                    break
                }
            }

            guard let lastChar = trimmed[...index].unicodeScalars.last else { continue }

            // 处理英文小数 3.14
            if lastChar == Unicode.Scalar(".") {
                let beforeIndex = trimmed.index(before: index)
                if let prevScalar = trimmed.unicodeScalars[...trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: trimmed.distance(from: trimmed.startIndex, to: beforeIndex))].last,
                   CharacterSet.decimalDigits.contains(prevScalar) {
                    continue
                }
            }

            if endingSymbols.contains(lastChar) { return true }
        }
        return false
    }

    // MARK: - 几何连通

    /// 两条 line 是否几何连通（各自膨胀半个行高后相交）
    private static func linesConnected(_ a: PDFLine, _ b: PDFLine) -> Bool {
        let insetA = a.rect.height * 0.5
        let insetB = b.rect.height * 0.5
        let ra = a.rect.insetBy(dx: -insetA, dy: -insetA)
        let rb = b.rect.insetBy(dx: -insetB, dy: -insetB)
        return ra.intersects(rb)
    }

    /// 将一组无序 line 按几何连通关系迭代拆成多个 block
    private static func buildBlocksIteratively(from lines: [PDFLine]) -> [[PDFLine]] {
        var remaining = lines
        var result: [[PDFLine]] = []

        while !remaining.isEmpty {
            let block = buildSingleBlock(from: remaining)
            guard !block.isEmpty else { break }
            result.append(block)
            remaining.removeAll { block.contains($0) }
        }
        return result
    }

    private static func buildSingleBlock(from lines: [PDFLine]) -> [PDFLine] {
        guard let start = lines.first else { return [] }
        var block: [PDFLine] = []
        var visited = Set<ObjectIdentifier>()
        var stack: [PDFLine] = [start]
        visited.insert(ObjectIdentifier(start))

        while let current = stack.popLast() {
            block.append(current)
            for other in lines {
                guard !visited.contains(ObjectIdentifier(other)) else { continue }
                if linesConnected(current, other) {
                    visited.insert(ObjectIdentifier(other))
                    stack.append(other)
                }
            }
        }
        return block
    }

    // MARK: - 阅读顺序 & 分列

    private static func readingOrder(forBlock block: [PDFLine]) -> [PDFLine] {
        let ranges       = xRanges(fromBlock: block)
        let columnRanges = mergeXRanges(ranges)
        let columns      = splitBlock(block, intoColumns: columnRanges)

        var result: [PDFLine] = []
        var paragraphIndex = 0
        for column in columns {
            let ordered = readingOrderByIndentOnly(column: column, paragraphStartIndex: &paragraphIndex)
            result.append(contentsOf: ordered)
        }
        return result
    }

    /// 把 block 里所有 line 的 rect 投影到 X 轴
    private static func xRanges(fromBlock block: [PDFLine]) -> [XLRange] {
        return block.map { XLRange(start: $0.rect.minX, end: $0.rect.maxX) }
    }

    /// 合并 X 上重叠 / 连续的区间 → 列区间
    private static func mergeXRanges(_ ranges: [XLRange]) -> [XLRange] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var columns: [XLRange] = []
        var current: XLRange?

        for r in sorted {
            if var c = current {
                if r.start <= c.end {
                    c.end = max(c.end, r.end)
                    current = c
                } else {
                    columns.append(c)
                    current = r
                }
            } else {
                current = r
            }
        }
        if let c = current { columns.append(c) }
        return columns
    }

    /// 把 line 分配进列
    private static func splitBlock(_ block: [PDFLine], intoColumns columnRanges: [XLRange]) -> [[PDFLine]] {
        var columns = Array(repeating: [PDFLine](), count: columnRanges.count)
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

    // MARK: - 分段

    /// 设置 paragraphIndex（按缩进 / 尾行空白 / 行间距判断段落边界）
    private static func readingOrderByIndentOnly(column: [PDFLine], paragraphStartIndex: inout Int) -> [PDFLine] {
        let sorted     = sortLinesByYDescending(column)
        let baseMinX   = self.baseMinX(forColumn: sorted)
        let baseMaxX   = self.baseMaxX(forColumn: sorted)
        let columnWidth = baseMaxX - baseMinX

        for (idx, line) in sorted.enumerated() {
            if idx > 0 {
                let prevLine = sorted[idx - 1]

                // 条件1：当前行首行缩进
                let indent = line.rect.minX - baseMinX
                let currentLineIsHead = indent > 10.0

                // 条件2：上一行是尾行（右侧留白超过列宽 10%）
                let prevLineTrailingGap = baseMaxX - prevLine.rect.maxX
                let prevLineIsTail = prevLineTrailingGap > columnWidth * 0.1

                // 条件3：行间距超过行高阈值
                let gap = prevLine.rect.minY - line.rect.maxY
                let lineHeight = line.rect.height
                let hasLargeGap = gap > lineHeight * 0.8

                if currentLineIsHead || prevLineIsTail || hasLargeGap {
                    paragraphStartIndex += 1
                }
            }
            line.paragraphIndex = paragraphStartIndex
        }
        return sorted
    }

    private static func baseMinX(forColumn column: [PDFLine]) -> CGFloat {
        return column.map { $0.rect.minX }.min() ?? 0
    }

    private static func baseMaxX(forColumn column: [PDFLine]) -> CGFloat {
        let sorted = column.map { $0.rect.maxX }.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private static func sortLinesByYDescending(_ lines: [PDFLine]) -> [PDFLine] {
        return lines.sorted {
            if $0.rect.maxY != $1.rect.maxY { return $0.rect.maxY > $1.rect.maxY }
            return false
        }
    }

    // MARK: - Block 定位

    /// 根据 line 定位其所在 block 的当前段落
    private static func blockContaining(line targetLine: PDFLine, fromBlocks blocks: [[PDFLine]]) -> [PDFLine] {
        let targetText = targetLine.text
        let targetRect = targetLine.rect
        guard !targetText.isEmpty else { return [] }

        for block in blocks {
            for line in block {
                guard isSameLine(r1: line.rect, r2: targetRect) else { continue }
                if line.text.contains(targetText) {
                    return paragraphLines(forParagraphIndex: line.paragraphIndex, inBlock: block)
                }
            }
        }
        return []
    }

    /// 从 block 中取出同一段的 lines
    private static func paragraphLines(forParagraphIndex index: Int, inBlock block: [PDFLine]) -> [PDFLine] {
        return block.filter { $0.paragraphIndex == index }
    }

    /// PDF 中同一行文字因字体 baseline 差异，midY 差值常在 1~3pt，使用行高的 50% 作为阈值
    private static func isSameLine(r1: CGRect, r2: CGRect) -> Bool {
        let threshold = min(r1.height, r2.height) * 0.5
        return abs(r1.midY - r2.midY) < threshold
    }

    private static func paragraphText(from lines: [PDFLine]) -> String {
        return lines.map { $0.text }.joined()
    }

    // MARK: - 多栏语义合并

    /// 先对所有 allPageLines 进行分列，将 blocks 归列后，
    /// 找出"段尾 block → 下一列段首 block"并合并，解决跨列语义连续问题
    private static func mergeSemanticContinuousBlocks(_ blocks: [[PDFLine]]) -> [[PDFLine]] {
        guard blocks.count >= 2 else { return blocks }

        // 直接从 blocks 展平生成 pageLines
        let pageLines = blocks.flatMap { $0 }
        
        let columnRanges = detectColumnRanges(from: pageLines)
        guard columnRanges.count >= 2 else { return blocks }

        // 按列分组
        var columns: [[NSMutableArray]] = Array(repeating: [], count: columnRanges.count)
        for block in blocks {
            let colIdx = columnIndex(forBlock: block, inRanges: columnRanges)
            if colIdx >= 0 {
                columns[colIdx].append(NSMutableArray(array: block))
            }
        }

        // 列内按 Y 排序（maxY 越大越靠上）
        for i in columns.indices {
            columns[i].sort {
                let maxYA = ($0 as! [PDFLine]).map { $0.rect.maxY }.max() ?? 0
                let maxYB = ($1 as! [PDFLine]).map { $0.rect.maxY }.max() ?? 0
                return maxYA > maxYB
            }
        }

        // 跨列合并
        for col in 0 ..< columns.count - 1 {
            let currentCol = columns[col]
            let nextCol    = columns[col + 1]
            guard !currentCol.isEmpty, !nextCol.isEmpty else { continue }

            let dominantHeight = dominantLineHeight(inColumn: currentCol as! [[NSMutableArray]])

            // 从当前列末尾找段尾 block
            var tailBlock: NSMutableArray?
            for blockIdx in stride(from: currentCol.count - 1, through: 0, by: -1) {
                let block = currentCol[blockIdx] as! [PDFLine]
                if lineHeightMatches(block, withHeight: dominantHeight) && isTailBlock(block) {
                    tailBlock = currentCol[blockIdx]
                    break
                }
            }
            guard let tail = tailBlock else { continue }
            let tailLines = tail as! [PDFLine]

            var searchCol = col + 1
            while searchCol < columns.count {
                let searchNextCol = columns[searchCol]
                guard !searchNextCol.isEmpty else { searchCol += 1; continue }

                var headBlock: [PDFLine]?
                var headIdx   = -1
                for i in 0 ..< searchNextCol.count {
                    let candidate = searchNextCol[i] as! [PDFLine]
                    if isHeadBlock(candidate)
                        && blockContainsParagraphEndingSymbol(candidate)
                        && lineHeightMatches(tailLines, with: candidate) {
                        headBlock = candidate
                        headIdx   = i
                        break
                    }
                }
                guard let head = headBlock else { break }

                mergeBlock(head, into: tail)
                columns[searchCol].remove(at: headIdx)

                if !isTailBlock(tail as! [PDFLine]) { break }
                searchCol += 1
            }

            columns[col] = currentCol
            columns[col + 1] = nextCol
        }

        // 重整 blockIndex + 构建结果数组
        var result: [[PDFLine]] = []
        var idx = 0
        for column in columns {
            for item in column {
                let block = item as! [PDFLine]
                block.forEach { $0.blockIndex = idx }
                idx += 1
                if blockContainsParagraphEndingSymbol(block) || block.count > 6 {
                    result.append(block)
                }
            }
        }
        return result
    }

    /// 按页面所有 lines 确定列边界，返回阅读顺序的 block 数组
    private static func readingOrderedBlocks(from blocks: [[PDFLine]], pageLines: [PDFLine]) -> [[PDFLine]] {
        guard !blocks.isEmpty else { return [] }

        let columnRanges = detectColumnRanges(from: pageLines)
        guard columnRanges.count >= 2 else { return sortBlocksByYDescending(blocks) }

        var columns    = Array(repeating: [PDFLine](), count: columnRanges.count)
        var unassigned = [[PDFLine]]()

        for block in blocks {
            let colIdx = columnIndex(forBlock: block, inRanges: columnRanges)
            if colIdx >= 0 {
                columns[colIdx].append(contentsOf: block)
            } else {
                unassigned.append(block)
            }
        }

        return columns
    }

    private static func sortBlocksByYDescending(_ blocks: [[PDFLine]]) -> [[PDFLine]] {
        return blocks.sorted {
            let maxYA = $0.map { $0.rect.maxY }.max() ?? 0
            let maxYB = $1.map { $0.rect.maxY }.max() ?? 0
            return maxYA > maxYB
        }
    }

    private static func insertionIndex(forBlock block: [PDFLine], inOrderedBlocks ordered: [[PDFLine]]) -> Int {
        let blockMaxY = block.map { $0.rect.maxY }.max() ?? 0
        for (i, candidate) in ordered.enumerated() {
            let candidateMaxY = candidate.map { $0.rect.maxY }.max() ?? 0
            if blockMaxY > candidateMaxY { return i }
        }
        return ordered.count
    }

    // MARK: - 列区间检测

    private static func detectColumnRanges(from lines: [PDFLine]) -> [XLRange] {
        guard !lines.isEmpty else { return [] }

        // 收集所有行的中心 X，排序
        let centerXList = lines.map { $0.rect.midX }.sorted()

        // 按间隙聚类：相邻两个 centerX 差值超过页宽 10% 则认为是列间距
        let pageRect     = lines[0].page?.bounds(for: .mediaBox) ?? .zero
        let gapThreshold = pageRect.width * 0.10

        var clusters: [[CGFloat]] = []
        var current:  [CGFloat]   = []

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

        // 每个 cluster 的 min/max 就是列的 X 范围，加适当 padding
        let padding = 4.0
        return clusters.map { cluster in
            XLRange(start: (cluster.first ?? 0) - padding,
                    end:   (cluster.last  ?? 0) + padding)
        }
    }

    private static func columnIndex(forBlock block: [PDFLine], inRanges columnRanges: [XLRange]) -> Int {
        guard !block.isEmpty else { return -1 }
        let centerX = block.map { $0.rect.midX }.reduce(0, +) / CGFloat(block.count)
        for (i, range) in columnRanges.enumerated() {
            if centerX >= range.start && centerX <= range.end { return i }
        }
        return -1
    }

    // MARK: - 段尾 / 段首 / 行高判断

    /// 段尾：末行无句末标点 且 右侧留白不明显
    private static func isTailBlock(_ block: [PDFLine]) -> Bool {
        guard let lastLine = block.last else { return false }
        let columnMaxX  = baseMaxX(forColumn: block)
        let columnMinX  = baseMinX(forColumn: block)
        let columnWidth = columnMaxX - columnMinX
        let trailingGap = columnMaxX - lastLine.rect.maxX
        return trailingGap <= columnWidth * 0.1 && !lineEndsWithParagraphSymbol(lastLine)
    }

    /// 段首：首行无明显缩进
    private static func isHeadBlock(_ block: [PDFLine]) -> Bool {
        guard let firstLine = block.first else { return false }
        let columnMinX = baseMinX(forColumn: block)
        let indent     = firstLine.rect.minX - columnMinX
        return indent <= 10.0
    }

    /// 行高一致：取末行 vs 首行，5% 容差
    private static func lineHeightMatches(_ a: [PDFLine], with b: [PDFLine]) -> Bool {
        guard let lastA = a.last, let firstB = b.first else { return false }
        let hA   = lastA.rect.height
        let hB   = firstB.rect.height
        let avgH = (hA + hB) * 0.5
        return avgH > 0 && abs(hA - hB) / avgH <= 0.05
    }

    private static func lineHeightMatches(_ a: [PDFLine], withHeight height: CGFloat) -> Bool {
        guard !a.isEmpty else { return false }
        let hA   = medianLineHeight(forBlock: a)
        let avgH = (hA + height) * 0.5
        return avgH > 0 && abs(hA - height) / avgH <= 0.05
    }

    /// 统计列内出现频率最高的行高，作为主体行高
    private static func dominantLineHeight(inColumn column: [[NSMutableArray]]) -> CGFloat {
        var heightCount: [Int: Int] = [:]
        for item in column {
            for line in (item as! [PDFLine]) {
                let key = Int(line.rect.height.rounded())
                heightCount[key, default: 0] += 1
            }
        }
        return CGFloat(heightCount.max(by: { $0.value < $1.value })?.key ?? 0)
    }

    /// 合并：将 next 的所有 line 追加进 prev，修正 blockIndex 和 paragraphIndex
    private static func mergeBlock(_ next: [PDFLine], into prev: NSMutableArray) {
        guard !next.isEmpty, prev.count > 0 else { return }
        let prevLines = prev as! [PDFLine]
        let maxParagraphIndex = prevLines.map { $0.paragraphIndex }.max() ?? 0
        let prevBlockIndex    = prevLines[0].blockIndex
        let nextBaseIndex     = next[0].paragraphIndex

        for line in next {
            line.blockIndex     = prevBlockIndex
            line.paragraphIndex = (line.paragraphIndex - nextBaseIndex) + maxParagraphIndex
            prev.add(line)
        }
    }

    // MARK: - 工具方法

    /// 判断一行是否以句末标点结尾（处理引号包裹和英文小数）
    private static func lineEndsWithParagraphSymbol(_ line: PDFLine) -> Bool {
        let endingSymbols = CharacterSet(charactersIn: "。！？；.!?;…")
        let wrapperSet    = CharacterSet(charactersIn: "\u{201C}\u{2018}\"')）】》〉 ")
        let trimmed       = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var index = trimmed.index(before: trimmed.endIndex)
        while index >= trimmed.startIndex {
            let scalar = trimmed.unicodeScalars[trimmed.unicodeScalars.index(trimmed.unicodeScalars.startIndex, offsetBy: trimmed.distance(from: trimmed.startIndex, to: index))]
            if wrapperSet.contains(scalar) {
                if index == trimmed.startIndex { return false }
                index = trimmed.index(before: index)
            } else {
                // 英文小数点不算句末
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

    /// 取 block 所有行行高的中位数
    private static func medianLineHeight(forBlock block: [PDFLine]) -> CGFloat {
        let heights = block.map { $0.rect.height }.sorted()
        guard !heights.isEmpty else { return 0 }
        return heights[heights.count / 2]
    }

    // MARK: - 字体

    /// 从多个 block 中统计全页主体字体（正文字体）
    /// 把所有 block 内的字体字符数累加，取最多的那个
    private static func dominantFont(fromBlocks blocks: [[PDFLine]]) -> UIFont? {
        var fontCount: [String: Int]    = [:]
        var fontMap:   [String: UIFont] = [:]

        for block in blocks {
            for line in block {
                guard let font = line.font else { continue }
                let key = "\(font.fontName)_\(String(format: "%.2f", font.pointSize))"
                fontCount[key, default: 0] += line.text.count
                if fontMap[key] == nil { fontMap[key] = font }
            }
        }

        guard let dominantKey = fontCount.max(by: { $0.value < $1.value })?.key else { return nil }
        return fontMap[dominantKey]
    }

    /// 判断 block 中是否含有指定的主体字体（任意一行匹配即返回 true）
    private static func blockFontMatches(_ block: [PDFLine], containsFont targetFont: UIFont?) -> Bool {
        guard let target = targetFont else { return true } // 保守处理
        return block.contains { fontMatches($0.font, target) }
    }

    /// 判断两个字体是否匹配（fontName + pointSize 均相同）
    private static func fontMatches(_ fontA: UIFont?, _ fontB: UIFont?) -> Bool {
        guard let a = fontA, let b = fontB else { return true } // 任一为空时不过滤
        return a.fontName == b.fontName && abs(a.pointSize - b.pointSize) < 0.5
    }

    /// 从 PDFSelection 中提取该行的主体字体（字符数最多的字体）
    private static func dominantFont(from selection: PDFSelection) -> UIFont? {
        let attrStr = selection.attributedString
        guard let attrStr, attrStr.length > 0 else { return nil }

        var fontCount: [String: Int]    = [:]
        var fontMap:   [String: UIFont] = [:]

        attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }
            let key = "\(font.fontName)_\(String(format: "%.2f", font.pointSize))"
            fontCount[key, default: 0] += range.length
            if fontMap[key] == nil { fontMap[key] = font }
        }

        guard let dominantKey = fontCount.max(by: { $0.value < $1.value })?.key else { return nil }
        return fontMap[dominantKey]
    }
}
