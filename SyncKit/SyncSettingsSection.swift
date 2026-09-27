import SwiftUI

/// iCloud sync controls, shared by the Mac settings window and the iOS settings sheet.
struct SyncSettingsSection: View {
    private let sync = ClipSync.shared

    @State private var confirmEnable = false
    @State private var confirmDelete = false
    @State private var counts = (clips: 0, pinboards: 0)

    var body: some View {
        Section {
            Toggle(isOn: toggleBinding) {
                Label("iCloud Sync", systemImage: "icloud")
            }
            .disabled(sync.phase == .starting)

            if sync.isEnabled || sync.phase == .needsAccount || isFailure {
                HStack(spacing: 8) {
                    statusIcon
                    Text(statusText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if sync.isEnabled {
                        Button("Sync Now") {
                            Task { await sync.syncNow() }
                        }
                        .disabled(sync.phase == .syncing || sync.phase == .starting)
                    }
                }
                .font(.callout)
            }

            if sync.isEnabled {
                Button("Delete iCloud Data…", role: .destructive) {
                    confirmDelete = true
                }
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Text, links, and colors in your history and pinboards sync between your Mac and iPhone through your private iCloud database. Clip contents are stored as encrypted fields. Images and files stay on the device where you copied them.")
        }
        .confirmationDialog("Turn On iCloud Sync?", isPresented: $confirmEnable, titleVisibility: .visible) {
            Button("Turn On") {
                Task { await sync.enable() }
            }
        } message: {
            Text("\(counts.clips) clips and \(counts.pinboards) pinboards on this device will be uploaded to your iCloud account.")
        }
        .confirmationDialog("Delete iCloud Data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete iCloud Data", role: .destructive) {
                Task { await sync.deleteCloudData() }
            }
        } message: {
            Text("Clipbara's data in iCloud is deleted and sync turns off on every device. Clips already on each device stay there.")
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { sync.isEnabled },
            set: { on in
                if on {
                    counts = sync.uploadCounts()
                    confirmEnable = true
                } else {
                    sync.disable()
                }
            }
        )
    }

    private var isFailure: Bool {
        if case .failed = sync.phase { return true }
        return false
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch sync.phase {
        case .syncing, .starting:
            ProgressView().controlSize(.small)
        case .upToDate:
            Image(systemName: "checkmark.icloud").foregroundStyle(.green)
        case .needsAccount:
            Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.icloud").foregroundStyle(.red)
        case .off:
            Image(systemName: "icloud.slash").foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch sync.phase {
        case .off:
            return String(localized: "Off")
        case .starting:
            return String(localized: "Connecting to iCloud…")
        case .syncing:
            return String(localized: "Syncing…")
        case .upToDate:
            if let date = sync.lastSyncedAt {
                let relative = date.formatted(.relative(presentation: .named))
                return String(localized: "Up to date, synced \(relative)")
            }
            return String(localized: "Up to date")
        case .needsAccount:
            return String(localized: "Sign in to iCloud to sync.")
        case .failed(let message):
            return message
        }
    }
}
