//
//  PDFProgressSlider.swift
//  XLiPadBook
//
//  Created by ice on 1/9/2025.
//

import UIKit
import PDFKit

protocol PDFProgressSliderDelegate: AnyObject {
    func progressSlider(_ slider: PDFProgressSlider, didSelectPage index: Int)
}

class PDFProgressSlider: UIView {

    weak var delegate: PDFProgressSliderDelegate?
    private var pdfDocument: PDFDocument?
    private var totalPageCount: Int = 0

    private let slider = UISlider()
    private let thumbnailPreview = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchEnded(_:)), for: [.touchUpInside, .touchUpOutside])
        addSubview(slider)
        
        thumbnailPreview.contentMode = .scaleAspectFit
        thumbnailPreview.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        thumbnailPreview.layer.cornerRadius = 6
        thumbnailPreview.clipsToBounds = true
        thumbnailPreview.isHidden = true
        addSubview(thumbnailPreview)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        slider.frame = bounds
    }

    func configure(with pdfDocument: PDFDocument) {
        self.pdfDocument = pdfDocument
        self.totalPageCount = pdfDocument.pageCount
        updateThumb(forPage: 0)
    }

    func updateProgress(currentPage: Int) {
        guard totalPageCount > 0 else { return }
        slider.value = Float(currentPage) / Float(totalPageCount - 1)
        updateThumb(forPage: currentPage)
    }

    // MARK: - 更新 thumb
    private func updateThumb(forPage pageIndex: Int) {
        let diameter: CGFloat = 36
        UIGraphicsBeginImageContextWithOptions(CGSize(width: diameter, height: diameter), false, 0)
        defer { UIGraphicsEndImageContext() }

        // 画圆
        let circlePath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        UIColor.systemBlue.setFill()
        circlePath.fill()

        // 画页码
        let text = "\(pageIndex + 1)"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.boldSystemFont(ofSize: 16),
            .paragraphStyle: style
        ]
        text.draw(in: CGRect(x: 0, y: (diameter - 20)/2, width: diameter, height: 20), withAttributes: attributes)

        if let image = UIGraphicsGetImageFromCurrentImageContext() {
            slider.setThumbImage(image, for: .normal)
        }
    }

    @objc private func sliderValueChanged(_ sender: UISlider) {
        guard totalPageCount > 0, let doc = pdfDocument else { return }
        let pageIndex = Int(round(sender.value * Float(totalPageCount - 1)))
        updateThumb(forPage: pageIndex)

        // 缩略图显示
        if let page = doc.page(at: pageIndex) {
            let thumb = page.thumbnail(of: CGSize(width: 80, height: 100), for: .cropBox)
            thumbnailPreview.image = thumb
            let trackRect = slider.trackRect(forBounds: slider.bounds)
            let thumbRect = slider.thumbRect(forBounds: slider.bounds, trackRect: trackRect, value: sender.value)
            thumbnailPreview.frame = CGRect(x: thumbRect.midX - 40, y: thumbRect.minY - 160, width: 80, height: 100)
            thumbnailPreview.isHidden = false
        }
    }

    @objc private func sliderTouchEnded(_ sender: UISlider) {
        guard totalPageCount > 0 else { return }
        let pageIndex = Int(round(sender.value * Float(totalPageCount - 1)))
        thumbnailPreview.isHidden = true
        delegate?.progressSlider(self, didSelectPage: pageIndex)
    }
}
