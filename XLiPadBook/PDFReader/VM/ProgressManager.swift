//
//  ProgressManager.swift
//  XLiPadBook
//
//  Created by ice on 29/8/2025.
//

import Foundation

class ProgressManager {
    static func saveProgress(page: Int, for bookId: String) {
        UserDefaults.standard.set(page, forKey: bookId)
    }
    
    static func lastProgress(for bookId: String) -> Int {
        return UserDefaults.standard.integer(forKey: bookId)
    }
}
