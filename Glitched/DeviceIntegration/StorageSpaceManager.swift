import UIKit
import Combine

/// Manages the in-game "junk mass" and detects when the player reclaims storage.
///
/// Two REAL device routes are detected (no in-scene always-on button anymore):
///   1. Cache-file route: a representative cache file is written to the app's
///      Caches dir; if the player offloads the app / clears its cache via
///      Settings, the file disappears and we fire `.storageCacheCleared`.
///   2. Free-space route: we snapshot system volume free space on activate; if
///      the player frees a meaningful amount of storage device-wide (deleting
///      photos, apps, etc.) we also fire `.storageCacheCleared`. This makes the
///      in-world prompt "FREE UP STORAGE" literally true, not just "delete this
///      app's cache".
///
/// On a release device where neither is practical, the Wave-2b "CAN'T DO THIS?"
/// escape hatch surfaces the storage fallback button, which posts the same event.
final class StorageSpaceManager: DeviceManager {
    static let shared = StorageSpaceManager()

    let supportedMechanics: Set<MechanicType> = [.storageSpace]

    private var isActive = false
    private var cacheFileURL: URL?
    private var timer: Timer?

    /// System free bytes captured at activation, used for the free-space route.
    private var baselineFreeBytes: Int64?
    /// How much the player must free (device-wide) to count as a purge. Kept
    /// small enough to be achievable by deleting a few photos/an app, large
    /// enough to ignore normal background churn.
    private let freeSpaceThreshold: Int64 = 50 * 1024 * 1024 // 50MB
    private var hasFired = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true
        hasFired = false

        createCacheFile()
        baselineFreeBytes = systemFreeBytes()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkCacheStatus()
            self?.checkFreeSpace()
        }

        print("StorageSpaceManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil

        // NOTE: Do NOT delete the cache file here. deactivate() also runs on app
        // backgrounding (DeviceManagerCoordinator.appDidEnterBackground), and the
        // intended solve path is for the player to clear the cache / free storage
        // from iOS Settings WHILE backgrounded. Deleting on background would
        // corrupt that flow and auto-bypass the puzzle. File removal happens only
        // on true level teardown via removeCacheFile().

        print("StorageSpaceManager: Deactivated")
    }

    /// Removes the on-disk cache file so it isn't orphaned. Call only on true
    /// level teardown (scene willMove), never on app backgrounding. Best-effort.
    func removeCacheFile() {
        if let url = cacheFileURL {
            try? FileManager.default.removeItem(at: url)
            cacheFileURL = nil
        }
        baselineFreeBytes = nil
    }

    private func createCacheFile() {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            print("StorageSpaceManager: No caches directory available")
            return
        }
        let fileURL = cacheDir.appendingPathComponent("glitched_data_mass.cache")
        cacheFileURL = fileURL

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let data = Data(repeating: 0x47, count: 5 * 1024 * 1024) // ~5MB
            try? data.write(to: fileURL)
        }
    }

    private func checkCacheStatus() {
        guard let url = cacheFileURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            firePurge()
        }
    }

    private func checkFreeSpace() {
        guard let baseline = baselineFreeBytes, let current = systemFreeBytes() else { return }
        if current - baseline >= freeSpaceThreshold {
            firePurge()
        }
    }

    /// Best-effort system free bytes for the volume backing the app's home dir.
    private func systemFreeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return nil
    }

    private func firePurge() {
        guard !hasFired else { return }
        hasFired = true
        DispatchQueue.main.async {
            InputEventBus.shared.post(.storageCacheCleared)
        }
    }

    /// Returns the size of the cache file in MB for display.
    func getCacheSizeMB() -> Double {
        guard let url = cacheFileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return Double(size) / (1024 * 1024)
    }

    /// Manually clear the representative cache file (fallback for simulator/testing).
    func clearCache() {
        guard let url = cacheFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        checkCacheStatus()
    }
}
