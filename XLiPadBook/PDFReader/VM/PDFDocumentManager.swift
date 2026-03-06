//
//  PDFDocumentManager.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//

import PDFKit

class PDFDocumentManager {
    let document: PDFDocument
    
    init?(filePath: String) {
        guard let doc = PDFDocument(url: URL(fileURLWithPath: filePath)) else { return nil }
        self.document = doc
    }
}
