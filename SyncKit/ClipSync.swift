import CloudKit
import Foundation
import Observation
import SwiftData
import os

/// Optional iCloud sync of history and pinboards through the person's private CloudKit
/// database, using CKSyncEngine.
///
/// The local SwiftData store stays the source of truth and keeps its current schema.
/// Local saves are picked up from `ModelContext.didSave` and queued for upload; changes
/// from other devices are written back through the same models.
@MainActor
@Observable
final class ClipSync {
    enum Phase: Equatable {
        case off
        case starting
        case syncing
        case upToDate
        case needsAccount
        case failed(String)
    }

    static let shared = ClipSync()
    static let enabledKey = "iCloudSyncEnabled"

    private(set) var phase: Phase = .off
    private(set) var lastSyncedAt: Date?

    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var defaults: UserDefaults = .standard
    @ObservationIgnored private lazy var metadata = SyncMetadataStore()
    @ObservationIgnored private var index: [PersistentIdentifier: SyncKey] = [:]
    @ObservationIgnored private var applyingRemote = false
    @ObservationIgnored private var saveObserver: NSObjectProtocol?

    private let log = Logger(subsystem: "com.minsang.Clipbara", category: "Sync")

    static var containerIdentifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "ClipbaraCloudKitContainer") as? String,
              id.hasPrefix("iCloud.") else { return nil }
        return id
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    private var context: ModelContext? { modelContainer?.mainContext }

    // MARK: - Lifecycle

    /// Call once at launch. Starts syncing only if the person turned it on earlier.
    func configure(container: ModelContainer, defaults: UserDefaults) {
        modelContainer = container
        self.defaults = defaults
        lastSyncedAt = metadata.value.lastSyncedAt
        if isEnabled {
            startEngine(initialUpload: false)
        }
    }

    /// Clips and pinboards that would be uploaded when sync is turned on.
    func uploadCounts() -> (clips: Int, pinboards: Int) {
        guard let context else { return (0, 0) }
        let clips = ((try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []).filter(SyncSchema.isEligible).count
        let boards = (try? context.fetchCount(FetchDescriptor<Pinboard>())) ?? 0
        return (clips, boards)
    }

    func enable() async {
        guard let identifier = Self.containerIdentifier else {
            phase = .failed(String(localized: "iCloud is not set up for this build."))
            return
        }
        phase = .starting
        let status = (try? await CKContainer(identifier: identifier).accountStatus()) ?? .couldNotDetermine
        guard status == .available else {
            phase = .needsAccount
            return
        }
        defaults.set(true, forKey: Self.enabledKey)
        metadata.reset()
        startEngine(initialUpload: true)
        await syncNow()
    }

    /// Stops syncing. Clips stay on this device and in iCloud.
    func disable() {
        defaults.set(false, forKey: Self.enabledKey)
        stopEngine()
        metadata.reset()
        lastSyncedAt = nil
        phase = .off
    }

    /// Deletes everything Clipbara stored in iCloud, then turns sync off here.
    /// Other devices notice the deleted zone and turn sync off too; their local clips stay.
    func deleteCloudData() async {
        guard let engine else {
            disable()
            return
        }
        engine.state.add(pendingDatabaseChanges: [.deleteZone(SyncKey.zoneID)])
        do {
            try await engine.sendChanges()
            disable()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
        guard let engine else { return }
        phase = .syncing
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            markSynced()
        } catch {
            log.error("sync failed: \(error.localizedDescription, privacy: .public)")
            phase = Self.phase(for: error)
        }
    }

    private func startEngine(initialUpload: Bool) {
        guard engine == nil, let identifier = Self.containerIdentifier, modelContainer != nil else { return }
        let database = CKContainer(identifier: identifier).privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: metadata.value.engineState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        phase = .starting
        rebuildIndex()
        observeSaves()
        if initialUpload {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncKey.zoneID))])
            enqueueEverything()
        }
    }

    private func stopEngine() {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
        saveObserver = nil
        engine = nil
        index = [:]
    }

    private func markSynced() {
        let now = Date()
        lastSyncedAt = now
        metadata.update { $0.lastSyncedAt = now }
        phase = .upToDate
    }

    private static func phase(for error: Error) -> Phase {
        if let ck = error as? CKError, ck.code == .notAuthenticated {
            return .needsAccount
        }
        return .failed(error.localizedDescription)
    }

    // MARK: - Local changes -> pending uploads

    private func observeSaves() {
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let inserted = info[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
            let updated = info[ModelContext.NotificationKey.updatedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
            let deleted = info[ModelContext.NotificationKey.deletedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
            MainActor.assumeIsolated {
                self?.handleLocalSave(changed: inserted + updated, deleted: deleted)
            }
        }
    }

    private func handleLocalSave(changed: [PersistentIdentifier], deleted: [PersistentIdentifier]) {
        guard let engine, let context else { return }
        var saves: [CKSyncEngine.PendingRecordZoneChange] = []
        var deletes: [CKSyncEngine.PendingRecordZoneChange] = []

        for identifier in changed {
            guard let pair = Self.key(for: context.model(for: identifier)) else { continue }
            let (key, eligible) = pair
            index[identifier] = key
            if eligible && !applyingRemote {
                saves.append(.saveRecord(key.recordID))
            }
        }
        for identifier in deleted {
            guard let key = index.removeValue(forKey: identifier) else { continue }
            if !applyingRemote {
                deletes.append(.deleteRecord(key.recordID))
            }
        }
        if !saves.isEmpty || !deletes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: saves + deletes)
        }
    }

    private static func key(for model: any PersistentModel) -> (SyncKey, Bool)? {
        switch model {
        case let item as ClipboardItem:
            return (SyncKey(kind: .clip, id: item.id), SyncSchema.isEligible(item))
        case let pinboard as Pinboard:
            return (SyncKey(kind: .pinboard, id: pinboard.id), true)
        case let entry as PinboardEntry:
            return (SyncKey(kind: .entry, id: entry.id), SyncSchema.isEligible(entry))
        default:
            return nil
        }
    }

    private func rebuildIndex() {
        guard let context else { return }
        index = [:]
        for item in (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? [] {
            index[item.persistentModelID] = SyncKey(kind: .clip, id: item.id)
        }
        for pinboard in (try? context.fetch(FetchDescriptor<Pinboard>())) ?? [] {
            index[pinboard.persistentModelID] = SyncKey(kind: .pinboard, id: pinboard.id)
        }
        for entry in (try? context.fetch(FetchDescriptor<PinboardEntry>())) ?? [] {
            index[entry.persistentModelID] = SyncKey(kind: .entry, id: entry.id)
        }
    }

    private func enqueueEverything() {
        guard let engine, let context else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for pinboard in (try? context.fetch(FetchDescriptor<Pinboard>())) ?? [] {
            changes.append(.saveRecord(SyncKey(kind: .pinboard, id: pinboard.id).recordID))
        }
        for item in (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? [] where SyncSchema.isEligible(item) {
            changes.append(.saveRecord(SyncKey(kind: .clip, id: item.id).recordID))
        }
        for entry in (try? context.fetch(FetchDescriptor<PinboardEntry>())) ?? [] where SyncSchema.isEligible(entry) {
            changes.append(.saveRecord(SyncKey(kind: .entry, id: entry.id).recordID))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: - Building records to send

    fileprivate func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let key = SyncKey(recordID: recordID), let context else { return nil }
        let record = metadata.record(for: key)
        let id = key.id
        switch key.kind {
        case .clip:
            let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
            guard let item = try? context.fetch(descriptor).first, SyncSchema.isEligible(item) else { return nil }
            SyncSchema.fill(record, from: item)
        case .pinboard:
            let descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })
            guard let pinboard = try? context.fetch(descriptor).first else { return nil }
            SyncSchema.fill(record, from: pinboard)
        case .entry:
            let descriptor = FetchDescriptor<PinboardEntry>(predicate: #Predicate { $0.id == id })
            guard let entry = try? context.fetch(descriptor).first, SyncSchema.isEligible(entry) else { return nil }
            SyncSchema.fill(record, from: entry)
        }
        return record
    }

    // MARK: - Events

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            metadata.update { $0.engineState = update.stateSerialization }

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == SyncKey.zoneID }) {
                // Deleted from another device (or from iCloud settings). Keep local clips.
                log.info("sync zone was deleted remotely; turning sync off")
                disable()
            }

        case .fetchedRecordZoneChanges(let changes):
            applyRemote(modifications: changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID))

        case .sentRecordZoneChanges(let sent):
            handleSent(sent)

        case .willFetchChanges, .willSendChanges:
            phase = .syncing

        case .didFetchChanges, .didSendChanges:
            if engine?.state.pendingRecordZoneChanges.isEmpty ?? true {
                markSynced()
            }

        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            enqueueEverything()
        case .signOut, .switchAccounts:
            // Never mix one account's clips into another. Local clips stay; sync turns off.
            disable()
            phase = .needsAccount
        @unknown default:
            break
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let engine else { return }
        for record in sent.savedRecords {
            metadata.remember(record)
        }
        for recordID in sent.deletedRecordIDs {
            metadata.forget(recordID)
        }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Keep our values on top of the newer server record.
                if let server = failure.error.serverRecord {
                    metadata.remember(server)
                }
                retry.append(.saveRecord(recordID))
            case .zoneNotFound:
                metadata.forget(recordID)
                needsZone = true
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // Deleted on another device: deletes win over edits.
                metadata.forget(recordID)
                if let key = SyncKey(recordID: recordID) {
                    applyRemote(modifications: [], deletions: [key.recordID])
                }
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .requestRateLimited, .notAuthenticated, .operationCancelled:
                break // CKSyncEngine retries these on its own.
            default:
                log.error("record save failed: \(failure.error.localizedDescription, privacy: .public)")
                phase = .failed(failure.error.localizedDescription)
            }
        }
        if needsZone {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncKey.zoneID))])
        }
        if !retry.isEmpty {
            engine.state.add(pendingRecordZoneChanges: retry)
        }
    }

    // MARK: - Remote changes -> local store

    private func applyRemote(modifications: [CKRecord], deletions: [CKRecord.ID]) {
        guard let context else { return }
        applyingRemote = true
        defer { applyingRemote = false }

        var followUps: [CKSyncEngine.PendingRecordZoneChange] = []
        let byKind = Dictionary(grouping: modifications) { SyncKey(recordID: $0.recordID)?.kind }

        for record in byKind[.pinboard] ?? [] {
            metadata.remember(record)
            applyPinboard(record, context: context)
        }
        for record in byKind[.clip] ?? [] {
            metadata.remember(record)
            followUps += applyClip(record, context: context)
        }
        for record in byKind[.entry] ?? [] {
            metadata.remember(record)
            guard let key = SyncKey(recordID: record.recordID),
                  let values = SyncSchema.entryValues(record, id: key.id) else { continue }
            if !applyEntry(values, context: context) {
                metadata.update { $0.orphanEntries[values.id] = values }
            }
        }
        for recordID in deletions {
            metadata.forget(recordID)
            guard let key = SyncKey(recordID: recordID) else { continue }
            deleteLocal(key, context: context)
        }
        retryOrphans(context: context)
        try? context.save()

        if !followUps.isEmpty {
            engine?.state.add(pendingRecordZoneChanges: followUps)
        }
    }

    private func applyPinboard(_ record: CKRecord, context: ModelContext) {
        guard let key = SyncKey(recordID: record.recordID) else { return }
        let id = key.id
        let pinboard: Pinboard
        if let existing = try? context.fetch(FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })).first {
            pinboard = existing
        } else {
            pinboard = Pinboard(name: "", displayOrder: 0)
            pinboard.id = id
            context.insert(pinboard)
        }
        pinboard.name = record.encryptedValues[SyncSchema.PinboardField.name] as String? ?? pinboard.name
        pinboard.displayOrder = record[SyncSchema.PinboardField.order] as? Int ?? pinboard.displayOrder
        pinboard.createdAt = record[SyncSchema.PinboardField.createdAt] as? Date ?? pinboard.createdAt
    }

    /// Returns follow-up uploads needed to settle a duplicate.
    private func applyClip(_ record: CKRecord, context: ModelContext) -> [CKSyncEngine.PendingRecordZoneChange] {
        guard let key = SyncKey(recordID: record.recordID), let values = SyncSchema.clipValues(record) else { return [] }
        let id = key.id

        if let existing = try? context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })).first {
            update(existing, with: values)
            return []
        }

        // Same content already saved here under another ID (e.g. copied on both devices).
        let hash = values.hash
        if !hash.isEmpty,
           let twin = try? context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.contentHash == hash })).first {
            let keep = SyncSchema.survivor(twin.id, id)
            if keep == twin.id {
                twin.copiedAt = max(twin.copiedAt, values.copiedAt)
                // The other device will drop its copy once it sees this delete.
                return [.deleteRecord(key.recordID), .saveRecord(SyncKey(kind: .clip, id: twin.id).recordID)]
            }
            let item = insertClip(id: id, values: values, context: context)
            var followUps: [CKSyncEngine.PendingRecordZoneChange] = []
            for entry in pinboardEntries(of: twin.id, context: context) {
                entry.clipboardItem = item
                followUps.append(.saveRecord(SyncKey(kind: .entry, id: entry.id).recordID))
            }
            item.isPinned = item.isPinned || twin.isPinned
            item.copiedAt = max(item.copiedAt, twin.copiedAt)
            if twin.userTitle != nil && item.userTitle == nil { item.userTitle = twin.userTitle }
            context.delete(twin)
            followUps.append(.deleteRecord(SyncKey(kind: .clip, id: twin.id).recordID))
            return followUps
        }

        insertClip(id: id, values: values, context: context)
        return []
    }

    @discardableResult
    private func insertClip(id: UUID, values: SyncSchema.ClipValues, context: ModelContext) -> ClipboardItem {
        let item = ClipboardItem(
            contentType: values.type,
            rawData: Data(values.text.utf8),
            textContent: values.text,
            sourceAppName: values.sourceApp,
            sourceAppBundleId: values.sourceBundle,
            contentHash: values.hash
        )
        item.id = id
        update(item, with: values)
        context.insert(item)
        return item
    }

    private func update(_ item: ClipboardItem, with values: SyncSchema.ClipValues) {
        item.copiedAt = values.copiedAt
        item.userTitle = values.title
        if item.textContent != values.text, SyncSchema.syncedType(item.contentType) == values.type {
            item.textContent = values.text
            item.rawData = Data(values.text.utf8)
        }
    }

    private func applyEntry(_ values: SyncSchema.EntryValues, context: ModelContext) -> Bool {
        let clipID = values.clipID
        let boardID = values.pinboardID
        let entryID = values.id
        guard let item = try? context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == clipID })).first,
              let pinboard = try? context.fetch(FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == boardID })).first else {
            return false
        }
        let entry: PinboardEntry
        if let existing = try? context.fetch(FetchDescriptor<PinboardEntry>(predicate: #Predicate { $0.id == entryID })).first {
            entry = existing
            entry.clipboardItem = item
            entry.pinboard = pinboard
        } else {
            entry = PinboardEntry(clipboardItem: item, pinboard: pinboard, displayOrder: values.order)
            entry.id = entryID
            context.insert(entry)
        }
        entry.displayOrder = values.order
        entry.addedAt = values.addedAt
        item.isPinned = true
        return true
    }

    private func retryOrphans(context: ModelContext) {
        let orphans = metadata.value.orphanEntries
        guard !orphans.isEmpty else { return }
        for (id, values) in orphans where applyEntry(values, context: context) {
            metadata.update { $0.orphanEntries.removeValue(forKey: id) }
        }
    }

    private func deleteLocal(_ key: SyncKey, context: ModelContext) {
        let id = key.id
        switch key.kind {
        case .clip:
            guard let item = try? context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })).first else { return }
            for entry in pinboardEntries(of: id, context: context) {
                context.delete(entry)
            }
            context.delete(item)
        case .pinboard:
            guard let pinboard = try? context.fetch(FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })).first else { return }
            let items = pinboard.entries.compactMap(\.clipboardItem)
            context.delete(pinboard)
            for item in items { refreshPinned(item, ignoring: pinboard.id, context: context) }
        case .entry:
            metadata.update { $0.orphanEntries.removeValue(forKey: id) }
            guard let entry = try? context.fetch(FetchDescriptor<PinboardEntry>(predicate: #Predicate { $0.id == id })).first else { return }
            let item = entry.clipboardItem
            let boardID = entry.pinboard?.id
            context.delete(entry)
            if let item { refreshPinned(item, ignoring: boardID, removingEntry: id, context: context) }
        }
    }

    private func pinboardEntries(of clipID: UUID, context: ModelContext) -> [PinboardEntry] {
        (try? context.fetch(FetchDescriptor<PinboardEntry>(predicate: #Predicate { $0.clipboardItem?.id == clipID }))) ?? []
    }

    private func refreshPinned(
        _ item: ClipboardItem,
        ignoring boardID: UUID?,
        removingEntry entryID: UUID? = nil,
        context: ModelContext
    ) {
        let remaining = pinboardEntries(of: item.id, context: context)
            .filter { $0.id != entryID && $0.pinboard?.id != boardID && !$0.isDeleted }
        item.isPinned = !remaining.isEmpty
    }
}

// MARK: - CKSyncEngineDelegate

extension ClipSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        handle(event)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }
}
