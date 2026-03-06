//
//  CustomPDFView.swift
//  XLiPadBook
//
//  自定义 PDFView：拦截文字选中弹框，实现「复制 / 写段评 / 高亮标记」
//

import UIKit
import PDFKit

// MARK: - Delegate Protocol

protocol CustomPDFViewDelegate: AnyObject {
    /// 用户点击「写段评」
    func customPDFView(_ view: CustomPDFView,
                       didRequestAnnotationFor selection: PDFSelection,
                       anchorRect: CGRect)
    /// 用户点击「高亮标记」
    func customPDFView(_ view: CustomPDFView,
                       didRequestHighlightFor selection: PDFSelection)
    /// 用户点击「复制」
    func customPDFView(_ view: CustomPDFView,
                       didCopy text: String)
}

// MARK: - CustomPDFView

final class CustomPDFView: PDFView {

    weak var customDelegate: CustomPDFViewDelegate?

    // 当前选中内容（避免与 PDFView.currentSelection 冲突，改名为 _activeSelection）
    private var _activeSelection: PDFSelection?

    // 自定义弹框
    private weak var menuView: SelectionMenuView?

    // MARK: - Setup

    override func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 监听 PDFView 的选中变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange),
            name: .PDFViewSelectionChanged,
            object: self
        )

        // 禁用系统长按菜单（iOS 16+）
        if #available(iOS 16.0, *) {
            // 移除所有系统交互（系统菜单通过 UIEditMenuInteraction 弹出）
            interactions.filter { $0 is UIEditMenuInteraction }.forEach { removeInteraction($0) }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 拦截系统菜单

    /// iOS 16 以下：阻止 UIMenuController 弹出
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 完全屏蔽系统菜单
        return false
    }

    // MARK: - 选中变化处理

    @objc private func handleSelectionChange() {
        // self.currentSelection 是 PDFView 的原生属性，延迟读取确保已更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let newSel = self.currentSelection  // PDFView 原生属性
            if let newSel, let text = newSel.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self._activeSelection = newSel
                self.showMenu(for: newSel)
            } else {
                self._activeSelection = nil
                self.dismissMenu()
            }
        }
    }

    // MARK: - 自定义弹框

    private func showMenu(for selection: PDFSelection) {
        dismissMenu()

        guard let anchorRect = selectionRect(for: selection) else { return }

        let menu = SelectionMenuView()
        // 用 frame 定位，不要关闭 autoresizing
        menu.translatesAutoresizingMaskIntoConstraints = true
        menu.onCopy = { [weak self] in
            guard let self else { return }
            if let text = self._activeSelection?.string {
                self.customDelegate?.customPDFView(self, didCopy: text)
            }
            self.dismissMenu()
            self.clearActiveSelection()
        }
        menu.onAnnotate = { [weak self] in
            guard let self, let sel = self._activeSelection else { return }
            self.customDelegate?.customPDFView(self, didRequestAnnotationFor: sel, anchorRect: anchorRect)
            self.dismissMenu()
        }
        menu.onHighlight = { [weak self] in
            guard let self, let sel = self._activeSelection else { return }
            self.customDelegate?.customPDFView(self, didRequestHighlightFor: sel)
            self.dismissMenu()
            self.clearActiveSelection()
        }

        addSubview(menu)
        self.menuView = menu

        let menuWidth: CGFloat = 300
        let menuHeight: CGFloat = 44
        let padding: CGFloat = 8

        var menuX = anchorRect.midX - menuWidth / 2
        menuX = max(8, min(menuX, bounds.width - menuWidth - 8))

        var menuY = anchorRect.minY - menuHeight - padding
        if menuY < safeAreaInsets.top + 8 {
            menuY = anchorRect.maxY + padding
        }

        menu.frame = CGRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)

        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            menu.alpha = 1
            menu.transform = .identity
        }
    }

    func dismissMenu() {
        menuView?.removeFromSuperview()
        menuView = nil
    }

    private func clearActiveSelection() {
        clearSelection()   // 调用 PDFView 原生方法清除视觉选中
        _activeSelection = nil
    }

    // MARK: - 计算选中区域 Rect（PDFView 坐标系）

    private func selectionRect(for selection: PDFSelection) -> CGRect? {
        var unionRect: CGRect?
        for page in selection.pages {
            // PDF 页面坐标：原点左下角，Y 向上
            let pdfBounds = selection.bounds(for: page)

            // 页面 mediaBox（PDF 坐标）
            let mediaBox = page.bounds(for: .mediaBox)

            // 页面在 PDFView 中的 frame（UIKit 坐标，已含缩放和滚动偏移）
            // convert(_:from:page) 虽存在但在缩放场景下 Y 轴不可靠
            // 改用 documentView 坐标系中转：
            // 1. 先把页面 mediaBox 的左上角转到 documentView 坐标
            // 2. 再把 documentView 坐标转到 self（CustomPDFView）坐标
            guard let docView = documentView else { continue }

            // PDFView 提供的 convert 方法：将 PDF 页坐标转为 PDFView 内 documentView 坐标
            // 用四个角取 union 来规避 Y 轴翻转问题
            let corners: [CGPoint] = [
                CGPoint(x: pdfBounds.minX, y: pdfBounds.minY),
                CGPoint(x: pdfBounds.maxX, y: pdfBounds.minY),
                CGPoint(x: pdfBounds.minX, y: pdfBounds.maxY),
                CGPoint(x: pdfBounds.maxX, y: pdfBounds.maxY)
            ]

            // PDFPage → documentView 坐标
            // PDFPage 坐标原点左下，mediaBox.height 用于翻转
            let pageFrameInDoc: CGRect = {
                // PDFView 的 convert(_:from:page) 返回的是 documentView 坐标
                // 用整页 mediaBox 转换来拿到页面在 documentView 中的 frame
                let originInDoc = convert(
                    CGPoint(x: mediaBox.minX, y: mediaBox.maxY), // PDF 左上角（Y 最大）
                    from: page
                )
                let scale = docView.bounds.width > 0
                    ? (convert(CGPoint(x: mediaBox.maxX, y: mediaBox.maxY), from: page).x
                       - originInDoc.x) / mediaBox.width
                    : 1.0
                return CGRect(
                    origin: originInDoc,
                    size: CGSize(width: mediaBox.width * scale, height: mediaBox.height * scale)
                )
            }()
            _ = pageFrameInDoc // suppress unused warning

            // 直接用 PDFView 的 convert(_:from:page) 转四个角，再 union
            let docPoints = corners.map { convert($0, from: page) }
            let minX = docPoints.map(\.x).min()!
            let minY = docPoints.map(\.y).min()!
            let maxX = docPoints.map(\.x).max()!
            let maxY = docPoints.map(\.y).max()!
            let rectInSelf = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            unionRect = unionRect.map { $0.union(rectInSelf) } ?? rectInSelf
        }
        return unionRect
    }
}

