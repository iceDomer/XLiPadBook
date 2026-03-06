//
//  PDFCacheManager.swift
//  XLiPadBook
//
//  Created by ice on 13/1/2026.
//

import Foundation
import CommonCrypto

// MARK: - Cache Item Model

private struct PDFCacheItem: Codable {
    let cacheKey: String
    let filePath: String
    var lastReadTime: TimeInterval
}

// MARK: - Download Delegate

private final class PDFDownloadDelegate: NSObject, URLSessionDownloadDelegate {

    let destinationURL: URL
    let progressHandler: (Double) -> Void
    let completion: (URL?) -> Void

    init(
        destinationURL: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (URL?) -> Void
    ) {
        self.destinationURL = destinationURL
        self.progressHandler = progress
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.progressHandler(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.completion(self.destinationURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.completion(nil)
            }
        }
    }
}

// MARK: - PDFCacheManager

final class PDFCacheManager {

    // MARK: Singleton
    static let shared = PDFCacheManager(maxCacheCount: 10)

    // MARK: Config
    private let maxCacheCount: Int

    // MARK: Private
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.pdf.cache.manager.queue")

    private let cacheDirectory: URL
    private let metaFileURL: URL

    private var cacheItems: [PDFCacheItem] = []

    // MARK: Init

    init(maxCacheCount: Int) {
        self.maxCacheCount = maxCacheCount

        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = baseURL.appendingPathComponent("PDFCache", isDirectory: true)
        self.metaFileURL = cacheDirectory.appendingPathComponent("meta.json")

        createCacheDirectoryIfNeeded()
        loadMeta()
    }

    // MARK: - Public API

    /// 加载 PDF（支持进度）
    func loadPDF(
        from remoteURL: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (URL?) -> Void
    ) {
        ioQueue.async {
            let key = self.cacheKey(for: remoteURL)
            let localURL = self.cacheDirectory.appendingPathComponent("\(key).pdf")

            // 已缓存
            if self.fileManager.fileExists(atPath: localURL.path) {
                self.updateLastReadTime(for: key)
                DispatchQueue.main.async {
                    completion(localURL)
                }
                return
            }

            // 下载
            let delegate = PDFDownloadDelegate(
                destinationURL: localURL,
                progress: progress
            ) { [weak self] url in
                guard let self, let url else {
                    completion(nil)
                    return
                }

                self.ioQueue.async {
                    self.addCacheItem(cacheKey: key, localURL: url)
                    self.cleanupIfNeeded()
                    DispatchQueue.main.async {
                        completion(url)
                    }
                }
            }

            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )

            let task = session.downloadTask(with: remoteURL)
            task.resume()
        }
    }

    /// 标记为最近阅读（刷新 LRU）
    func markAsRead(url: URL) {
        let key = cacheKey(for: url)
        ioQueue.async {
            self.updateLastReadTime(for: key)
        }
    }

    /// 清空缓存（调试 / 设置页用）
    func clearAllCache() {
        ioQueue.async {
            for item in self.cacheItems {
                try? self.fileManager.removeItem(atPath: item.filePath)
            }
            self.cacheItems.removeAll()
            self.saveMeta()
        }
    }
}

// MARK: - LRU Logic

private extension PDFCacheManager {

    func addCacheItem(cacheKey: String, localURL: URL) {
        let item = PDFCacheItem(
            cacheKey: cacheKey,
            filePath: localURL.path,
            lastReadTime: Date().timeIntervalSince1970
        )
        cacheItems.append(item)
        saveMeta()
    }

    func updateLastReadTime(for cacheKey: String) {
        guard let index = cacheItems.firstIndex(where: { $0.cacheKey == cacheKey }) else { return }
        cacheItems[index].lastReadTime = Date().timeIntervalSince1970
        saveMeta()
    }

    func cleanupIfNeeded() {
        guard cacheItems.count > maxCacheCount else { return }

        let sorted = cacheItems.sorted {
            $0.lastReadTime < $1.lastReadTime
        }

        let removeCount = cacheItems.count - maxCacheCount
        let removeItems = sorted.prefix(removeCount)

        for item in removeItems {
            try? fileManager.removeItem(atPath: item.filePath)
            cacheItems.removeAll { $0.cacheKey == item.cacheKey }
        }

        saveMeta()
    }
}

// MARK: - Meta Persistence

private extension PDFCacheManager {

    func loadMeta() {
        guard
            let data = try? Data(contentsOf: metaFileURL),
            let items = try? JSONDecoder().decode([PDFCacheItem].self, from: data)
        else { return }

        cacheItems = items
    }

    func saveMeta() {
        guard let data = try? JSONEncoder().encode(cacheItems) else { return }
        try? data.write(to: metaFileURL, options: .atomic)
    }
}

// MARK: - File System

private extension PDFCacheManager {

    func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    func cacheKey(for url: URL) -> String {
        return url.absoluteString.sha256
    }
}

// MARK: - String Hash

private extension String {

    var sha256: String {
        guard let data = data(using: .utf8) else { return UUID().uuidString }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
