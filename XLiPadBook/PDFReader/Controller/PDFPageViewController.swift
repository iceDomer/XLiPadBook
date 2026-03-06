//
//  PDFPageViewController.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//

import UIKit
import PDFKit

class PDFPageViewController: UIViewController {
    var pageIndex: Int = 0
    var document: PDFDocument?
    private var pdfView: CustomPDFView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pdfView = CustomPDFView(frame: view.bounds)
        pdfView.autoScales = true
        pdfView.displayDirection = .horizontal
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        // 接入代理
        pdfView.customDelegate = self
        view.addSubview(pdfView)
        
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        updateDisplayMode(for: view.bounds.size)

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let doc = document, let page = doc.page(at: pageIndex) {
            pdfView.document = doc
            pdfView.go(to: page)
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateDisplayMode(for: size)
        })
    }
    
    private func updateDisplayMode(for size: CGSize) {
        if size.width > size.height {
            // 横屏 → 双页
            pdfView.displayMode = .twoUp
            pdfView.displaysAsBook = true   // 左右翻页像书本
        } else {
            // 竖屏 → 单页
            pdfView.displayMode = .singlePage
            pdfView.displaysAsBook = true
        }
        // 重置缩放，让页面重新填充
        pdfView.autoScales = true
    }
}
// MARK: - CustomPDFViewDelegate

extension PDFPageViewController: CustomPDFViewDelegate {

    // MARK: 复制

    func customPDFView(_ view: CustomPDFView, didCopy text: String) {
        UIPasteboard.general.string = text
        print("复制")
    }

    // MARK: 写段评

    func customPDFView(_ view: CustomPDFView,
                       didRequestAnnotationFor selection: PDFSelection,
                       anchorRect: CGRect) {
        print("写段评")
        if let doc = document {
            let text = PDFParagraphEngine.paragraphText(from: selection, document: doc)
            print(text)
        }
    }

    // MARK: 高亮标记

    func customPDFView(_ view: CustomPDFView,
                       didRequestHighlightFor selection: PDFSelection) {
        print("高亮标记")
    }

}
