//
//  PDFPageViewController.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//


import UIKit
import PDFKit

class PDFPageViewController: UIViewController {

    // MARK: - Public

    var pageIndex: Int = 0
    var document: PDFDocument?
    var onToggleToolbar: (() -> Void)?

    var currentDisplayMode: PDFDisplayMode {
        pdfView?.displayMode ?? .singlePage
    }

    // MARK: - Internal

    private(set) var pdfView: CustomPDFView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // 关键：只有在真正被移除时才 detach
        if self.parent == nil {
            detachPDFView()
        }
    }
    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.pdfView.map { self.updateDisplayMode(for: size, on: $0) }
        })
    }

    // MARK: - PDFView 注入

    /// 由 PageContainerController 调用，注入池子里的 PDFView
    func attachPDFView(_ newPDFView: CustomPDFView, pageIndex: Int, document: PDFDocument?) {
        // 移除旧的
        if let old = pdfView, old !== newPDFView {
            old.customDelegate = nil
            old.removeFromSuperview()
        }

        self.pageIndex = pageIndex
        self.document  = document
        self.pdfView   = newPDFView

        // 重置状态
        newPDFView.customDelegate   = self
        newPDFView.autoScales       = true
        newPDFView.displayDirection = .horizontal
        newPDFView.displaysAsBook   = false
        newPDFView.translatesAutoresizingMaskIntoConstraints = false

        if newPDFView.superview !== view {
            newPDFView.removeFromSuperview()
            newPDFView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(newPDFView)
            NSLayoutConstraint.activate([
                newPDFView.topAnchor.constraint(equalTo: view.topAnchor),
                newPDFView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                newPDFView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newPDFView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
        if let doc = document, let page = doc.page(at: pageIndex) {
            if newPDFView.document !== doc { newPDFView.document = doc }
            newPDFView.go(to: page)
        }
        updateDisplayMode(for: view.bounds.size, on: newPDFView)
        setupGestures(on: newPDFView)

       
    }

    /// 回收前调用，清理引用
    func detachPDFView() {
        pdfView?.customDelegate = nil
        pdfView?.removeFromSuperview()
        pdfView = nil
    }

    // MARK: - Display Mode

    private func updateDisplayMode(for size: CGSize, on view: CustomPDFView) {
        view.displayMode    = size.width > size.height ? .twoUp : .singlePage
        view.displaysAsBook = false
        view.autoScales     = true
    }

    // MARK: - Gestures

    private func setupGestures(on targetView: CustomPDFView) {
        // 移除之前注册的单击手势，避免重复
        targetView.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0.numberOfTapsRequired == 1 }
            .forEach { targetView.removeGestureRecognizer($0) }

        let existingDoubleTap = targetView.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 2 }

        let singleTap = UITapGestureRecognizer(target: self,
                                               action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        if let doubleTap = existingDoubleTap {
            singleTap.require(toFail: doubleTap)
        }
        targetView.addGestureRecognizer(singleTap)
    }

    @objc private func handleSingleTap(_ tap: UITapGestureRecognizer) {
        guard let pdfView else { return }
        let ratio = tap.location(in: pdfView).x / pdfView.bounds.width
        if ratio < 0.25 {
            pdfView.goToPreviousPage(nil)
        } else if ratio > 0.75 {
            pdfView.goToNextPage(nil)
        } else {
            onToggleToolbar?()
        }
    }
}

// MARK: - CustomPDFViewDelegate

extension PDFPageViewController: CustomPDFViewDelegate {

    func customPDFView(_ view: CustomPDFView, didCopy text: String) {
        UIPasteboard.general.string = text
        print("复制")
    }

    func customPDFView(_ view: CustomPDFView,
                       didRequestAnnotationFor selection: PDFSelection,
                       anchorRect: CGRect) {
        print("写段评")
        if let doc = document {
            let text = PDFParagraphEngine.paragraphText(from: selection, document: doc)
            print(text)
        }
    }

    func customPDFView(_ view: CustomPDFView,
                       didRequestHighlightFor selection: PDFSelection) {
        print("高亮标记")
    }
}
