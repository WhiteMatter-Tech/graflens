import Foundation
import UIKit

actor PanelCacheManager {
    static let shared = PanelCacheManager()

    private let cacheDir: URL
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    private init() {
        let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = docs.appendingPathComponent("panelCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Image Cache

    func cacheImage(_ image: UIImage, dashboardUID: String, panelID: Int) {
        let key = cacheKey(dashboardUID: dashboardUID, panelID: panelID)
        let url = cacheDir.appendingPathComponent(key + ".png")
        if let data = image.pngData() {
            try? data.write(to: url)
        }
        // Save timestamp
        let metaURL = cacheDir.appendingPathComponent(key + ".meta")
        let timestamp = "\(Date().timeIntervalSince1970)"
        try? timestamp.data(using: .utf8)?.write(to: metaURL)
    }

    func loadCachedImage(dashboardUID: String, panelID: Int) -> (image: UIImage, age: TimeInterval)? {
        let key = cacheKey(dashboardUID: dashboardUID, panelID: panelID)
        let url = cacheDir.appendingPathComponent(key + ".png")
        let metaURL = cacheDir.appendingPathComponent(key + ".meta")

        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data),
              let metaData = try? Data(contentsOf: metaURL),
              let metaString = String(data: metaData, encoding: .utf8),
              let timestamp = TimeInterval(metaString) else { return nil }

        let age = Date().timeIntervalSince1970 - timestamp
        guard age < maxCacheAge else {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: metaURL)
            return nil
        }

        return (image, age)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    var cacheSize: Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.compactMap { try? fm.attributesOfItem(atPath: $0.path)[.size] as? Int64 }.reduce(0, +)
    }

    private func cacheKey(dashboardUID: String, panelID: Int) -> String {
        "\(dashboardUID)_\(panelID)"
    }
}