// MARK: - SelectionMenuView

/// 选中文字后弹出的操作菜单（气泡样式）
final class SelectionMenuView: UIView {

    var onCopy: (() -> Void)?
    var onAnnotate: (() -> Void)?
    var onHighlight: (() -> Void)?

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 背景气泡
        backgroundColor = UIColor(white: 0.12, alpha: 0.95)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 6

        // 按钮栈
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let buttons: [(String, String, () -> Void)] = [
            ("doc.on.doc", "复制", { [weak self] in self?.onCopy?() }),
            ("pencil.and.ellipsis.rectangle", "写段评", { [weak self] in self?.onAnnotate?() }),
            ("highlighter", "高亮", { [weak self] in self?.onHighlight?() })
        ]

        for (i, (icon, title, action)) in buttons.enumerated() {
            let btn = makeButton(icon: icon, title: title, action: action)
            stackView.addArrangedSubview(btn)

            // 分隔线（最后一个不加）
            if i < buttons.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.white.withAlphaComponent(0.15)
                sep.translatesAutoresizingMaskIntoConstraints = false
                addSubview(sep)
                // 分隔线通过绝对定位（相对按钮宽度 1/3）
                NSLayoutConstraint.activate([
                    sep.widthAnchor.constraint(equalToConstant: 0.5),
                    sep.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                    sep.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
                    sep.leadingAnchor.constraint(equalTo: stackView.leadingAnchor,
                                                 constant: CGFloat(i + 1) * (240.0 / 3.0))
                ])
            }
        }
    }

    private func makeButton(icon: String, title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        config.title = title
        config.imagePlacement = .leading
        config.imagePadding = 5
        config.baseForegroundColor = .white
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor.white
        ]))

        let btn = UIButton(configuration: config)
        btn.configurationUpdateHandler = { button in
            button.alpha = button.state == .highlighted ? 0.6 : 1.0
        }

        // 用 closure 绑定（iOS 14+）
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    // 点击菜单外区域时不拦截（让事件穿透到 PDFView）
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
