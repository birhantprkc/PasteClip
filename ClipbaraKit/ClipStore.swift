import Foundation
import SwiftData

/// Local SwiftData store shared by the iOS app and its extensions through the app group.
enum ClipStore {
    static let appGroupID = "group.com.minsang.Clipbara"

    static let schema = Schema([
        ClipboardItem.self,
        Pinboard.self,
        PinboardEntry.self,
    ])

    /// Shared defaults (falls back to standard defaults when the app group is unavailable).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func storeURL() -> URL {
        let fm = FileManager.default
        let directory: URL
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = group
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Clipbara", isDirectory: true)
        } else {
            directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Clipbara", isDirectory: true)
        }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Clipbara.store")
    }

    /// Every configuration is explicitly local: with iCloud entitlements the default
    /// `.automatic` would turn on SwiftData's CloudKit mirroring and fail to open.
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, url: storeURL(), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never delete the user's store here. Fall back to memory so the app still opens.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Cannot create any ModelContainer: \(error)")
            }
        }
    }
}
