//
//  PageContainerController.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//

import UIKit
import PDFKit

class PageContainerController: UIPageViewController,
                                UIPageViewControllerDataSource,
                                UIPageViewControllerDelegate {

    // MARK: - Public

    var document: PDFDocument?
    var currentPageIndex: Int = 0
    var onToggleToolbar: (() -> Void)?
    var onPageDidChange: ((Int) -> Void)?

    // MARK: - PDFView 池子

    /// 固定数量的 CustomPDFView，全部共享同一个 document
    private var pdfViewPool: [CustomPDFView] = []

    /// 当前占用关系：pageIndex → CustomPDFView
    private var pageViewMap: [Int: CustomPDFView] = [:]

    private let prefetchRange = 2

    private var isTwoUp: Bool {
        let size = view.bounds.size
        return size.width > size.height
    }

    /// 池子大小随横竖屏动态调整
    private var poolSize: Int {
        let range = isTwoUp ? prefetchRange * 2 + 1 : prefetchRange + 1
        return range
    }


    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource    = self
        delegate      = self

        setupPDFViewPool()

        if let firstVC = makeVC(for: currentPageIndex) {
            setViewControllers([firstVC], direction: .forward, animated: false)
        }

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

    }

    // MARK: - 池子初始化
    private func setupPDFViewPool() {
        guard let doc = document else { return }

        pdfViewPool = (0 ..< poolSize).map { _ in
            let v = CustomPDFView()
            v.document         = doc   // 所有实例共享同一个 document
            v.autoScales       = true
            v.displayDirection = .horizontal
            v.displaysAsBook   = false
            v.backgroundColor  = .white
            return v
        }
        print("[pool] 初始化 \(poolSize) 个 CustomPDFView")
    }

    // MARK: - 池子管理
    /// 为 index 分配一个空闲 PDFView（已占用则直接返回）
    private func dequeue(for index: Int) -> CustomPDFView {
        if let existing = pageViewMap[index] {
            return existing
        }

        let used = Set(pageViewMap.values.map { ObjectIdentifier($0) })
        if let free = pdfViewPool.first(where: { !used.contains(ObjectIdentifier($0)) }) {
            pageViewMap[index] = free
            print("[pool] 分配 page \(index)，占用 \(pageViewMap.count)/\(pdfViewPool.count)")
            return free
        }

        // 兜底扩容
        print("[pool] ⚠️ 池子耗尽，扩容，index=\(index)")
        let extra = CustomPDFView()
        extra.document         = document
        extra.autoScales       = true
        extra.displayDirection = .horizontal
        extra.displaysAsBook   = false
        extra.backgroundColor  = .white
        pdfViewPool.append(extra)
        pageViewMap[index] = extra
        return extra
    }

    /// 归还 index 占用的 PDFView
    private func recycle(index: Int) {
        guard pageViewMap[index] != nil else { return }
        pageViewMap.removeValue(forKey: index)
        print("[pool] 归还 page \(index)，剩余占用 \(pageViewMap.count)")
    }

    /// 翻页完成后归还超出保留窗口的 PDFView
    private func recycleOutOfRange(center: Int) {
        let range    = isTwoUp ? prefetchRange * 2 + 1 : prefetchRange + 1
        let extraEnd = isTwoUp ? 1 : 0
        let keepStart = max(0, center - range)
        let keepEnd   = min((document?.pageCount ?? 1) - 1, center + range + extraEnd)

        for index in pageViewMap.keys where index < keepStart || index > keepEnd {
            recycle(index: index)
        }
    }

    // MARK: - VC 工厂（每次新建）
    private func makeVC(for index: Int) -> PDFPageViewController? {
        guard let doc = document, index >= 0, index < doc.pageCount else { return nil }

        let vc = PDFPageViewController()
        vc.onToggleToolbar = onToggleToolbar
        // goToPage：document 不变，只跳页，PDFKit 瓦片缓存保留
        let pv = dequeue(for: index)
        
        vc.attachPDFView(pv, pageIndex: index, document: doc)

        return vc
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? PDFPageViewController else { return nil }
        let prevIndex = vc.pageIndex - (isTwoUp ? 2 : 1)
        return makeVC(for: prevIndex)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? PDFPageViewController else { return nil }
        let nextIndex = vc.pageIndex + (isTwoUp ? 2 : 1)
        return makeVC(for: nextIndex)
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed,
              let vc = pageViewController.viewControllers?.first as? PDFPageViewController
        else { return }

        currentPageIndex = vc.pageIndex
        recycleOutOfRange(center: currentPageIndex)
//        prefetch(around: currentPageIndex)
        onPageDidChange?(currentPageIndex)
    }

    // MARK: - 跳转到指定页
    func goToPage(_ index: Int, animated: Bool = false) {
        guard index >= 0, let doc = document, index < doc.pageCount else { return }
        // 删掉 guard index != currentPageIndex，允许刷新当前页

        let direction: UIPageViewController.NavigationDirection =
            index > currentPageIndex ? .forward : .reverse

        if let targetVC = makeVC(for: index) {
            setViewControllers([targetVC], direction: direction, animated: animated) { [weak self] finished in
                guard let self, finished else { return }
                self.currentPageIndex = index
                self.recycleOutOfRange(center: index)
//                self.prefetch(around: index)
                self.onPageDidChange?(index)
            }
        }
    }
}
