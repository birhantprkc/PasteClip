import CloudKit
import Foundation
import SwiftData

/// Identifies one synced object. Record names are "<kind>.<model UUID>" so local models
/// keep their existing IDs and nothing in the Mac store has to change.
struct SyncKey: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case clip, pinboard, entry

        var recordType: CKRecord.RecordType {
            switch self {
            case .clip: "Clip"
            case .pinboard: "Pinboard"
            case .entry: "PinboardEntry"
            }
        }
    }

    let kind: Kind
    let id: UUID

    static let zoneID = CKRecordZone.ID(zoneName: "Clipbara", ownerName: CKCurrentUserDefaultName)

    var recordName: String { "\(kind.rawValue).\(id.uuidString)" }

    var recordID: CKRecord.ID { CKRecord.ID(recordName: recordName, zoneID: Self.zoneID) }

    init(kind: Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }

    init?(recordName: String) {
        let parts = recordName.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        self.init(kind: kind, id: id)
    }

    init?(recordID: CKRecord.ID) {
        self.init(recordName: recordID.recordName)
    }
}

/// Field names and the rules for what syncs.
///
/// Only text-like clips sync for now: plain text, links, and colors. Rich text and HTML
/// sync as their plain text. Images and files stay on the device they were copied on.
enum SyncSchema {
    static let maxTextBytes = 200_000

    enum ClipField {
        static let type = "type"            // plain
        static let copiedAt = "copiedAt"    // plain
        static let text = "text"            // encrypted
        static let title = "title"          // encrypted
        static let hash = "hash"            // encrypted
        static let sourceApp = "sourceApp"  // encrypted
        static let sourceBundle = "sourceBundle" // encrypted
    }

    enum PinboardField {
        static let name = "name"            // encrypted
        static let order = "order"
        static let createdAt = "createdAt"
    }

    enum EntryField {
        static let clipID = "clipID"
        static let pinboardID = "pinboardID"
        static let order = "order"
        static let addedAt = "addedAt"
    }

    static func syncText(of item: ClipboardItem) -> String? {
        if let text = item.textContent, !text.isEmpty { return text }
        guard [.plainText, .url, .color].contains(item.contentType) else { return nil }
        return String(data: item.rawData, encoding: .utf8)
    }

    static func isEligible(_ item: ClipboardItem) -> Bool {
        switch item.contentType {
        case .plainText, .richText, .html, .url, .color, .unknown:
            guard let text = syncText(of: item), !text.isEmpty else { return false }
            return text.utf8.count <= maxTextBytes
        case .image, .fileURL:
            return false
        }
    }

    static func isEligible(_ entry: PinboardEntry) -> Bool {
        guard let item = entry.clipboardItem, entry.pinboard != nil else { return false }
        return isEligible(item)
    }

    /// Rich text and HTML arrive on the other device as plain text.
    static func syncedType(_ type: ContentType) -> ContentType {
        switch type {
        case .richText, .html, .unknown: .plainText
        default: type
        }
    }

    // MARK: - Model -> record

    static func fill(_ record: CKRecord, from item: ClipboardItem) {
        let secret = record.encryptedValues
        record[ClipField.type] = syncedType(item.contentType).rawValue as NSString
        record[ClipField.copiedAt] = item.copiedAt as NSDate
        secret[ClipField.text] = syncText(of: item) ?? ""
        secret[ClipField.title] = item.userTitle
        secret[ClipField.hash] = item.contentHash
        secret[ClipField.sourceApp] = item.sourceAppName
        secret[ClipField.sourceBundle] = item.sourceAppBundleId
    }

    static func fill(_ record: CKRecord, from pinboard: Pinboard) {
        record.encryptedValues[PinboardField.name] = pinboard.name
        record[PinboardField.order] = pinboard.displayOrder as NSNumber
        record[PinboardField.createdAt] = pinboard.createdAt as NSDate
    }

    static func fill(_ record: CKRecord, from entry: PinboardEntry) {
        record[EntryField.clipID] = (entry.clipboardItem?.id.uuidString ?? "") as NSString
        record[EntryField.pinboardID] = (entry.pinboard?.id.uuidString ?? "") as NSString
        record[EntryField.order] = entry.displayOrder as NSNumber
        record[EntryField.addedAt] = entry.addedAt as NSDate
    }

    // MARK: - Record -> values

    struct ClipValues {
        let type: ContentType
        let copiedAt: Date
        let text: String
        let title: String?
        let hash: String
        let sourceApp: String?
        let sourceBundle: String?
    }

    static func clipValues(_ record: CKRecord) -> ClipValues? {
        let secret = record.encryptedValues
        guard let text = secret[ClipField.text] as String?, !text.isEmpty else { return nil }
        let type = (record[ClipField.type] as? String).flatMap(ContentType.init(rawValue:)) ?? .plainText
        return ClipValues(
            type: type,
            copiedAt: record[ClipField.copiedAt] as? Date ?? Date(),
            text: text,
            title: secret[ClipField.title] as String?,
            hash: secret[ClipField.hash] as String? ?? "",
            sourceApp: secret[ClipField.sourceApp] as String?,
            sourceBundle: secret[ClipField.sourceBundle] as String?
        )
    }

    struct EntryValues: Codable, Sendable {
        let id: UUID
        let clipID: UUID
        let pinboardID: UUID
        let order: Int
        let addedAt: Date
    }

    static func entryValues(_ record: CKRecord, id: UUID) -> EntryValues? {
        guard let clip = (record[EntryField.clipID] as? String).flatMap(UUID.init(uuidString:)),
              let board = (record[EntryField.pinboardID] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        return EntryValues(
            id: id,
            clipID: clip,
            pinboardID: board,
            order: (record[EntryField.order] as? Int) ?? 0,
            addedAt: record[EntryField.addedAt] as? Date ?? Date()
        )
    }

    /// When two devices saved the same content under different IDs, both keep the clip
    /// with the smaller ID, so they converge without talking to each other.
    static func survivor(_ a: UUID, _ b: UUID) -> UUID {
        a.uuidString < b.uuidString ? a : b
    }
}
