//
//  PageContainerController.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//

import UIKit
import PDFKit

class PageContainerController: UIPageViewController, UIPageViewControllerDataSource {
    var document: PDFDocument?
    var currentPageIndex: Int = 0
    private var didInitialJump = false

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        isDoubleSided = true   // 纸张翻页效果
        
        if let firstVC = pageController(for: currentPageIndex) {
            setViewControllers([firstVC], direction: .forward, animated: false, completion: nil)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didInitialJump else { return }
        didInitialJump = true

        goToPage(currentPageIndex, animated: false)
    }

    
    func pageController(for index: Int) -> PDFPageViewController? {
        guard let doc = document, index >= 0, index < doc.pageCount else { return nil }
        let vc = PDFPageViewController()
        vc.pageIndex = index
        vc.document = doc
        return vc
    }
    
    // MARK: - DataSource
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? PDFPageViewController else { return nil }
        return pageController(for: vc.pageIndex - 1)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? PDFPageViewController else { return nil }
        return pageController(for: vc.pageIndex + 1)
    }
    
    // MARK: - 跳转到指定页
    func goToPage(_ index: Int, animated: Bool = false) {
        guard index >= 0, let doc = document, index < doc.pageCount else { return }
        guard index != currentPageIndex else { return }
        
        let direction: UIPageViewController.NavigationDirection = index > currentPageIndex ? .forward : .reverse
        if let targetVC = pageController(for: index) {
            setViewControllers([targetVC], direction: direction, animated: animated) { finished in
                if finished {
                    self.currentPageIndex = index
                }
            }
        }
    }
}
