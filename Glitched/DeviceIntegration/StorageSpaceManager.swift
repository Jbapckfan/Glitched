import UIKit
import Combine

/// Manages temporary cache files and detects when storage is cleared
final class StorageSpaceManager: DeviceManager {
    static let shared = StorageSpaceManager()

    let supportedMechanics: Set<MechanicType> = [.storageSpace]

    private var isActive = false
    private var cacheFileURL: URL?
    private var timer: Timer?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Create a cache file that represents the "data mass" in-game
        createCacheFile()

        // Poll to detect if user cleared it
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkCacheStatus()
        }

        print("StorageSpaceManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        print("StorageSpaceManager: Deactivated")
    }

    private func createCacheFile() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cacheDir.appendingPathComponent("glitched_data_mass.cache")
        cacheFileURL = fileURL

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // Create a ~5MB cache file
            let data = Data(repeating: 0x47, count: 5 * 1024 * 1024)
            try? data.write(to: fileURL)
        }
    }

    private func checkCacheStatus() {
        guard let url = cacheFileURL else { return }

        if !FileManager.default.fileExists(atPath: url.path) {
            // Cache was cleared by user via Settings
            DispatchQueue.main.async {
                InputEventBus.shared.post(.storageCacheCleared)
            }
        }
    }

    /// Returns the size of the cache file in MB for display
    func getCacheSizeMB() -> Double {
        guard let url = cacheFileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return Double(size) / (1024 * 1024)
    }

    /// Manually clear the cache (fallback for simulator/testing)
    func clearCache() {
        guard let url = cacheFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        checkCacheStatus()
    }
}
