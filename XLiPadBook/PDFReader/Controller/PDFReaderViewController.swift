//
//  PDFReaderViewController.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//
import UIKit
import PDFKit

final class PDFReaderViewController: UIViewController {

    // MARK: - Properties

    private let remoteURL: URL
    private let bookId: String

    private var document: PDFDocument?
    private var pageController: PageContainerController!

    private let progressSlider = PDFProgressSlider()

    private let loadingView = UIView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()

    // MARK: - Init

    init(remoteURL: URL, bookId: String) {
        self.remoteURL = remoteURL
        self.bookId = bookId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLoadingUI()
        loadPDF()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveReadingProgress()
    }
}

// MARK: - PDF Loading

private extension PDFReaderViewController {

    func loadPDF() {
        loadingView.isHidden = false
        progressView.progress = 0
        progressLabel.text = "正在下载… 0%"

        PDFCacheManager.shared.loadPDF(
            from: remoteURL,
            progress: { [weak self] progress in
                guard let self else { return }
                self.progressView.progress = Float(progress)
                self.progressLabel.text = "正在下载… \(Int(progress * 100))%"
            },
            completion: { [weak self] localURL in
                guard
                    let self = self,
                    let localURL,
                    let document = PDFDocument(url: localURL)
                else { return }

                self.loadingView.isHidden = true

                self.document = document

                // 标记为已阅读（LRU）
                PDFCacheManager.shared.markAsRead(url: self.remoteURL)

                self.setupReader(with: document)
                
                if let page = document.page(at: 0),
                   let pageRef = page.pageRef {
                    
                    let dict = pageRef.dictionary!
                    var resources: CGPDFDictionaryRef?
                    CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
                    
                    guard let resources else { return }
                    
                    var xObject: CGPDFDictionaryRef?
                    CGPDFDictionaryGetDictionary(resources, "XObject", &xObject)
                    
                    guard let xObject else { return }
                    
                    var imageStream: CGPDFStreamRef?
                    CGPDFDictionaryGetStream(xObject, "Im0", &imageStream)
                    
                    guard let imageStream else { return }
                    
                    let streamDict = CGPDFStreamGetDictionary(imageStream)!
                    
                    // 查压缩格式
                    var filterName: CGPDFObjectRef?
                    CGPDFDictionaryGetObject(streamDict, "Filter", &filterName)
                    var namePtr: UnsafePointer<CChar>?
                    if CGPDFObjectGetValue(filterName!, .name, &namePtr), let namePtr {
                        print("Filter:", String(cString: namePtr))
                        // DCTDecode  → 普通 JPEG（快）
                        // JPXDecode  → JPEG2000（慢 3~5 倍）
                        // FlateDecode → zlib 压缩的原始位图（超慢）
                    }
                    
                    // 查图片尺寸
                    var width: Int = 0
                    var height: Int = 0
                    CGPDFDictionaryGetInteger(streamDict, "Width", &width)
                    CGPDFDictionaryGetInteger(streamDict, "Height", &height)
                    print("Image size: \(width) × \(height) px")
                }
            }
        )
    }

    
}

// MARK: - UI Setup

private extension PDFReaderViewController {

    func setupReader(with document: PDFDocument) {
//        let lastPage = ProgressManager.lastProgress(for: bookId)
        let lastPage = 0
        // Page Container
        pageController = PageContainerController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        pageController.document = document
        pageController.currentPageIndex = lastPage

        addChild(pageController)
        pageController.view.frame = view.bounds
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)

        // Progress Slider
        progressSlider.configure(with: document)
        progressSlider.delegate = self
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressSlider)

        NSLayoutConstraint.activate([
            progressSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            progressSlider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            progressSlider.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func setupLoadingUI() {
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        loadingView.layer.cornerRadius = 10
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)

        progressLabel.text = "正在下载… 0%"
        progressLabel.textColor = .white
        progressLabel.font = .systemFont(ofSize: 14)
        progressLabel.textAlignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.progress = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false

        loadingView.addSubview(progressLabel)
        loadingView.addSubview(progressView)

        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingView.widthAnchor.constraint(equalToConstant: 220),
            loadingView.heightAnchor.constraint(equalToConstant: 80),

            progressLabel.topAnchor.constraint(equalTo: loadingView.topAnchor, constant: 16),
            progressLabel.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor, constant: 12),
            progressLabel.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor, constant: -12),

            progressView.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor, constant: -16)
        ])
    }

}

// MARK: - Progress

private extension PDFReaderViewController {

    func saveReadingProgress() {
        guard
            let vc = pageController?.viewControllers?.first as? PDFPageViewController
        else { return }

        ProgressManager.saveProgress(page: vc.pageIndex, for: bookId)
    }
}

// MARK: - PDFProgressSliderDelegate

extension PDFReaderViewController: PDFProgressSliderDelegate {

    /// 拖动进度条跳页
    func progressSlider(_ slider: PDFProgressSlider, didSelectPage index: Int) {
        pageController.goToPage(index)
    }

    /// 页面变化时同步进度
    func pageDidChange(to index: Int) {
        progressSlider.updateProgress(currentPage: index)
    }
}

