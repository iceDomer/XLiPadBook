//
//  ViewController.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//

import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        let button = UIButton(type: .system)
        button.setTitle("打开 PDF", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        button.addTarget(self, action: #selector(openPDF), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    @objc private func openPDF() {
//        let url2 = "https://imgcdn.cbnweek.com/2c3df2b21237467795425dc4778f3bab?size=40368024";
        let url1 = "https://imgcdn.cbnweek.com/2a8cb359698f4ff5bd83832de5e26a8a?size=55081313";
//        if let path = Bundle.main.path(forResource: "2025.07无广告", ofType: "pdf") {
//            let readerVC = PDFReaderViewController(filePath: path, bookId: "sampleBook")
//            navigationController?.pushViewController(readerVC, animated: true)
//        }
        if let url = URL(string: url1) {
            let readerVC = PDFReaderViewController(
                remoteURL: url,
                bookId: "cbnweek_202401"
            )
            navigationController?.pushViewController(readerVC, animated: true)
        }

    }
}
