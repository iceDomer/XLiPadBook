//
//  PDFLine.swift
//  XLiPadBook
//
//  Created by ice on 6/3/2026.
//

import Foundation
import PDFKit

class PDFLine: NSObject {
    var selection: PDFSelection?
    var page: PDFPage?
    var pageIndex: Int = 0
    var rect: CGRect = .zero
    var text: String = ""
    var blockIndex: Int = 0       // 所属块索引
    var paragraphIndex: Int = 0   // 所属段落索引
    var font: UIFont?
}
