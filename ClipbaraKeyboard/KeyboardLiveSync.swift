import CloudKit
import Foundation

/// With Full Access, the keyboard asks iCloud for what changed since the app last
/// checked, so a clip copied on the Mac a moment ago shows up without opening Clipbara.
///
/// It never writes to the clip store or moves the app's change token: the app still
/// imports everything itself the next time it runs. Text only; the keyboard cannot
/// insert images, and it has a tight memory limit.
enum KeyboardLiveSync {
    static let maxRecords = 300

    private static let keys: [CKRecord.FieldKey] = [
        SyncSchema.ClipField.type, SyncSchema.ClipField.copiedAt, SyncSchema.ClipField.text,
        SyncSchema.ClipField.title,
        SyncSchema.PinboardField.name, SyncSchema.PinboardField.createdAt,
        SyncSchema.EntryField.clipID, SyncSchema.EntryField.pinboardID, SyncSchema.EntryField.order,
    ]

    /// Whether a live fetch is possible right now, and with which token.
    static func startingToken() -> CKServerChangeToken? {
        let defaults = ClipStore.defaults
        guard defaults.bool(forKey: "iCloudSyncEnabled"),
              let data = defaults.data(forKey: "iCloudSyncPollToken") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    static var containerIdentifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ClipbaraCloudKitContainer") as? String,
              id.hasPrefix("iCloud.") else { return nil }
        return id
    }

    static func fetchDelta(since token: CKServerChangeToken) async throws -> KeyboardDelta {
        guard let identifier = containerIdentifier else { return KeyboardDelta() }
        let database = CKContainer(identifier: identifier).privateCloudDatabase
        var delta = KeyboardDelta()
        var current: CKServerChangeToken? = token
        var fetched = 0
        var moreComing = true

        while moreComing && fetched < maxRecords {
            let result = try await database.recordZoneChanges(
                inZoneWith: SyncKey.zoneID,
                since: current,
                desiredKeys: keys,
                resultsLimit: 100
            )
            for (_, outcome) in result.modificationResultsByID {
                guard case .success(let modification) = outcome else { continue }
                apply(modification.record, to: &delta)
                fetched += 1
            }
            for deletion in result.deletions {
                guard let key = SyncKey(recordID: deletion.recordID) else { continue }
                switch key.kind {
                case .clip: delta.deletedClipIDs.insert(key.id)
                case .pinboard: delta.deletedPinboardIDs.insert(key.id)
                case .entry: delta.deletedEntryIDs.insert(key.id)
                }
            }
            current = result.changeToken
            moreComing = result.moreComing
        }
        return delta
    }

    private static func apply(_ record: CKRecord, to delta: inout KeyboardDelta) {
        guard let key = SyncKey(recordID: record.recordID) else { return }
        switch key.kind {
        case .clip:
            let type = (record[SyncSchema.ClipField.type] as? String).flatMap(ContentType.init(rawValue:)) ?? .plainText
            guard KeyboardSnapshot.insertableTypes.contains(type),
                  let text = record.encryptedValues[SyncSchema.ClipField.text] as String?, !text.isEmpty else { return }
            delta.clips.append(KeyboardSnapshot.Clip(
                id: key.id,
                contentTypeRaw: type.rawValue,
                text: String(text.prefix(KeyboardSnapshot.textLimit)),
                userTitle: record.encryptedValues[SyncSchema.ClipField.title] as String?,
                copiedAt: record[SyncSchema.ClipField.copiedAt] as? Date ?? Date()
            ))
        case .pinboard:
            delta.pinboards.append(KeyboardDelta.Pinboard(
                id: key.id,
                name: record.encryptedValues[SyncSchema.PinboardField.name] as String? ?? "",
                createdAt: record[SyncSchema.PinboardField.createdAt] as? Date ?? Date()
            ))
        case .entry:
            guard let values = SyncSchema.entryValues(record, id: key.id) else { return }
            delta.entries.append(KeyboardDelta.Entry(
                id: values.id, clipID: values.clipID, pinboardID: values.pinboardID, order: values.order
            ))
        }
    }
}
